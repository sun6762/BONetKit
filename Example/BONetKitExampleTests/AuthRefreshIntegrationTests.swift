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

    /// 请求中间件加密 password，Mock 返回加密整包，响应中间件解密后应正常解析登录结果。
    func testRequestAndResponseEncryptionMiddlewareRoundTrip() {
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://mock.local",
                protocolClasses: [DemoMockURLProtocol.self],
                requestMiddlewares: [
                    DemoFieldEncryptionRequestMiddleware(fields: ["password"])
                ],
                responseMiddlewares: [DemoEncryptedResponseMiddleware()]
            )
        )

        let exp = expectation(description: "encryption middleware round trip")
        BONetClient.shared.request(
            "/login",
            method: .post,
            parameters: ["username": "demo", "password": "123456"],
            of: LoginResult.self
        ) { result in
            XCTAssertEqual(try? result.get().token, "mock-token-abc123")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

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

    /// 兜底回归：绕过 updateCredential，直接写 store.credential，也应自动同步给拦截器并鉴权成功。
    func testDirectStoreWriteSyncsToInterceptor() {
        let store = BOInMemoryTokenStore()
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://mock.local",
                tokenStore: store,
                tokenRefresh: { current, completion in
                    completion(.success(BOCredential(accessToken: DemoMockURLProtocol.freshAccessToken,
                                                     refreshToken: current.refreshToken,
                                                     expiration: Date(timeIntervalSinceNow: 3600))))
                },
                protocolClasses: [DemoMockURLProtocol.self]
            )
        )

        // 直接写 store（不调 updateCredential）——靠变化回调兜底同步给拦截器。
        store.credential = BOCredential(accessToken: DemoMockURLProtocol.freshAccessToken,
                                        refreshToken: "r",
                                        expiration: Date(timeIntervalSinceNow: 3600))

        let exp = expectation(description: "direct store write synced")
        BONetClient.shared.request("/secure", of: SecureModel.self) { result in
            if case .success = result {
                exp.fulfill()
            } else {
                XCTFail("直接写 store 应经回调兜底同步并鉴权成功")
            }
        }
        wait(for: [exp], timeout: 10)
    }

    /// AUTH-01 回归：启动时无凭证配置，登录后 updateCredential，无需重新 configure 即可鉴权成功。
    func testUpdateCredentialAfterLoginWithoutInitialCredential() {
        // 启动时 store 为空凭证（未登录）。
        let store = BOInMemoryTokenStore()
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://mock.local",
                tokenStore: store,
                tokenRefresh: { current, completion in
                    completion(.success(BOCredential(accessToken: DemoMockURLProtocol.freshAccessToken,
                                                     refreshToken: current.refreshToken,
                                                     expiration: Date(timeIntervalSinceNow: 3600))))
                },
                protocolClasses: [DemoMockURLProtocol.self]
            )
        )

        // 模拟登录成功：写入有效凭证（accessToken 即 mock 认可的 fresh token）。
        BONetClient.shared.updateCredential(
            BOCredential(accessToken: DemoMockURLProtocol.freshAccessToken,
                         refreshToken: "r",
                         expiration: Date(timeIntervalSinceNow: 3600))
        )

        // 不重新 configure，直接请求受保护接口，应携带 token 并成功。
        let exp = expectation(description: "auth after updateCredential")
        BONetClient.shared.request("/secure", of: SecureModel.self) { result in
            if case .success = result {
                exp.fulfill()
            } else {
                XCTFail("updateCredential 后应鉴权成功（AUTH-01）")
            }
        }
        wait(for: [exp], timeout: 10)
    }
}
