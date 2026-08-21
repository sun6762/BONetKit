//
//  BOFlexibleDecoding.swift
//  BONetKit
//
//  ⚠️ 备用方案（按需使用）
//  ------------------------------------------------------------------
//  本文件提供两个「宽容解码」工具，用于兼容**不规范**的后端响应：
//    1. `@BOFlexible<T>`      —— 单个字段类型漂移（如 age 时而 Int、时而 "25"、时而 25.0）。
//    2. `BOObjectOrArray<T>`  —— 同一接口的某字段有时是对象、有时是数组。
//
//  定位说明：
//  - 这不是主路径。理想情况下后端应返回规范、稳定的类型；这些工具是在
//    「无法推动后端修正」时的**客户端兜底**手段。
//  - 仅在确有类型漂移的字段上按需使用，不要无脑套用到所有字段——
//    过度使用会掩盖后端问题、也会削弱类型系统的校验价值。
//  ------------------------------------------------------------------

import Foundation

// MARK: - 1. 字段类型漂移：@BOFlexible

/// 可从多种 JSON 标量类型宽容构造的目标类型所遵循的协议。
///
/// 为 `Int` / `String` / `Double` / `Bool` 等基础类型分别提供「如何从其他类型转成我」的规则，
/// 供 `@BOFlexible` 的统一解码逻辑复用——**解码逻辑只写一份，目标类型各自给转换规则**。
public protocol BOFlexibleDecodable {
    /// 从 Int 尝试构造；无法表示时返回 nil。
    static func fromInt(_ value: Int) -> Self?
    /// 从 Double 尝试构造。
    static func fromDouble(_ value: Double) -> Self?
    /// 从 String 尝试构造。
    static func fromString(_ value: String) -> Self?
    /// 从 Bool 尝试构造。
    static func fromBool(_ value: Bool) -> Self?
}

extension Int: BOFlexibleDecodable {
    public static func fromInt(_ value: Int) -> Int? { value }
    public static func fromDouble(_ value: Double) -> Int? { Int(value) }   // 25.0 → 25（截断）
    public static func fromString(_ value: String) -> Int? {
        // 先按整数解析，失败再尝试 "25.5" 这类带小数的字符串。
        Int(value) ?? Double(value).map(Int.init)
    }
    public static func fromBool(_ value: Bool) -> Int? { value ? 1 : 0 }
}

extension Double: BOFlexibleDecodable {
    public static func fromInt(_ value: Int) -> Double? { Double(value) }
    public static func fromDouble(_ value: Double) -> Double? { value }
    public static func fromString(_ value: String) -> Double? { Double(value) }
    public static func fromBool(_ value: Bool) -> Double? { value ? 1 : 0 }
}

extension String: BOFlexibleDecodable {
    public static func fromInt(_ value: Int) -> String? { String(value) }
    public static func fromDouble(_ value: Double) -> String? { String(value) }
    public static func fromString(_ value: String) -> String? { value }
    public static func fromBool(_ value: Bool) -> String? { value ? "true" : "false" }
}

extension Bool: BOFlexibleDecodable {
    public static func fromInt(_ value: Int) -> Bool? { value != 0 }        // 0→false 非0→true
    public static func fromDouble(_ value: Double) -> Bool? { value != 0 }
    public static func fromString(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }
    public static func fromBool(_ value: Bool) -> Bool? { value }
}

/// 宽容解码属性包装器：兼容后端返回类型与目标类型不一致的情况。
///
/// 解码时依次尝试 Int / Double / Bool / String，命中后按目标类型的转换规则归一。
/// 全部失败时抛出解码错误。
///
/// 用法：
/// ```swift
/// struct User: Decodable {
///     let name: String
///     @BOFlexible var age: Int      // 后端 age 为 25 / "25" / 25.0 均可解为 Int
/// }
/// // 取值：user.age（直接是 Int）
/// ```
///
/// 说明：本包装器要求字段存在且为非空值（无效非空值会抛解码错误，不会静默变 nil）。
/// 若字段**可能缺失或为 null**，请改用 `@BOFlexibleOptional var age: Int?`。
@propertyWrapper
public struct BOFlexible<T: BOFlexibleDecodable>: Decodable {

