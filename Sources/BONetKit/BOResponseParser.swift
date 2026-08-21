//
//  BOResponseParser.swift
//  BONetKit
//

import Foundation

/// 响应解析器协议：把（经中间件链处理后的）原始响应解析为业务模型。
///
/// 这是「后端业务结构」的可插拔点。默认实现按 `{ code, message, data }` 解析，
/// 若后端采用其他结构（如 `{ status, result, msg }`、裸对象、裸数组等），
/// 可实现本协议并通过 `BONetConfiguration.responseParser` 注入自定义解析。
///
/// 执行位置：**固定在响应中间件链之后**。中间件负责横切逻辑（日志、上报、改写、短路），
/// 解析器负责「原始数据 → 业务模型 / 业务错误」的结构转换。二者职责分离，顺序固定。
public protocol BOResponseParser {

    /// 将响应上下文解析为目标模型。
    /// - Parameters:
    ///   - context: 经中间件链处理后的原始响应上下文。
    ///   - type: 目标模型类型。
    ///   - decoder: 库配置好的解码器（已应用 `keyDecodingStrategy`）。
    /// - Returns: 成功模型或 `BONetError`。
    func parse<T: Decodable>(
        _ context: BOResponseContext,
        as type: T.Type,
        decoder: JSONDecoder
    ) -> Result<T, BONetError>
}

/// 默认解析器：按后端统一结构 `{ code, message, data }` 解析。
///
/// 处理顺序（关键：先判业务码，再按需解码 `data`）：
/// 网络错误 → HTTP 状态码错误 → 空数据 → **解外层读 code/message/原始 data**
/// → 业务失败则直接返回 `.business`（不依赖成功模型 T）
/// → 业务成功才把原始 `data` 解码为 `T`。
///
/// 这样可避免「失败响应的 data 与成功模型 T 不匹配时，业务错误被误报为解码错误」。
public struct BODefaultResponseParser: BOResponseParser {

    /// 判定业务成功的规则，默认 `code == 0`。可自定义以适配不同后端。
    private let isSuccessCode: (Int) -> Bool

    /// - Parameter isSuccessCode: 给定业务码返回是否成功，默认 `$0 == 0`。
    public init(isSuccessCode: @escaping (Int) -> Bool = { $0 == 0 }) {
        self.isSuccessCode = isSuccessCode
    }

    public func parse<T: Decodable>(
        _ context: BOResponseContext,
        as type: T.Type,
        decoder: JSONDecoder
    ) -> Result<T, BONetError> {
        // 网络层错误优先。
        if let underlyingError = context.underlyingError {
            if let statusCode = context.httpResponse?.statusCode,
               !(200..<300).contains(statusCode) {
                return .failure(.httpStatus(code: statusCode, data: context.data))
            }
            return .failure(.network(underlying: underlyingError))
        }

        // 无网络错误但状态码非 2xx。
        if let statusCode = context.httpResponse?.statusCode,
           !(200..<300).contains(statusCode) {
            return .failure(.httpStatus(code: statusCode, data: context.data))
        }

        guard let data = context.data, !data.isEmpty else {
            return .failure(.emptyData)
        }

        // 第一步：只解外层，读 code / message / 原始 data（不涉及成功模型 T）。
        let envelope: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.decoding(underlying: BOParseError.notObject))
            }
            envelope = obj
        } catch {
            return .failure(.decoding(underlying: error))
        }

        let code = (envelope["code"] as? Int) ?? -1
        let message = (envelope["message"] as? String) ?? ""

        // 第二步：先判业务码。失败直接返回 .business，并把 data 内容作为附加信息保留，
        // 完全不依赖成功模型 T。
        guard isSuccessCode(code) else {
            let userInfo = (envelope["data"] as? [String: Any]) ?? [:]
            return .failure(.makeBusiness(code: code, message: message, userInfo: userInfo))
        }

        // 第三步：业务成功，才把原始 data 解码为 T。
        guard let dataValue = envelope["data"], !(dataValue is NSNull) else {
            return .failure(.emptyData)
        }
        do {
            // 把 data 那一段重新序列化，再用配置好的 decoder 解成 T（保持 keyDecodingStrategy 等设置）。
            // fragmentsAllowed：兼容 data 为标量（数字/字符串/布尔）的情况。
            let dataData = try JSONSerialization.data(withJSONObject: dataValue, options: [.fragmentsAllowed])
            let payload = try decoder.decode(T.self, from: dataData)
            return .success(payload)
        } catch {
            return .failure(.decoding(underlying: error))
        }
    }
}

/// 解析器内部错误。
enum BOParseError: Error {
    /// 响应体顶层不是 JSON 对象。
    case notObject
}
