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

        // 注入公共请求头。
        for (field, value) in configuration.commonHeaders {
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

    /// 失败重试策略：仅对可重试的底层错误重试，且不超过配置的最大次数。
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

        // 仅对具备可重试性的 URLError（如超时、连接中断）重试。
        if let urlError = error.asAFError?.underlyingError as? URLError,
           Self.retryableURLErrorCodes.contains(urlError.code) {
            completion(.retryWithDelay(0.5))
        } else {
            completion(.doNotRetry)
        }
    }

    /// 可重试的 URLError 错误码集合。
    private static let retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost,
        .notConnectedToInternet,
        .cannotConnectToHost
    ]
}
