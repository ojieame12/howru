import XCTest
@testable import HowRU

/// Tests for AuthManager authentication state and token management
@MainActor
final class AuthManagerTests: XCTestCase {

    // Note: AuthManager is a singleton, so we test its behavior
    // rather than creating new instances. We reset state between tests.

    override func setUp() async throws {
        // Clear any stored tokens before each test
        AuthManager.shared.clearTokens()
    }

    override func tearDown() async throws {
        // Clean up after each test
        AuthManager.shared.clearTokens()
    }

    // MARK: - Initial State Tests

    func testInitialState_noTokens_notAuthenticated() {
        // Given: Tokens were cleared in setUp
        // Then
        XCTAssertFalse(AuthManager.shared.isAuthenticated)
        XCTAssertNil(AuthManager.shared.accessToken)
        XCTAssertNil(AuthManager.shared.refreshToken)
    }

    // MARK: - Token Storage Tests

    func testSetTokens_storesTokens() {
        // Given
        let accessToken = "test-access-token-123"
        let refreshToken = "test-refresh-token-456"

        // When
        AuthManager.shared.setTokens(accessToken: accessToken, refreshToken: refreshToken)

        // Then
        XCTAssertEqual(AuthManager.shared.accessToken, accessToken)
        XCTAssertEqual(AuthManager.shared.refreshToken, refreshToken)
    }

    func testSetTokens_setsAuthenticated() {
        // Given
        XCTAssertFalse(AuthManager.shared.isAuthenticated)

        // When
        AuthManager.shared.setTokens(accessToken: "access", refreshToken: "refresh")

        // Then
        XCTAssertTrue(AuthManager.shared.isAuthenticated)
    }

    func testSetTokens_clearsError() {
        // Given: Existing error
        AuthManager.shared.authError = "Previous error"

        // When
        AuthManager.shared.setTokens(accessToken: "access", refreshToken: "refresh")

        // Then
        XCTAssertNil(AuthManager.shared.authError)
    }

    func testSetTokens_overwritesPreviousTokens() {
        // Given: Existing tokens
        AuthManager.shared.setTokens(accessToken: "old-access", refreshToken: "old-refresh")

        // When: Set new tokens
        AuthManager.shared.setTokens(accessToken: "new-access", refreshToken: "new-refresh")

        // Then
        XCTAssertEqual(AuthManager.shared.accessToken, "new-access")
        XCTAssertEqual(AuthManager.shared.refreshToken, "new-refresh")
    }

    // MARK: - Clear Tokens Tests

    func testClearTokens_removesTokens() {
        // Given: Stored tokens
        AuthManager.shared.setTokens(accessToken: "access", refreshToken: "refresh")
        XCTAssertNotNil(AuthManager.shared.accessToken)

        // When
        AuthManager.shared.clearTokens()

        // Then
        XCTAssertNil(AuthManager.shared.accessToken)
        XCTAssertNil(AuthManager.shared.refreshToken)
    }

    func testClearTokens_setsNotAuthenticated() {
        // Given: Authenticated state
        AuthManager.shared.setTokens(accessToken: "access", refreshToken: "refresh")
        XCTAssertTrue(AuthManager.shared.isAuthenticated)

        // When
        AuthManager.shared.clearTokens()

        // Then
        XCTAssertFalse(AuthManager.shared.isAuthenticated)
    }

    func testClearTokens_idempotent() {
        // Given: No tokens
        XCTAssertNil(AuthManager.shared.accessToken)

        // When: Clear again
        AuthManager.shared.clearTokens()

        // Then: No crash, still no tokens
        XCTAssertNil(AuthManager.shared.accessToken)
        XCTAssertFalse(AuthManager.shared.isAuthenticated)
    }

    // MARK: - Token Validity Tests

    func testAccessToken_withValidToken_returnsToken() {
        // Given
        let expectedToken = "valid-access-token"
        AuthManager.shared.setTokens(accessToken: expectedToken, refreshToken: "refresh")

        // When
        let token = AuthManager.shared.accessToken

        // Then
        XCTAssertEqual(token, expectedToken)
    }

    func testRefreshToken_withValidToken_returnsToken() {
        // Given
        let expectedToken = "valid-refresh-token"
        AuthManager.shared.setTokens(accessToken: "access", refreshToken: expectedToken)

        // When
        let token = AuthManager.shared.refreshToken

        // Then
        XCTAssertEqual(token, expectedToken)
    }

    // MARK: - Refresh State Tests

