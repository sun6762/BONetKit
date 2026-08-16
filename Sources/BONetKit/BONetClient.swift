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

    /// 当前配置；调用 `configure(_:)` 后生效。
    private var configuration: BONetConfiguration?

    /// 底层 Alamofire 会话，随配置一同创建。
    private var session: Session?

    /// 用于解码后端响应的解码器。其键名转换策略在 `configure(_:)` 时按配置设定。
    private let decoder = JSONDecoder()

    /// 进行中请求的注册表：id → 句柄。用串行队列保护，保证线程安全。
    private var activeTickets: [UUID: BORequestTicket] = [:]
    private let ticketsQueue = DispatchQueue(label: "com.bonetkit.activetickets")

    // MARK: - Init

    private init() {}
}

// MARK: - Public Methods

public extension BONetClient {

    /// 使用给定配置初始化客户端。通常在 App 启动时调用一次。
    /// - Parameter configuration: 网络配置。
    func configure(_ configuration: BONetConfiguration) {
        self.configuration = configuration

        // 应用响应解码的键名转换策略（如 snake_case 转 camelCase）。
        decoder.keyDecodingStrategy = configuration.keyDecodingStrategy

        let sessionConfiguration = URLSessionConfiguration.af.default
        sessionConfiguration.timeoutIntervalForRequest = configuration.timeoutInterval

        // 注入自定义 URLProtocol（测试 / 本地 mock 用），置于最前以优先拦截。
        if !configuration.protocolClasses.isEmpty {
            let existing = sessionConfiguration.protocolClasses ?? []
            sessionConfiguration.protocolClasses = configuration.protocolClasses + existing
        }

        self.session = makeSession(configuration: configuration, sessionConfiguration: sessionConfiguration)
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
    ///   - deduplicate: 开启后，若已有相同请求进行中，取消旧的用新的。
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
        errorHandler: BOErrorHandlerProtocol? = nil,
        completion: @escaping (Result<T, BONetError>) -> Void
    ) -> BORequestTicket? {
        guard let session, let configuration else {
            deliver(.failure(.unknown(underlying: nil)), to: errorHandler, completion: completion)
            return nil
        }

        let url = Self.resolveURL(path: path, baseURL: configuration.baseURL)

        // 去重处理：按策略决定是否发起新请求。
        var fingerprint: String?
        if deduplication != .none {
            let fp = Self.fingerprint(method: method, url: url, parameters: parameters)
            fingerprint = fp
            switch deduplication {
            case .cancelPrevious:
                // 取消同指纹进行中的旧请求，随后照常发起新请求。
                cancelExistingRequests(fingerprint: fp)
            case .discardNew:
                // 已有相同请求进行中则丢弃本次：不发起，回调 .cancelled。
                if hasExistingRequest(fingerprint: fp) {
                    deliver(.failure(.cancelled), to: errorHandler, completion: completion)
                    return nil
                }
            case .none:
                break
            }
        }

        let request = makeRequest(
            session: session, url: url, method: method,
            parameters: parameters, encoding: encoding, headers: headers,
            expiredCodes: configuration.tokenExpiredBusinessCodes
        )

        // 创建票据并登记到注册表，供手动 / 分组取消 / 去重。
        let ticket = BORequestTicket(group: group, fingerprint: fingerprint, request: request)
        registerTicket(ticket)

        request.responseData { [weak self] response in
            self?.handleResponse(response, ticket: ticket, as: T.self,
                                 errorHandler: errorHandler, completion: completion)
        }

        return ticket
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
    ) -> Session {
        let builtInInterceptor = BORequestInterceptor(configuration: configuration)
        var interceptors: [RequestInterceptor] = [builtInInterceptor]

        if let tokenStore = configuration.tokenStore,
           let tokenRefresh = configuration.tokenRefresh,
           let credential = tokenStore.credential {
            let authenticator = BOAuthenticator(store: tokenStore, refreshHandler: tokenRefresh)
            interceptors.append(AuthenticationInterceptor(authenticator: authenticator, credential: credential))
        }

        interceptors.append(contentsOf: configuration.additionalInterceptors)

        return Session(
            configuration: sessionConfiguration,
            interceptor: Interceptor(interceptors: interceptors)
        )
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
        as type: T.Type,
        errorHandler: BOErrorHandlerProtocol?,
        completion: @escaping (Result<T, BONetError>) -> Void
    ) {
        // 无论结果如何，先从注册表移除，避免泄漏。
        unregisterTicket(id: ticket.id)

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

        // 响应中间件链（日志、上报、改写、短路等横切逻辑）。
        let middlewares = configuration?.responseMiddlewares ?? []
        if !middlewares.isEmpty {
            context = BOResponseMiddlewareChain.run(middlewares, context: context)
        }

        // 链后统一解析为业务模型。使用配置的解析器；缺失时兜底为默认解析器。
        let parser = configuration?.responseParser ?? BODefaultResponseParser()
        let result = parser.parse(context, as: T.self, decoder: decoder)
        deliver(result, to: errorHandler, completion: completion)
    }

    /// 是否存在同指纹的进行中请求（去重 discardNew 策略用）。
    func hasExistingRequest(fingerprint: String) -> Bool {
        ticketsQueue.sync {
            activeTickets.values.contains { $0.fingerprint == fingerprint }
        }
    }

    /// 取消与给定指纹相同的进行中请求（去重 cancelPrevious 策略用）。
    func cancelExistingRequests(fingerprint: String) {
        let targets = ticketsQueue.sync {
            activeTickets.values.filter { $0.fingerprint == fingerprint }
        }
        targets.forEach { $0.cancel() }
    }

    /// 登记进行中请求。
    func registerTicket(_ ticket: BORequestTicket) {
        ticketsQueue.sync { activeTickets[ticket.id] = ticket }
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

    /// 计算请求去重指纹：method + 完整 URL + 参数。
    static func fingerprint(
        method: HTTPMethod,
        url: String,
        parameters: [String: Any]?
    ) -> String {
        var parts = [method.rawValue, url]
        if let parameters, !parameters.isEmpty {
            let sorted = parameters.sorted { $0.key < $1.key }
            parts.append(sorted.map { "\($0.key)=\($0.value)" }.joined(separator: "&"))
        }
        return parts.joined(separator: "|")
    }

    /// 拼接最终请求 URL：`path` 为完整 URL 时直接使用，否则与 `baseURL` 拼接。
    static func resolveURL(path: String, baseURL: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let trimmedPath = path.hasPrefix("/") ? path : "/\(path)"
        return trimmedBase + trimmedPath
    }

    /// 按 HTTP 方法选择默认参数编码：GET 用 URL 编码，其余用 JSON。
    static func defaultEncoding(for method: HTTPMethod) -> ParameterEncoding {
        method == .get ? URLEncoding.default : JSONEncoding.default
    }
}
