//
//  BOErrorDispatcherTests.swift
//  BONetKit Tests
//

import XCTest
@testable import BONetKit

@MainActor
private final class MockHandler: BOErrorHandlerProtocol {
    var handled: BONetError?
    var returnValue: Bool
    init(returnValue: Bool) { self.returnValue = returnValue }
    func handleError(_ error: BONetError) -> Bool {
        handled = error
        return returnValue
    }
}

@MainActor
final class BOErrorDispatcherTests: XCTestCase {

    override func tearDown() {
        BOErrorDispatcher.shared.fallbackHandler = nil
        super.tearDown()
    }

    func testHandlerConsumesError() {
        let handler = MockHandler(returnValue: true)
        var fallbackCalled = false
        BOErrorDispatcher.shared.fallbackHandler = { _ in fallbackCalled = true }

        BOErrorDispatcher.shared.dispatch(.emptyData, to: handler)

        XCTAssertNotNil(handler.handled)
        XCTAssertFalse(fallbackCalled)   // handler 消费了，不走兜底
    }

    func testFallbackWhenHandlerDoesNotConsume() {
        let handler = MockHandler(returnValue: false)
        var fallbackError: BONetError?
        BOErrorDispatcher.shared.fallbackHandler = { fallbackError = $0 }

        BOErrorDispatcher.shared.dispatch(.emptyData, to: handler)

        XCTAssertNotNil(handler.handled)
        XCTAssertNotNil(fallbackError)   // 未消费，走兜底
    }

    func testCancellationDoesNotReachHandlerOrFallback() {
        let handler = MockHandler(returnValue: false)
        var fallbackCalled = false
        BOErrorDispatcher.shared.fallbackHandler = { _ in fallbackCalled = true }

        BOErrorDispatcher.shared.dispatch(.cancelled, to: handler)

        XCTAssertNil(handler.handled)
        XCTAssertFalse(fallbackCalled)
    }

    func testDeduplicatedDoesNotReachHandlerOrFallback() {
        let handler = MockHandler(returnValue: false)
        var fallbackCalled = false
        BOErrorDispatcher.shared.fallbackHandler = { _ in fallbackCalled = true }

        BOErrorDispatcher.shared.dispatch(.deduplicated, to: handler)

        XCTAssertNil(handler.handled)
        XCTAssertFalse(fallbackCalled)
    }
}
