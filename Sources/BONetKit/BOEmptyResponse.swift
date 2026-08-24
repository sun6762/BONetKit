//
//  BOEmptyResponse.swift
//  BONetKit
//

import Foundation

/// 表示调用方预期接口成功时不返回业务数据。
///
/// 适用于 HTTP 204，或其他合法 2xx 但响应体为空的接口。
public struct BOEmptyResponse: Decodable, Equatable, Sendable {
    public init() {}
}
