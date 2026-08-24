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
    static var requestObserver: ((URLRequest) -> Void)?

    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestObserver?(request)
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
        TestMockURLProtocol.requestObserver = nil
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

    func testDiscardNewReturnsDeduplicatedWithoutStartingSecondRequest() {
        TestMockURLProtocol.slowPaths = ["discard"]
        TestMockURLProtocol.routes["discard"] = (200, #"{ "code": 0, "message": "ok", "data": { "id": 1 } }"#)
        var requestCount = 0
        TestMockURLProtocol.requestObserver = { _ in requestCount += 1 }

        let firstExp = expectation(description: "first done")
        let discardedExp = expectation(description: "second discarded")

        BONetClient.shared.request(
            "/discard", of: P.self, deduplication: .discardNew
        ) { result in
            XCTAssertEqual(try? result.get(), P(id: 1))
            firstExp.fulfill()
        }
        let discardedTicket = BONetClient.shared.request(
            "/discard", of: P.self, deduplication: .discardNew
        ) { result in
            if case .failure(let error) = result {
                XCTAssertTrue(error.isDeduplicated)
                XCTAssertFalse(error.isCancelled)
            } else {
                XCTFail("重复请求应被去重策略丢弃")
            }
            discardedExp.fulfill()
        }

        XCTAssertNil(discardedTicket)
        wait(for: [discardedExp, firstExp], timeout: 5)
        XCTAssertEqual(requestCount, 1)
    }

    func testRequestMiddlewareRunsBeforeParameterEncoding() {
        struct EncryptPasswordMiddleware: BORequestMiddleware {
            func process(_ context: BORequestContext) -> BORequestContext {
                var result = context
                result.parameters?["password"] = "encrypted-value"
                result.headers["X-Processed"] = "1"
                return result
            }
        }

        TestMockURLProtocol.routes["login"] = (200, #"{ "code": 0, "message": "ok", "data": { "id": 1 } }"#)
        let observed = expectation(description: "encoded request observed")
        TestMockURLProtocol.requestObserver = { request in
            let object = TestMockURLProtocol.bodyData(from: request).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            XCTAssertEqual(object?["password"] as? String, "encrypted-value")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Processed"), "1")
            observed.fulfill()
        }
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://test.local",
                protocolClasses: [TestMockURLProtocol.self],
                requestMiddlewares: [EncryptPasswordMiddleware()]
            )
        )

        let completed = expectation(description: "request completed")
        BONetClient.shared.request(
            "/login",
            method: .post,
            parameters: ["password": "plain-value"],
            of: P.self
        ) { result in
            XCTAssertEqual(try? result.get(), P(id: 1))
            completed.fulfill()
        }

        wait(for: [observed, completed], timeout: 5)
    }

    func testIndependentClientsKeepConfigurationsIsolated() {
        TestMockURLProtocol.routes["client-a"] = (200, #"{ "code": 0, "message": "ok", "data": { "id": 1 } }"#)
        TestMockURLProtocol.routes["client-b"] = (200, #"{ "code": 0, "message": "ok", "data": { "id": 2 } }"#)

        let clientA = BONetClient()
        clientA.configure(BONetConfiguration(
            baseURL: "https://a.example.com",
            protocolClasses: [TestMockURLProtocol.self]
        ))
        let clientB = BONetClient()
        clientB.configure(BONetConfiguration(
            baseURL: "https://b.example.com",
            protocolClasses: [TestMockURLProtocol.self]
        ))

        var observedHosts: [String] = []
        TestMockURLProtocol.requestObserver = { request in
            if let host = request.url?.host { observedHosts.append(host) }
        }

        let first = expectation(description: "client A")
        clientA.request("/client-a", of: P.self) { result in
            XCTAssertEqual(try? result.get(), P(id: 1))
            first.fulfill()
        }
        wait(for: [first], timeout: 5)

        let second = expectation(description: "client B")
        clientB.request("/client-b", of: P.self) { result in
            XCTAssertEqual(try? result.get(), P(id: 2))
            second.fulfill()
        }
        wait(for: [second], timeout: 5)

        XCTAssertEqual(observedHosts, ["a.example.com", "b.example.com"])
    }
}
