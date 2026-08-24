//
//  BONetClient.swift
//  BONetKit
//

import Foundation
import Alamofire

/// 网络请求入口。
///
/// 提供泛型 `Codable` 的 `completion` 回调接口，内部整合请求拦截器
/// （注入 token / 公共头、重试）与响应处理（校验后端统一结构 `{code, message, data}`）。
///
/// 代码组织：主类只声明属性与初始化；公共方法在 `public extension`；
/// 私有方法在 `private extension`；交互（点击 / 手势）方法在 `@objc private extension`。
public final class BONetClient {

    // MARK: - Properties

    /// 全局共享客户端。
    public static let shared = BONetClient()

    /// 当前生效的运行时快照（配置 + session + 认证拦截器 + 解码器）。
    /// 由 `configure(_:)` 原子替换，`request(...)` 原子读取。受 `stateLock` 保护。
    private var runtime: BONetRuntime?

    /// 保护 `runtime` 读写的锁，避免 configure 与 request 并发时的数据竞争。
    private let stateLock = NSLock()

    /// 线程安全读取当前运行时快照。
    private var currentRuntime: BONetRuntime? {
        stateLock.lock(); defer { stateLock.unlock() }
        return runtime
    }

    /// 进行中请求的注册表：id → 句柄。用串行队列保护，保证线程安全。
    private var activeTickets: [UUID: BORequestTicket] = [:]
    /// 去重预留的指纹集合：覆盖「去重决策」到「注册票据」之间的并发窗口，
    /// 保证 discardNew/cancelPrevious 的检查与占位在同一临界区内原子完成（DEDUP-02）。
    private var reservedFingerprints: Set<String> = []
    private let ticketsQueue = DispatchQueue(label: "com.bonetkit.activetickets")

    // MARK: - Init

    /// 创建一个状态完全独立的网络客户端。
    ///
    /// 每个实例分别持有配置、Session、鉴权状态、请求注册表和去重状态。
    /// 创建后需先调用 `configure(_:)`；仅需单一全局配置时可继续使用 `shared`。
    public init() {}
}

/// 一次配置生效后的不可变运行时快照。
///
/// `configure(_:)` 构建一份新快照并原子替换；`request(...)` 发起时捕获当前快照，
/// 整个请求生命周期（含响应回调）都使用这份快照，不再回读可变的 `self.configuration`。
/// 这样运行中重新配置不会影响进行中的请求（STATE-01）。
private final class BONetRuntime {
    let configuration: BONetConfiguration
    let session: Session
    let requestInterceptor: BORequestInterceptor
    let authInterceptor: AuthenticationInterceptor<BOAuthenticator>?
    /// 本快照独占的解码器（不与其他请求共享，避免并发解码竞争）。
    let decoder: JSONDecoder

    init(
        configuration: BONetConfiguration,
        session: Session,
        requestInterceptor: BORequestInterceptor,
        authInterceptor: AuthenticationInterceptor<BOAuthenticator>?,
        decoder: JSONDecoder
    ) {
        self.configuration = configuration
        self.session = session
        self.requestInterceptor = requestInterceptor
        self.authInterceptor = authInterceptor
        self.decoder = decoder
    }
}

// MARK: - Public Methods

public extension BONetClient {

    /// 校验配置后初始化客户端。非法配置会在创建 Session 前抛出明确错误。
    func configure(validating configuration: BONetConfiguration) throws {
        try configuration.validate()
        configure(configuration)
    }

    /// 使用给定配置初始化客户端。通常在 App 启动时调用一次。
    /// - Parameter configuration: 网络配置。
    func configure(_ configuration: BONetConfiguration) {
        let sessionConfiguration = URLSessionConfiguration.af.default
        sessionConfiguration.timeoutIntervalForRequest = configuration.timeoutInterval

        // 注入自定义 URLProtocol（测试 / 本地 mock 用），置于最前以优先拦截。
        if !configuration.protocolClasses.isEmpty {
            let existing = sessionConfiguration.protocolClasses ?? []
            sessionConfiguration.protocolClasses = configuration.protocolClasses + existing
        }

        // 本快照独占的解码器，应用键名策略。
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = configuration.keyDecodingStrategy

        let (session, requestInterceptor, authInterceptor) = makeSession(
            configuration: configuration,
            sessionConfiguration: sessionConfiguration
        )

        let newRuntime = BONetRuntime(
            configuration: configuration,
            session: session,
            requestInterceptor: requestInterceptor,
            authInterceptor: authInterceptor,
            decoder: decoder
        )

        // 原子替换当前运行时快照。
        stateLock.lock()
        self.runtime = newRuntime
        stateLock.unlock()
    }

