# BONetKit

基于 [Alamofire](https://github.com/Alamofire/Alamofire) 的轻量网络请求封装工具。

- 最低支持 **iOS 13**，Swift 5。
- 通过 **CocoaPods** 集成，依赖 Alamofire `~> 5.8`。
- 泛型 `Codable` 请求接口（当前为 completion 回调，后续将增补 async/await）。
- 内置请求拦截器（token / 公共头注入、失败重试）与响应处理（校验后端统一结构）。
- 统一错误模型 `BONetError` 与错误分发中心 `BOErrorHandlerProtocol`。

## 安装

```ruby
pod 'BONetKit', :git => 'https://github.com/sun6762/BONetKit.git'
```

执行 `pod install`。Alamofire 会作为传递依赖自动引入，无需在 Podfile 中单独声明。

## 关于 Alamofire 版本

BONetKit 依赖声明为 `Alamofire ~> 5.8`，即兼容 `>= 5.8, < 6.0` 的全部 5.x 版本。
本库仅使用 Alamofire 的核心稳定接口，在该区间内均可正常编译运行。

- **推荐版本：`5.8.x`**。功能成熟稳定，对 Xcode 版本要求宽松，是本库的验证基线。
- 不加约束时，CocoaPods 会在区间内选择**最新版本**（当前为 `5.12.x`）。该版本同样受支持，
  但较新的 Alamofire 需要较新的 Xcode 工具链才能编译；若你的构建环境较旧，建议锁定到 5.8。
- **锁定到推荐版本**：在你的 Podfile 中显式声明即可
  ```ruby
  pod 'Alamofire', '~> 5.8.0'   # 锁定 5.8.x
  ```
- 本库不会随 Alamofire 6.0 自动升级（约束已排除 `>= 6.0`）；届时会评估适配后再放开。

## 配置

App 启动时配置一次：

```swift
import BONetKit

BONetClient.shared.configure(
    BONetConfiguration(
        baseURL: "https://api.example.com",
        timeoutInterval: 30,
        commonHeaders: ["Accept": "application/json"],
        maxRetryCount: 1
    )
)
```

鉴权（注入 token、自动刷新）通过 `tokenStore` / `tokenRefresh` 配置，见「鉴权与 Token 刷新」。

## 发起请求

后端约定统一结构 `{ "code": 0, "message": "ok", "data": { ... } }`，`code == 0` 为成功。
`data` 会被解码为你传入的模型：

```swift
struct UserProfile: Decodable {
    let id: Int
    let name: String
}

BONetClient.shared.request(
    "/user/profile",
    method: .get,
    parameters: ["id": 1],
    of: UserProfile.self
) { result in
    switch result {
    case .success(let profile):
        print(profile.name)
    case .failure(let error):
        print(error.localizedDescription)
    }
}
```

## 鉴权与 Token 刷新

鉴权采用**单一 token 来源**架构：token 的注入与刷新都围绕同一个 `BOTokenStore`，
不存在多个注入者需要协调的问题。

### Token 来源：BOTokenStore

`BOTokenStore` 是 token 的唯一权威来源。库内置线程安全的 `BOInMemoryTokenStore`，
也可自行实现该协议（如对接 Keychain 持久化）。

```swift
let tokenStore = BOInMemoryTokenStore(
    headerField: "Authorization",
    headerValueBuilder: { "Bearer \($0)" }   // 头值格式，默认即 Bearer
)

BONetClient.shared.configure(
    BONetConfiguration(baseURL: "https://api.example.com", tokenStore: tokenStore)
)
```

凭证用 `BOCredential`（双 token；单 token 场景 `refreshToken` / `expiration` 可省略）：

```swift
// 登录成功后写入，后续请求自动带上鉴权头，无需重新 configure：
tokenStore.credential = BOCredential(
    accessToken: "xxx",
    refreshToken: "yyy",
    expiration: Date(timeIntervalSinceNow: 3600)
)
```

### 自动刷新（基于 401）

额外提供 `tokenRefresh` 后，即启用自动刷新：**并发请求遇 401 会被挂起、只刷新一次、
刷新成功后用新 token 自动重发**（并发协调由 Alamofire `AuthenticationInterceptor` 保证）。
另因 `BOCredential.requiresRefresh` 留有余量，token 常在过期前就被主动刷新，401 是兜底。

```swift
BONetClient.shared.configure(
    BONetConfiguration(
        baseURL: "https://api.example.com",
        tokenStore: tokenStore,
        tokenRefresh: { current, completion in
            // 用 current.refreshToken 调刷新接口，成功回调新凭证
            api.refresh(current.refreshToken) { newAccess, newRefresh, exp in
                completion(.success(BOCredential(
                    accessToken: newAccess, refreshToken: newRefresh, expiration: exp
                )))
            }
            // 失败：completion(.failure(error))
        }
    )
)
```

刷新得到的新凭证由库自动写回同一个 `tokenStore`。

- 只配 `tokenStore`：只注入、不刷新（适合单 token、无需刷新）。
- 配 `tokenStore` + `tokenRefresh`：注入 + 401 自动刷新重发。
- 都不配：不注入鉴权头。

> ⚠️ 刷新请求本身**不要走已启用刷新的同一个 client**，否则刷新请求自身返回 401
> 会再次触发刷新，形成死循环。请用独立会话（如单独的 `URLSession`）发起刷新。

### 业务码失效（HTTP 200 + 业务码）

有些后端登录态失效时返回的是 **HTTP 200 但业务码表示失效**（如 `code == 40101`），
这种响应 Alamofire 视为成功、不会触发 401 刷新。配置 `tokenExpiredBusinessCodes`
即可让这类业务码复用同一套刷新重发机制：

```swift
BONetConfiguration(
    baseURL: "https://api.example.com",
    tokenStore: tokenStore,
    tokenRefresh: { current, completion in /* ... */ },
    tokenExpiredBusinessCodes: [40101]   // 命中这些码 → 触发刷新 → 重发
)
```

原理：命中失效码时，库让该请求的校验失败并转成认证失效信号，从而复用与 401 相同的
挂起 / 单次刷新 / 重发流程。为空（默认）时不启用此检测。

> 注：启用后，每个响应会额外做一次轻量 JSON 解析以探测业务码；不需要该能力时留空即可。

## 请求取消

`request(...)` 返回一个 `BORequestToken?` 句柄（`@discardableResult`，不接收返回值也可）。
请求被取消时，回调返回 `BONetError.cancelled`（可用 `error.isCancelled` 判断），通常无需提示为错误。

### 手动取消

持有句柄，在需要时取消（如页面退出、搜索词变化）：

```swift
let token = BONetClient.shared.request("/user", of: User.self) { result in
    if case .failure(let error) = result, error.isCancelled { return }
    // ...
}
token?.cancel()
```

### 分组取消

发起时传 `group`，之后按组批量取消（如页面销毁时取消该页所有请求）：

```swift
BONetClient.shared.request("/a", of: A.self, group: "profile") { ... }
BONetClient.shared.request("/b", of: B.self, group: "profile") { ... }

BONetClient.shared.cancel(group: "profile")   // 取消该组全部
BONetClient.shared.cancelAll()                 // 取消所有进行中请求
```

### 自动去重

开启 `deduplicate` 后，发起时若已有「相同请求」进行中，会**取消旧的、用新的**
（适合搜索框输入、防重复提交等场景）。相同的判定依据是 `method + URL + 参数`
（参数不同则视为不同请求）：

```swift
BONetClient.shared.request(
    "/search", parameters: ["q": keyword], of: Result.self,
    deduplicate: true
) { ... }
```

被去重取消的旧请求，其回调返回 `.cancelled`。默认关闭，逐请求控制。

## 错误处理

失败时回调返回 `BONetError`，同时经错误分发中心路由。业务控制器可遵守
`BOErrorHandlerProtocol` 并在请求时传入自身作为处理者：

```swift
extension MyViewController: BOErrorHandlerProtocol {
    func handleError(_ error: BONetError) -> Bool {
        // 处理错误，返回 true 表示已消费
        showToast(error.localizedDescription)
        return true
    }
}

// 请求时传入 errorHandler
BONetClient.shared.request(
    "/user/profile", of: UserProfile.self, errorHandler: self
) { result in ... }
```

也可设置全局兜底处理：

```swift
BOErrorDispatcher.shared.fallbackHandler = { error in
    // 无具体处理者消费时的兜底
}
```

> 注：把错误自动定位分发到「当前业务控制器」的策略尚在设计中，当前提供
> 「请求时显式传入 handler」与「全局兜底」两种方式。

## 自定义请求拦截器

除了库内置的拦截器（注入公共头 / token、失败重试），你可以传入自己的
Alamofire `RequestInterceptor`，在库内与内置拦截器组合成一条链统一执行。
适合注入业务自定义的请求加工（签名、埋点头等）或额外的重试策略。

```swift
import Alamofire

final class SignatureInterceptor: RequestInterceptor {
    func adapt(_ urlRequest: URLRequest, for session: Session,
               completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var request = urlRequest
        request.setValue(sign(request), forHTTPHeaderField: "X-Signature")
        completion(.success(request))
    }

    func retry(_ request: Request, for session: Session, dueTo error: Error,
               completion: @escaping (RetryResult) -> Void) {
        completion(.doNotRetry)   // 不介入重试
    }
}

// 通过配置传入，可传多个
BONetClient.shared.configure(
    BONetConfiguration(
        baseURL: "https://api.example.com",
        additionalInterceptors: [SignatureInterceptor()]
    )
)
```

### 执行顺序

拦截器链的执行顺序为 **库内置拦截器 →（按数组顺序）用户拦截器**：

- **`adapt`（请求加工）**：库内置的先执行（注入公共头与 token），你的拦截器在其基础上继续加工。
- **`retry`（失败重试）**：按同样顺序尝试，**第一个给出重试决定的拦截器生效**。
  库内置拦截器排在最前，因此其基于 `maxRetryCount` 的重试会优先。若你的重试策略需要优先，
  当前实现下会被内置逻辑抢先——如有此需求请告知，可调整为可配置的顺序。

## 响应中间件

响应侧提供一条可插拔的中间件链，对称于请求拦截器。中间件在响应被解析为业务模型
**之前**执行，处理原始响应层（`BOResponseContext`：request / httpResponse / data / error / duration），
适合日志、错误上报、响应体改写、按状态码短路等横切逻辑。

采用洋葱模型：数组靠前的中间件在外层（最先进入、最后退出），可在 `next(context)`
前后插入逻辑，也可不调用 `next` 以短路后续处理。

内置两个中间件：

```swift
BONetClient.shared.configure(
    BONetConfiguration(
        baseURL: "https://api.example.com",
        responseMiddlewares: [
            BOLoggingMiddleware(),                       // 打印请求/响应/耗时
            BOErrorReportingMiddleware { context in      // 网络错误或非 2xx 时回调
                report(context)
            }
        ]
    )
)
```

自定义中间件实现 `BOResponseMiddleware`：

```swift
struct MyMiddleware: BOResponseMiddleware {
    func process(_ context: BOResponseContext,
                 next: (BOResponseContext) -> BOResponseContext) -> BOResponseContext {
        // next 之前：处理请求发出后的逻辑
        var result = next(context)
        // next 之后：处理响应返回后的逻辑，可读取/改写 result
        return result
    }
}
```

> 说明：响应中间件是**同步**的，适合日志、上报、改写、短路等横切逻辑。
> 需要异步的场景（如 token 过期后刷新再重发）不属于响应中间件，应在请求侧的
> 重试机制中处理。

## 响应解析器

「后端返回什么业务结构」是可插拔的。响应解析器负责把（经中间件链处理后的）
原始响应解析为业务模型，**执行位置固定在响应中间件链之后**。

默认解析器 `BODefaultResponseParser` 按 `{ code, message, data }`（`code == 0` 成功）解析。
若后端采用其他结构（如 `{ status, result, msg }`、裸对象、裸数组），实现 `BOResponseParser` 注入：

```swift
struct AltParser: BOResponseParser {
    func parse<T: Decodable>(_ context: BOResponseContext, as type: T.Type,
                             decoder: JSONDecoder) -> Result<T, BONetError> {
        // 按后端实际结构解析，返回成功模型或 BONetError
    }
}

BONetClient.shared.configure(
    BONetConfiguration(baseURL: "...", responseParser: AltParser())
)
```

要点：

- **解析固定在中间件链之后**执行，顺序不受中间件影响。
- **有兜底**：`responseParser` 默认即 `BODefaultResponseParser`，不配置也能正常工作。
- **解析器是全局的**：切换后需保证所有接口返回同一结构。若个别接口结构不同，
  建议在该接口的模型层单独处理，而非频繁切换全局解析器。

## 响应解码

后端响应统一按 `{ code, message, data }` 结构解析，`data` 会被解码为你传入的模型。
针对后端不规范的情况，提供以下能力。

### 键名命名不一致

后端常用 snake_case（`user_name`），Swift 惯用 camelCase（`userName`）。两种处理方式：

**方式一：全局自动转换（推荐，后端统一 snake_case 时）**

配置时设 `keyDecodingStrategy`，全局生效，模型无需写映射：

```swift
BONetClient.shared.configure(
    BONetConfiguration(
        baseURL: "https://api.example.com",
        keyDecodingStrategy: .convertFromSnakeCase   // user_name → userName
    )
)
```

可选值：`.useDefaultKeys`（默认，不转换）、`.convertFromSnakeCase`、`.custom(...)`。

**方式二：模型内手动映射（个别不规则字段）**

在模型中用 `CodingKeys` 把属性名映射到 JSON 键名：

```swift
struct UserProfile: Decodable {
    let userName: String
    let avatarURL: String

    enum CodingKeys: String, CodingKey {   // 名称必须是 CodingKeys
        case userName = "user_name"
        case avatarURL = "avatar_url"
    }
}
```

两种方式可并存：全局自动转换 + 个别字段手动覆盖。

### 字段类型漂移（备用）

后端同一字段类型不稳定（如 `age` 时而 `25`、时而 `"25"`、时而 `25.0`）时，
用 `@BOFlexible` 归一到目标类型：

```swift
struct User: Decodable {
    let name: String
    @BOFlexible var age: Int       // 25 / "25" / 25.0 均解为 Int
    @BOFlexible var score: Double  // "98.5" / 98.5 均解为 Double
}
// 取值：user.age（直接是 Int）
```

支持 Int / Double / String / Bool 互转；字段可能缺失时声明为可选：`@BOFlexible var age: Int?`。

### 对象 / 数组漂移（备用）

后端同一字段有时是对象、有时是数组时，用 `BOObjectOrArray` 归一为数组：

```swift
struct Feed: Decodable {
    let items: BOObjectOrArray<Item>   // 后端 [Item] 或单个 Item 均可
}
// 取值：feed.items.values —— 恒为 [Item]
```

> `@BOFlexible` 与 `BOObjectOrArray` 是**备用方案**，用于兼容不规范的后端响应。
> 理想情况下应推动后端返回规范类型；仅在确有漂移的字段上按需使用，不要无脑套用。

## BONetError

统一错误模型，区分以下情况：

| case | 含义 |
|------|------|
| `.network(underlying:)` | 网络层失败（连接、超时、取消等） |
| `.httpStatus(code:data:)` | HTTP 状态码非 2xx |
| `.decoding(underlying:)` | 响应体解码失败 |
| `.business(code:message:userInfo:)` | 后端业务错误（`code != 0`），可携带附加数据 |
| `.emptyData` | 无有效响应数据 |
| `.cancelled` | 请求被主动取消（手动 / 分组 / 去重），可用 `isCancelled` 判断 |
| `.unknown(underlying:)` | 其他未归类错误 |

### 业务错误的附加数据

`.business` 除 `code` / `message` 外，还可携带 `userInfo`（`[String: Any]`，默认空），
用于承载后端返回的其他字段。构造时用便利方法 `makeBusiness`（`userInfo` 可省略）：

```swift
// 在自定义解析器中构造：
.makeBusiness(code: 1001, message: "余额不足")                          // 不带附加数据
.makeBusiness(code: 1001, message: "余额不足", userInfo: ["balance": 5.0]) // 带附加数据
```

在业务层按错误码分流并读取附加数据：

```swift
switch result {
case .failure(let error):
    switch error.businessCode {
    case 1001: showRecharge(balance: error.businessUserInfo["balance"])
    case 40101: goToLogin()
    default:   showToast(error.localizedDescription)
    }
case .success(let value):
    ...
}
```

- `businessCode`：业务错误码，非业务错误时为 `nil`。
- `businessUserInfo`：业务错误的附加数据，非业务错误时为空字典。

> 说明：`BONetError` 是封闭枚举，无法从外部新增 case。业务上的「特殊错误类型」
> 应通过 `.business` 的 `code` 区分、`userInfo` 携带额外信息，在业务层解读，
> 而非扩展错误类型本身。

## 许可证

MIT 许可证，见 [`LICENSE`](LICENSE)。
