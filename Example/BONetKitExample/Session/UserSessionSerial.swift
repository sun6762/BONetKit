//
//  UserSessionSerial.swift
//  BONetKitExample
//

import Foundation

/// 登录态存储 —— 写法 B：串行队列 + sync。
///
/// 适用场景：通用、实现最简单，读写量都不大的情况。
///
/// 并发策略：
/// - 队列是**串行**的：任意时刻只有一个操作在执行，读和写都排在同一条队列上，
///   天然互斥，因此无需 barrier 即可避免数据竞争。
/// - 读、写都用 `sync`：调用方会同步等待操作完成。
///
/// 与写法 A（并发 + barrier）的差别：
/// - 串行队列下，多个读操作会被**强制排队**，无法并行；当大量接口在同一瞬间
///   读取 token 时，它们会依次执行。不过 token 读取是纳秒级的内存访问，
///   即便排队，累计延迟通常也远小于一次网络请求的开销，实际影响一般可忽略。
/// - 写用 `sync` 会阻塞调用方直到写完；写法 A 的 `async(flags: .barrier)` 写则不阻塞调用方。
///
/// 选型建议：
/// - 追求实现简单、并发压力不大 → 用本写法（串行 sync）。
/// - 读多写少、希望读并行且写不阻塞调用方 → 用写法 A（并发 + barrier）。
final class UserSessionSerial {

    static let shared = UserSessionSerial()
    private init() {}

    /// 串行队列：所有读写在此排队执行，天然互斥。
    private let queue = DispatchQueue(label: "com.bonetkit.usersession.serial")

    /// 受队列保护的底层存储，禁止直接访问。
    private var _token: String?

    /// 线程安全的 token 访问。
    var token: String? {
        get { queue.sync { _token } }
        set { queue.sync { _token = newValue } }
    }

    /// 清除 token（如退出登录）。
    func clear() {
        queue.sync { _token = nil }
    }
}