    /// 发起请求并将响应解码为指定模型。
    ///
    /// - Parameters:
    ///   - path: 相对路径（与配置的 `baseURL` 拼接）或完整 URL。
    ///   - method: HTTP 方法，默认 `.get`。
    ///   - parameters: 请求参数，默认空。
    ///   - encoding: 参数编码方式，默认按方法自动选择（GET 用 URL 编码，其余用 JSON）。
    ///   - headers: 本次请求附加的请求头。
    ///   - type: 目标模型类型，对应后端 `data` 字段。
    ///   - group: 分组标识，用于按组批量取消。
    ///   - deduplication: 去重策略，默认 `.none`。
    ///   - deduplicationKey: 自定义去重键，优先于自动指纹。适合复杂参数或自定义编码场景。
    ///   - allowsRetryOnNonIdempotent: 允许本次非幂等请求（POST/PATCH）在瞬时网络错误时重试。
    ///     默认 false——非幂等请求默认不重试以避免重复副作用。仅在确认该接口可安全重试时开启。
    ///   - errorHandler: 本次请求的错误处理者，失败时经错误分发中心路由。
    ///   - completion: 结果回调，成功携带解码后的模型，失败携带 `BONetError`。
    /// - Returns: 请求句柄，可用于取消；未配置时返回 nil。
    @discardableResult
    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .get,
        parameters: [String: Any]? = nil,
        encoding: ParameterEncoding? = nil,
        headers: [String: String]? = nil,
        of type: T.Type,
        group: String? = nil,
        deduplication: BODeduplicationPolicy = .none,
        deduplicationKey: String? = nil,
        allowsRetryOnNonIdempotent: Bool = false,
        errorHandler: BOErrorHandlerProtocol? = nil,
        completion: @escaping (Result<T, BONetError>) -> Void
    ) -> BORequestTicket? {
        // 捕获当前运行时快照：本请求全程（含响应回调）使用它，不再回读可变状态。
        guard let runtime = currentRuntime else {
            deliver(.failure(.unknown(underlying: nil)), to: errorHandler, completion: completion)
            return nil
        }
        let configuration = runtime.configuration

        // 编码前按顺序执行请求中间件。后续 URL 解析、去重和参数编码全部使用处理结果。
        let requestContext = BORequestMiddlewareChain.run(
            configuration.requestMiddlewares,
            context: BORequestContext(
                path: path,
                method: method,
                parameters: parameters,
                headers: headers ?? [:],
                group: group,
                deduplication: deduplication
            )
        )
        let resolvedPath = requestContext.path
        let resolvedMethod = requestContext.method
        let resolvedParameters = requestContext.parameters
        let url = Self.resolveURL(path: resolvedPath, baseURL: configuration.baseURL)

        // 去重处理：在单个临界区内原子完成「检查 + 决策 + 预留」（DEDUP-02），
        // 避免两个相同请求的检查与注册交错导致都被放行。
        var fingerprint: String?
        if deduplication != .none {
            // 调用方显式提供 deduplicationKey 时优先用它（应对复杂参数 / 自定义编码）；
            // 否则用 method + URL + 规范化参数自动计算。
            let fp = deduplicationKey ?? Self.fingerprint(
                method: resolvedMethod,
                url: url,
                parameters: resolvedParameters
            )
            fingerprint = fp
            let decision = reserveFingerprint(fp, policy: deduplication)
            // discardNew 且已有相同请求在跑 → 丢弃本次。
            guard decision.shouldProceed else {
                deliver(.failure(.deduplicated), to: errorHandler, completion: completion)
                return nil
            }
            // cancelPrevious → 在临界区外取消收集到的旧请求。
            decision.ticketsToCancel.forEach { $0.cancel() }
        }

        // 请求级重试覆盖：仅登记在客户端内部，不污染真实 HTTP 请求头。
        let finalHeaders = requestContext.headers

        let request = makeRequest(
            session: runtime.session, url: url, method: resolvedMethod,
            parameters: resolvedParameters, encoding: encoding,
            headers: finalHeaders.isEmpty ? nil : finalHeaders,
            expiredCodes: configuration.tokenExpiredBusinessCodes
        )

        if allowsRetryOnNonIdempotent {
            runtime.requestInterceptor.allowNonIdempotentRetry(for: request)
        }

        // 创建票据并登记到注册表，供手动 / 分组取消 / 去重。
        let ticket = BORequestTicket(group: group, fingerprint: fingerprint, request: request)
        registerTicket(ticket)

        request.responseData { [weak self] response in
            // 用发起时捕获的 runtime 快照处理响应，不回读 self.runtime。
            self?.handleResponse(response, ticket: ticket, runtime: runtime, as: T.self,
                                 errorHandler: errorHandler, completion: completion)
        }

        return ticket
    }

    /// 更新鉴权凭证（登录成功、手动刷新后调用）。
    ///
    /// 库内同步更新两处：`tokenStore` 与认证拦截器内部凭证——因此无需重新 `configure`，
    /// 后续请求即可携带新凭证并正常进入自动刷新流程。
    /// - Parameter credential: 新凭证。
    func updateCredential(_ credential: BOCredential) {
        let rt = currentRuntime
        rt?.configuration.tokenStore?.credential = credential
        rt?.authInterceptor?.credential = credential
    }

    /// 清除鉴权凭证（退出登录时调用）。
    ///
    /// 同步清空 `tokenStore` 与认证拦截器内部凭证，之后的请求不再携带鉴权头。
    func clearCredential() {
        let rt = currentRuntime
        rt?.configuration.tokenStore?.credential = nil
        rt?.authInterceptor?.credential = nil
    }

    /// 取消指定分组的所有进行中请求。
    /// - Parameter group: 分组标识（发起请求时传入的 `group`）。
    func cancel(group: String) {
        let targets = ticketsQueue.sync {
            activeTickets.values.filter { $0.group == group }
        }
        targets.forEach { $0.cancel() }
    }

    /// 取消所有进行中请求。
    func cancelAll() {
        let targets = ticketsQueue.sync { Array(activeTickets.values) }
        targets.forEach { $0.cancel() }
    }
}

