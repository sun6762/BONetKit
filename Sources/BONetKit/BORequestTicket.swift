//
//  BORequestTicket.swift
//  BONetKit
//

import Foundation
import Alamofire

/// 请求去重策略：当已有「相同请求」进行中时如何处理新请求。
public enum BODeduplicationPolicy {
    /// 不去重（默认调用时不开启即为此语义）。
    case none
    /// 取消旧的、发起新的（适合搜索 / 筛选：新请求作废旧请求）。默认策略。
    case cancelPrevious
    /// 丢弃新的、保留旧的（适合防重复提交：已有相同请求在跑就不再发）。
    case discardNew
}

/// 请求票据：调用 `request(...)` 的返回值，用于取消对应请求。
///
/// 持有它即可在任意时机取消该请求（如页面退出、搜索词变化）。
/// 请求完成后再次 `cancel()` 无副作用。
///
/// 命名说明：用「票据（Ticket）」而非「token」，避免与登录鉴权的
/// accessToken / refreshToken 混淆。
public final class BORequestTicket {

    /// 句柄唯一标识。
    public let id: UUID

    /// 所属分组（可空）。用于按组批量取消。
    public let group: String?

    /// 去重指纹（可空）。仅在开启去重时有值，用于识别「相同请求」。
    let fingerprint: String?

    /// 底层 Alamofire 请求。弱引用，避免与 Session 的持有形成环。
    private weak var request: Request?

    init(id: UUID = UUID(), group: String?, fingerprint: String? = nil, request: Request) {
        self.id = id
        self.group = group
        self.fingerprint = fingerprint
        self.request = request
    }

    /// 取消该请求。已完成或已取消时调用无副作用。
    public func cancel() {
        request?.cancel()
    }

    /// 请求是否已结束（完成或取消）。
    public var isFinished: Bool {
        guard let request else { return true }
        return request.isCancelled || request.isFinished
    }
}
