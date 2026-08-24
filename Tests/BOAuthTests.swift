//
//  BOAuthTests.swift
//  BONetKit Tests
//

import XCTest
@testable import BONetKit

final class BOAuthTests: XCTestCase {

    func testInMemoryStoreReadWrite() {
        let store = BOInMemoryTokenStore()
        XCTAssertNil(store.credential)
        store.credential = BOCredential(accessToken: "a")
        XCTAssertEqual(store.credential?.accessToken, "a")
    }

    func testInMemoryStoreNotifiesCredentialObserver() {
        let store = BOInMemoryTokenStore()
        var observedToken: String?
        store.setCredentialObserver { observedToken = $0?.accessToken }

        store.credential = BOCredential(accessToken: "updated")

        XCTAssertEqual(observedToken, "updated")
    }

    func testHeaderValueDefault() {
        let store = BOInMemoryTokenStore()
        XCTAssertEqual(store.headerField, "Authorization")
        XCTAssertEqual(store.headerValue(for: "abc"), "Bearer abc")
    }

    func testHeaderValueCustom() {
        let store = BOInMemoryTokenStore(
            headerField: "X-Token",
            headerValueBuilder: { "Token \($0)" }
        )
        XCTAssertEqual(store.headerField, "X-Token")
        XCTAssertEqual(store.headerValue(for: "abc"), "Token abc")
    }

    func testCredentialRequiresRefreshWhenExpired() {
        let expired = BOCredential(accessToken: "a", refreshToken: "r",
                                   expiration: Date(timeIntervalSinceNow: -10))
        XCTAssertTrue(expired.requiresRefresh)
    }

    func testCredentialNotRequireRefreshWhenFresh() {
        let fresh = BOCredential(accessToken: "a", refreshToken: "r",
                                 expiration: Date(timeIntervalSinceNow: 3600))
        XCTAssertFalse(fresh.requiresRefresh)
    }

    func testCredentialCodableRoundTrip() throws {
        let original = BOCredential(accessToken: "a", refreshToken: "r",
                                    expiration: Date(timeIntervalSince1970: 1000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BOCredential.self, from: data)
        XCTAssertEqual(decoded.accessToken, "a")
        XCTAssertEqual(decoded.refreshToken, "r")
        XCTAssertEqual(decoded.expiration, original.expiration)
    }

    func testSingleTokenDefaults() {
        // 单 token 场景：refreshToken/expiration 可省略
        let c = BOCredential(accessToken: "only")
        XCTAssertEqual(c.refreshToken, "")
        XCTAssertEqual(c.expiration, .distantFuture)
        XCTAssertFalse(c.requiresRefresh)
    }
}
