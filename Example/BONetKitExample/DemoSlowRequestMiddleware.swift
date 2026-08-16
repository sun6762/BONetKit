//
//  DemoSlowRequestMiddleware.swift
//  BONetKitExample
//

import Foundation
import BONetKit

/// 自定义响应中间件示范：标记慢请求。
///
/// 演示如何实现 `BOResponseMiddleware`——在 `next` 之后读取响应上下文，
/// 当耗时超过阈值时打印一条告警。它是只读观察，不改写响应。
///
/// 通过 `BONetConfiguration.responseMiddlewares` 传入即可加入响应中间件链。
/// 与内置的 `BOLoggingMiddleware` / `BOErrorReportingMiddleware` 组成一条链，
/// 按数组顺序（洋葱模型）执行。
struct DemoSlowRequestMiddleware: BOResponseMiddleware {

    /// 慢请求阈值（秒）。超过则告警。
    let threshold: TimeInterval

    init(threshold: TimeInterval = 1.0) {
        self.threshold = threshold
    }

    func process(
        _ context: BOResponseContext,
        next: (BOResponseContext) -> BOResponseContext
    ) -> BOResponseContext {
        // next 之前：可记录开始信息（这里从 context.duration 取耗时即可，无需自行计时）。
        let result = next(context)

        // next 之后：读取处理后的上下文，判断是否为慢请求。
        if let duration = result.duration, duration > threshold {
            let url = result.request?.url?.absoluteString ?? "?"
            print(String(format: "[慢请求告警] %@ 耗时 %.3fs（阈值 %.1fs）", url, duration, threshold))
        }

        return result
    }
}
