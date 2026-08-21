//
//  BOFlexibleDecodingTests.swift
//  BONetKit Tests
//

import XCTest
@testable import BONetKit

private struct FlexModel: Decodable {
    @BOFlexible var intValue: Int
    @BOFlexible var doubleValue: Double
    @BOFlexible var stringValue: String
    @BOFlexible var boolValue: Bool
}

private struct OptModel: Decodable {
    @BOFlexibleOptional var score: Int?
}

private struct Item: Decodable, Equatable {
    let sku: String
}

private struct ArrModel: Decodable {
    let items: BOObjectOrArray<Item>
}

final class BOFlexibleDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testFlexibleIntFromString() throws {
        // age 是字符串 "25"，仍归一为 Int
        let json = #"{ "intValue": "25", "doubleValue": 1, "stringValue": "x", "boolValue": true }"#
        let m = try decode(json, as: FlexModel.self)
        XCTAssertEqual(m.intValue, 25)
    }

    func testFlexibleIntFromDouble() throws {
        let json = #"{ "intValue": 25.9, "doubleValue": 1, "stringValue": "x", "boolValue": true }"#
        let m = try decode(json, as: FlexModel.self)
        XCTAssertEqual(m.intValue, 25) // 截断
    }

    func testFlexibleDoubleFromString() throws {
        let json = #"{ "intValue": 1, "doubleValue": "98.5", "stringValue": "x", "boolValue": true }"#
        let m = try decode(json, as: FlexModel.self)
        XCTAssertEqual(m.doubleValue, 98.5, accuracy: 0.0001)
    }

    func testFlexibleStringFromInt() throws {
        let json = #"{ "intValue": 1, "doubleValue": 1, "stringValue": 123, "boolValue": true }"#
        let m = try decode(json, as: FlexModel.self)
        XCTAssertEqual(m.stringValue, "123")
    }

    func testFlexibleBoolFromInt() throws {
        let json = #"{ "intValue": 1, "doubleValue": 1, "stringValue": "x", "boolValue": 1 }"#
        let m = try decode(json, as: FlexModel.self)
        XCTAssertTrue(m.boolValue)
    }

    func testObjectOrArrayFromSingleObject() throws {
        let json = #"{ "items": { "sku": "x1" } }"#
        let m = try decode(json, as: ArrModel.self)
        XCTAssertEqual(m.items.values, [Item(sku: "x1")])
    }

    func testObjectOrArrayFromArray() throws {
        let json = #"{ "items": [ { "sku": "x1" }, { "sku": "x2" } ] }"#
        let m = try decode(json, as: ArrModel.self)
        XCTAssertEqual(m.items.values.count, 2)
    }

    // MARK: - FLEX-01：BOFlexibleOptional

    func testFlexibleOptionalMissingKey() throws {
        // 字段缺失 → nil
        let m = try decode(#"{}"#, as: OptModel.self)
        XCTAssertNil(m.score)
    }

    func testFlexibleOptionalNull() throws {
        // JSON null → nil
        let m = try decode(#"{ "score": null }"#, as: OptModel.self)
        XCTAssertNil(m.score)
    }

    func testFlexibleOptionalValueConverted() throws {
        // 字符串 "25" → Int 25
        let m = try decode(#"{ "score": "25" }"#, as: OptModel.self)
        XCTAssertEqual(m.score, 25)
    }

    func testFlexibleOptionalInvalidThrows() {
        // 无效非空值（无法转 Int）应抛错，不静默变 nil
        XCTAssertThrowsError(try decode(#"{ "score": {"a":1} }"#, as: OptModel.self))
    }
}
