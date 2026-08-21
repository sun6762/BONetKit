//
//  BOAuth.swift
//  BONetKit
//

import Foundation
import Alamofire

/// 双 token 凭证（access + refresh）。单 token 场景可将 `refreshToken` / `expiration` 留空。
///
/// 遵从 Alamofire `AuthenticationCredential`：`requiresRefresh` 让框架能在 token 过期前
/// 主动刷新（仅在配置了刷新处理器时生效）。
public struct BOCredential: AuthenticationCredential, Codable {
    
    /// 访问令牌，注入到请求鉴权头。
    public let accessToken: String

    /// 刷新令牌，用于换取新的访问令牌。单 token 场景可为空串。
    public let refreshToken: String

    /// 访问令牌过期时间。不关心过期（如单 token）时可传 `.distantFuture`。
    public let expiration: Date

    public init(
        accessToken: String,
        refreshToken: String = "",
        expiration: Date = .distantFuture
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiration = expiration
    }

    /// 是否需要刷新。留 5 分钟余量，避免临界点请求带着即将过期的 token 发出。
    public var requiresRefresh: Bool {
        Date(timeIntervalSinceNow: 5 * 60) > expiration
    }
}

/// token 的单一权威来源。
///
/// 注入（读 accessToken）与刷新（写回新凭证）都围绕同一个 store 进行，
/// 因此不存在「多个 token 注入者需要协调」的问题——这是本库鉴权架构的核心。
/// 实现需保证线程安全（`credential` 可能在网络回调线程被读写）。
public protocol BOTokenStore: AnyObject {

    /// 当前凭证。nil 表示未登录，不注入鉴权头。
    var credential: BOCredential? { get set }
    
    /// 鉴权头字段名，默认 `Authorization`。
    var headerField: String { get }

    /// 由 accessToken 生成鉴权头值，默认 `"Bearer \(token)"`。
    func headerValue(for accessToken: String) -> String

    /// 注册凭证变化观察者（兜底同步用）。
    ///
    /// 当 `credential` 被外部直接赋值时，实现应回调 `observer` 通知新值。
    /// `BONetClient` 借此在凭证变化时自动同步给认证拦截器——即便调用方绕过
    /// `updateCredential(_:)` 直接写 store，也能保持一致。
    ///
    /// 默认空实现：不支持观察的自定义 store 不受影响（但直接写 store 不会自动同步，
    /// 此时应改用 `BONetClient.updateCredential(_:)`）。
    func setCredentialObserver(_ observer: ((BOCredential?) -> Void)?)
}

public extension BOTokenStore {
    var headerField: String { "Authorization" }
    func headerValue(for accessToken: String) -> String { "Bearer \(accessToken)" }
    func setCredentialObserver(_ observer: ((BOCredential?) -> Void)?) {}
}

/// 内置的线程安全内存 token store（开箱即用）。
///
/// 用并发队列 + barrier 保护：读并行、写独占。若需持久化（如 Keychain），
/// 可自行实现 `BOTokenStore`。
public final class BOInMemoryTokenStore: BOTokenStore, @unchecked Sendable {

    private let queue = DispatchQueue(
        label: "com.bonetkit.tokenstore",
        attributes: .concurrent
    )
    private var _credential: BOCredential?
    private let _headerField: String
    private let _headerValueBuilder: (String) -> String
    private var credentialObserver: ((BOCredential?) -> Void)?

    /// - Parameters:
    ///   - credential: 初始凭证，默认 nil。
    ///   - headerField: 鉴权头字段名，默认 `Authorization`。
    ///   - headerValueBuilder: 头值生成方式，默认 `"Bearer \(token)"`。
    public init(
        credential: BOCredential? = nil,
        headerField: String = "Authorization",
        headerValueBuilder: @escaping (String) -> String = { "Bearer \($0)" }
    ) {
        self._credential = credential
        self._headerField = headerField
        self._headerValueBuilder = headerValueBuilder
    }

    public var credential: BOCredential? {
        get { queue.sync { _credential } }
        set {
            queue.sync(flags: .barrier) { self._credential = newValue }
            // 通知观察者（在栅栏写之外调用，避免持写锁期间执行外部回调）。
            credentialObserver?(newValue)
        }
    }

    public var headerField: String { _headerField }

    public func headerValue(for accessToken: String) -> String {
        _headerValueBuilder(accessToken)
    }

    public func setCredentialObserver(_ observer: ((BOCredential?) -> Void)?) {
        queue.sync(flags: .barrier) { self.credentialObserver = observer }
    }
}

