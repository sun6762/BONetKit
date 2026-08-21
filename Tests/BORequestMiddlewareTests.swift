//
//  BORequestMiddlewareTests.swift
//  BONetKit Tests
//

import XCTest
import Alamofire
@testable import BONetKit

private struct AppendRequestMiddleware: BORequestMiddleware {
    let name: String
    let log: (String) -> Void

    func process(_ context: BORequestContext) -> BORequestContext {
        var result = context
        log(name)
        result.parameters?[name] = true
        result.headers["X-\(name)"] = "1"
        return result
    }
}

final class BORequestMiddlewareTests: XCTestCase {

    func testRunsInArrayOrderAndPassesModifiedContextForward() {
        var order: [String] = []
        let middlewares: [BORequestMiddleware] = [
            AppendRequestMiddleware(name: "first", log: { order.append($0) }),
            AppendRequestMiddleware(name: "second", log: { order.append($0) })
        ]
        let context = BORequestContext(
            path: "/submit",
            method: .post,
            parameters: [:],
            headers: [:],
            group: "form",
            deduplication: .discardNew
        )

        let result = BORequestMiddlewareChain.run(middlewares, context: context)

        XCTAssertEqual(order, ["first", "second"])
        XCTAssertEqual(result.parameters?["first"] as? Bool, true)
        XCTAssertEqual(result.parameters?["second"] as? Bool, true)
        XCTAssertEqual(result.headers["X-first"], "1")
        XCTAssertEqual(result.headers["X-second"], "1")
        XCTAssertEqual(result.group, "form")
        if case .discardNew = result.deduplication {} else {
            XCTFail("只读请求元信息应保持不变")
        }
    }

    func testEmptyChainReturnsOriginalContext() {
        let context = BORequestContext(
            path: "/users",
            method: .get,
            parameters: ["page": 1],
            headers: ["Accept": "application/json"]
        )

        let result = BORequestMiddlewareChain.run([], context: context)

        XCTAssertEqual(result.path, "/users")
        XCTAssertEqual(result.method, .get)
        XCTAssertEqual(result.parameters?["page"] as? Int, 1)
        XCTAssertEqual(result.headers["Accept"], "application/json")
    }
}
