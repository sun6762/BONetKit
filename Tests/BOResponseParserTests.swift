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

    // MARK: - PARSE-01 回归

    /// 失败响应的 data 结构与成功模型 T 不匹配时，应返回 .business 而非 .decoding。
    func testBusinessErrorNotMaskedByDecoding() {
        // code 非 0（失败），且 data 是与 P（{id:Int}）完全不同的结构。
        let ctx = context(json: #"{ "code": 1001, "message": "参数错误", "data": { "field": "id", "reason": "缺失" } }"#)
        let result = parser.parse(ctx, as: P.self, decoder: decoder)
        if case .failure(.business(let code, let message, _)) = result {
            XCTAssertEqual(code, 1001)
            XCTAssertEqual(message, "参数错误")
        } else {
            XCTFail("业务失败应返回 .business，不应被 data 解码失败掩盖")
        }
    }

    /// 业务失败时，data 里的附加字段应保留到 businessUserInfo。
    func testBusinessUserInfoPreserved() {
        let ctx = context(json: #"{ "code": 1001, "message": "x", "data": { "field": "id" } }"#)
        let result = parser.parse(ctx, as: P.self, decoder: decoder)
        if case .failure(let error) = result {
            XCTAssertEqual(error.businessUserInfo["field"] as? String, "id")
        } else {
            XCTFail("应为失败")
        }
    }

    /// 自定义成功码规则：code == 200 视为成功。
    func testCustomSuccessCode() {
        let customParser = BODefaultResponseParser(isSuccessCode: { $0 == 200 })
        let ctx = context(json: #"{ "code": 200, "message": "ok", "data": { "id": 5 } }"#)
        let result = customParser.parse(ctx, as: P.self, decoder: decoder)
        XCTAssertEqual(try? result.get(), P(id: 5))
    }
}
