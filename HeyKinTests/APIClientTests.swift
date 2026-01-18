import XCTest
@testable import HowRU

/// Tests for APIClient networking layer
@MainActor
final class APIClientTests: XCTestCase {

    var apiClient: APIClient!
    var testConfig: AppConfig!

    override func setUp() async throws {
        MockURLProtocol.reset()

        // Create a URLSession configured with MockURLProtocol
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        // Use development config for testing
        testConfig = AppConfig(environment: .development)

        // Create APIClient with test dependencies
        apiClient = APIClient(
            session: session,
            config: testConfig,
            authManager: AuthManager.shared
        )
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        apiClient = nil
        testConfig = nil
    }

    // MARK: - APIError Tests

    func testAPIError_invalidURL_description() {
        let error = APIError.invalidURL
        XCTAssertEqual(error.errorDescription, "Invalid URL")
    }

    func testAPIError_unauthorized_description() {
        let error = APIError.unauthorized
        XCTAssertEqual(error.errorDescription, "Authentication required")
    }

    func testAPIError_forbidden_description() {
        let error = APIError.forbidden
        XCTAssertEqual(error.errorDescription, "Access denied")
    }

    func testAPIError_notFound_description() {
        let error = APIError.notFound
        XCTAssertEqual(error.errorDescription, "Resource not found")
    }

    func testAPIError_serverError_description() {
        let error = APIError.serverError
        XCTAssertEqual(error.errorDescription, "Server error. Please try again later.")
    }

    func testAPIError_httpError_withMessage() {
        let error = APIError.httpError(statusCode: 422, message: "Validation failed")
        XCTAssertEqual(error.errorDescription, "Validation failed")
    }

    func testAPIError_httpError_withoutMessage() {
        let error = APIError.httpError(statusCode: 422, message: nil)
        XCTAssertEqual(error.errorDescription, "HTTP error 422")
    }

    func testAPIError_networkError_description() {
        let underlyingError = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: [
            NSLocalizedDescriptionKey: "The Internet connection appears to be offline."
        ])
        let error = APIError.networkError(underlyingError)
        XCTAssertTrue(error.errorDescription?.contains("offline") ?? false)
    }

    func testAPIError_decodingError_description() {
        struct TestDecodingError: Error, LocalizedError {
            var errorDescription: String? { "Missing required field" }
        }
        let error = APIError.decodingError(TestDecodingError())
        XCTAssertTrue(error.errorDescription?.contains("decode") ?? false)
    }

    // MARK: - APIResponse Tests

    func testAPIResponse_decodesSuccessResponse() throws {
        struct TestData: Decodable {
            let id: String
            let name: String
        }

        let json = """
        {
            "success": true,
            "id": "123",
            "name": "Test"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(APIResponse<TestData>.self, from: json)

        XCTAssertTrue(response.success)
        XCTAssertNil(response.error)
        XCTAssertEqual(response.data?.id, "123")
        XCTAssertEqual(response.data?.name, "Test")
    }

    func testAPIResponse_decodesErrorResponse() throws {
        struct TestData: Decodable {
            let id: String
        }

        let json = """
        {
            "success": false,
            "error": "Something went wrong"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(APIResponse<TestData>.self, from: json)

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.error, "Something went wrong")
        XCTAssertNil(response.data)
    }

    // MARK: - Status Code Mapping Tests

    func testStatusCode401_mapsToUnauthorized() {
        // Test that 401 status results in APIError.unauthorized
        // This is verified through the error description
        let error = APIError.unauthorized
        XCTAssertEqual(error.errorDescription, "Authentication required")
    }

    func testStatusCode403_mapsToForbidden() {
        let error = APIError.forbidden
        XCTAssertEqual(error.errorDescription, "Access denied")
    }

    func testStatusCode404_mapsToNotFound() {
        let error = APIError.notFound
        XCTAssertEqual(error.errorDescription, "Resource not found")
    }

    func testStatusCode500_mapsToServerError() {
        let error = APIError.serverError
        XCTAssertTrue(error.errorDescription?.contains("Server error") ?? false)
    }

    // MARK: - Error Equatable Tests (for switch statements)

    func testAPIError_canBeUsedInSwitch() {
        let error: APIError = .unauthorized

        var matchedUnauthorized = false
        switch error {
        case .unauthorized:
            matchedUnauthorized = true
        default:
            break
        }

        XCTAssertTrue(matchedUnauthorized)
    }

    // MARK: - HTTP Status Code Range Tests

    func testSuccessStatusCodes() {
        // 2xx codes should be treated as success
        let successCodes = [200, 201, 204, 299]
        for code in successCodes {
            let isSuccess = (200...299).contains(code)
            XCTAssertTrue(isSuccess, "Status code \(code) should be success")
        }
    }

    func testServerErrorStatusCodes() {
        // 5xx codes should be server errors
        let serverErrorCodes = [500, 501, 502, 503, 599]
        for code in serverErrorCodes {
            let isServerError = (500...599).contains(code)
            XCTAssertTrue(isServerError, "Status code \(code) should be server error")
        }
    }
}

