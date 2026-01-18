import XCTest
import SwiftData
@testable import HowRU

/// Tests for InviteManager deep link handling
@MainActor
final class InviteManagerTests: XCTestCase {

    var container: TestContainer!
    var inviteManager: InviteManager!

    override func setUp() async throws {
        container = try TestContainer()
        inviteManager = InviteManager()
    }

    override func tearDown() async throws {
        try container.reset()
        container = nil
        inviteManager = nil
    }

    // MARK: - URL Parsing Tests

    func testHandleURL_validInviteLink_extractsCode() {
        // Given
        let url = URL(string: "howru://invite?code=ABC123")!

        // When
        inviteManager.handleURL(url)

        // Then
        XCTAssertEqual(inviteManager.pendingInviteCode, "ABC123")
        XCTAssertNil(inviteManager.error)
    }

    func testHandleURL_validInviteLink_withLongCode() {
        // Given: Real-world invite code
        let url = URL(string: "howru://invite?code=invite_Xk7mN2pQ9rT5vW8y")!

        // When
        inviteManager.handleURL(url)

        // Then
        XCTAssertEqual(inviteManager.pendingInviteCode, "invite_Xk7mN2pQ9rT5vW8y")
    }

    func testHandleURL_invalidScheme_doesNotSetCode() {
        // Given: Wrong URL scheme
        let url = URL(string: "https://howru.app/invite?code=ABC123")!

        // When
        inviteManager.handleURL(url)

        // Then
        XCTAssertNil(inviteManager.pendingInviteCode)
    }

    func testHandleURL_invalidHost_doesNotSetCode() {
        // Given: Wrong host
        let url = URL(string: "howru://checkin?code=ABC123")!

        // When
        inviteManager.handleURL(url)

        // Then
        XCTAssertNil(inviteManager.pendingInviteCode)
    }

    func testHandleURL_missingCode_setsError() {
        // Given: No code parameter
        let url = URL(string: "howru://invite")!

        // When
        inviteManager.handleURL(url)

        // Then
        XCTAssertNil(inviteManager.pendingInviteCode)
        XCTAssertEqual(inviteManager.error, "Invalid invite link")
    }

    func testHandleURL_emptyCode_setsError() {
        // Given: Empty code value
        let url = URL(string: "howru://invite?code=")!

        // When
        inviteManager.handleURL(url)

        // Then
        XCTAssertNil(inviteManager.pendingInviteCode)
        XCTAssertEqual(inviteManager.error, "Invalid invite link")
    }

    func testHandleURL_codeWithSpecialCharacters() {
        // Given: Code with URL-safe special characters
        let url = URL(string: "howru://invite?code=ABC-123_XYZ")!

        // When
        inviteManager.handleURL(url)

        // Then
        XCTAssertEqual(inviteManager.pendingInviteCode, "ABC-123_XYZ")
    }

    func testHandleURL_withAdditionalQueryParams_extractsCode() {
        // Given: URL with extra params
        let url = URL(string: "howru://invite?code=ABC123&utm_source=sms")!

        // When
        inviteManager.handleURL(url)

        // Then
        XCTAssertEqual(inviteManager.pendingInviteCode, "ABC123")
    }

    // MARK: - State Management Tests

    func testClearPendingInvite_resetsAllState() {
        // Given: Manager with pending invite
        inviteManager.pendingInviteCode = "ABC123"
        inviteManager.invitePreview = InvitePreview(
            code: "ABC123",
            inviterName: "Test User",
            role: "supporter",
            permissions: InvitePermissions(
                canSeeMood: true,
                canSeeLocation: false,
                canSeeSelfie: true,
                canPoke: true
            ),
            expiresAt: nil
        )
        inviteManager.isLoading = true
        inviteManager.error = "Some error"
        inviteManager.requiresAuth = true

        // When
        inviteManager.clearPendingInvite()

        // Then
        XCTAssertNil(inviteManager.pendingInviteCode)
        XCTAssertNil(inviteManager.invitePreview)
        XCTAssertFalse(inviteManager.isLoading)
        XCTAssertNil(inviteManager.error)
        XCTAssertFalse(inviteManager.requiresAuth)
    }

