//
//  BORequestInterceptor.swift
//  BONetKit
//

import Foundation
import Alamofire

/// 请求拦截器。
///
/// - `adapt`：为每个请求注入公共请求头与鉴权 token。
/// - `retry`：对可重试的失败按配置的最大次数进行重试。
///
/// 标注为 `@unchecked Sendable`：本类型仅持有一份初始化后不再修改的 `configuration`，
/// 拦截器方法只读取配置、不改变自身状态，因此跨并发域使用是安全的。
/// （`BONetConfiguration` 因持有 Alamofire 未标 `Sendable` 的拦截器数组而无法自动推断为
/// `Sendable`，故在此显式声明本类型的线程安全性。）
final class BORequestInterceptor: RequestInterceptor, @unchecked Sendable {

    private let configuration: BONetConfiguration

    init(configuration: BONetConfiguration) {
        self.configuration = configuration
    }

    /// 在请求发出前注入公共头与鉴权信息。
    func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping (Result<URLRequest, Error>) -> Void
    ) {
        var request = urlRequest

        // 注入公共请求头。单次请求头优先：仅当该字段尚不存在时才写入公共值，
        // 避免公共头覆盖调用方在本次请求显式设置的同名头（HEADER-01）。
        // `value(forHTTPHeaderField:)` 大小写不敏感，天然按 HTTP 规范匹配。
        for (field, value) in configuration.commonHeaders
        where request.value(forHTTPHeaderField: field) == nil {
            request.setValue(value, forHTTPHeaderField: field)
        }

        // 注入鉴权 token：从单一来源 tokenStore 读取。
        // 注意：当配置了刷新（tokenRefresh）时，token 的注入与刷新统一交由认证拦截器负责，
        // 这里不再注入，避免与其重复。二者读写的是同一个 tokenStore，不存在冲突。
        if configuration.tokenRefresh == nil,
           let credential = configuration.tokenStore?.credential,
           !credential.accessToken.isEmpty,
           let store = configuration.tokenStore {
            let value = store.headerValue(for: credential.accessToken)
            request.setValue(value, forHTTPHeaderField: store.headerField)
        }
        
        completion(.success(request))
    }

    /// 失败重试策略。
    ///
    /// 安全约束（RETRY-01）：默认只对**幂等方法**（GET/HEAD/PUT/DELETE/OPTIONS/TRACE）自动重试；
    /// POST/PATCH 等非幂等方法默认不重试，避免重复下单/支付/提交等副作用。
    /// 若某个非幂等请求确认可安全重试，可在 `request(...)` 时开启 `allowsRetryOnNonIdempotent`。
    ///
    /// 重试延迟采用指数退避 + 随机抖动，而非固定间隔。
    func retry(
        _ request: Request,
        for session: Session,
        dueTo error: Error,
        completion: @escaping (RetryResult) -> Void
    ) {
        // 达到最大重试次数则不再重试。
        guard request.retryCount < configuration.maxRetryCount else {
            completion(.doNotRetry)
            return
        }

        // 仅对可重试的底层 URLError（超时、连接中断等）重试。
        guard let urlError = error.asAFError?.underlyingError as? URLError,
              Self.retryableURLErrorCodes.contains(urlError.code) else {
            completion(.doNotRetry)
            return
        }

        // 幂等性检查：非幂等方法默认不重试，除非请求显式开启。
        let method = request.request?.httpMethod?.uppercased() ?? "GET"
        let isIdempotent = Self.idempotentMethods.contains(method)
        let explicitlyAllowed = request.request?
            .value(forHTTPHeaderField: Self.allowRetryHeader) == "1"
        guard isIdempotent || explicitlyAllowed else {
            completion(.doNotRetry)
            return
        }

        completion(.retryWithDelay(Self.backoffDelay(forRetryCount: request.retryCount)))
    }

    /// 幂等 HTTP 方法（可安全自动重试）。
    private static let idempotentMethods: Set<String> = [
        "GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"
    ]

    /// 标记「本请求允许在非幂等方法下重试」的内部请求头。
    static let allowRetryHeader = "X-BONet-Allow-Retry"

    /// 可重试的 URLError 错误码集合。
    private static let retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost,
        .notConnectedToInternet,
        .cannotConnectToHost
    ]

    /// 指数退避 + 随机抖动：base * 2^retryCount + [0, 0.5) 随机抖动，上限 30s。
    private static func backoffDelay(forRetryCount retryCount: Int) -> TimeInterval {
        let base = 0.5
        let exponential = base * pow(2.0, Double(retryCount))
        let jitter = Double.random(in: 0..<0.5)
        return min(exponential + jitter, 30)
    }
}
