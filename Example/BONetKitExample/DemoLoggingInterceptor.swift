//
//  DemoLoggingInterceptor.swift
//  BONetKitExample
//

import Foundation
import Alamofire

/// 示例自定义请求拦截器：演示如何把用户自己的拦截器传入 BONetKit 统一处理。
///
/// - `adapt`：为每个请求追加一个自定义头，并打印请求日志。
/// - `retry`：不参与重试，交回给链上的其他拦截器（返回 `.doNotRetry`）。
///
/// 通过 `BONetConfiguration.additionalInterceptors` 传入即可生效；
/// 它会排在库内置拦截器之后执行（即公共头 / token 已注入后，再由本拦截器加工）。
final class DemoLoggingInterceptor: RequestInterceptor {

    func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping (Result<URLRequest, Error>) -> Void
    ) {
        var request = urlRequest
        // 追加业务自定义头，演示在库内置注入之后继续加工请求。
        request.setValue("BONetKitExample", forHTTPHeaderField: "X-Demo-Client")

        let method = request.httpMethod ?? "?"
        let url = request.url?.absoluteString ?? "?"
        print("[DemoLoggingInterceptor] → \(method) \(url)")

        completion(.success(request))
    }

    func retry(
        _ request: Request,
        for session: Session,
        dueTo error: Error,
        completion: @escaping (RetryResult) -> Void
    ) {
        // 本拦截器不介入重试，交由链上其他拦截器（如库内置的重试逻辑）决定。
        completion(.doNotRetry)
    }
}
