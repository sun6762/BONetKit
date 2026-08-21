//
//  DemoMockURLProtocol.swift
//  BONetKitExample
//

import Foundation

/// 本地 mock：拦截请求并返回预置的 `{ code, message, data }` 响应，
/// 用于在无真实后端时验证 BONetKit 的成功解析链路。
///
/// 通过 `BONetConfiguration.protocolClasses` 注入到底层会话即可生效。
///
/// 支持三类路径：
/// - 普通路径：返回 `code == 0` 的成功数据。
/// - 含 `fail`：返回 `code == 1001` 的业务错误。
/// - 含 `weak`：模拟弱网——前若干次抛出网络错误（可被请求拦截器重试），
///   达到成功阈值后返回成功数据，用于演示 `maxRetryCount` 重试。
final class DemoMockURLProtocol: URLProtocol {

    /// 弱网路径在第几次尝试时成功（前面的尝试都会失败）。
    /// 设为 2 表示：第 1 次失败、第 2 次成功，需要 `maxRetryCount >= 1` 才能最终成功。
    static let weakNetworkSucceedAttempt = 2

    /// 弱网路径已发生的尝试次数（跨重试累计）。
    private static var weakNetworkAttemptCount = 0

    /// 重置弱网计数，便于重复演示。
    static func resetWeakNetworkCounter() {
        weakNetworkAttemptCount = 0
    }

    /// 刷新接口是否返回失败。true → /refresh 返回 401，用于演示「刷新失败 → 跳登录」。
    static var refreshShouldFail = false

    /// 是否拦截该请求：这里拦截所有 http(s) 请求。
    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let path = request.url?.path ?? ""

