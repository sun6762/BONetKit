//
//  DemoEncryptionMiddleware.swift
//  BONetKitExample
//

import Foundation
import BONetKit

/// 示例请求中间件：在 Alamofire 编码前，对指定字符串字段做 Base64 转换。
/// Base64 仅用于展示“字段级处理”的执行位置，不代表生产级加密算法。
struct DemoFieldEncryptionRequestMiddleware: BORequestMiddleware {
    let fields: Set<String>

    func process(_ context: BORequestContext) -> BORequestContext {
        var result = context
        var didEncrypt = false

        for field in fields {
            guard let value = result.parameters?[field] as? String,
                  let data = value.data(using: .utf8) else { continue }
            result.parameters?[field] = data.base64EncodedString()
            didEncrypt = true
        }

        if didEncrypt {
            result.headers["X-Demo-Request-Encrypted"] = "1"
        }
        return result
    }
}

/// 示例响应中间件：默认解析器运行前，解开 Mock 服务返回的 Base64 整包响应。
struct DemoEncryptedResponseMiddleware: BOResponseMiddleware {
    func process(
        _ context: BOResponseContext,
        next: (BOResponseContext) -> BOResponseContext
    ) -> BOResponseContext {
        guard context.httpResponse?.value(forHTTPHeaderField: "X-Demo-Response-Encrypted") == "1",
              let data = context.data,
              let encoded = String(data: data, encoding: .utf8),
              let decoded = Data(base64Encoded: encoded) else {
            return next(context)
        }

        var result = context
        result.data = decoded
        return next(result)
    }
}
