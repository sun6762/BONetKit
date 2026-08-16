//
//  DemoAltResponseParser.swift
//  BONetKitExample
//

import Foundation
import BONetKit

/// 自定义响应解析器示范：适配非默认的后端结构 `{ status, result, msg }`。
///
/// 用途：当后端不采用 BONetKit 默认的 `{ code, message, data }`，而是别的字段名 /
/// 成功判定时，实现 `BOResponseParser` 并通过 `BONetConfiguration.responseParser` 注入。
///
/// 本示范约定：`status == 200` 为成功，业务数据在 `result` 字段，提示语在 `msg`。
struct DemoAltResponseParser: BOResponseParser {

    /// 与默认解析器一样，先处理网络 / HTTP 层错误，再解析业务结构。
    func parse<T: Decodable>(
        _ context: BOResponseContext,
        as type: T.Type,
        decoder: JSONDecoder
    ) -> Result<T, BONetError> {
        // 网络层错误优先。
        if let underlyingError = context.underlyingError {
            if let code = context.httpResponse?.statusCode, !(200..<300).contains(code) {
                return .failure(.httpStatus(code: code, data: context.data))
            }
            return .failure(.network(underlying: underlyingError))
        }
        if let code = context.httpResponse?.statusCode, !(200..<300).contains(code) {
            return .failure(.httpStatus(code: code, data: context.data))
        }
        guard let data = context.data, !data.isEmpty else {
            return .failure(.emptyData)
        }

        // 按自定义结构 { status, result, msg } 解析。
        do {
            let wrapper = try decoder.decode(AltWrapper<T>.self, from: data)
            guard wrapper.status == 200 else {
                // 复用库的业务错误类型，把 status/msg 映射进去。
                // 演示携带附加数据：把原始 status 也放进 userInfo（也可放后端返回的其他字段）。
                return .failure(.makeBusiness(
                    code: wrapper.status,
                    message: wrapper.msg ?? "",
                    userInfo: ["rawStatus": wrapper.status]
                ))
            }
            guard let result = wrapper.result else {
                return .failure(.emptyData)
            }
            return .success(result)
        } catch {
            return .failure(.decoding(underlying: error))
        }
    }

    /// 对应后端结构 `{ "status": 200, "msg": "ok", "result": { ... } }`。
    private struct AltWrapper<U: Decodable>: Decodable {
        let status: Int
        let msg: String?
        let result: U?
    }
}