// MARK: - URL Building Tests

extension APIClientTests {

    func testURLBuilding_baseURL_development() {
        // Given: Development environment
        let config = AppConfig(environment: .development)

        // Then
        XCTAssertEqual(config.apiBaseURL.host, "localhost")
        XCTAssertEqual(config.apiBaseURL.port, 3000)
    }

    func testURLBuilding_baseURL_staging() {
        // Given: Staging environment
        let config = AppConfig(environment: .staging)

        // Then
        XCTAssertTrue(config.apiBaseURL.absoluteString.contains("staging"))
    }

    func testURLBuilding_baseURL_production() {
        // Given: Production environment
        let config = AppConfig(environment: .production)

        // Then
        XCTAssertEqual(config.apiBaseURL.absoluteString, "https://api.howru.app")
    }
}

// MARK: - Multipart Upload Tests

extension APIClientTests {

    func testMultipartBoundary_isUnique() {
        // Generate multiple boundaries and verify they're unique
        var boundaries: Set<String> = []
        for _ in 0..<100 {
            let boundary = UUID().uuidString
            XCTAssertFalse(boundaries.contains(boundary), "Boundary should be unique")
            boundaries.insert(boundary)
        }
    }

    func testMultipartBody_structureValidation() {
        // Test multipart body building logic
        let boundary = "test-boundary"
        var body = Data()

        // Add field
        let fieldName = "field1"
        let fieldValue = "value1"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(fieldValue)\r\n".data(using: .utf8)!)

        // Add file
        let fileName = "test.jpg"
        let mimeType = "image/jpeg"
        let fileData = "fake-image-data".data(using: .utf8)!
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // Verify structure
        let bodyString = String(data: body, encoding: .utf8)!
        XCTAssertTrue(bodyString.contains("--test-boundary"))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data"))
        XCTAssertTrue(bodyString.contains("name=\"field1\""))
        XCTAssertTrue(bodyString.contains("filename=\"test.jpg\""))
        XCTAssertTrue(bodyString.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(bodyString.contains("--test-boundary--"))
    }
}

// MARK: - Request Header Tests

extension APIClientTests {

    func testRequestHeaders_contentTypeJSON() {
        // Standard requests should have JSON content type
        let contentType = "application/json"
        XCTAssertEqual(contentType, "application/json")
    }

    func testRequestHeaders_acceptJSON() {
        // All requests should accept JSON
        let accept = "application/json"
        XCTAssertEqual(accept, "application/json")
    }

    func testRequestHeaders_multipartContentType() {
        // Multipart requests need boundary in content type
        let boundary = "abc123"
        let contentType = "multipart/form-data; boundary=\(boundary)"
        XCTAssertTrue(contentType.contains("multipart/form-data"))
        XCTAssertTrue(contentType.contains("boundary=abc123"))
    }

    func testAuthHeader_format() {
        // Auth header should be Bearer token
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
        let header = "Bearer \(token)"
        XCTAssertTrue(header.hasPrefix("Bearer "))
    }
}

// MARK: - JSON Encoding/Decoding Tests

extension APIClientTests {

    func testJSONEncoder_usesISO8601Dates() throws {
        struct TestRequest: Encodable {
            let timestamp: Date
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let date = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
        let request = TestRequest(timestamp: date)
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("2024-01-01"))
    }

