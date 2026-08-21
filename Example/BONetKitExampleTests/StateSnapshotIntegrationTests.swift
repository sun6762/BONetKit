//
//  StateSnapshotIntegrationTests.swift
//  BONetKitExampleTests
//
//  STATE-01 回归：请求发起后重新 configure，进行中的请求仍用发起时的运行时快照处理。
//

import XCTest
import BONetKit
@testable import BONetKitExample

private struct SlowModel: Decodable { let id: Int }

/// 自定义解析器：把成功数据里的 id 固定改写为一个标记值，用于区分"用了哪个解析器"。
private struct MarkerParser: BOResponseParser {
    let marker: Int
    func parse<T: Decodable>(_ context: BOResponseContext, as type: T.Type,
                             decoder: JSONDecoder) -> Result<T, BONetError> {
        // 忽略真实数据，直接构造一个带 marker 的 SlowModel。
        guard let model = SlowModel(id: marker) as? T else {
            return .failure(.decoding(underlying: NSError(domain: "marker", code: 0)))
        }
        return .success(model)
    }
}

final class StateSnapshotIntegrationTests: XCTestCase {

    /// 发起慢请求（快照 A，解析器 marker=1）后，立刻重新 configure（快照 B，解析器 marker=2）。
    /// 慢请求返回时应仍用快照 A 的解析器 → 结果 id == 1，而非 2。
    func testInflightRequestUsesSnapshotAtStart() {
        // 快照 A：marker=1
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://mock.local",
                protocolClasses: [DemoMockURLProtocol.self],
                responseParser: MarkerParser(marker: 1)
            )
        )

        let exp = expectation(description: "inflight uses snapshot A")
        BONetClient.shared.request("/slow", of: SlowModel.self) { result in
            switch result {
            case .success(let model):
                XCTAssertEqual(model.id, 1, "进行中的请求应使用发起时快照 A 的解析器(marker=1)")
            case .failure:
                XCTFail("不应失败")
            }
            exp.fulfill()
        }

        // 请求已发出（/slow 延迟 2s），立刻重新配置为快照 B：marker=2。
        BONetClient.shared.configure(
            BONetConfiguration(
                baseURL: "https://mock.local",
                protocolClasses: [DemoMockURLProtocol.self],
                responseParser: MarkerParser(marker: 2)
            )
        )

        wait(for: [exp], timeout: 10)
    }
}