/// 刷新处理器：用当前凭证换取新凭证。
///
/// ⚠️ 实现时**不要用已启用刷新的同一个 `BONetClient` 发起刷新请求**，否则刷新请求
/// 自身返回 401 会再次触发刷新，形成死循环。请使用独立会话发起刷新。
///
/// - Parameters:
///   - current: 当前（已过期或被拒）的凭证。
///   - completion: 刷新完成回调，成功返回新凭证，失败返回错误。
public typealias BORefreshHandler = (
    _ current: BOCredential,
    _ completion: @escaping (Result<BOCredential, Error>) -> Void
) -> Void

/// 内部标记错误：表示「HTTP 200 但业务码判定为 token 失效」。
///
/// 业务码失效时 HTTP 状态码仍是 200，无法靠状态码触发刷新。为复用 Alamofire 的
/// 挂起 / 单次刷新 / 重发机制，请求校验（validation）在命中失效业务码时抛出本错误，
/// 使 Alamofire 判定该请求失败并进入 retry；`BOAuthenticator.didRequest` 再据此识别
/// 为认证失效、触发刷新。
struct BOAuthValidationError: Error {
    /// 命中的业务失效码。
    let businessCode: Int
}

/// BONetKit 认证器，桥接 Alamofire `AuthenticationInterceptor`。
///
/// 注入与刷新都围绕同一个 `BOTokenStore`：`apply` 从 store 读 token 注入，
/// `refresh` 刷新后把新凭证写回 store。标注 `@unchecked Sendable`：仅持有初始化后
/// 不变的 store 引用与刷新闭包，方法内的状态读写由 store 自身保证线程安全。
final class BOAuthenticator: Authenticator, @unchecked Sendable {

    typealias Credential = BOCredential

    private let store: BOTokenStore
    private let refreshHandler: BORefreshHandler

    init(store: BOTokenStore, refreshHandler: @escaping BORefreshHandler) {
        self.store = store
        self.refreshHandler = refreshHandler
    }

    /// 【apply】把凭证应用到请求上。
    ///
    /// 每个请求发出前由 Alamofire 调用，将 accessToken 按 store 约定的字段名与格式
    /// 写入鉴权头。这样「如何注入 token」只有这一处定义。
    func apply(_ credential: BOCredential, to urlRequest: inout URLRequest) {
        urlRequest.setValue(
            store.headerValue(for: credential.accessToken),
            forHTTPHeaderField: store.headerField
        )
    }

    /// 【refresh】刷新凭证。
    ///
    /// 触发刷新时由 Alamofire 调用（同一时刻的并发刷新会被框架合并为一次）。
    /// 这里转调业务提供的 `refreshHandler` 去后端换取新凭证；成功后把新凭证
    /// 写回同一个 store，保证后续与被挂起的请求都读到最新 token。
    func refresh(
        _ credential: BOCredential,
        for session: Session,
        completion: @escaping (Result<BOCredential, Error>) -> Void
    ) {
        refreshHandler(credential) { [store] result in
            // 刷新成功后写回同一来源，保证后续请求读到新凭证。
            if case .success(let newCredential) = result {
                store.credential = newCredential
            }
            completion(result)
        }
    }

    /// 【didRequest】判定一次失败是否属于「认证失效」，决定是否触发刷新。
    ///
    /// 返回 true → 触发刷新并在成功后重发；false → 不刷新，请求按失败结束。
    /// 这里以 HTTP 401 作为失效标志（最常见）。若后端也用 403 等状态码表示失效，
    /// 可扩展为 `[401, 403].contains(response.statusCode)`。
    ///
    /// 判定失效的两种情况：
    /// 1. HTTP 401（标准认证失效）；
    /// 2. `BOAuthValidationError`——「HTTP 200 + 业务码失效」经请求校验转化而来的信号。
    ///    这样业务码失效也能复用 Alamofire 的挂起 / 单次刷新 / 重发机制。
    /// 若后端也用 403 等状态码表示失效，可扩展第 1 项。
    func didRequest(
        _ urlRequest: URLRequest,
        with response: HTTPURLResponse,
        failDueToAuthenticationError error: Error
    ) -> Bool {
        if response.statusCode == 401 {
            return true
        }
        // 从 AFError 中还原底层错误，识别业务码失效标记。
        if (error.asAFError?.underlyingError ?? error) is BOAuthValidationError {
            return true
        }
        return false
    }

    /// 【isRequest】判断该请求携带的是否为「当前凭证」的 accessToken。
    ///
    /// 用于并发刷新场景：刷新完成后，Alamofire 据此找出「用旧 token 发出的请求」
    /// 进行重发，避免误重发用了其他 token 的请求。
    func isRequest(
        _ urlRequest: URLRequest,
        authenticatedWith credential: BOCredential
    ) -> Bool {
        let expected = store.headerValue(for: credential.accessToken)
        let actual = urlRequest.value(forHTTPHeaderField: store.headerField)
        return actual == expected
    }
}
