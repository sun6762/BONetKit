//
//  BOResponseMiddlewareTests.swift
//  BONetKit Tests
//

import XCTest
@testable import BONetKit

/// 记录执行顺序的测试中间件。
private struct OrderMiddleware: BOResponseMiddleware {
    let name: String
    let log: (String) -> Void
    func process(_ context: BOResponseContext,
                 next: (BOResponseContext) -> BOResponseContext) -> BOResponseContext {
        log("\(name)-before")
        let result = next(context)
        log("\(name)-after")
        return result
    }
}

/// 短路中间件：不调用 next。
private struct ShortCircuitMiddleware: BOResponseMiddleware {
    let log: (String) -> Void
    func process(_ context: BOResponseContext,
                 next: (BOResponseContext) -> BOResponseContext) -> BOResponseContext {
        log("short-circuit")
        return context   // 不调用 next
    }
}

/// 改写数据的中间件。
private struct RewriteMiddleware: BOResponseMiddleware {
    func process(_ context: BOResponseContext,
                 next: (BOResponseContext) -> BOResponseContext) -> BOResponseContext {
        var ctx = context
        ctx.data = Data("rewritten".utf8)
        return next(ctx)
    }
}

final class BOResponseMiddlewareTests: XCTestCase {

    private func emptyContext() -> BOResponseContext {
        BOResponseContext(request: nil, httpResponse: nil, data: nil, underlyingError: nil)
    }

    func testOnionOrder() {
        var logs: [String] = []
        let mws: [BOResponseMiddleware] = [
            OrderMiddleware(name: "A", log: { logs.append($0) }),
            OrderMiddleware(name: "B", log: { logs.append($0) })
        ]
        _ = BOResponseMiddlewareChain.run(mws, context: emptyContext())
        // 洋葱模型：A 外层、B 内层
        XCTAssertEqual(logs, ["A-before", "B-before", "B-after", "A-after"])
    }

    func testShortCircuitStopsChain() {
        var logs: [String] = []
        let mws: [BOResponseMiddleware] = [
            ShortCircuitMiddleware(log: { logs.append($0) }),
            OrderMiddleware(name: "B", log: { logs.append($0) })
        ]
        _ = BOResponseMiddlewareChain.run(mws, context: emptyContext())
        // 短路后 B 不应执行
        XCTAssertEqual(logs, ["short-circuit"])
    }

    func testRewriteData() {
        let result = BOResponseMiddlewareChain.run([RewriteMiddleware()], context: emptyContext())
        XCTAssertEqual(result.data, Data("rewritten".utf8))
    }

    func testEmptyChainReturnsContext() {
        var ctx = emptyContext()
        ctx.data = Data("x".utf8)
        let result = BOResponseMiddlewareChain.run([], context: ctx)
        XCTAssertEqual(result.data, Data("x".utf8))
    }

    func testLoggingDefaultsToNoResponseBody() {
        let middleware = BOLoggingMiddleware()
        XCTAssertFalse(middleware.logsBody)
    }

    func testLoggingRedactsSensitiveQueryAndTruncatesBody() {
        let url = URL(string: "https://example.com/user?access_token=secret&name=alice")!
        let request = URLRequest(url: url)
        let context = BOResponseContext(
            request: request,
            httpResponse: nil,
            data: Data("123456789".utf8),
            underlyingError: nil
        )
        let middleware = BOLoggingMiddleware(logsBody: true, maxBodyLength: 4)
        let result = middleware.process(context, next: { $0 })
        XCTAssertEqual(result.data, context.data)
        XCTAssertEqual(
            BOLoggingMiddleware.redactedURL(url),
            "https://example.com/user?access_token=%3Credacted%3E&name=alice"
        )
        XCTAssertEqual(String("123456789".prefix(middleware.maxBodyLength)), "1234")
    }
}
