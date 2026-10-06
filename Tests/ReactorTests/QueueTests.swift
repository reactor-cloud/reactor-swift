import XCTest
@testable import Reactor

final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    struct Step {
        var status: Int
        var body: Data
    }

    nonisolated(unsafe) static var steps: [Step] = []
    nonisolated(unsafe) static var seen: [(method: String, path: String, body: String)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = Self.body(of: request)
        Self.seen.append((request.httpMethod ?? "", request.url?.path ?? "", String(data: data, encoding: .utf8) ?? ""))
        let step = Self.steps.isEmpty ? Step(status: 200, body: Data()) : Self.steps.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: step.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class QueueTests: XCTestCase {
    private func client() -> ReactorClient {
        RecordingURLProtocol.steps = [
            .init(status: 201, body: Data(#"{"name":"jobs"}"#.utf8)),
            .init(status: 200, body: Data(#"[{"name":"jobs","created_at":"2026-01-01T00:00:00Z"}]"#.utf8)),
            .init(status: 201, body: Data(#"{"msg_id":7}"#.utf8)),
            .init(status: 200, body: Data(#"[{"msg_id":7,"message":{"hello":"world"},"read_ct":0}]"#.utf8)),
            .init(status: 200, body: Data(#"[{"msg_id":7,"message":{"hello":"world"},"read_ct":0}]"#.utf8)),
            .init(status: 204, body: Data()),
            .init(status: 204, body: Data()),
            .init(status: 201, body: Data()),
            .init(status: 204, body: Data()),
            .init(status: 201, body: Data(#"{"id":"task-1"}"#.utf8)),
            .init(status: 200, body: Data(#"{"id":"task-1","status":"queued"}"#.utf8)),
        ]
        RecordingURLProtocol.seen = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        return ReactorClient(url: "http://reactor.test", anonKey: "service-key", urlSession: URLSession(configuration: config))
    }

    func testQueueAndEnqueueUseTheServiceRoutes() async throws {
        let reactor = client()
        let created = try await reactor.queue.create("jobs")
        XCTAssertEqual(created["name"]?.string(), "jobs")
        let listed = try await reactor.queue.list()
        XCTAssertEqual(listed.array()?.first?["name"]?.string(), "jobs")
        let sent = try await reactor.queue.send("jobs", message: .object(["hello": .string("world")]), delaySecs: 5)
        guard case .int(7) = sent["msg_id"] else {
            return XCTFail("msg id \(String(describing: sent["msg_id"]))")
        }
        let read = try await reactor.queue.read("jobs", vtSecs: 10, qty: 2)
        XCTAssertEqual(read.array()?.count, 1)
        let peeked = try await reactor.queue.peek("jobs")
        XCTAssertEqual(peeked.array()?.count, 1)
        try await reactor.queue.delete("jobs", msgId: 7)
        try await reactor.queue.archive("jobs", msgId: 7)
        try await reactor.queue.subscribe("jobs", functionName: "echo", vtSecs: 30, qty: 1, maxReads: 3)
        try await reactor.queue.unsubscribe("jobs", functionName: "echo")
        let task = try await reactor.functions.enqueue("ping", body: .object(["n": .int(1)]), delaySecs: 2, maxAttempts: 1)
        XCTAssertEqual(task["id"]?.string(), "task-1")
        let status = try await reactor.functions.task("task-1")
        XCTAssertEqual(status["status"]?.string(), "queued")

        let paths = RecordingURLProtocol.seen.map { "\($0.method) \($0.path)" }
        XCTAssertEqual(paths, [
            "POST /queue/v1/queues",
            "GET /queue/v1/queues",
            "POST /queue/v1/queues/jobs/send",
            "POST /queue/v1/queues/jobs/read",
            "GET /queue/v1/queues/jobs/peek",
            "POST /queue/v1/queues/jobs/delete",
            "POST /queue/v1/queues/jobs/archive",
            "POST /queue/v1/queues/jobs/subscriptions",
            "DELETE /queue/v1/queues/jobs/subscriptions",
            "POST /fn/v1/ping/enqueue",
            "GET /fn/v1/_admin/tasks/task-1",
        ])
        let sendBody = try JSONSerialization.jsonObject(with: Data(RecordingURLProtocol.seen[2].body.utf8)) as! [String: Any]
        XCTAssertEqual((sendBody["message"] as! [String: Any])["hello"] as! String, "world")
        XCTAssertEqual(sendBody["delay_secs"] as! Int, 5)
        let readBody = try JSONSerialization.jsonObject(with: Data(RecordingURLProtocol.seen[3].body.utf8)) as! [String: Any]
        XCTAssertEqual(readBody["vt_secs"] as! Int, 10)
        XCTAssertEqual(readBody["qty"] as! Int, 2)
        let subBody = try JSONSerialization.jsonObject(with: Data(RecordingURLProtocol.seen[7].body.utf8)) as! [String: Any]
        XCTAssertEqual(subBody["function_name"] as! String, "echo")
        XCTAssertEqual(subBody["max_reads"] as! Int, 3)
        let unsubBody = try JSONSerialization.jsonObject(with: Data(RecordingURLProtocol.seen[8].body.utf8)) as! [String: Any]
        XCTAssertEqual(unsubBody["function_name"] as! String, "echo")
        let enqueueBody = try JSONSerialization.jsonObject(with: Data(RecordingURLProtocol.seen[9].body.utf8)) as! [String: Any]
        XCTAssertEqual(enqueueBody["delay_secs"] as! Int, 2)
        XCTAssertEqual(enqueueBody["max_attempts"] as! Int, 1)
    }
}