// MARK: - Private Methods

private extension BONetClient {

    /// 组合拦截器链并创建会话。库内置拦截器在前，认证拦截器居中（如启用刷新），
    /// 用户自定义拦截器在后。
    func makeSession(
        configuration: BONetConfiguration,
        sessionConfiguration: URLSessionConfiguration
    ) -> (
        session: Session,
        requestInterceptor: BORequestInterceptor,
        authInterceptor: AuthenticationInterceptor<BOAuthenticator>?
    ) {
        let builtInInterceptor = BORequestInterceptor(configuration: configuration)
        var interceptors: [RequestInterceptor] = [builtInInterceptor]
        var authInterceptor: AuthenticationInterceptor<BOAuthenticator>?

        // 只要配置了 tokenStore + tokenRefresh 就建立认证拦截器（不依赖启动时是否已有凭证）。
        // 初始凭证取 store 当前值（可能为 nil，合法）；登录后经 updateCredential(_:) 同步。
        if let tokenStore = configuration.tokenStore,
           let tokenRefresh = configuration.tokenRefresh {
            let authenticator = BOAuthenticator(store: tokenStore, refreshHandler: tokenRefresh)
            let interceptor = AuthenticationInterceptor(
                authenticator: authenticator,
                credential: tokenStore.credential
            )
            authInterceptor = interceptor
            interceptors.append(interceptor)

            // 兜底：订阅 store 凭证变化，自动同步给认证拦截器。
            // 这样即便调用方绕过 updateCredential(_:) 直接写 store，两份凭证也保持一致。
            tokenStore.setCredentialObserver { [weak interceptor] newCredential in
                interceptor?.credential = newCredential
            }
        }

        interceptors.append(contentsOf: configuration.additionalInterceptors)

        let session = Session(
            configuration: sessionConfiguration,
            interceptor: Interceptor(interceptors: interceptors)
        )
        return (session, builtInInterceptor, authInterceptor)
    }

