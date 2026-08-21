//
//  RetryIntegrationTests.swift
//  BONetKitExampleTests
//
//  弱网重试集成测试：复用 DemoMockURLProtocol 的弱网路径。
//

import XCTest
import BONetKit
@testable import BONetKitExample

private struct DemoPostModel: Decodable { let id: Int }

final class RetryIntegrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        DemoMockURLProtocol.resetWeakNetworkCounter()
    }

    /// 弱网路径首次失败、重试后成功：需要 maxRetryCount >= 1。
    func testWeakNetworkRetrySucceeds() {
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://mock.local",
                maxRetryCount: 1,
                protocolClasses: [DemoMockURLProtocol.self]
            )
        )

        let exp = expectation(description: "retry success")
        BONetClient.shared.request("/posts/weak", of: DemoPostModel.self) { result in
            if case .success = result {
                exp.fulfill()
            } else {
                XCTFail("重试后应成功")
            }
        }
        wait(for: [exp], timeout: 5)
    }

    /// maxRetryCount = 0 时不重试，弱网首次失败即失败。
    func testWeakNetworkNoRetryFails() {
        DemoMockURLProtocol.resetWeakNetworkCounter()
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://mock.local",
                maxRetryCount: 0,
                protocolClasses: [DemoMockURLProtocol.self]
            )
        )

        let exp = expectation(description: "no retry fails")
        BONetClient.shared.request("/posts/weak", of: DemoPostModel.self) { result in
            if case .failure = result {
                exp.fulfill()
            } else {
                XCTFail("不重试应失败")
            }
        }
        wait(for: [exp], timeout: 5)
    }

    /// RETRY-01：POST（非幂等）默认不重试，弱网首次失败即失败（即便 maxRetryCount>0）。
    func testPOSTNotRetriedByDefault() {
        DemoMockURLProtocol.resetWeakNetworkCounter()
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://mock.local",
                maxRetryCount: 2,                        // 允许重试次数 > 0
                protocolClasses: [DemoMockURLProtocol.self]
            )
        )

        let exp = expectation(description: "POST not retried")
        BONetClient.shared.request("/posts/weak", method: .post, of: DemoPostModel.self) { result in
            if case .failure = result {
                exp.fulfill()   // POST 非幂等，默认不重试 → 首次失败即失败
            } else {
                XCTFail("POST 默认不应重试")
            }
        }
        wait(for: [exp], timeout: 5)
    }

    /// RETRY-01：POST 显式开启 allowsRetryOnNonIdempotent 后，可重试并成功。
    func testPOSTRetriesWhenExplicitlyAllowed() {
        DemoMockURLProtocol.resetWeakNetworkCounter()
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://mock.local",
                maxRetryCount: 2,
                protocolClasses: [DemoMockURLProtocol.self]
            )
        )

        let exp = expectation(description: "POST retried when allowed")
        BONetClient.shared.request("/posts/weak", method: .post, of: DemoPostModel.self,
                                   allowsRetryOnNonIdempotent: true) { result in
            if case .success = result {
                exp.fulfill()   // 显式允许 → 重试后成功
            } else {
                XCTFail("显式允许后 POST 应重试成功")
            }
        }
        wait(for: [exp], timeout: 5)
    }
}
