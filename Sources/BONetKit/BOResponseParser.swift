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

/// 默认解析器：按后端统一结构 `{ code, message, data }` 解析，`code == 0` 视为成功。
///
/// 处理顺序：网络错误 → HTTP 状态码错误 → 空数据 → 解码统一结构 → 校验业务码 → 取 `data`。
public struct BODefaultResponseParser: BOResponseParser {

    public init() {}

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

        do {
            let wrapper = try decoder.decode(BONetResponse<T>.self, from: data)
            guard wrapper.isSuccess else {
                return .failure(.makeBusiness(code: wrapper.code, message: wrapper.message))
            }
            guard let payload = wrapper.data else {
                return .failure(.emptyData)
            }
            return .success(payload)
        } catch {
            return .failure(.decoding(underlying: error))
        }
    }
}
