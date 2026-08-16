//
//  AuthService.swift
//  BONetKitExample
//

import Foundation
import BONetKit

/// 鉴权服务：封装「调刷新接口换新凭证」与「跳转登录页」。
///
/// 关键点：刷新请求**不能走带认证拦截器的主 client**，否则刷新请求自身若返回 401
/// 会再次触发刷新，形成死循环。这里用一个独立的 URLSession（含 mock 的 URLProtocol）
/// 直接发刷新请求，绕开认证链路。
enum AuthService {

    /// 刷新接口返回的数据结构。
    private struct RefreshResponse: Decodable {
        struct Data: Decodable {
            let accessToken: String
            let refreshToken: String
            let expiresIn: TimeInterval
        }
        let code: Int
        let message: String
        let data: Data?
    }

    /// 独立会话：注入 mock 的 URLProtocol，且不带任何认证拦截器。
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.protocolClasses = [DemoMockURLProtocol.self]
        return URLSession(configuration: config)
    }()

    /// 用 refreshToken 调刷新接口换取新凭证。
    /// - Parameters:
    ///   - refreshToken: 当前刷新令牌。
    ///   - completion: 成功回调新 `BOCredential`，失败回调错误。
    static func refresh(
        refreshToken: String,
        completion: @escaping (Result<BOCredential, Error>) -> Void
    ) {
        var request = URLRequest(url: URL(string: "https://mock.local/refresh")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refreshToken": refreshToken])

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(statusCode), let data else {
                completion(.failure(NSError(domain: "AuthService", code: statusCode,
                                            userInfo: [NSLocalizedDescriptionKey: "刷新失败：HTTP \(statusCode)"])))
                return
            }
            do {
                let resp = try JSONDecoder().decode(RefreshResponse.self, from: data)
                guard resp.code == 0, let payload = resp.data else {
                    completion(.failure(NSError(domain: "AuthService", code: resp.code,
                                                userInfo: [NSLocalizedDescriptionKey: resp.message])))
                    return
                }
                let credential = BOCredential(
                    accessToken: payload.accessToken,
                    refreshToken: payload.refreshToken,
                    expiration: Date(timeIntervalSinceNow: payload.expiresIn)
                )
                completion(.success(credential))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    /// 跳转到登录页（刷新失败、需要重新登录时调用）。
    ///
    /// 示例中仅清空凭证并打印提示；真实项目应在此把根控制器切换为登录页
    /// （如 `window.rootViewController = LoginViewController()`）。
    @MainActor
    static func goToLogin(reason: String) {
        AppEnvironment.tokenStore.credential = nil
        print("[AuthService] 需要重新登录：\(reason) —— 此处应跳转登录页")
        // 真实项目示例：
        // let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        // scene?.windows.first?.rootViewController = UINavigationController(rootViewController: LoginViewController())
    }
}
