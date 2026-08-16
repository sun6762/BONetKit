//
//  BONetClientIntegrationTests.swift
//  BONetKit Tests
//
//  用注入的 mock URLProtocol 测 BONetClient.request 全链路，不依赖真实网络。
//

import XCTest
@testable import BONetKit

/// 测试用 mock：按 path 返回预置响应。
final class TestMockURLProtocol: URLProtocol {

    /// path 关键字 → (状态码, JSON)。
    static var routes: [String: (Int, String)] = [:]
    /// 延迟返回的 path 关键字（用于取消测试）。
    static var slowPaths: Set<String> = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""

        if Self.slowPaths.contains(where: { path.contains($0) }) {
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.finish(path: path)
            }
            return
        }
        finish(path: path)
    }

    private func finish(path: String) {
        let (status, json) = Self.routes.first { path.contains($0.key) }?.value ?? (200, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct P: Decodable, Equatable { let id: Int }

final class BONetClientIntegrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestMockURLProtocol.routes = [:]
        TestMockURLProtocol.slowPaths = []
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://test.local",
                protocolClasses: [TestMockURLProtocol.self]
            )
        )
    }

    func testRequestSuccess() {
        TestMockURLProtocol.routes["ok"] = (200, #"{ "code": 0, "message": "ok", "data": { "id": 42 } }"#)
        let exp = expectation(description: "success")
        BONetClient.shared.request("/ok", of: P.self) { result in
            XCTAssertEqual(try? result.get(), P(id: 42))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testRequestBusinessError() {
        TestMockURLProtocol.routes["fail"] = (200, #"{ "code": 1001, "message": "biz", "data": null }"#)
        let exp = expectation(description: "biz")
        BONetClient.shared.request("/fail", of: P.self) { result in
            if case .failure(let error) = result {
                XCTAssertEqual(error.businessCode, 1001)
            } else { XCTFail() }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testManualCancel() {
        TestMockURLProtocol.slowPaths = ["slow"]
        TestMockURLProtocol.routes["slow"] = (200, #"{ "code": 0, "message": "ok", "data": { "id": 1 } }"#)
        let exp = expectation(description: "cancel")
        let token = BONetClient.shared.request("/slow", of: P.self) { result in
            if case .failure(let error) = result {
                XCTAssertTrue(error.isCancelled)
            } else { XCTFail("应被取消") }
            exp.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { token?.cancel() }
        wait(for: [exp], timeout: 5)
    }

    func testDeduplicationCancelsOld() {
        TestMockURLProtocol.slowPaths = ["dedup"]
        TestMockURLProtocol.routes["dedup"] = (200, #"{ "code": 0, "message": "ok", "data": { "id": 1 } }"#)
        let firstExp = expectation(description: "first cancelled")
        let secondExp = expectation(description: "second done")

        BONetClient.shared.request("/dedup", parameters: ["q": "x"], of: P.self, deduplication: .cancelPrevious) { result in
            if case .failure(let error) = result, error.isCancelled { firstExp.fulfill() }
        }
        BONetClient.shared.request("/dedup", parameters: ["q": "x"], of: P.self, deduplication: .cancelPrevious) { result in
            if case .success = result { secondExp.fulfill() }
        }
        wait(for: [firstExp, secondExp], timeout: 5)
    }
}
