//
//  AuthRefreshIntegrationTests.swift
//  BONetKitExampleTests
//
//  401 自动刷新集成测试：复用 DemoMockURLProtocol 的 /secure 与刷新逻辑。
//  说明：这类测试依赖异步刷新时序，相对纯逻辑测试更易受环境影响。
//

import XCTest
import BONetKit
@testable import BONetKitExample

private struct SecureModel: Decodable { let id: Int }

final class AuthRefreshIntegrationTests: XCTestCase {

    /// 构造一个带过期旧 token 的 store + 刷新处理器（返回新 token）。
    private func makeConfig() -> BONetConfiguration {
        let store = BOInMemoryTokenStore(
            credential: BOCredential(
                accessToken: "old-token",
                refreshToken: "refresh-token",
                expiration: Date(timeIntervalSinceNow: -1)   // 已过期
            )
        )
        return BONetConfiguration(
            baseURL: "https://mock.local",
            tokenStore: store,
            tokenRefresh: { current, completion in
                // 直接返回带新 accessToken 的凭证（不再发真实请求，聚焦刷新重发时序）。
                completion(.success(BOCredential(
                    accessToken: DemoMockURLProtocol.freshAccessToken,
                    refreshToken: current.refreshToken,
                    expiration: Date(timeIntervalSinceNow: 3600)
                )))
            },
            protocolClasses: [DemoMockURLProtocol.self]
        )
    }

    /// /secure 首次带旧 token → 401 → 自动刷新 → 用新 token 重发 → 成功。
    func testAuthRefreshOn401Succeeds() {
        BONetClient.shared.configure(makeConfig())

        let exp = expectation(description: "auth refresh success")
        BONetClient.shared.request("/secure", of: SecureModel.self) { result in
            if case .success = result {
                exp.fulfill()
            } else {
                XCTFail("401 刷新后应成功")
            }
        }
        wait(for: [exp], timeout: 10)
    }

    /// 业务码失效（HTTP 200 + code 40101）也应触发刷新重发。
    func testBusinessCodeRefreshSucceeds() {
        let store = BOInMemoryTokenStore(
            credential: BOCredential(accessToken: "old-token", refreshToken: "r",
                                     expiration: Date(timeIntervalSinceNow: 3600))
        )
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://mock.local",
                tokenStore: store,
                tokenRefresh: { current, completion in
                    completion(.success(BOCredential(
                        accessToken: DemoMockURLProtocol.freshAccessToken,
                        refreshToken: current.refreshToken,
                        expiration: Date(timeIntervalSinceNow: 3600))))
                },
                tokenExpiredBusinessCodes: [40101],
                protocolClasses: [DemoMockURLProtocol.self]
            )
        )

        let exp = expectation(description: "biz code refresh success")
        BONetClient.shared.request("/secure-bizfail", of: SecureModel.self) { result in
            if case .success = result {
                exp.fulfill()
            } else {
                XCTFail("业务码失效刷新后应成功")
            }
        }
        wait(for: [exp], timeout: 10)
    }
}
