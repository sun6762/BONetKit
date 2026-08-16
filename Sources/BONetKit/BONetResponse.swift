//
//  BONetResponse.swift
//  BONetKit
//

import Foundation

/// 后端统一响应结构：`{ "code": 0, "message": "ok", "data": { ... } }`。
///
/// 泛型 `T` 对应 `data` 字段的业务模型。响应拦截器会先将原始数据解码为该结构，
/// 再根据 `code` 判定成功与否。
public struct BONetResponse<T: Decodable>: Decodable {

    /// 业务状态码；约定 `0` 表示成功。
    public let code: Int

    /// 提示信息。
    public let message: String

    /// 业务数据；失败或无数据时可能为空。
    public let data: T?

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(Int.self, forKey: .code) ?? -1
        // 兼容后端可能缺省 message 的情况。
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        data = try container.decodeIfPresent(T.self, forKey: .data)
    }

    /// 约定的成功判定：`code == 0`。
    public var isSuccess: Bool {
        code == 0
    }
}
