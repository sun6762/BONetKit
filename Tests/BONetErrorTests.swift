//
//  BONetErrorTests.swift
//  BONetKit Tests
//

import XCTest
@testable import BONetKit

final class BONetErrorTests: XCTestCase {

    func testBusinessCodeExtraction() {
        let error = BONetError.makeBusiness(code: 1001, message: "余额不足")
        XCTAssertEqual(error.businessCode, 1001)
        XCTAssertNil(BONetError.emptyData.businessCode)
    }

    func testBusinessUserInfo() {
        let error = BONetError.makeBusiness(code: 1, message: "x", userInfo: ["balance": 5])
        XCTAssertEqual(error.businessUserInfo["balance"] as? Int, 5)
        // 非业务错误返回空字典
        XCTAssertTrue(BONetError.emptyData.businessUserInfo.isEmpty)
    }

    func testMakeBusinessDefaultUserInfoIsEmpty() {
        let error = BONetError.makeBusiness(code: 1, message: "x")
        XCTAssertTrue(error.businessUserInfo.isEmpty)
    }

    func testIsCancelled() {
        XCTAssertTrue(BONetError.cancelled.isCancelled)
        XCTAssertFalse(BONetError.deduplicated.isCancelled)
        XCTAssertFalse(BONetError.emptyData.isCancelled)
    }

    func testIsDeduplicated() {
        XCTAssertTrue(BONetError.deduplicated.isDeduplicated)
        XCTAssertFalse(BONetError.cancelled.isDeduplicated)
    }

    func testErrorDescriptionNotNil() {
        let errors: [BONetError] = [
            .network(underlying: NSError(domain: "t", code: 0)),
            .httpStatus(code: 500, data: nil),
            .decoding(underlying: NSError(domain: "t", code: 0)),
            .makeBusiness(code: 1, message: "m"),
            .emptyData,
            .cancelled,
            .deduplicated,
            .unknown(underlying: nil)
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
        }
    }
}
