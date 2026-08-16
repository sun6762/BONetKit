//
//  UserSessionKeychain.swift
//  BONetKitExample
//

import Foundation
import KeychainAccess

/// 登录态存储 —— 写法 D：Keychain 持久化 + 内存缓存（生产级）。
///
/// 这是面向真实项目的推荐实现，兼顾**安全**与**性能**：
/// - **安全**：token 属于敏感凭证，持久化到 Keychain（加密存储），而非 UserDefaults（明文）。
/// - **性能**：每次网络请求的 `tokenProvider` 都会同步读取 token，若直接读 Keychain
///   （毫秒级、涉及系统加密操作）在高频请求下开销累积。因此在内存中维护一份缓存，
///   高频读走内存（纳秒级），仅在写入 / 首次读取时访问 Keychain。
///
/// 双层结构：
/// - 持久层：`KeychainAccess.Keychain`，权威存储，App 重启后仍在。
/// - 缓存层：并发队列 + barrier 保护的内存变量，供 `tokenProvider` 快速同步读取。
///
/// 线程安全：内存缓存用「并发读 + barrier 写」保护（读可并行、写独占），
/// 与 `UserSessionBarrier` 同一策略；Keychain 本身也是线程安全的。
///
/// Accessibility 选型：使用 `.afterFirstUnlockThisDeviceOnly`——
/// - `afterFirstUnlock`：设备重启后只要用户解锁过一次即可读取，保证后台任务 / 启动流程可用；
/// - `ThisDeviceOnly`：不随 iCloud / iTunes 备份迁移到其他设备，降低凭证外泄风险。
///
/// 读写调用方法（均为同步，可直接用于 `tokenProvider`）：
/// ```swift
/// // 登录成功后写入：
/// UserSessionKeychain.shared.token = loginResult.token
///
/// // 读取（例如配置 tokenProvider）：
/// tokenProvider: { UserSessionKeychain.shared.token }
///
/// // 退出登录清除：
/// UserSessionKeychain.shared.clear()
/// ```
final class UserSessionKeychain {

    static let shared = UserSessionKeychain()

    /// Keychain 中存储 token 的键名。
    private let tokenKey = "com.bonetkit.example.authToken"

    /// KeychainAccess 实例。以 bundle id 作为 service 维度，并设定 accessibility。
    private let keychain: Keychain

    /// 保护内存缓存的并发队列（读并行、写 barrier 独占）。
    private let queue = DispatchQueue(
        label: "com.bonetkit.example.session.keychain",
        attributes: .concurrent
    )

    /// 内存缓存。首次读取时从 Keychain 惰性载入。
    private var cachedToken: String?

    /// 标记缓存是否已从 Keychain 载入过，避免重复读取 Keychain。
    private var isCacheLoaded = false

    private init() {
        let service = Bundle.main.bundleIdentifier ?? "com.bonetkit.example"
        self.keychain = Keychain(service: service)
            .accessibility(.afterFirstUnlockThisDeviceOnly)
    }

    /// 线程安全的 token 访问。
    ///
    /// - 读：优先返回内存缓存；首次读取时从 Keychain 惰性载入并回填缓存。
    /// - 写：同时更新 Keychain（持久）与内存缓存（加速后续读取）。
    var token: String? {
        get { loadTokenIfNeeded() }
        set { store(newValue) }
    }

    /// 清除 token（退出登录）。同时清空 Keychain 与内存缓存。
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            // 移除 Keychain 中的持久值；失败仅记录，不中断流程。
            do {
                try self.keychain.remove(self.tokenKey)
            } catch {
                print("[UserSessionKeychain] 清除 Keychain 失败：\(error)")
            }
            self.cachedToken = nil
            self.isCacheLoaded = true
        }
    }

    // MARK: - 内部实现

    /// 读取 token：命中缓存直接返回；否则从 Keychain 载入一次并回填。
    private func loadTokenIfNeeded() -> String? {
        // 并发 sync 读：多个读可并行。
        let (loaded, cached) = queue.sync { (isCacheLoaded, cachedToken) }
        if loaded {
            return cached
        }

        // 未载入过：从 Keychain 读取（可能较慢），再用 barrier 写回缓存。
        let tokenFromKeychain = try? keychain.get(tokenKey)
        queue.sync(flags: .barrier) {
            // 双重检查：避免并发下重复载入覆盖已写入的新值。
            if !isCacheLoaded {
                cachedToken = tokenFromKeychain
                isCacheLoaded = true
            }
        }
        return queue.sync { cachedToken }
    }

    /// 写入 token：更新 Keychain 与内存缓存。
    private func store(_ newValue: String?) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            do {
                if let value = newValue, !value.isEmpty {
                    try self.keychain.set(value, key: self.tokenKey)
                } else {
                    // 传入 nil / 空串视为清除。
                    try self.keychain.remove(self.tokenKey)
                }
            } catch {
                print("[UserSessionKeychain] 写入 Keychain 失败：\(error)")
            }
            self.cachedToken = newValue
            self.isCacheLoaded = true
        }
    }
}
