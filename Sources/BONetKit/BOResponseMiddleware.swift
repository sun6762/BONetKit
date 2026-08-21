//
//  BOResponseMiddleware.swift
//  BONetKit
//

import Foundation

/// 响应中间件处理的上下文（原始响应层，类型擦除，不含具体模型 `T`）。
///
/// 中间件在响应解析成业务模型**之前**介入，只面对原始数据与 HTTP 元信息，
/// 因此不受泛型模型类型的约束，可统一放进一个数组串成链。
public struct BOResponseContext {

    /// 发起的请求（可能为 nil）。
    public let request: URLRequest?

    /// HTTP 响应元信息：状态码、header 等（可能为 nil）。
    public let httpResponse: HTTPURLResponse?

    /// 原始响应体。中间件可读取或改写（例如解密、修正）。
    public var data: Data?

    /// 底层网络错误（连接失败、超时等）；无则为 nil。
    public var underlyingError: Error?

    /// 从发起到收到响应的耗时（秒），供日志类中间件使用（可能为 nil）。
    public var duration: TimeInterval?

    public init(
        request: URLRequest?,
        httpResponse: HTTPURLResponse?,
        data: Data?,
        underlyingError: Error?,
        duration: TimeInterval? = nil
    ) {
        self.request = request
        self.httpResponse = httpResponse
        self.data = data
        self.underlyingError = underlyingError
        self.duration = duration
    }
}

/// 响应中间件协议。
///
/// 采用「洋葱模型」：每个中间件在调用 `next(context)` 前后都可插入逻辑，
/// 可以观察、改写上下文，甚至不调用 `next` 以**短路**后续处理。
/// 多个中间件按数组顺序组成链，最外层最先进入、最后退出。
///
/// 定位：中间件处理**原始响应层**（`BOResponseContext`），在响应被解析为业务模型之前执行。
/// 适合日志、错误上报、响应体改写、按状态码短路等**横切关注点**；
/// 「解析成什么业务结构」不在这里，而是由链之后的解析步骤统一完成。
public protocol BOResponseMiddleware {

    /// 处理响应上下文。
    /// - Parameters:
    ///   - context: 当前响应上下文。
    ///   - next: 调用它把（可能已改写的）上下文传给链上的下一个中间件；
    ///           不调用则短路后续中间件。
    /// - Returns: 处理后的上下文。
    func process(
        _ context: BOResponseContext,
        next: (BOResponseContext) -> BOResponseContext
    ) -> BOResponseContext
}

// MARK: - 链执行器

enum BOResponseMiddlewareChain {

    /// 按顺序执行中间件链（洋葱模型）。
    /// - Parameters:
    ///   - middlewares: 中间件数组，靠前的在洋葱外层（最先进入、最后退出）。
    ///   - context: 初始上下文。
    /// - Returns: 全链处理后的上下文。
    static func run(
        _ middlewares: [BOResponseMiddleware],
        context: BOResponseContext
    ) -> BOResponseContext {
        // 链尾：没有更多中间件时，原样返回上下文。
        var next: (BOResponseContext) -> BOResponseContext = { $0 }

        // 从后往前包裹，形成嵌套调用；最终 next 即为最外层（数组第一个）中间件。
        for middleware in middlewares.reversed() {
            let currentNext = next
            next = { ctx in middleware.process(ctx, next: currentNext) }
        }

        return next(context)
    }
}

// MARK: - 内置中间件：日志

/// 日志中间件（只读观察）：打印请求 URL、状态码、耗时与原始响应体。
///
/// 仅用于调试。它不改写上下文，调用 `next` 后打印结果。
public struct BOLoggingMiddleware: BOResponseMiddleware {

    /// 是否打印响应体内容（可能较大，且可能含敏感信息）。
    public let logsBody: Bool

    /// - Parameter logsBody: 是否打印响应体。默认值随构建配置而定：
    ///   **DEBUG 默认 true，Release 默认 false**——避免生产环境把响应体（可能含
    ///   token / 手机号等敏感数据）写入系统日志（LOG-01）。显式传值可覆盖默认。
    public init(logsBody: Bool? = nil) {
        if let logsBody {
            self.logsBody = logsBody
        } else {
            #if DEBUG
            self.logsBody = true
            #else
            self.logsBody = false
            #endif
        }
    }

    public func process(
        _ context: BOResponseContext,
        next: (BOResponseContext) -> BOResponseContext
    ) -> BOResponseContext {
        let result = next(context)

        let method = result.request?.httpMethod ?? "?"
        let url = result.request?.url?.absoluteString ?? "?"
        let status = result.httpResponse?.statusCode.description ?? "-"
        let durationText = result.duration.map { String(format: "%.3fs", $0) } ?? "-"

        var lines = ["[BONet] \(method) \(url) → \(status) (\(durationText))"]
        if let error = result.underlyingError {
            lines.append("  error: \(error.localizedDescription)")
        }
        if logsBody, let data = result.data, let body = String(data: data, encoding: .utf8) {
            lines.append("  body: \(body)")
        }
        print(lines.joined(separator: "\n"))

        return result
    }
}

// MARK: - 内置中间件：错误上报

/// 错误上报中间件（只读观察）：当响应存在网络错误或非 2xx 状态码时，回调上报钩子。
///
/// 它不改变处理结果，仅把「疑似失败的响应」抛给使用方提供的上报闭包
/// （可对接自有的埋点 / 监控系统）。是否为业务错误（如 code != 0）在解析阶段判定，
/// 不在此处；本中间件只覆盖原始层可见的失败（网络错误、HTTP 状态码）。
public struct BOErrorReportingMiddleware: BOResponseMiddleware {

    /// 上报回调：参数为发生问题的上下文。
    public let report: (BOResponseContext) -> Void

    public init(report: @escaping (BOResponseContext) -> Void) {
        self.report = report
    }

    public func process(
        _ context: BOResponseContext,
        next: (BOResponseContext) -> BOResponseContext
    ) -> BOResponseContext {
        let result = next(context)

        let hasNetworkError = result.underlyingError != nil
        let hasHTTPError: Bool = {
            guard let code = result.httpResponse?.statusCode else { return false }
            return !(200..<300).contains(code)
        }()

        if hasNetworkError || hasHTTPError {
            report(result)
        }

        return result
    }
}
