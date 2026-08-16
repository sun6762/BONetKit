//
//  Models.swift
//  BONetKitExample
//

import Foundation
import BONetKit

/// 示例模型，对应后端统一结构中的 `data` 字段。
struct DemoPost: Decodable {
    let id: Int
    let title: String
    let body: String
}

/// 登录接口返回的数据模型，对应统一结构中的 `data` 字段。
struct LoginResult: Decodable {
    let token: String
}

/// 手动键名映射范例。
///
/// 适用场景：后端命名与 Swift 属性名不一致，且**未**开启全局的
/// `.convertFromSnakeCase`，或字段命名不规则、无法靠自动转换覆盖时。
///
/// 假设后端返回的 `data` 形如：
/// ```json
/// {
///   "user_name": "张三",
///   "avatar_url": "https://.../a.png",
///   "is_vip": true
/// }
/// ```
/// 属性名想用 Swift 惯用的 camelCase，就通过 `CodingKeys` 把「属性名」映射到「JSON 键名」。
struct UserProfile: Decodable {

    // Swift 侧使用 camelCase 属性名。
    let userName: String
    let avatarURL: String
    let isVIP: Bool

    /// 键名映射表。
    ///
    /// 要点：
    /// 1. 名称**必须**是 `CodingKeys`（这是 Swift 约定名，编译器只认这个拼写）。
    /// 2. 必须遵从 `String, CodingKey`：`String` 让每个 case 的 rawValue 作为 JSON 键名。
    /// 3. 每个需要解码的属性都要有对应 case。
    /// 4. `case 属性名 = "JSON里的键名"`：左边对应结构体属性，右边是后端实际键名。
    ///    未写 `= "..."` 的 case，其 JSON 键名默认等于 case 名本身。
    enum CodingKeys: String, CodingKey {
        case userName = "user_name"     // 属性 userName ← JSON 的 user_name
        case avatarURL = "avatar_url"   // 属性 avatarURL ← JSON 的 avatar_url
        case isVIP = "is_vip"           // 属性 isVIP ← JSON 的 is_vip
    }
}

/// `@BOFlexible` 使用范例（字段类型漂移）。
///
/// 假设后端 `age` 字段类型不稳定，可能返回 25、"25" 或 25.0；`score` 可能返回
/// "98.5" 或 98.5。用 `@BOFlexible` 后，无论后端给哪种类型，都会归一到目标类型。
///
/// 对应 mock（DemoMockURLProtocol 的 `/flexible` 路径）：
/// ```json
/// { "name": "张三", "age": "25", "score": 98.5 }
/// ```
struct FlexibleDemo: Decodable {
    let name: String
    @BOFlexible var age: Int       // 后端 "25" / 25 / 25.0 → Int 25
    @BOFlexible var score: Double  // 后端 "98.5" / 98.5 → Double 98.5
}

/// `BOObjectOrArray` 使用范例（对象 / 数组漂移）。
///
/// 假设后端 `items` 字段有时是数组、有时是单个对象。用 `BOObjectOrArray` 后，
/// 通过 `.values` 始终拿到数组。
///
/// 对应 mock（DemoMockURLProtocol 的 `/feed` 路径，此处返回单个对象以演示归一）：
/// ```json
/// { "items": { "sku": "x1", "price": 10 } }
/// ```
struct FeedDemo: Decodable {
    let items: BOObjectOrArray<FeedItem>
}

struct FeedItem: Decodable {
    let sku: String
    let price: Int
}