    /// 创建带校验的 Alamofire 请求。配置了业务失效码时追加自定义校验。
    func makeRequest(
        session: Session,
        url: String,
        method: HTTPMethod,
        parameters: [String: Any]?,
        encoding: ParameterEncoding?,
        headers: [String: String]?,
        expiredCodes: [Int]
    ) -> DataRequest {
        let resolvedEncoding = encoding ?? Self.defaultEncoding(for: method)
        let afHeaders = headers.map { HTTPHeaders($0) }

        let request = session.request(
            url, method: method, parameters: parameters,
            encoding: resolvedEncoding, headers: afHeaders
        )
        .validate(statusCode: 200..<300)

        // 业务码失效检测：命中失效码则让校验失败（抛 BOAuthValidationError），
        // 从而复用 401 的刷新重发机制。
        if !expiredCodes.isEmpty {
            request.validate { _, _, data in
                guard let data, !data.isEmpty else { return .success(()) }
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let code = obj["code"] as? Int,
                      expiredCodes.contains(code) else {
                    return .success(())
                }
                return .failure(BOAuthValidationError(businessCode: code))
            }
        }
        return request
    }

    /// 处理响应：清理注册表 → 识别取消 → 跑中间件链 → 解析 → 回调。
    func handleResponse<T: Decodable>(
        _ response: AFDataResponse<Data>,
        ticket: BORequestTicket,
        runtime: BONetRuntime,
        as type: T.Type,
        errorHandler: BOErrorHandlerProtocol?,
        completion: @escaping (Result<T, BONetError>) -> Void
    ) {
        // 无论结果如何，先从注册表移除，避免泄漏。
        unregisterTicket(id: ticket.id)
        if let request = ticket.underlyingRequest {
            runtime.requestInterceptor.removeRetryState(for: request)
        }

        // 被主动取消：直接回 .cancelled，不走解析。
        if let afError = response.error?.asAFError, afError.isExplicitlyCancelledError {
            deliver(.failure(.cancelled), to: errorHandler, completion: completion)
            return
        }

        var context = BOResponseContext(
            request: response.request,
            httpResponse: response.response,
            data: response.data,
            underlyingError: response.error,
            duration: response.metrics?.taskInterval.duration
        )

        // 以下全部使用发起时捕获的 runtime 快照，不回读 self，保证请求用发起时的配置处理。
        // 响应中间件链（日志、上报、改写、短路等横切逻辑）。
        let middlewares = runtime.configuration.responseMiddlewares
        if !middlewares.isEmpty {
            context = BOResponseMiddlewareChain.run(middlewares, context: context)
        }

        // 链后统一解析为业务模型，使用快照的解析器与解码器。
        let parser = runtime.configuration.responseParser
        let result = parser.parse(context, as: T.self, decoder: runtime.decoder)
        deliver(result, to: errorHandler, completion: completion)
    }

    /// 去重决策 + 预留（在单个临界区内原子完成，DEDUP-02）。
    /// - Returns: `shouldProceed` 是否应发起新请求；`ticketsToCancel` 需在锁外取消的旧请求。
    func reserveFingerprint(
        _ fingerprint: String,
        policy: BODeduplicationPolicy
    ) -> (shouldProceed: Bool, ticketsToCancel: [BORequestTicket]) {
        ticketsQueue.sync {
            // 「进行中」= 已注册的活动请求 或 已预留但尚未注册的指纹。
            let activeMatches = activeTickets.values.filter { $0.fingerprint == fingerprint }
            let existsInflight = !activeMatches.isEmpty || reservedFingerprints.contains(fingerprint)

            switch policy {
            case .discardNew:
                if existsInflight {
                    return (false, [])   // 已有相同请求，丢弃本次
                }
                reservedFingerprints.insert(fingerprint)   // 预留占位
                return (true, [])
            case .cancelPrevious:
                reservedFingerprints.insert(fingerprint)
                return (true, Array(activeMatches))         // 旧请求待锁外取消
            case .none:
                return (true, [])
            }
        }
    }

