//
//  BOResponseParserTests.swift
//  BONetKit Tests
//

import XCTest
@testable import BONetKit

private struct P: Decodable, Equatable { let id: Int }

final class BOResponseParserTests: XCTestCase {

    private let parser = BODefaultResponseParser()
    private let decoder = JSONDecoder()

    private func context(status: Int = 200, json: String? = nil, error: Error? = nil) -> BOResponseContext {
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://x")!, statusCode: status,
            httpVersion: nil, headerFields: nil
        )
        return BOResponseContext(
            request: nil,
            httpResponse: httpResponse,
            data: json.map { Data($0.utf8) },
            underlyingError: error
        )
    }

    func testParseSuccess() {
        let ctx = context(json: #"{ "code": 0, "message": "ok", "data": { "id": 7 } }"#)
        let result = parser.parse(ctx, as: P.self, decoder: decoder)
        XCTAssertEqual(try? result.get(), P(id: 7))
    }

    func testParseBusinessError() {
        let ctx = context(json: #"{ "code": 500, "message": "biz", "data": null }"#)
        let result = parser.parse(ctx, as: P.self, decoder: decoder)
        if case .failure(.business(let code, _, _)) = result {
            XCTAssertEqual(code, 500)
        } else {
            XCTFail("应为 business 错误")
        }
    }

    func testParseHTTPError() {
        let ctx = context(status: 500, json: nil, error: nil)
        let result = parser.parse(ctx, as: P.self, decoder: decoder)
        if case .failure(.httpStatus(let code, _)) = result {
            XCTAssertEqual(code, 500)
        } else {
            XCTFail("应为 httpStatus 错误")
        }
    }

    func testParseEmptyData() {
        let ctx = context(json: nil)
        let result = parser.parse(ctx, as: P.self, decoder: decoder)
        if case .failure(.emptyData) = result {} else {
            XCTFail("应为 emptyData")
        }
    }

    func testParseDecodingError() {
        let ctx = context(json: #"{ "code": 0, "data": { "id": "not-int" } }"#)
        let result = parser.parse(ctx, as: P.self, decoder: decoder)
        if case .failure(.decoding) = result {} else {
            XCTFail("应为 decoding 错误")
        }
    }
}
