Pod::Spec.new do |s|
  s.name             = 'BONetKit'
  s.version          = '0.3.0'
  s.summary          = '基于 Alamofire 的轻量网络请求封装工具。'

  s.description      = <<-DESC
  BONetKit 基于 Alamofire 封装，提供：
  1. 泛型 Codable 的请求接口（completion 回调）。
  2. 请求拦截器：统一注入 token / 公共 header，失败重试。
  3. 响应拦截器：校验后端统一结构 { code, message, data }。
  4. 统一错误模型 BONetError 与错误分发中心 BOErrorHandlerProtocol。
  DESC

  s.homepage         = 'https://github.com/sun6762/BONetKit'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'sun6762' => 'https://github.com/sun6762' }
  s.source           = { :git => 'https://github.com/sun6762/BONetKit.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version    = '5.0'

  s.source_files     = 'Sources/BONetKit/**/*.swift'

  s.dependency 'Alamofire', '~> 5.8'

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/**/*.swift'
  end
end
