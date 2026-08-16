//
//  BONetError.swift
//  BONetKit
//

import Foundation

/// 统一的网络错误模型。
///
/// 将底层 Alamofire 错误、HTTP 状态码错误、解码错误和后端业务错误
/// 归拢为一种可判别的类型，便于调用方与错误分发中心统一处理。
public enum BONetError: Error {

    /// 网络层失败（连接失败、超时、被取消等），携带底层错误。
    case network(underlying: Error)

    /// HTTP 状态码非 2xx，携带状态码与原始响应数据。
    case httpStatus(code: Int, data: Data?)

    /// 响应体解码为目标模型失败，携带底层解码错误。
    case decoding(underlying: Error)

    /// 后端业务错误：统一结构中 `code != 0`，携带业务码、提示信息与附加数据。
    ///
    /// `userInfo` 用于携带 code / message 之外的额外信息（如后端返回的其他字段），
    /// 默认为空字典。构造时可用便利方法 `BONetError.business(code:message:)` 省略它。
    case business(code: Int, message: String, userInfo: [String: Any])

    /// 未收到有效响应数据。
    case emptyData

    /// 请求被主动取消（手动 cancel 或分组取消）。通常无需向用户提示为错误。
    case cancelled

    /// 其他未归类错误。
    case unknown(underlying: Error?)

    /// 构造业务错误的便利方法，`userInfo` 默认为空字典。
    ///
    /// enum 的关联值不支持默认值，故用本方法实现「默认不传 userInfo」。
    /// 方法名与 case 不同（`makeBusiness`）以避免与 case 构造器产生歧义。
    /// - Parameters:
    ///   - code: 业务码。
    ///   - message: 提示信息。
    ///   - userInfo: 附加数据，默认空。
    public static func makeBusiness(
        code: Int,
        message: String,
        userInfo: [String: Any] = [:]
    ) -> BONetError {
        .business(code: code, message: message, userInfo: userInfo)
    }
}

extension BONetError: LocalizedError {

    /// 面向调试与展示的错误描述。
    public var errorDescription: String? {
        switch self {
        case .network(let underlying):
            return "网络请求失败：\(underlying.localizedDescription)"
        case .httpStatus(let code, _):
            return "HTTP 状态码错误：\(code)"
        case .decoding(let underlying):
            return "响应解析失败：\(underlying.localizedDescription)"
        case .business(let code, let message, _):
            return "业务错误（\(code)）：\(message)"
        case .emptyData:
            return "未收到有效响应数据"
        case .cancelled:
            return "请求已取消"
        case .unknown(let underlying):
            return "未知错误：\(underlying?.localizedDescription ?? "无详情")"
        }
    }

    /// 是否为主动取消。
    public var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    /// 后端业务错误码；仅业务错误场景有值，便于分发中心按码路由。
    public var businessCode: Int? {
        if case .business(let code, _, _) = self {
            return code
        }
        return nil
    }

    /// 业务错误携带的附加数据；仅业务错误场景有值，其余为空字典。
    public var businessUserInfo: [String: Any] {
        if case .business(_, _, let userInfo) = self {
            return userInfo
        }
        return [:]
    }
}
