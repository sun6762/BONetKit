//
//  UserSessionActor.swift
//  BONetKitExample
//

import Foundation

/// 登录态存储 —— 写法 C：actor（iOS 15+）。
///
/// 适用场景：项目已采用 Swift 并发（async/await），希望用语言原生机制保证线程安全。
///
/// 并发策略：
/// - `actor` 是 Swift 并发提供的引用类型，编译器保证其可变状态（`token`）在任意时刻
///   只被一个任务访问，从根本上杜绝数据竞争，**无需手动管理队列或锁**。
/// - 对 actor 内部状态的访问是**跨隔离域**的，因此是**异步**的：外部读写都必须 `await`，
///   并且只能在异步上下文（`Task { }` 或 `async` 函数）中进行。
///
/// 与写法 A（并发 + barrier）/ 写法 B（串行 sync）的关键差别：
/// - A、B 的 `token` 是**同步**属性，可直接 `let t = UserSessionXxx.shared.token` 读取；
/// - actor 的读写是**异步**的，必须 `await`。这一点直接影响调用方式，也影响能否接入
///   同步 API：`BONetConfiguration.tokenProvider` 是**同步闭包**，无法直接 `await` 本 actor，
///   因此若要配合本写法，需要在业务层先把 token 取到同步可读的地方（见下方说明）。
///
/// 版本要求：标注 `@available(iOS 15.0, *)`。actor 语法本身较低版本即可编译，
/// 这里按需求显式限定 iOS 15+。
///
/// 读写调用方法：
/// ```swift
/// // 写入（如登录成功后）：
/// Task {
///     await UserSessionActor.shared.setToken("abc123")
/// }
///
/// // 读取：
/// Task {
///     let token = await UserSessionActor.shared.token
///     print(token ?? "无 token")
/// }
///
/// // 在已有的 async 函数中：
/// func refresh() async {
///     let token = await UserSessionActor.shared.token
///     await UserSessionActor.shared.setToken(newToken)
/// }
///
/// // 清除（如退出登录）：
/// Task { await UserSessionActor.shared.clear() }
/// ```
///
/// 关于接入同步的 `tokenProvider`：
/// 由于 `tokenProvider` 是同步闭包、无法 `await`，不能在其中直接读取本 actor。
/// 实践做法是在登录 / 刷新时把最新 token 同步镜像到一个同步可读的存储
/// （例如 UserDefaults / Keychain / 一个受锁保护的属性），供 `tokenProvider` 同步读取；
/// actor 仅作为并发安全的“权威来源”。这部分将在后续讨论持久化存储时一并处理。
@available(iOS 15.0, *)
actor UserSessionActor {

    static let shared = UserSessionActor()
    private init() {}

    /// 受 actor 隔离保护的 token。外部读取需 `await`。
    private(set) var token: String?

    /// 写入 token（如登录成功后）。外部调用需 `await`。
    func setToken(_ newToken: String?) {
        token = newToken
    }

    /// 清除 token（如退出登录）。外部调用需 `await`。
    func clear() {
        token = nil
    }
}
