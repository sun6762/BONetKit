//
//  ViewController.swift
//  BONetKitExample
//

import UIKit
import BONetKit

/// 最小示例页面：点击按钮发起一次真实网络请求，并展示结果或错误。
final class ViewController: UIViewController {

    private let loginButton = UIButton(type: .system)
    private let requestButton = UIButton(type: .system)
    private let failButton = UIButton(type: .system)
    private let weakNetButton = UIButton(type: .system)
    private let flexibleButton = UIButton(type: .system)
    private let feedButton = UIButton(type: .system)
    private let secureButton = UIButton(type: .system)
    private let bizFailButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let dedupButton = UIButton(type: .system)
    private let groupCancelButton = UIButton(type: .system)
    private let resultTextView = UITextView()

    /// 去重演示的结果计数（两个请求分别回调，用于汇总展示）。
    private var dedupCancelledCount = 0
    private var dedupSucceededCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "BONetKit 示例"
        view.backgroundColor = .systemBackground

        configureButtons()
        configureResultView()
    }

    private func configureButtons() {
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        loginButton.setTitle("① 登录（写入 token）", for: .normal)
        loginButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        loginButton.addTarget(self, action: #selector(login), for: .touchUpInside)
        view.addSubview(loginButton)

        requestButton.translatesAutoresizingMaskIntoConstraints = false
        requestButton.setTitle("② 成功请求（带 token）", for: .normal)
        requestButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        requestButton.addTarget(self, action: #selector(sendSuccessRequest), for: .touchUpInside)
        view.addSubview(requestButton)

        failButton.translatesAutoresizingMaskIntoConstraints = false
        failButton.setTitle("失败请求（业务错误）", for: .normal)
        failButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        failButton.addTarget(self, action: #selector(sendFailRequest), for: .touchUpInside)
        view.addSubview(failButton)

        weakNetButton.translatesAutoresizingMaskIntoConstraints = false
        weakNetButton.setTitle("弱网请求（重试后成功）", for: .normal)
        weakNetButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        weakNetButton.addTarget(self, action: #selector(sendWeakNetworkRequest), for: .touchUpInside)
        view.addSubview(weakNetButton)

        flexibleButton.translatesAutoresizingMaskIntoConstraints = false
        flexibleButton.setTitle("@BOFlexible 示例（类型漂移）", for: .normal)
        flexibleButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        flexibleButton.addTarget(self, action: #selector(sendFlexibleRequest), for: .touchUpInside)
        view.addSubview(flexibleButton)

        feedButton.translatesAutoresizingMaskIntoConstraints = false
        feedButton.setTitle("BOObjectOrArray 示例（对象/数组）", for: .normal)
        feedButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        feedButton.addTarget(self, action: #selector(sendFeedRequest), for: .touchUpInside)
        view.addSubview(feedButton)

        secureButton.translatesAutoresizingMaskIntoConstraints = false
        secureButton.setTitle("鉴权请求（401 自动刷新 token）", for: .normal)
        secureButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        secureButton.addTarget(self, action: #selector(sendSecureRequest), for: .touchUpInside)
        view.addSubview(secureButton)

        bizFailButton.translatesAutoresizingMaskIntoConstraints = false
        bizFailButton.setTitle("业务码失效（200+40101 自动刷新）", for: .normal)
        bizFailButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        bizFailButton.addTarget(self, action: #selector(sendBizFailRequest), for: .touchUpInside)
        view.addSubview(bizFailButton)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("取消演示（发慢请求后取消）", for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        cancelButton.addTarget(self, action: #selector(sendAndCancelRequest), for: .touchUpInside)
        view.addSubview(cancelButton)

        dedupButton.translatesAutoresizingMaskIntoConstraints = false
        dedupButton.setTitle("去重演示（连发两个相同请求）", for: .normal)
        dedupButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        dedupButton.addTarget(self, action: #selector(sendDeduplicatedRequests), for: .touchUpInside)
        view.addSubview(dedupButton)

        groupCancelButton.translatesAutoresizingMaskIntoConstraints = false
        groupCancelButton.setTitle("分组取消演示（进入子页面）", for: .normal)
        groupCancelButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        groupCancelButton.addTarget(self, action: #selector(openGroupCancelDemo), for: .touchUpInside)
        view.addSubview(groupCancelButton)

        NSLayoutConstraint.activate([
            loginButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            requestButton.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 12),
            requestButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            failButton.topAnchor.constraint(equalTo: requestButton.bottomAnchor, constant: 12),
            failButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            weakNetButton.topAnchor.constraint(equalTo: failButton.bottomAnchor, constant: 12),
            weakNetButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            flexibleButton.topAnchor.constraint(equalTo: weakNetButton.bottomAnchor, constant: 12),
            flexibleButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            feedButton.topAnchor.constraint(equalTo: flexibleButton.bottomAnchor, constant: 12),
            feedButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            secureButton.topAnchor.constraint(equalTo: feedButton.bottomAnchor, constant: 12),
            secureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bizFailButton.topAnchor.constraint(equalTo: secureButton.bottomAnchor, constant: 12),
            bizFailButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.topAnchor.constraint(equalTo: bizFailButton.bottomAnchor, constant: 12),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dedupButton.topAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: 12),
            dedupButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            groupCancelButton.topAnchor.constraint(equalTo: dedupButton.bottomAnchor, constant: 12),
            groupCancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func configureResultView() {
        resultTextView.translatesAutoresizingMaskIntoConstraints = false
        resultTextView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        resultTextView.isEditable = false
        resultTextView.text = "点击按钮发起请求…"
        resultTextView.backgroundColor = .secondarySystemBackground
        resultTextView.layer.cornerRadius = 8
        view.addSubview(resultTextView)

        NSLayoutConstraint.activate([
            resultTextView.topAnchor.constraint(equalTo: groupCancelButton.bottomAnchor, constant: 24),
            resultTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            resultTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            resultTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    /// 登录：发登录请求，成功后把 token 写入 Keychain（含内存缓存）。
    /// 写入后，后续任意请求的 tokenProvider 都会取到它，并按
    /// `authorizationValueBuilder` 拼成 `Authorization: Token <token>` 头。
    @objc private func login() {
        resultTextView.text = "登录中…"

        BONetClient.shared.request(
            "/login",
            method: .post,
            parameters: ["username": "demo", "password": "123456"],
            of: LoginResult.self,
            errorHandler: self
        ) { [weak self] result in
            switch result {
            case .success(let login):
                // 关键：登录成功仅需把新凭证写入单一来源 tokenStore，
                // 无需重新 configure；后续请求会自动从 store 读取并注入。
                AppEnvironment.tokenStore.credential = BOCredential(
                    accessToken: login.token,
                    refreshToken: "refresh-token",
                    expiration: Date(timeIntervalSinceNow: 3600)
                )
                self?.resultTextView.text = """
                ✅ 登录成功，凭证已写入 tokenStore
                token: \(login.token)
                之后任意请求都会自动带上：
                Authorization: Bearer \(login.token)
                """
            case .failure(let error):
                self?.resultTextView.text = "❌ 登录失败：\(error.localizedDescription)"
            }
        }
    }

    /// 成功请求：mock 返回 code=0，走成功解析分支。
    /// 若已登录，本次请求会自动带上 Authorization: Token <token> 头。
    @objc private func sendSuccessRequest() {
        resultTextView.text = "请求中…"

        BONetClient.shared.request(
            "/posts/1",
            method: .get,
            of: DemoPost.self,
            errorHandler: self
        ) { [weak self] result in
            switch result {
            case .success(let post):
                self?.resultTextView.text = """
                ✅ 成功
                id: \(post.id)
                title: \(post.title)
                body: \(post.body)
                """
            case .failure(let error):
                self?.resultTextView.text = "❌ 失败：\(error.localizedDescription)"
            }
        }
    }

    /// 失败请求：mock 对含 "fail" 的路径返回 code=1001，走业务错误分支，
    /// 经错误分发中心回调到本页 handleError(_:)。
    @objc private func sendFailRequest() {
        resultTextView.text = "请求中…"

        BONetClient.shared.request(
            "/posts/fail",
            method: .get,
            of: DemoPost.self,
            errorHandler: self
        ) { [weak self] result in
            if case .failure(let error) = result {
                self?.resultTextView.text = "❌ 失败：\(error.localizedDescription)"
            }
        }
    }

    /// 弱网请求：mock 对含 "weak" 的路径先返回网络错误，
    /// 由请求拦截器按 `maxRetryCount` 重试，重试后成功。
    /// 演示方案 3——不延长超时，靠重试应对弱网。
    @objc private func sendWeakNetworkRequest() {
        // 重置计数，保证每次点击都从「第一次失败」开始，便于反复演示。
        DemoMockURLProtocol.resetWeakNetworkCounter()
        resultTextView.text = "弱网请求中（首次失败将自动重试）…"

        BONetClient.shared.request(
            "/posts/weak",
            method: .get,
            of: DemoPost.self,
            errorHandler: self
        ) { [weak self] result in
            switch result {
            case .success(let post):
                self?.resultTextView.text = """
                ✅ 弱网重试后成功
                id: \(post.id)
                title: \(post.title)
                （首次网络失败已被自动重试）
                """
            case .failure(let error):
                self?.resultTextView.text = "❌ 重试后仍失败：\(error.localizedDescription)"
            }
        }
    }

    /// @BOFlexible 示例：mock 的 age 返回字符串 "25"、score 返回数字，
    /// 经 @BOFlexible 归一后仍解析为 Int / Double。
    @objc private func sendFlexibleRequest() {
        resultTextView.text = "请求中…"

        BONetClient.shared.request(
            "/flexible",
            method: .get,
            of: FlexibleDemo.self,
            errorHandler: self
        ) { [weak self] result in
            switch result {
            case .success(let demo):
                self?.resultTextView.text = """
                ✅ @BOFlexible 归一成功
                name: \(demo.name)
                age:  \(demo.age)  （后端返回的是字符串 "25"）
                score:\(demo.score)（后端返回的是数字 98.5）
                """
            case .failure(let error):
                self?.resultTextView.text = "❌ 失败：\(error.localizedDescription)"
            }
        }
    }

    /// BOObjectOrArray 示例：mock 的 items 返回单个对象（而非数组），
    /// 经 BOObjectOrArray 归一后通过 .values 得到数组。
    @objc private func sendFeedRequest() {
        resultTextView.text = "请求中…"

        BONetClient.shared.request(
            "/feed",
            method: .get,
            of: FeedDemo.self,
            errorHandler: self
        ) { [weak self] result in
            switch result {
            case .success(let feed):
                let items = feed.items.values
                self?.resultTextView.text = """
                ✅ BOObjectOrArray 归一成功
                后端返回的是单个对象，已归一为数组
                items.count: \(items.count)
                first: sku=\(items.first?.sku ?? "-") price=\(items.first?.price ?? 0)
                """
            case .failure(let error):
                self?.resultTextView.text = "❌ 失败：\(error.localizedDescription)"
            }
        }
    }

    /// 鉴权请求：初始 token 已过期，/secure 返回 401，
    /// 认证拦截器自动刷新 token 并用新 token 重发，最终成功。全程无需手动介入。
    @objc private func sendSecureRequest() {
        resultTextView.text = "鉴权请求中（旧 token 将触发 401 → 自动刷新 → 重发）…"

        BONetClient.shared.request(
            "/secure",
            method: .get,
            of: DemoPost.self,
            errorHandler: self
        ) { [weak self] result in
            switch result {
            case .success(let post):
                self?.resultTextView.text = """
                ✅ 鉴权请求成功（401 已被自动刷新并重发）
                id: \(post.id)
                title: \(post.title)
                body: \(post.body)
                """
            case .failure(let error):
                self?.resultTextView.text = "❌ 失败：\(error.localizedDescription)"
            }
        }
    }

    /// 业务码失效请求：/secure-bizfail 首次返回 HTTP 200 但 code==40101（失效），
    /// 被业务码失效检测识别 → 复用刷新机制 → 用新 token 重发 → 成功。
    @objc private func sendBizFailRequest() {
        resultTextView.text = "业务码失效请求中（HTTP 200 + code 40101 → 自动刷新 → 重发）…"

        BONetClient.shared.request(
            "/secure-bizfail",
            method: .get,
            of: DemoPost.self,
            errorHandler: self
        ) { [weak self] result in
            switch result {
            case .success(let post):
                self?.resultTextView.text = """
                ✅ 业务码失效已被自动刷新并重发
                id: \(post.id)
                title: \(post.title)
                body: \(post.body)
                """
            case .failure(let error):
                self?.resultTextView.text = "❌ 失败：\(error.localizedDescription)"
            }
        }
    }

    /// 取消演示：发一个慢请求（2 秒返回），拿到句柄后 0.5 秒主动取消。
    /// 回调收到 BONetError.cancelled，说明取消生效。
    /// 也可用 group 批量取消：请求时传 group，之后调 BONetClient.shared.cancel(group:)。
    @objc private func sendAndCancelRequest() {
        resultTextView.text = "已发出慢请求，0.5 秒后将主动取消…"

        let ticket = BONetClient.shared.request(
            "/slow",
            method: .get,
            of: DemoPost.self,
            group: "demo-page",          // 也可按此分组批量取消
            errorHandler: self
        ) { [weak self] result in
            switch result {
            case .success(let post):
                self?.resultTextView.text = "❓ 未取消成功，请求返回了：\(post.title)"
            case .failure(let error):
                if error.isCancelled {
                    self?.resultTextView.text = "✅ 请求已被取消（收到 .cancelled）"
                } else {
                    self?.resultTextView.text = "❌ 失败：\(error.localizedDescription)"
                }
            }
        }

        // 0.5 秒后取消（此时慢请求尚未返回）。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ticket?.cancel()
            // 等价的分组取消：BONetClient.shared.cancel(group: "demo-page")
        }
    }

    /// 去重演示：策略 .cancelPrevious，连发两个「相同」的慢请求。
    /// 第二个发起时会取消第一个（策略：取消旧的用新的），
    /// 结果应为：第一个 .cancelled，第二个成功。
    @objc private func sendDeduplicatedRequests() {
        dedupCancelledCount = 0
        dedupSucceededCount = 0
        resultTextView.text = "连发两个相同请求（已开启去重）…"

        for index in 1...2 {
            BONetClient.shared.request(
                "/slow",
                method: .get,
                parameters: ["q": "same"],   // 相同参数 → 相同指纹
                of: DemoPost.self,
                deduplication: .cancelPrevious,
                errorHandler: self
            ) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.dedupSucceededCount += 1
                case .failure(let error) where error.isCancelled:
                    self.dedupCancelledCount += 1
                case .failure:
                    break
                }
                self.resultTextView.text = """
                去重结果（第 \(index) 个回调）：
                被取消：\(self.dedupCancelledCount) 个
                成功：\(self.dedupSucceededCount) 个
                预期：1 个被取消（旧的）、1 个成功（新的）
                """
            }
        }
    }

    /// 进入分组取消演示子页面：该页发起多个带 group 的请求，
    /// 返回时在其 deinit 中按 group 一次性取消。
    @objc private func openGroupCancelDemo() {
        navigationController?.pushViewController(GroupCancelDemoViewController(), animated: true)
    }
}

// MARK: - BOErrorHandlerProtocol

extension ViewController: BOErrorHandlerProtocol {

    /// 由错误分发中心回调；这里演示消费错误（弹窗提示）并返回 true。
    func handleError(_ error: BONetError) -> Bool {
        // 主动取消不视为需要提示的错误。
        if error.isCancelled { return true }

        let alert = UIAlertController(
            title: "请求出错",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
        return true
    }
}