    func testDeclineInvite_clearsState() {
        // Given: Manager with pending invite
        inviteManager.pendingInviteCode = "ABC123"
        inviteManager.invitePreview = InvitePreview(
            code: "ABC123",
            inviterName: "Test User",
            role: "supporter",
            permissions: InvitePermissions(
                canSeeMood: true,
                canSeeLocation: false,
                canSeeSelfie: true,
                canPoke: true
            ),
            expiresAt: nil
        )

        // When
        inviteManager.declineInvite()

        // Then
        XCTAssertNil(inviteManager.pendingInviteCode)
        XCTAssertNil(inviteManager.invitePreview)
    }

    // MARK: - Accept Invite Tests

    func testAcceptInvite_withoutPendingCode_returnsFalse() async {
        // Given: No pending invite
        XCTAssertNil(inviteManager.pendingInviteCode)
        let currentUser = Factories.supporter(name: "Current User")

        // When
        let result = await inviteManager.acceptInvite(
            modelContext: container.context,
            currentUser: currentUser
        )

        // Then
        XCTAssertFalse(result)
        XCTAssertEqual(inviteManager.error, "No pending invite")
    }

    // Note: The acceptInvite method now calls the API, so these tests
    // would require network mocking. The URL parsing tests above cover
    // the synchronous logic. API integration tests should be done separately.

    // MARK: - Fetch Preview Tests
    // Note: fetchInvitePreview now calls the API, so these tests would
    // require network mocking. See APIClientTests for network testing patterns.

    // MARK: - InvitePreview Tests

    func testInvitePreview_supporterRole() {
        let preview = InvitePreview(
            code: "ABC123",
            inviterName: "Mom",
            role: "supporter",
            permissions: InvitePermissions(
                canSeeMood: true,
                canSeeLocation: true,
                canSeeSelfie: true,
                canPoke: true
            ),
            expiresAt: nil
        )

        XCTAssertEqual(preview.role, "supporter")
        XCTAssertTrue(preview.permissions.canSeeMood)
        XCTAssertTrue(preview.permissions.canPoke)
    }

    func testInvitePreview_withExpiration() {
        let futureDate = Date().addingTimeInterval(24 * 60 * 60) // 24 hours from now
        let preview = InvitePreview(
            code: "ABC123",
            inviterName: "Mom",
            role: "supporter",
            permissions: InvitePermissions(
                canSeeMood: true,
                canSeeLocation: false,
                canSeeSelfie: false,
                canPoke: true
            ),
            expiresAt: futureDate
        )

        XCTAssertNotNil(preview.expiresAt)
        XCTAssertEqual(preview.inviterName, "Mom")
    }

    // MARK: - Edge Cases

    func testHandleURL_consecutiveCalls_overwritesPreviousCode() {
        // Given: First invite
        let url1 = URL(string: "howru://invite?code=FIRST")!
        inviteManager.handleURL(url1)
        XCTAssertEqual(inviteManager.pendingInviteCode, "FIRST")

        // When: Second invite
        let url2 = URL(string: "howru://invite?code=SECOND")!
        inviteManager.handleURL(url2)

        // Then: Should have new code
        XCTAssertEqual(inviteManager.pendingInviteCode, "SECOND")
    }

    func testInitialState() {
        // Given: Fresh instance
        let manager = InviteManager()

        // Then: All state should be nil/false
        XCTAssertNil(manager.pendingInviteCode)
        XCTAssertNil(manager.invitePreview)
        XCTAssertFalse(manager.isLoading)
        XCTAssertNil(manager.error)
        XCTAssertFalse(manager.requiresAuth)
    }

    // MARK: - RequiresAuth State Tests

    func testRequiresAuth_initiallyFalse() {
        XCTAssertFalse(inviteManager.requiresAuth)
    }

    func testRequiresAuth_clearedOnClear() {
        // Given
        inviteManager.requiresAuth = true

        // When
        inviteManager.clearPendingInvite()

        // Then
        XCTAssertFalse(inviteManager.requiresAuth)
    }
}
