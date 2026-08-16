//
//  AppEnvironment.swift
//  BONetKitExample
//

import Foundation
import BONetKit

/// 示例 App 的共享环境。持有全局 token store，供配置、登录写入、请求读取共用同一来源。
enum AppEnvironment {

    /// 全局唯一的 token store（单一 token 来源）。
    ///
    /// 这里用内存 store，并初始放一个已过期的旧 token，以便每次启动都能复现
    /// /secure 的 401 → 自动刷新 → 重发 流程。
    ///
    /// 若需**持久化**（App 重启后 token 仍在），把下面替换为 `KeychainTokenStore` 即可：
    ///     static let tokenStore: BOTokenStore = KeychainTokenStore()
    /// 见 Session/KeychainTokenStore.swift。注意：持久化后旧 token 会被保留，
    /// 401 演示需先清除或写入过期凭证才能复现。
    static let tokenStore = BOInMemoryTokenStore(
        credential: BOCredential(
            accessToken: "old-token",
            refreshToken: "refresh-token",
            expiration: Date(timeIntervalSinceNow: -1)   // 已过期
        ),
        headerField: "Authorization",
        headerValueBuilder: { "Bearer \($0)" }
    )
}
