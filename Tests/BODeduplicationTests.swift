//
//  BODeduplicationTests.swift
//  BONetKit Tests
//

import XCTest
import Alamofire
@testable import BONetKit

final class BODeduplicationTests: XCTestCase {

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
}
