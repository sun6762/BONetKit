//
//  UserSessionBarrier.swift
//  BONetKitExample
//

import Foundation

/// 登录态存储 —— 写法 A：并发队列 + barrier。
///
/// 适用场景：读多写少（token 频繁被各请求读取，仅登录 / 刷新时写入）。
///
/// 并发策略：
/// - 队列声明为 `.concurrent`，因此**多个读操作可以真正并行**，
///   不会像串行队列那样被迫排队，缓解大量接口同时读取 token 时的相互等待。
/// - 读用 `sync`：读取需要返回值，必须同步等待结果；但由于队列是并发的，
///   多个 `sync` 读之间互不阻塞。
/// - 写用 `async(flags: .barrier)`：
///   - `barrier` 保证写操作独占队列——执行期间没有任何读 / 写并行，从而避免数据竞争；
///   - `async` 使写入不阻塞调用方（如登录成功回调可立即返回）。
///
/// 说明：`tokenProvider` 闭包可能在 Alamofire 的后台线程被调用，因此此处的
/// 线程安全保护是必要的。对于 token 这种纳秒级的内存读写，串行队列其实也够用，
/// 本写法的价值在于「读可并行 + 写不阻塞调用方」的语义更贴合读多写少的场景。
final class UserSessionBarrier {

    static let shared = UserSessionBarrier()
    private init() {}

    /// 并发队列：读并行、写用 barrier 独占。
    private let queue = DispatchQueue(
        label: "com.bonetkit.usersession.barrier",
        attributes: .concurrent
    )

    /// 受队列保护的底层存储，禁止直接访问。
    private var _token: String?

    /// 线程安全的 token 访问。
    var token: String? {
        get {
            // 并发 sync 读：多个读可并行，仅在有 barrier 写进行时等待。
            queue.sync { _token }
        }
        set {
            // barrier async 写：独占执行且不阻塞调用方。
            queue.async(flags: .barrier) { [weak self] in
                self?._token = newValue
            }
        }
    }

    /// 清除 token（如退出登录）。同样走 barrier 写。
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?._token = nil
        }
    }
}
