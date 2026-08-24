//
//  BONetConfiguration.swift
//  BONetKit
//

import Foundation
import Alamofire

/// 网络客户端配置校验错误。
public enum BONetConfigurationError: Error, Equatable, Sendable {
    case invalidBaseURL(String)
    case unsupportedScheme(String)
    case invalidTimeout(TimeInterval)
    case negativeMaxRetryCount(Int)
}

extension BONetConfigurationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            return "baseURL 不是包含 Host 的有效 URL：\(value)"
        case .unsupportedScheme(let scheme):
            return "baseURL 仅支持 HTTP/HTTPS，当前 Scheme：\(scheme)"
        case .invalidTimeout(let value):
            return "timeoutInterval 必须是大于 0 的有限值，当前值：\(value)"
        case .negativeMaxRetryCount(let value):
            return "maxRetryCount 不能小于 0，当前值：\(value)"
        }
    }
}

/// 网络客户端配置。
///
/// 其中的闭包属性标注为 `@Sendable`，调用方传入时需保证线程安全（例如读取 token 时）。
///
/// 关于 `Sendable`：它是 Swift 的标记协议，表示某类型的值可安全跨并发域
/// （线程 / 任务 / actor）传递而不引发数据竞争，由**编译期**检查保证。
/// `Sendable` / `@Sendable` 不依赖运行时库，**没有最低 iOS 版本要求**，
/// 因此不会抬高本库的部署目标（仍为 iOS 13）。这一点与 `async/await`、`actor`
/// 等**运行时**并发特性不同，后者才有系统版本门槛。
///
/// 注意：本类型持有用户自定义的 `additionalInterceptors`（Alamofire 的
/// `RequestInterceptor`，在 Alamofire 5.8 中未声明 `Sendable`），因此本类型
/// 不再整体遵从 `Sendable`。配置对象应在初始化后视为不可变并在主线程装配。
public struct BONetConfiguration {
    
    /// 接口基础地址，例如 `https://api.example.com`。
    /// 请求时传入相对路径会与该地址拼接。
    public var baseURL: String

    /// 单个请求的超时时间，单位秒。
    public var timeoutInterval: TimeInterval

    /// token 的单一权威来源。
    ///
    /// 为 nil 时不注入鉴权头。传入后：请求拦截器从中读取 accessToken 注入；
    /// 若同时配置了 `tokenRefresh`，401 时会自动刷新并把新凭证写回同一个 store。
    /// 注入头字段与格式也由 store 决定（`headerField` / `headerValue(for:)`）。
    public var tokenStore: BOTokenStore?

    /// token 刷新处理器（可选）。
    ///
    /// 提供后启用基于 401 的自动刷新：并发请求会被挂起、只刷新一次、成功后自动重发。
    /// 不提供则只注入、不刷新（适合单 token 且无需刷新的场景）。
    /// 需与 `tokenStore` 搭配使用。
    ///
    /// ⚠️ 重要：**刷新请求本身不要走已配置了本刷新逻辑的 `BONetClient`**。
    /// 否则刷新请求若也返回 401，会再次触发刷新，形成无限递归/死循环。
    /// 请用独立的会话（如单独的 `URLSession` 或未配置 `tokenRefresh` 的另一个客户端）
    /// 发起刷新请求。
    public var tokenRefresh: BORefreshHandler?

    /// 表示「token 失效」的业务码集合（默认空）。
    ///
    /// 用于处理「HTTP 200 但业务码表示登录态失效（如 40101）」的情况：命中这些码时，
    /// 请求会被判定为认证失效，从而复用与 401 相同的挂起 / 单次刷新 / 重发流程。
    /// 需与 `tokenStore` + `tokenRefresh` 搭配使用；为空时不启用业务码失效检测。
    public var tokenExpiredBusinessCodes: [Int]

    /// 附加到每个请求的公共请求头。
    public var commonHeaders: [String: String]

    /// 请求失败时的最大重试次数（由请求拦截器执行）。
    public var maxRetryCount: Int

    /// 自定义 `URLProtocol` 类，会被插入到底层会话配置的最前面。
    /// 主要用于测试或本地 mock：拦截请求并返回构造好的响应。生产环境通常留空。
    public var protocolClasses: [AnyClass]

