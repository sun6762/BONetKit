//
//  BONetResponseTests.swift
//  BONetKit Tests
//

import XCTest
@testable import BONetKit

private struct Payload: Decodable, Equatable {
    let id: Int
    let name: String
}

final class BONetResponseTests: XCTestCase {

    private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> BONetResponse<T> {
        try JSONDecoder().decode(BONetResponse<T>.self, from: Data(json.utf8))
    }

    func testSuccessDecoding() throws {
        let json = #"{ "code": 0, "message": "ok", "data": { "id": 1, "name": "a" } }"#
        let resp = try decode(json, as: Payload.self)
        XCTAssertTrue(resp.isSuccess)
        XCTAssertEqual(resp.code, 0)
        XCTAssertEqual(resp.data, Payload(id: 1, name: "a"))
    }

    func testBusinessFailureCode() throws {
        let json = #"{ "code": 1001, "message": "fail", "data": null }"#
        let resp = try decode(json, as: Payload.self)
        XCTAssertFalse(resp.isSuccess)
        XCTAssertEqual(resp.code, 1001)
        XCTAssertNil(resp.data)
    }

    func testMissingMessageTolerated() throws {
        // message 缺失时容错为空串
        let json = #"{ "code": 0, "data": { "id": 2, "name": "b" } }"#
        let resp = try decode(json, as: Payload.self)
        XCTAssertEqual(resp.message, "")
        XCTAssertEqual(resp.data?.id, 2)
    }

    func testMissingCodeDefaultsToFailure() throws {
        // code 缺失默认为 -1（非成功）
        let json = #"{ "message": "x", "data": null }"#
        let resp = try decode(json, as: Payload.self)
        XCTAssertEqual(resp.code, -1)
        XCTAssertFalse(resp.isSuccess)
    }

    func testDataAsArray() throws {
        let json = #"{ "code": 0, "message": "ok", "data": [ { "id": 1, "name": "a" }, { "id": 2, "name": "b" } ] }"#
        let resp = try decode(json, as: [Payload].self)
        XCTAssertEqual(resp.data?.count, 2)
    }
}