    /// 登记进行中请求，并清除其指纹的预留占位（若有）。
    func registerTicket(_ ticket: BORequestTicket) {
        ticketsQueue.sync {
            activeTickets[ticket.id] = ticket
            if let fp = ticket.fingerprint {
                reservedFingerprints.remove(fp)
            }
        }
    }

    /// 从注册表移除请求。
    func unregisterTicket(id: UUID) {
        ticketsQueue.sync { _ = activeTickets.removeValue(forKey: id) }
    }

    /// 在主线程回调结果，并在失败时经错误分发中心路由。
    func deliver<T>(
        _ result: Result<T, BONetError>,
        to errorHandler: BOErrorHandlerProtocol?,
        completion: @escaping (Result<T, BONetError>) -> Void
    ) {
        DispatchQueue.main.async {
            if case .failure(let error) = result {
                BOErrorDispatcher.shared.dispatch(error, to: errorHandler)
            }
            completion(result)
        }
    }

    /// 拼接最终请求 URL：完整 URL 独立解析；相对路径与 baseURL 的 path/query 结构化合并。
    static func resolveURL(path: String, baseURL: String) -> String {
        if let absolute = URLComponents(string: path),
           absolute.scheme != nil,
           absolute.host != nil {
            return absolute.string ?? path
        }

        guard var base = URLComponents(string: baseURL),
              base.scheme != nil,
              base.host != nil,
              let relative = URLComponents(string: path) else {
            return legacyResolvedURL(path: path, baseURL: baseURL)
        }

        if !relative.path.isEmpty {
            let basePath = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let relativePath = relative.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let segments = [basePath, relativePath].filter { !$0.isEmpty }
            base.path = segments.isEmpty ? "/" : "/" + segments.joined(separator: "/")
        }

        let queryItems = (base.queryItems ?? []) + (relative.queryItems ?? [])
        base.queryItems = queryItems.isEmpty ? nil : queryItems
        if let fragment = relative.fragment {
            base.fragment = fragment
        }

        return base.string ?? legacyResolvedURL(path: path, baseURL: baseURL)
    }

    /// URLComponents 无法解析非法输入时的兼容兜底。
    private static func legacyResolvedURL(path: String, baseURL: String) -> String {
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let trimmedPath = path.hasPrefix("/") ? path : "/\(path)"
        return trimmedBase + trimmedPath
    }

    /// 按 HTTP 方法选择默认参数编码：GET 用 URL 编码，其余用 JSON。
    static func defaultEncoding(for method: HTTPMethod) -> ParameterEncoding {
        method == .get ? URLEncoding.default : JSONEncoding.default
    }
}

// MARK: - Internal (供测试)

extension BONetClient {

    /// 计算请求去重指纹：method + 完整 URL + 规范化后的参数。
    ///
    /// 参数用 `JSONSerialization` 的 `.sortedKeys` 规范化——**嵌套字典的键也会递归排序**，
    /// 因此参数插入顺序不影响指纹（DEDUP-01）。无法序列化时回退到排序键值对拼接。
    static func fingerprint(
        method: HTTPMethod,
        url: String,
        parameters: [String: Any]?
    ) -> String {
        var parts = [method.rawValue, url]
        if let parameters, !parameters.isEmpty {
            parts.append(normalizedParameters(parameters))
        }
        return parts.joined(separator: "|")
    }

    /// 把参数规范化为稳定字符串：优先用 sortedKeys 的 JSON；失败则回退。
    static func normalizedParameters(_ parameters: [String: Any]) -> String {
        if JSONSerialization.isValidJSONObject(parameters),
           let data = try? JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return parameters.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
    }
}