    /// 编码前请求中间件链。
    ///
    /// 按数组顺序同步执行，每个中间件都可读取和修改结构化的 path、method、parameters
    /// 与 headers。适合字段级加密、签名、公共业务参数和埋点参数等编码前处理。
    public var requestMiddlewares: [BORequestMiddleware]

    /// 用户自定义请求拦截器。
    ///  
    /// 会与库内置拦截器组合成一条链，统一由底层会话执行：
    /// - `adapt`（请求加工）：**库内置拦截器先执行**（注入公共头与 token），
    ///   随后按数组顺序依次执行这里的拦截器；
    /// - `retry`（失败重试）：按同样顺序尝试，第一个给出重试决定的拦截器生效。
    ///
    /// 适合注入业务自定义的请求加工（如签名、埋点头）或额外的重试策略。
    public var additionalInterceptors: [RequestInterceptor]

    /// 响应解码时的键名转换策略，应用于 `data` 的模型解析。
    ///
    /// - `.useDefaultKeys`（默认）：不转换，JSON 键名需与属性名（或模型的 `CodingKeys`）一致。
    /// - `.convertFromSnakeCase`：自动把后端 snake_case（如 `user_name`）转为
    ///   Swift 的 camelCase（`userName`），适合后端统一使用下划线命名的场景。
    /// - `.custom(...)`：完全自定义键名映射，用于不规则命名。
    ///
    /// 说明：即便开启了 `.convertFromSnakeCase`，个别不规则字段仍可在对应模型中
    /// 用 `CodingKeys` 单独覆盖，两者可以并存。
    public var keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy

    /// 响应中间件链。
    ///
    /// 在响应被解析为业务模型**之前**，按数组顺序（洋葱模型）处理原始响应
    /// （`BOResponseContext`）。适合日志、错误上报、响应体改写、按状态码短路等横切逻辑。
    /// 内置可用中间件：`BOLoggingMiddleware`、`BOErrorReportingMiddleware`。
    public var responseMiddlewares: [BOResponseMiddleware]

    /// 响应解析器：把原始响应解析为业务模型的可插拔点。
    ///
    /// 默认 `BODefaultResponseParser`，按 `{ code, message, data }`（`code == 0` 成功）解析。
    /// 后端采用其他结构时，实现 `BOResponseParser` 并在此注入。
    /// 执行位置固定在响应中间件链之后。
    public var responseParser: BOResponseParser

    public init(
        baseURL: String,
        timeoutInterval: TimeInterval = 30,
        tokenStore: BOTokenStore? = nil,
        tokenRefresh: BORefreshHandler? = nil,
        tokenExpiredBusinessCodes: [Int] = [],
        commonHeaders: [String: String] = [:],
        maxRetryCount: Int = 0,
        protocolClasses: [AnyClass] = [],
        requestMiddlewares: [BORequestMiddleware] = [],
        additionalInterceptors: [RequestInterceptor] = [],
        keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        responseMiddlewares: [BOResponseMiddleware] = [],
        responseParser: BOResponseParser = BODefaultResponseParser()
    ) {
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
        self.tokenStore = tokenStore
        self.tokenRefresh = tokenRefresh
        self.tokenExpiredBusinessCodes = tokenExpiredBusinessCodes
        self.commonHeaders = commonHeaders
        self.maxRetryCount = maxRetryCount
        self.protocolClasses = protocolClasses
        self.requestMiddlewares = requestMiddlewares
        self.additionalInterceptors = additionalInterceptors
        self.keyDecodingStrategy = keyDecodingStrategy
        self.responseMiddlewares = responseMiddlewares
        self.responseParser = responseParser
    }

    /// 校验会影响请求创建和重试行为的基础配置。
    public func validate() throws {
        if let validationError {
            throw validationError
        }
    }

    var validationError: BONetConfigurationError? {
        guard let components = URLComponents(string: baseURL),
              components.url != nil,
              let scheme = components.scheme,
              let host = components.host,
              !host.isEmpty else {
            return .invalidBaseURL(baseURL)
        }
        guard scheme.lowercased() == "http" || scheme.lowercased() == "https" else {
            return .unsupportedScheme(scheme)
        }
        guard timeoutInterval.isFinite, timeoutInterval > 0 else {
            return .invalidTimeout(timeoutInterval)
        }
        guard maxRetryCount >= 0 else {
            return .negativeMaxRetryCount(maxRetryCount)
        }
        return nil
    }
}
