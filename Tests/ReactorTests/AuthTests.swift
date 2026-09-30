import XCTest
@testable import Reactor

final class ScriptedURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class AuthTests: XCTestCase {
    private func client(json: String) -> ReactorClient {
        ScriptedURLProtocol.payload = Data(json.utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedURLProtocol.self]
        return ReactorClient(url: "http://reactor.test", anonKey: "anon", urlSession: URLSession(configuration: config))
    }

    func testVerificationDoesNotStoreASession() async throws {
        let reactor = client(json: #"{"verification_required":true,"user":{"id":"u","email":"a@b.co"}}"#)
        let outcome = try await reactor.auth.signUp(email: "a@b.co", password: "password123")
        guard case .verificationRequired(let user) = outcome else {
            return XCTFail("expected verification")
        }
        XCTAssertEqual(user.email, "a@b.co")
        XCTAssertNil(reactor.auth.getSession())
    }

    func testMfaAndEnrollmentStayOutOfTheSession() async throws {
        var reactor = client(json: #"{"mfa_required":true,"mfa_token":"mfa","factors":["totp"]}"#)
        let challenged = try await reactor.auth.signInWithPassword(email: "a@b.co", password: "password123")
        guard case .mfaRequired(let token, let factors) = challenged else {
            return XCTFail("expected mfa")
        }
        XCTAssertEqual(token, "mfa")
        XCTAssertEqual(factors, ["totp"])
        XCTAssertNil(reactor.auth.getSession())

        reactor = client(json: #"{"enrollment_required":true,"enroll_token":"enroll","factors":[]}"#)
        let enroll = try await reactor.auth.signInWithPassword(email: "a@b.co", password: "password123")
        guard case .enrollmentRequired(let enrollToken, _) = enroll else {
            return XCTFail("expected enrollment")
        }
        XCTAssertEqual(enrollToken, "enroll")
        XCTAssertNil(reactor.auth.getSession())
    }

    func testSessionAndOAuthCodeAreStored() async throws {
        let reactor = client(json: #"{"access_token":"access","refresh_token":"refresh","user":{"id":"u","email":"a@b.co"}}"#)
        let verified = try await reactor.auth.verifyEmail(email: "a@b.co", code: "123456")
        XCTAssertEqual(verified.accessToken, "access")
        XCTAssertEqual(reactor.auth.getSession()?.accessToken, "access")
        let url = reactor.auth.signInWithOAuth(provider: "google", redirectTo: "https://app.example/cb")
        XCTAssertEqual(url.path, "/auth/v1/authorize")
        XCTAssertTrue(url.query?.contains("provider=google") == true)
        let exchanged = try await reactor.auth.exchangeCode("code")
        XCTAssertEqual(exchanged.refreshToken, "refresh")
    }
}
