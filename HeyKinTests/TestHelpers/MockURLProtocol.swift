import Foundation

/// Mock URL Protocol for testing network requests
class MockURLProtocol: URLProtocol {
    /// Map of URL patterns to response handlers
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Error to throw for simulating network errors
    static var error: Error?

    /// Recorded requests for verification
    static var recordedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        // Record the request
        MockURLProtocol.recordedRequests.append(request)

        // Check for simulated error
        if let error = MockURLProtocol.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        // Get mock response
        guard let handler = MockURLProtocol.requestHandler else {
            let error = NSError(domain: "MockURLProtocol", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "No request handler set"
            ])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op
    }

    /// Reset all state between tests
    static func reset() {
        requestHandler = nil
        error = nil
        recordedRequests = []
    }

    /// Create a mock JSON response
    static func mockJSONResponse(
        statusCode: Int,
        json: [String: Any],
        url: URL = URL(string: "http://localhost:3000")!
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = try! JSONSerialization.data(withJSONObject: json)
        return (response, data)
    }

    /// Create a mock success response with Codable data
    static func mockCodableResponse<T: Encodable>(
        statusCode: Int = 200,
        data: T,
        url: URL = URL(string: "http://localhost:3000")!
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let responseData = try! encoder.encode(data)
        return (response, responseData)
    }
}