        // 慢响应路径：延迟 2 秒返回，用于演示「请求取消」（在响应返回前取消）。
        // 若期间请求被取消，URLSession 不会再调用 startLoading 的后续，stopLoading 会被调用。
        if path.contains("slow") {
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !self.isStopped else { return }
                self.respond(statusCode: 200, json: #"""
                { "code": 0, "message": "ok", "data": { "id": 7, "title": "慢响应完成", "body": "2 秒后返回" } }
                """#)
            }
            return
        }

        // 弱网路径：未达成功阈值前，抛出可重试的网络错误。
        if path.contains("weak") {
            Self.weakNetworkAttemptCount += 1
            if Self.weakNetworkAttemptCount < Self.weakNetworkSucceedAttempt {
                let error = URLError(.networkConnectionLost)
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            // 达到阈值，本轮演示结束后重置，方便再次点击演示。
            Self.weakNetworkAttemptCount = 0
        }

        // 刷新接口：/refresh 返回新凭证。
        // 由 refreshShouldFail 开关控制成功/失败，用于分别演示「刷新成功重发」与「刷新失败跳登录」。
        if path.contains("refresh") {
            if Self.refreshShouldFail {
                // 模拟 refresh token 也失效（如已过期/被吊销）→ 刷新失败。
                respond(statusCode: 401, json: #"{ "code": 401, "message": "refresh token expired", "data": null }"#)
            } else {
                respond(statusCode: 200, json: #"""
                { "code": 0, "message": "ok", "data": { "accessToken": "\#(Self.freshAccessToken)", "refreshToken": "new-refresh-token", "expiresIn": 3600 } }
                """#)
            }
            return
        }

        // 登录加解密闭环：校验编码后的请求体已包含被请求中间件处理过的 password，
        // 然后返回 Base64 编码的完整业务响应，由响应中间件在解析前解开。
        if path.contains("login") {
            let body = Self.bodyData(from: request).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            guard request.value(forHTTPHeaderField: "X-Demo-Request-Encrypted") == "1",
                  body?["password"] as? String == Data("123456".utf8).base64EncodedString() else {
                respond(statusCode: 400, json: #"{ "code": 1002, "message": "password 未在编码前处理", "data": null }"#)
                return
            }

            let plainResponse = #"{ "code": 0, "message": "ok", "data": { "token": "mock-token-abc123" } }"#
            let encryptedResponse = Data(plainResponse.utf8).base64EncodedString()
            respond(
                statusCode: 200,
                json: encryptedResponse,
                headers: ["X-Demo-Response-Encrypted": "1"]
            )
            return
        }

        // 业务码失效演示：/secure-bizfail 返回 HTTP 200，但旧 token 时业务码为 40101（失效）。
        // 用于演示「HTTP 200 + 业务码失效」如何复用 401 的刷新重发机制。
        if path.contains("bizfail") {
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if !auth.contains(Self.freshAccessToken) {
                // 旧 token → HTTP 200 但业务码 40101，触发业务码失效检测 → 刷新。
                respond(statusCode: 200, json: #"{ "code": 40101, "message": "token expired", "data": null }"#)
            } else {
                // 新 token → 成功。
                respond(statusCode: 200, json: #"""
                { "code": 0, "message": "ok", "data": { "id": 10, "title": "业务码刷新后成功", "body": "HTTP 200 业务码失效已被自动刷新并重发" } }
                """#)
            }
            return
        }

        // 鉴权刷新演示：/secure 路径校验 Authorization 头。
        // 带「旧 token」返回 401（触发自动刷新），带「刷新后的新 token」返回成功。
        if path.contains("secure") {
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if !auth.contains(Self.freshAccessToken) {
                // 旧 token / 无 token → 401，触发 AuthenticationInterceptor 刷新。
                respond(statusCode: 401, json: #"{ "code": 401, "message": "unauthorized", "data": null }"#)
                return
            }
            // 已是刷新后的新 token → 成功。
            respond(statusCode: 200, json: #"""
            { "code": 0, "message": "ok", "data": { "id": 9, "title": "鉴权通过", "body": "使用刷新后的新 token 访问成功" } }
            """#)
            return
        }

        // 返回成功或业务错误响应。
        respond(statusCode: 200, json: Self.mockJSON(for: path))
    }

    /// 刷新后的新 access token 标识。带此 token 的 /secure 请求视为通过。
    static let freshAccessToken = "fresh-access-token"

    /// URLSession 交给 URLProtocol 时，请求体可能位于 httpBody 或 httpBodyStream。
    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    /// 统一构造并回发响应。
    private func respond(statusCode: Int, json: String, headers: [String: String] = [:]) {
        let data = Data(json.utf8)
        var responseHeaders = ["Content-Type": "application/json"]
        responseHeaders.merge(headers) { _, new in new }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://mock.local")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: responseHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// 请求是否已被停止（取消）。慢响应的延迟回调据此避免向已取消的请求写数据。
    private var isStopped = false

    override func stopLoading() {
        isStopped = true
    }

    /// 构造 mock JSON。
    /// - `/login`：返回 code=0 + 一个 token，模拟登录成功。
    /// - `/fail`：返回业务错误 code=1001。
    /// - `/flexible`：`age` 故意返回字符串、`score` 返回数字，演示 @BOFlexible 归一。
    /// - `/feed`：`items` 故意返回单个对象（而非数组），演示 BOObjectOrArray 归一。
    /// - 其他：返回一条成功的 post 数据。
    private static func mockJSON(for path: String) -> String {
        if path.contains("flexible") {
            // age 故意用字符串 "25"，score 用数字 98.5，演示类型漂移被归一。
            return #"""
            {
              "code": 0,
              "message": "ok",
              "data": { "name": "张三", "age": "25", "score": 98.5 }
            }
            """#
        }
        if path.contains("feed") {
            // items 故意返回单个对象（而非数组），演示 BOObjectOrArray 归一为数组。
            return #"""
            {
              "code": 0,
              "message": "ok",
              "data": { "items": { "sku": "x1", "price": 10 } }
            }
            """#
        }
        if path.contains("fail") {
            return #"{ "code": 1001, "message": "模拟业务失败", "data": null }"#
        }
        return #"""
        {
          "code": 0,
          "message": "ok",
          "data": {
            "id": 1,
            "title": "BONetKit Mock 标题",
            "body": "这是通过本地 mock 返回的内容，用于验证成功解析链路。"
          }
        }
        """#
    }
}