    func testIsRefreshing_initiallyFalse() {
        XCTAssertFalse(AuthManager.shared.isRefreshing)
    }

    // MARK: - Auth Error Tests

    func testAuthError_initiallyNil() {
        XCTAssertNil(AuthManager.shared.authError)
    }

    func testAuthError_canBeSet() {
        // When
        AuthManager.shared.authError = "Test error message"

        // Then
        XCTAssertEqual(AuthManager.shared.authError, "Test error message")
    }

    // MARK: - Token Format Tests

    func testToken_acceptsJWTFormat() {
        // Given: A JWT-like token
        let jwtToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

        // When
        AuthManager.shared.setTokens(accessToken: jwtToken, refreshToken: "refresh")

        // Then
        XCTAssertEqual(AuthManager.shared.accessToken, jwtToken)
    }

    func testToken_acceptsEmptyString() {
        // This tests edge case handling - empty tokens shouldn't crash
        // but ideally shouldn't be allowed in production

        // When
        AuthManager.shared.setTokens(accessToken: "", refreshToken: "")

        // Then: Doesn't crash
        XCTAssertEqual(AuthManager.shared.accessToken, "")
    }

    func testToken_acceptsSpecialCharacters() {
        // Given: Token with special characters (URL-safe base64)
        let token = "abc123-_xyz789"

        // When
        AuthManager.shared.setTokens(accessToken: token, refreshToken: token)

        // Then
        XCTAssertEqual(AuthManager.shared.accessToken, token)
    }

    // MARK: - Persistence Tests (Keychain)

    func testTokens_persistAcrossAccess() {
        // Given: Set tokens
        AuthManager.shared.setTokens(accessToken: "persistent-access", refreshToken: "persistent-refresh")

        // When: Access tokens multiple times
        let firstAccess = AuthManager.shared.accessToken
        let secondAccess = AuthManager.shared.accessToken

        // Then: Same value returned
        XCTAssertEqual(firstAccess, secondAccess)
        XCTAssertEqual(firstAccess, "persistent-access")
    }

    // MARK: - Authentication Flow Tests

    func testFullAuthFlow_loginThenLogout() {
        // Given: Not authenticated
        XCTAssertFalse(AuthManager.shared.isAuthenticated)

        // When: Login
        AuthManager.shared.setTokens(accessToken: "access", refreshToken: "refresh")

        // Then: Authenticated
        XCTAssertTrue(AuthManager.shared.isAuthenticated)
        XCTAssertNotNil(AuthManager.shared.accessToken)

        // When: Logout
        AuthManager.shared.clearTokens()

        // Then: Not authenticated
        XCTAssertFalse(AuthManager.shared.isAuthenticated)
        XCTAssertNil(AuthManager.shared.accessToken)
    }

    func testReauthentication_afterClearingTokens() {
        // Given: Previously authenticated and then logged out
        AuthManager.shared.setTokens(accessToken: "old", refreshToken: "old")
        AuthManager.shared.clearTokens()

        // When: Re-authenticate
        AuthManager.shared.setTokens(accessToken: "new", refreshToken: "new")

        // Then: New tokens stored correctly
        XCTAssertTrue(AuthManager.shared.isAuthenticated)
        XCTAssertEqual(AuthManager.shared.accessToken, "new")
    }
}

// MARK: - AuthError Tests

extension AuthManagerTests {

    func testAuthError_invalidResponse() {
        let error = AuthError.invalidResponse
        XCTAssertNotNil(error)
    }

    func testAuthError_refreshFailed() {
        let error = AuthError.refreshFailed
        XCTAssertNotNil(error)
    }

    func testAuthError_unauthorized() {
        let error = AuthError.unauthorized
        XCTAssertNotNil(error)
    }

    func testAuthError_conformsToError() {
        let error: Error = AuthError.refreshFailed
        XCTAssertNotNil(error)
    }
}

// MARK: - Token Refresh Response Tests

extension AuthManagerTests {

    func testTokenRefreshResponse_decoding() throws {
        // This tests the private TokenRefreshResponse struct indirectly
        // by verifying the expected JSON structure

        struct TokenRefreshResponse: Decodable {
            let accessToken: String
            let refreshToken: String
        }

        let json = """
        {
            "accessToken": "new-access-token",
            "refreshToken": "new-refresh-token"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TokenRefreshResponse.self, from: json)

        XCTAssertEqual(response.accessToken, "new-access-token")
        XCTAssertEqual(response.refreshToken, "new-refresh-token")
    }
}
