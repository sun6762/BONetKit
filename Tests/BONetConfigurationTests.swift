//
//  BONetConfigurationTests.swift
//  BONetKit Tests
//

import XCTest
@testable import BONetKit

final class BONetConfigurationTests: XCTestCase {

    func testValidConfigurationPassesValidation() {
        let configuration = BONetConfiguration(baseURL: "https://api.example.com/v1")
        XCTAssertNoThrow(try configuration.validate())
    }

    func testInvalidBaseURLFailsValidation() {
        let configuration = BONetConfiguration(baseURL: "not-a-url")
        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(error as? BONetConfigurationError, .invalidBaseURL("not-a-url"))
        }
    }

    func testUnsupportedSchemeFailsValidation() {
        let configuration = BONetConfiguration(baseURL: "ftp://example.com")
        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(error as? BONetConfigurationError, .unsupportedScheme("ftp"))
        }
    }

    func testNonPositiveTimeoutFailsValidation() {
        let configuration = BONetConfiguration(
            baseURL: "https://api.example.com",
            timeoutInterval: 0
        )
        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(error as? BONetConfigurationError, .invalidTimeout(0))
        }
    }

    func testInfiniteTimeoutFailsValidation() {
        let configuration = BONetConfiguration(
            baseURL: "https://api.example.com",
            timeoutInterval: .infinity
        )
        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(error as? BONetConfigurationError, .invalidTimeout(.infinity))
        }
    }

    func testNegativeRetryCountFailsValidation() {
        let configuration = BONetConfiguration(
            baseURL: "https://api.example.com",
            maxRetryCount: -1
        )
        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(error as? BONetConfigurationError, .negativeMaxRetryCount(-1))
        }
    }

    func testNonThrowingConfigureReturnsValidationError() {
        let configuration = BONetConfiguration(baseURL: "not-a-url")
        let error = BONetClient.shared.configure(configuration)
        XCTAssertEqual(error, .invalidBaseURL("not-a-url"))
    }
}
