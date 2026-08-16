//
//  KeychainTokenStore.swift
//  BONetKitExample
//

import Foundation
import BONetKit
import KeychainAccess

/// 持久化 token store 示范：把凭证整体存入 Keychain（生产级）。
///
/// 为什么三个字段（accessToken / refreshToken / expiration）统一存：
/// 它们是一个完整凭证，分开存会有一致性风险（如 access 存了、refresh 没存上，
/// 刷新链路就断了）。这里把 `BOCredential` 整体编码为 JSON，一次读写保证原子性。
///
/// 性能：Keychain 读写是毫秒级，比内存慢。因此内存中缓存一份，`credential` 读取
/// 优先走缓存（并发安全），只有写入与首次读取才访问 Keychain——兼顾持久化与高频读性能。
final class KeychainTokenStore: BOTokenStore, @unchecked Sendable {

    private let keychain: Keychain
    private let key = "com.bonetkit.example.credential"

    private let queue = DispatchQueue(label: "com.bonetkit.example.keychainstore", attributes: .concurrent)
    private var cache: BOCredential?
    private var cacheLoaded = false

    let headerField: String
    private let headerValueBuilder: (String) -> String

    init(
        headerField: String = "Authorization",
        headerValueBuilder: @escaping (String) -> String = { "Bearer \($0)" }
    ) {
        self.headerField = headerField
        self.headerValueBuilder = headerValueBuilder
        let service = Bundle.main.bundleIdentifier ?? "com.bonetkit.example"
        self.keychain = Keychain(service: service)
            .accessibility(.afterFirstUnlockThisDeviceOnly)
    }

    func headerValue(for accessToken: String) -> String {
        headerValueBuilder(accessToken)
    }

    var credential: BOCredential? {
        get {
            // 命中缓存直接返回；首次从 Keychain 惰性载入。
            let (loaded, cached) = queue.sync { (cacheLoaded, cache) }
            if loaded { return cached }

            let fromKeychain: BOCredential? = {
                guard let data = try? keychain.getData(key) else { return nil }
                return try? JSONDecoder().decode(BOCredential.self, from: data)
            }()
            queue.sync(flags: .barrier) {
                if !cacheLoaded { cache = fromKeychain; cacheLoaded = true }
            }
            return queue.sync { cache }
        }
        set {
            // 同时更新 Keychain（持久）与内存缓存（加速后续读取）。
            queue.async(flags: .barrier) { [self] in
                if let newValue, let data = try? JSONEncoder().encode(newValue) {
                    try? keychain.set(data, key: key)
                } else {
                    try? keychain.remove(key)
                }
                cache = newValue
                cacheLoaded = true
            }
        }
    }
}