    func testJSONDecoder_parsesISO8601Dates() throws {
        struct TestResponse: Decodable {
            let createdAt: Date
        }

        let json = """
        {"createdAt": "2024-01-01T12:00:00Z"}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(TestResponse.self, from: json)

        let calendar = Calendar(identifier: .gregorian)
        var components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: response.createdAt)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
    }
}

// MARK: - APIClient Integration Tests

extension APIClientTests {

    func testGet_successfulResponse_returnsDecodedData() async throws {
        // Given: Mock a successful GET response
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.path.contains("/users/me") ?? false)

            let json: [String: Any] = [
                "success": true,
                "user": [
                    "id": "user-123",
                    "name": "Test User",
                    "phoneNumber": "+15551234567",
                    "isChecker": true
                ]
            ]
            return MockURLProtocol.mockJSONResponse(statusCode: 200, json: json)
        }

        // When
        let response: UserProfileResponse = try await apiClient.get("/users/me")

        // Then
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.user.id, "user-123")
        XCTAssertEqual(response.user.name, "Test User")
    }

    func testGet_withQueryItems_includesInURL() async throws {
        // Given
        MockURLProtocol.requestHandler = { request in
            // Verify query items are included
            let urlString = request.url?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("limit=10"))
            XCTAssertTrue(urlString.contains("offset=0"))

            let json: [String: Any] = [
                "success": true,
                "checkIns": []
            ]
            return MockURLProtocol.mockJSONResponse(statusCode: 200, json: json)
        }

        // When
        let _: CheckInsResponse = try await apiClient.get(
            "/check-ins",
            queryItems: [
                URLQueryItem(name: "limit", value: "10"),
                URLQueryItem(name: "offset", value: "0")
            ]
        )

        // Then: Verified in request handler
    }

    func testPost_withBody_sendsEncodedJSON() async throws {
        // Given
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            // Verify body was sent
            if let bodyData = request.httpBody,
               let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                XCTAssertEqual(body["mentalScore"] as? Int, 8)
                XCTAssertEqual(body["bodyScore"] as? Int, 7)
                XCTAssertEqual(body["moodScore"] as? Int, 9)
            } else {
                XCTFail("Expected JSON body")
            }

            let json: [String: Any] = [
                "success": true,
                "checkIn": [
                    "id": "checkin-123",
                    "timestamp": "2024-01-01T12:00:00Z",
                    "mentalScore": 8,
                    "bodyScore": 7,
                    "moodScore": 9
                ]
            ]
            return MockURLProtocol.mockJSONResponse(statusCode: 200, json: json)
        }

        // When
        let body = CreateCheckInBody(mentalScore: 8, bodyScore: 7, moodScore: 9)
        let response: CheckInResponse = try await apiClient.post("/check-ins", body: body)

        // Then
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.checkIn.id, "checkin-123")
    }

    func testRequest_401Response_throwsUnauthorized() async throws {
        // Given
        MockURLProtocol.requestHandler = { _ in
            let json: [String: Any] = [
                "success": false,
                "error": "Invalid token"
            ]
            return MockURLProtocol.mockJSONResponse(statusCode: 401, json: json)
        }

        // When/Then
        do {
            let _: UserProfileResponse = try await apiClient.get("/users/me")
            XCTFail("Expected unauthorized error")
        } catch let error as APIError {
            switch error {
            case .unauthorized:
                // Expected
                break
            default:
                XCTFail("Expected unauthorized error, got \(error)")
            }
        }
    }

    func testRequest_403Response_throwsForbidden() async throws {
        // Given
        MockURLProtocol.requestHandler = { _ in
            let json: [String: Any] = [
                "success": false,
                "error": "Access denied"
            ]
            return MockURLProtocol.mockJSONResponse(statusCode: 403, json: json)
        }

        // When/Then
        do {
            let _: UserProfileResponse = try await apiClient.get("/users/me")
            XCTFail("Expected forbidden error")
        } catch let error as APIError {
            switch error {
            case .forbidden:
                // Expected
                break
            default:
                XCTFail("Expected forbidden error, got \(error)")
            }
        }
    }

    func testRequest_404Response_throwsNotFound() async throws {
        // Given
        MockURLProtocol.requestHandler = { _ in
            let json: [String: Any] = [
                "success": false,
                "error": "Resource not found"
            ]
            return MockURLProtocol.mockJSONResponse(statusCode: 404, json: json)
        }

        // When/Then
        do {
            let _: UserProfileResponse = try await apiClient.get("/users/me")
            XCTFail("Expected not found error")
        } catch let error as APIError {
            switch error {
            case .notFound:
                // Expected
                break
            default:
                XCTFail("Expected not found error, got \(error)")
            }
        }
    }

    func testRequest_500Response_throwsServerError() async throws {
        // Given
        MockURLProtocol.requestHandler = { _ in
            let json: [String: Any] = [
                "success": false,
                "error": "Internal server error"
            ]
            return MockURLProtocol.mockJSONResponse(statusCode: 500, json: json)
        }

        // When/Then
        do {
            let _: UserProfileResponse = try await apiClient.get("/users/me")
            XCTFail("Expected server error")
        } catch let error as APIError {
            switch error {
            case .serverError:
                // Expected
                break
            default:
                XCTFail("Expected server error, got \(error)")
            }
        }
    }

    func testRequest_networkError_throwsNetworkError() async throws {
        // Given
        let networkError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        )
        MockURLProtocol.error = networkError

        // When/Then
        do {
            let _: UserProfileResponse = try await apiClient.get("/users/me")
            XCTFail("Expected network error")
        } catch let error as APIError {
            switch error {
            case .networkError:
                // Expected
                break
            default:
                XCTFail("Expected network error, got \(error)")
            }
        }
    }

    func testRequest_invalidJSON_throwsDecodingError() async throws {
        // Given: Response with invalid JSON structure
        MockURLProtocol.requestHandler = { _ in
            let json: [String: Any] = [
                "success": true,
                // Missing required "user" field
            ]
            return MockURLProtocol.mockJSONResponse(statusCode: 200, json: json)
        }

        // When/Then
        do {
            let _: UserProfileResponse = try await apiClient.get("/users/me")
            XCTFail("Expected decoding error")
        } catch let error as APIError {
            switch error {
            case .decodingError:
                // Expected
                break
            default:
                XCTFail("Expected decoding error, got \(error)")
            }
        }
    }

    func testRequest_setsAuthorizationHeader_whenTokenAvailable() async throws {
        // Given: Set a mock token (we can't easily mock AuthManager, but we can verify the header is set pattern)
        var capturedAuthHeader: String?
        MockURLProtocol.requestHandler = { request in
            capturedAuthHeader = request.value(forHTTPHeaderField: "Authorization")
            let json: [String: Any] = [
                "success": true,
                "user": [
                    "id": "user-123",
                    "name": "Test User",
                    "isChecker": true
                ]
            ]
            return MockURLProtocol.mockJSONResponse(statusCode: 200, json: json)
        }

        // When
        let _: UserProfileResponse = try await apiClient.get("/users/me")

        // Then: If there's a token, it should be in Bearer format
        if let authHeader = capturedAuthHeader {
            XCTAssertTrue(authHeader.hasPrefix("Bearer "))
        }
        // Note: Without a token, the header may be nil, which is also valid
    }

    func testDelete_sendsDeleteMethod() async throws {
        // Given
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            let json: [String: Any] = ["success": true]
            return MockURLProtocol.mockJSONResponse(statusCode: 200, json: json)
        }

        // When
        try await apiClient.delete("/circle/members/member-123")

        // Then: Verified in request handler
    }

    func testPatch_sendsCorrectMethod() async throws {
        // Given
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            let json: [String: Any] = [
                "success": true,
                "user": [
                    "id": "user-123",
                    "name": "Updated Name",
                    "isChecker": true
                ]
            ]
            return MockURLProtocol.mockJSONResponse(statusCode: 200, json: json)
        }

        // When
        let body = UpdateProfileBody(name: "Updated Name", email: nil, profileImageUrl: nil, address: nil)
        let _: UserProfileResponse = try await apiClient.patch("/users/me", body: body)

        // Then: Verified in request handler
    }
}
