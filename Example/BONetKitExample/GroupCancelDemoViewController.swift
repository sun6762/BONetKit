//
//  GroupCancelDemoViewController.swift
//  BONetKitExample
//

import UIKit
import BONetKit

/// 演示「页面级分组取消」：进入页面发起多个慢请求，退出页面时在 deinit 里
/// 按 group 一次性取消该页所有未完成请求。
///
/// 这是分组取消的典型用法——用 VC 名（或任意唯一标识）作为 group，
/// 页面销毁时统一取消，避免回调时 VC 已释放、浪费流量、操作已销毁的 UI。
final class GroupCancelDemoViewController: UIViewController {

    /// 用本 VC 的名称作为请求分组标识。
    private let requestGroup = "GroupCancelDemoViewController"

    private let logView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "分组取消演示"
        view.backgroundColor = .systemBackground
        configureLogView()
        sendGroupedRequests()
    }

    private func configureLogView() {
        logView.translatesAutoresizingMaskIntoConstraints = false
        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        logView.text = "已发起 3 个慢请求（group = \(requestGroup)）。\n返回上一页将触发 deinit 分组取消。\n\n"
        view.addSubview(logView)
        NSLayoutConstraint.activate([
            logView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            logView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            logView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            logView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    /// 发起多个慢请求，全部打上同一个 group。
    private func sendGroupedRequests() {
        for index in 1...3 {
            BONetClient.shared.request(
                "/slow",
                method: .get,
                of: DemoPost.self,
                group: requestGroup          // 关键：同一分组
            ) { [weak self] result in
                let line: String
                switch result {
                case .success(let post):
                    line = "请求 \(index) 成功：\(post.title)"
                case .failure(let error) where error.isCancelled:
                    line = "请求 \(index) 已被取消"
                case .failure(let error):
                    line = "请求 \(index) 失败：\(error.localizedDescription)"
                }
                self?.logView.text.append(line + "\n")
            }
        }
    }

    deinit {
        // 页面销毁：一次性取消本页所有未完成请求。
        // deinit 中调用单例的 cancel(group:) 是安全的——不依赖正在释放的 self。
        BONetClient.shared.cancel(group: requestGroup)
        print("[GroupCancelDemo] deinit：已取消 group=\(requestGroup) 的所有请求")
    }
}
