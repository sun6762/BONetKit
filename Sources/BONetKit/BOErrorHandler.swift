//
//  BOErrorHandler.swift
//  BONetKit
//

import UIKit

/// 错误处理协议。业务控制器可遵守该协议并实现 `handleError(_:)`，
/// 以接管网络错误的展示与处理。
@MainActor
public protocol BOErrorHandlerProtocol: AnyObject {

    /// 处理一个网络错误。
    /// - Parameter error: 统一错误模型。
    /// - Returns: 是否已消费该错误。返回 `false` 时，分发中心会继续走全局兜底处理。
    @discardableResult
    func handleError(_ error: BONetError) -> Bool
}

/// 错误分发中心。
///
/// 网络请求失败时，分发中心负责把 `BONetError` 路由给合适的
/// `BOErrorHandlerProtocol` 处理者，并在无人处理时执行全局兜底。
///
/// 说明：把错误精确分发到「哪个业务控制器」的定位策略尚未定稿
/// （自动查找顶层控制器，或由调用方显式传入）。当前先提供两种可用入口：
/// - 请求时显式传入 `errorHandler`；
/// - 设置全局兜底 `fallbackHandler`。
/// 待整体功能跑通后再定稿自动定位策略。
@MainActor
public final class BOErrorDispatcher {

    /// 全局共享分发中心。
    public static let shared = BOErrorDispatcher()

    /// 全局兜底错误处理闭包；当没有具体处理者消费错误时调用。
    public var fallbackHandler: ((BONetError) -> Void)?

    private init() {}

    /// 分发一个错误。
    /// - Parameters:
    ///   - error: 待处理的错误。
    ///   - handler: 本次请求指定的处理者（通常是发起请求的业务控制器），可为空。
    func dispatch(_ error: BONetError, to handler: BOErrorHandlerProtocol?) {
        // 取消和去重是预期控制流，只通过请求 completion 返回，不触发业务错误提示或上报。
        guard !error.isCancelled, !error.isDeduplicated else { return }

        // 优先交给显式指定的处理者；其未消费时走全局兜底。
        if let handler, handler.handleError(error) {
            return
        }
        fallbackHandler?(error)
    }
}
