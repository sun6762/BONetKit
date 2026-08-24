//
//  BODeduplicationTests.swift
//  BONetKit Tests
//

import XCTest
import Alamofire
@testable import BONetKit

final class BODeduplicationTests: XCTestCase {

    // MARK: - URL 解析

    func testResolveURLAppendsToBasePathAndMergesQuery() {
        let result = BONetClient.resolveURL(
            path: "/users?active=true",
            baseURL: "https://api.example.com/v1?tenant=cn"
        )
        XCTAssertEqual(result, "https://api.example.com/v1/users?tenant=cn&active=true")
    }

    func testResolveURLPercentEncodesUnicodeAndSpaces() {
        let result = BONetClient.resolveURL(
            path: "/用户/张 三",
            baseURL: "https://api.example.com/v1/"
        )
        XCTAssertEqual(result, "https://api.example.com/v1/%E7%94%A8%E6%88%B7/%E5%BC%A0%20%E4%B8%89")
    }

    func testResolveURLKeepsAbsoluteURLIndependentFromBaseURL() {
        let result = BONetClient.resolveURL(
            path: "https://cdn.example.com/files/a.json?token=1",
            baseURL: "https://api.example.com/v1"
        )
        XCTAssertEqual(result, "https://cdn.example.com/files/a.json?token=1")
    }

    // MARK: - DEDUP-01：指纹稳定性

    /// 顶层参数插入顺序不同，指纹应相同。
    func testFingerprintStableAcrossTopLevelOrder() {
        let a = BONetClient.fingerprint(method: .get, url: "https://x/a",
                                        parameters: ["a": 1, "b": 2])
        let b = BONetClient.fingerprint(method: .get, url: "https://x/a",
                                        parameters: ["b": 2, "a": 1])
        XCTAssertEqual(a, b)
    }

    /// 嵌套字典的键顺序不同，指纹也应相同（递归排序）。
    func testFingerprintStableAcrossNestedOrder() {
        let a = BONetClient.fingerprint(method: .post, url: "https://x/a",
                                        parameters: ["p": ["x": 1, "y": 2]])
        let b = BONetClient.fingerprint(method: .post, url: "https://x/a",
                                        parameters: ["p": ["y": 2, "x": 1]])
        XCTAssertEqual(a, b)
    }

    /// 参数值不同，指纹应不同（不误碰撞）。
    func testFingerprintDiffersForDifferentValues() {
        let a = BONetClient.fingerprint(method: .get, url: "https://x/a", parameters: ["id": 1])
        let b = BONetClient.fingerprint(method: .get, url: "https://x/a", parameters: ["id": 2])
        XCTAssertNotEqual(a, b)
    }

    /// HTTP 方法不同，指纹应不同。
    func testFingerprintDiffersForMethod() {
        let a = BONetClient.fingerprint(method: .get, url: "https://x/a", parameters: nil)
        let b = BONetClient.fingerprint(method: .post, url: "https://x/a", parameters: nil)
        XCTAssertNotEqual(a, b)
    }

    func testFingerprintDiffersForHeadersEncodingAndAuthentication() {
        let base = BONetClient.fingerprint(
            method: .post, url: "https://x/a", parameters: ["id": 1],
            headers: ["X-Tenant": "a"], encodingIdentifier: "json",
            authenticationIdentity: "Authorization:token-a"
        )
        let differentHeader = BONetClient.fingerprint(
            method: .post, url: "https://x/a", parameters: ["id": 1],
            headers: ["X-Tenant": "b"], encodingIdentifier: "json",
            authenticationIdentity: "Authorization:token-a"
        )
        let differentEncoding = BONetClient.fingerprint(
            method: .post, url: "https://x/a", parameters: ["id": 1],
            headers: ["X-Tenant": "a"], encodingIdentifier: "url",
            authenticationIdentity: "Authorization:token-a"
        )
        let differentAuthentication = BONetClient.fingerprint(
            method: .post, url: "https://x/a", parameters: ["id": 1],
            headers: ["X-Tenant": "a"], encodingIdentifier: "json",
            authenticationIdentity: "Authorization:token-b"
        )

        XCTAssertNotEqual(base, differentHeader)
        XCTAssertNotEqual(base, differentEncoding)
        XCTAssertNotEqual(base, differentAuthentication)
        XCTAssertFalse(base.contains("token-a"))
        XCTAssertFalse(base.contains("https://x/a"))
    }

    func testFingerprintHeaderNamesAreCaseInsensitive() {
        let upper = BONetClient.fingerprint(
            method: .get, url: "https://x/a", parameters: nil,
            headers: ["X-Tenant": "a"]
        )
        let lower = BONetClient.fingerprint(
            method: .get, url: "https://x/a", parameters: nil,
            headers: ["x-tenant": "a"]
        )
        XCTAssertEqual(upper, lower)
    }

    func testCustomDeduplicationKeyIsHashed() {
        let fingerprint = BONetClient.fingerprint(forCustomKey: "user-secret-key")
        XCTAssertFalse(fingerprint.contains("user-secret-key"))
        XCTAssertEqual(fingerprint, BONetClient.fingerprint(forCustomKey: "user-secret-key"))
    }
}