    public var wrappedValue: T

    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // 依次尝试各标量类型，命中即按目标类型转换规则归一。
        if let v = try? container.decode(Int.self), let r = T.fromInt(v) {
            wrappedValue = r
        } else if let v = try? container.decode(Double.self), let r = T.fromDouble(v) {
            wrappedValue = r
        } else if let v = try? container.decode(Bool.self), let r = T.fromBool(v) {
            wrappedValue = r
        } else if let v = try? container.decode(String.self), let r = T.fromString(v) {
            wrappedValue = r
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "BOFlexible 无法把响应值转换为 \(T.self)"
            )
        }
    }
}

/// 可选版宽容解码：字段**缺失或为 null** 时解为 nil；存在则按 `BOFlexible` 规则归一。
///
/// 行为约定（区分三种情况）：
/// - 字段缺失 / JSON null → `nil`。
/// - 合法的替代标量类型（如 `"25"` → Int）→ 转换后的值。
/// - 无效的非空值（无法转换）→ 抛解码错误（不静默变 nil）。
///
/// 用法：
/// ```swift
/// struct User: Decodable {
///     @BOFlexibleOptional var age: Int?     // 缺失/null → nil；"25"/25.0 → 25
/// }
/// ```
///
/// 注意：需配合下方 `KeyedDecodingContainer` 扩展，才能正确处理「键缺失」——
/// 这是属性包装器 + 可选字段解码的标准做法。
@propertyWrapper
public struct BOFlexibleOptional<T: BOFlexibleDecodable>: Decodable {

    public var wrappedValue: T?

    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // JSON null → nil。
        if container.decodeNil() {
            wrappedValue = nil
            return
        }

        // 依次尝试各标量类型，命中即归一。
        if let v = try? container.decode(Int.self), let r = T.fromInt(v) {
            wrappedValue = r
        } else if let v = try? container.decode(Double.self), let r = T.fromDouble(v) {
            wrappedValue = r
        } else if let v = try? container.decode(Bool.self), let r = T.fromBool(v) {
            wrappedValue = r
        } else if let v = try? container.decode(String.self), let r = T.fromString(v) {
            wrappedValue = r
        } else {
            // 无效的非空值：抛错，不静默变 nil。
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "BOFlexibleOptional 无法把非空响应值转换为 \(T.self)"
            )
        }
    }
}

/// 让 `@BOFlexibleOptional` 的属性在「键缺失」时也能解为 nil（而非抛 keyNotFound）。
extension KeyedDecodingContainer {
    public func decode<T>(
        _ type: BOFlexibleOptional<T>.Type,
        forKey key: Key
    ) throws -> BOFlexibleOptional<T> where T: BOFlexibleDecodable {
        // 键缺失 → nil；键存在（含 null）→ 交给 BOFlexibleOptional 自身处理。
        try decodeIfPresent(BOFlexibleOptional<T>.self, forKey: key)
            ?? BOFlexibleOptional(wrappedValue: nil)
    }
}

// MARK: - 2. 对象 / 数组漂移：BOObjectOrArray

/// 兼容「同一字段有时是单个对象、有时是数组」的宽容容器。
///
/// 解码时先尝试按数组解析，失败再尝试按单个对象解析并包成单元素数组，
/// 从而让**使用端始终拿到数组**（`values`），无需关心后端返回的是单个还是多个。
///
/// 用法：
/// ```swift
/// struct Feed: Decodable {
///     // 后端 items 可能是 [Item] 或单个 Item
///     let items: BOObjectOrArray<Item>
/// }
/// // 取值：feed.items.values —— 恒为 [Item]
/// ```
///
/// 提示：对象/数组漂移多为后端设计缺陷，能推动后端统一返回数组最好；
/// 本类型是无法修改后端时的客户端兜底。
public struct BOObjectOrArray<T: Decodable>: Decodable {

    /// 归一后的数组。无论后端返回单对象还是数组，这里都是数组。
    public let values: [T]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // 先按数组解，成功直接用。
        if let array = try? container.decode([T].self) {
            values = array
        } else {
            // 再按单个对象解，成功则包成单元素数组。
            let single = try container.decode(T.self)
            values = [single]
        }
    }
}
