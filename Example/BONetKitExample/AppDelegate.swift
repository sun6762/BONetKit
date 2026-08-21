//
//  AppDelegate.swift
//  BONetKitExample
//

import UIKit
import BONetKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 启动时配置一次网络客户端。
        // 这里注入本地 mock（DemoMockURLProtocol），拦截请求返回 {code,message,data}
        // 结构的数据，无需真实后端即可跑通成功解析链路。
        // 接入真实后端时，改用真实 baseURL 并移除 protocolClasses 即可。
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://mock.local",
                timeoutInterval: 15,
                // token 单一来源（共享的 AppEnvironment.tokenStore）。注入与刷新都围绕它，无互斥。
                tokenStore: AppEnvironment.tokenStore,
                // 刷新处理器：真正调用刷新接口换新凭证（AuthService 用独立会话，不走认证链路，
                // 避免刷新请求自身 401 导致死循环）。成功后框架自动写回 tokenStore 并重发挂起请求；
                // 失败则跳转登录页（refresh token 也失效的情况）。
                tokenRefresh: { current, completion in
                    AuthService.refresh(refreshToken: current.refreshToken) { result in
                        switch result {
                        case .success(let credential):
                            completion(.success(credential))
                        case .failure(let error):
                            // 刷新失败：清空凭证并跳登录。仍把失败回传，让本次请求以失败结束。
                            Task { @MainActor in
                                AuthService.goToLogin(reason: error.localizedDescription)
                            }
                            completion(.failure(error))
                        }
                    }
                },
                // 业务码失效：HTTP 200 但 code==40101 视为 token 失效，复用刷新重发机制。
                tokenExpiredBusinessCodes: [40101],
                commonHeaders: ["Accept": "application/json"],
                maxRetryCount: 1,
                protocolClasses: [DemoMockURLProtocol.self],
                // 编码前请求中间件：登录请求中的 password 会先做字段级转换，再交给 Alamofire 编码。
                requestMiddlewares: [
                    DemoFieldEncryptionRequestMiddleware(fields: ["password"])
                ],
                additionalInterceptors: [DemoLoggingInterceptor()],   // 用户自定义请求拦截器
                // 响应中间件链：日志 + 错误上报。
                responseMiddlewares: [
                    DemoEncryptedResponseMiddleware(),                // Mock 加密响应先解密，再交给解析器
                    BOLoggingMiddleware(),                       // 内置：日志
                    DemoSlowRequestMiddleware(threshold: 1.0),   // 自定义：慢请求告警
                    BOErrorReportingMiddleware { context in      // 内置：错误上报
                        let url = context.request?.url?.absoluteString ?? "?"
                        let status = context.httpResponse?.statusCode ?? -1
                        print("[错误上报] \(url) status=\(status) error=\(String(describing: context.underlyingError))")
                    }
                ]
                // 响应解析器：不传即用默认 { code, message, data }。
                // 自定义结构见 DemoAltResponseParser.swift。
            )
        )

        // 设置全局兜底错误处理，便于观察未被具体页面消费的错误。
        BOErrorDispatcher.shared.fallbackHandler = { error in
            print("[全局兜底] \(error.localizedDescription)")
        }

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
