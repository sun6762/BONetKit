//
//  BORequestInterceptorTests.swift
//  BONetKit Tests
//

import XCTest
import Alamofire
@testable import BONetKit

final class BORequestInterceptorTests: XCTestCase {

    /// 用 adapt 处理一个请求，返回处理后的请求头。
    private func adaptedHeaders(
        commonHeaders: [String: String],
        requestHeaders: [String: String]
    ) -> [String: String] {
        let config = BONetConfiguration(baseURL: "https://x", commonHeaders: commonHeaders)
        let interceptor = BORequestInterceptor(configuration: config)

        var urlRequest = URLRequest(url: URL(string: "https://x/a")!)
        for (k, v) in requestHeaders {
            urlRequest.setValue(v, forHTTPHeaderField: k)
        }

        var result: [String: String] = [:]
        let exp = expectation(description: "adapt")
        interceptor.adapt(urlRequest, for: Session.default) { r in
            if case .success(let req) = r {
                result = req.allHTTPHeaderFields ?? [:]
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        return result
    }

    // MARK: - HEADER-01

    /// 单次请求头优先：同名字段下，单次头不被公共头覆盖。
    func testPerRequestHeaderOverridesCommon() {
        let headers = adaptedHeaders(
            commonHeaders: ["Accept": "application/json"],
            requestHeaders: ["Accept": "text/plain"]
        )
        XCTAssertEqual(headers["Accept"], "text/plain", "单次头应优先于公共头")
    }

    /// 无单次覆盖时，公共头仍然生效。
    func testCommonHeaderAppliedWhenNoOverride() {
        let headers = adaptedHeaders(
            commonHeaders: ["Accept": "application/json"],
            requestHeaders: [:]
        )
        XCTAssertEqual(headers["Accept"], "application/json")
    }

    /// 头字段匹配大小写不敏感：单次的 "accept" 应挡住公共的 "Accept"。
    func testHeaderMatchCaseInsensitive() {
        let headers = adaptedHeaders(
            commonHeaders: ["Accept": "application/json"],
            requestHeaders: ["accept": "text/plain"]
        )
        // 不应同时出现两个语义相同的头；单次值优先。
        let acceptValues = headers.filter { $0.key.lowercased() == "accept" }.map { $0.value }
        XCTAssertEqual(acceptValues, ["text/plain"])
    }
}
