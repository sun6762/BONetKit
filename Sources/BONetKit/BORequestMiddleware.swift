//
//  BORequestMiddleware.swift
//  BONetKit
//

import Foundation
import Alamofire

/// 请求中间件处理的上下文（编码前的结构化请求信息，可读可改）。
///
/// 与「Alamofire 请求拦截器」处理的层不同：中间件在参数**被编码成 URLRequest 之前**执行，
/// 拿到的是结构化的 `parameters` / `headers`，因此可做字段级加密、签名、加公共参数等；
/// 而拦截器在编码后处理 `URLRequest`（如注入 token）。二者互补。
public struct BORequestContext {

    /// 请求路径（相对或完整 URL）。
    public var path: String

    /// HTTP 方法。
    public var method: HTTPMethod

    /// 请求参数（结构化，可增删改，用于字段级加密 / 加签名参数等）。
    public var parameters: [String: Any]?

    /// 本次请求的附加请求头（可增改）。
    public var headers: [String: String]

    /// 请求分组标识，仅供中间件读取。
    public let group: String?

    /// 请求去重策略，仅供中间件读取。
    public let deduplication: BODeduplicationPolicy

    public init(
        path: String,
        method: HTTPMethod,
        parameters: [String: Any]?,
        headers: [String: String],
        group: String? = nil,
        deduplication: BODeduplicationPolicy = .none
    ) {
        self.path = path
        self.method = method
        self.parameters = parameters
        self.headers = headers
        self.group = group
        self.deduplication = deduplication
    }
}

/// 请求中间件协议。
///
/// 在请求参数被编码之前执行，可读取并修改请求上下文（参数、请求头等）。
/// 多个中间件按数组顺序依次处理（上一个的输出作为下一个的输入），同步执行。
/// 适合：字段级加密、请求签名、统一注入业务参数、埋点等。
public protocol BORequestMiddleware {

    /// 处理并返回（可能已修改的）请求上下文。
    /// - Parameter context: 当前请求上下文。
    /// - Returns: 处理后的上下文，传给下一个中间件或用于最终发起请求。
    func process(_ context: BORequestContext) -> BORequestContext
}

enum BORequestMiddlewareChain {

    /// 按数组顺序依次执行请求中间件（上一个输出作为下一个输入）。
    static func run(
        _ middlewares: [BORequestMiddleware],
        context: BORequestContext
    ) -> BORequestContext {
        middlewares.reduce(context) { ctx, middleware in
            middleware.process(ctx)
        }
    }
}
