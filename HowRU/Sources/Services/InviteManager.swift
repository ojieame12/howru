import Foundation

/// Represents invite preview data from the API
struct InvitePreview {
    let code: String
    let inviterName: String
    let role: String
    let permissions: InvitePermissions
    let expiresAt: Date?
}

struct InvitePermissions {
    let canSeeMood: Bool
    let canSeeLocation: Bool
    let canSeeSelfie: Bool
    let canPoke: Bool
}

/// Manages deep link invite handling and invite creation
@MainActor
@Observable
final class InviteManager {
    // MARK: - State

    var pendingInviteCode: String?
    var invitePreview: InvitePreview?
    var isLoading = false
    var error: String?
    var requiresAuth = false

    // Created invite state
    var createdInviteCode: String?
    var createdInviteLink: String?

    // MARK: - Create Invite

    /// Create a new invite link
    /// - Parameters:
    ///   - role: The role for the invited user (supporter or checker)
    ///   - canSeeMood: Whether they can see mood scores
    ///   - canSeeLocation: Whether they can see location
    ///   - canSeeSelfie: Whether they can see selfies
    ///   - canPoke: Whether they can send pokes
    /// - Returns: The invite link or nil if failed
    func createInvite(
        role: String = "supporter",
        canSeeMood: Bool = true,
        canSeeLocation: Bool = false,
        canSeeSelfie: Bool = false,
        canPoke: Bool = true
    ) async -> String? {
        guard AuthManager.shared.isAuthenticated else {
            error = "Please sign in to create invites"
            return nil
        }

        isLoading = true
        error = nil

        do {
            let body = CreateInviteBody(
                role: role,
                canSeeMood: canSeeMood,
                canSeeLocation: canSeeLocation,
                canSeeSelfie: canSeeSelfie,
                canPoke: canPoke,
                expiresInHours: 48
            )

            let response: CreateInviteResponse = try await APIClient.shared.post("/circle/invites", body: body)

            createdInviteCode = response.invite.code
            createdInviteLink = response.invite.link

            isLoading = false
            return response.invite.link
        } catch {
            self.error = "Failed to create invite"
            isLoading = false
            return nil
        }
    }

    /// Send invite via email
    func sendInviteViaEmail(
        email: String,
        role: String = "supporter",
        canSeeMood: Bool = true,
        canSeeLocation: Bool = false,
        canSeeSelfie: Bool = false,
        canPoke: Bool = true
    ) async -> Bool {
        guard AuthManager.shared.isAuthenticated else {
            error = "Please sign in to send invites"
            return false
        }

        isLoading = true
        error = nil

        do {
            let body = SendInviteBody(
                email: email,
                role: role,
                canSeeMood: canSeeMood,
                canSeeLocation: canSeeLocation,
                canSeeSelfie: canSeeSelfie,
                canPoke: canPoke
            )

            let _: SendInviteResponse = try await APIClient.shared.post("/circle/invites/send", body: body)

            isLoading = false
            return true
        } catch {
            self.error = "Failed to send invite"
            isLoading = false
            return false
        }
    }

    /// Clear created invite state
    func clearCreatedInvite() {
        createdInviteCode = nil
        createdInviteLink = nil
    }

    // MARK: - URL Handling

    /// Handle incoming URL and extract invite code
    func handleURL(_ url: URL) {
        guard url.scheme == "howru",
              url.host == "invite" else {
            return
        }

        // Parse ?code=XXX from URL
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let codeItem = components.queryItems?.first(where: { $0.name == "code" }),
              let code = codeItem.value,
              !code.isEmpty else {
            error = "Invalid invite link"
            return
        }

        pendingInviteCode = code
        Task {
            await fetchInvitePreview(code: code)
        }
    }

    // MARK: - API Calls

    /// Fetch invite details from backend
    func fetchInvitePreview(code: String) async {
        isLoading = true
        error = nil
        requiresAuth = false

        do {
            // Check if user is authenticated
            let isAuthenticated = AuthManager.shared.isAuthenticated

            if isAuthenticated {
                // Fetch from authenticated endpoint
                let response: InvitePreviewResponse = try await APIClient.shared.get("/circle/invites/\(code)")

                invitePreview = InvitePreview(
                    code: code,
                    inviterName: response.invite.inviterName,
                    role: response.invite.role,
                    permissions: InvitePermissions(
                        canSeeMood: response.invite.permissions.canSeeMood,
                        canSeeLocation: response.invite.permissions.canSeeLocation,
                        canSeeSelfie: response.invite.permissions.canSeeSelfie,
                        canPoke: response.invite.permissions.canPoke
                    ),
                    expiresAt: response.invite.expiresAt
                )
            } else {
                // Try public endpoint first
                do {
                    let response: InvitePreviewResponse = try await fetchPublicInvitePreview(code: code)

                    invitePreview = InvitePreview(
                        code: code,
                        inviterName: response.invite.inviterName,
                        role: response.invite.role,
                        permissions: InvitePermissions(
                            canSeeMood: response.invite.permissions.canSeeMood,
                            canSeeLocation: response.invite.permissions.canSeeLocation,
                            canSeeSelfie: response.invite.permissions.canSeeSelfie,
                            canPoke: response.invite.permissions.canPoke
                        ),
                        expiresAt: response.invite.expiresAt
                    )
                } catch APIError.unauthorized {
                    // Public endpoint not available, user needs to log in
                    requiresAuth = true
                    error = "Please sign in to view this invite"
                }
            }

            isLoading = false
        } catch APIError.notFound {
            error = "This invite link has expired or is invalid"
            isLoading = false
        } catch APIError.unauthorized {
            requiresAuth = true
            error = "Please sign in to view this invite"
            isLoading = false
        } catch {
            self.error = "Failed to load invite details"
            isLoading = false
        }
    }

    /// Fetch invite preview from public endpoint (no auth required)
    private func fetchPublicInvitePreview(code: String) async throws -> InvitePreviewResponse {
        let url = AppConfig.shared.apiBaseURL.appendingPathComponent("/circle/invites/\(code)/public")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(InvitePreviewResponse.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    /// Accept the pending invite
    func acceptInvite() async -> Bool {
        guard let code = pendingInviteCode else {
            error = "No pending invite"
            return false
        }

        isLoading = true
        error = nil

        do {
            let response: AcceptInviteResponse = try await APIClient.shared.post("/circle/invites/\(code)/accept")

            // The backend creates the CircleLink - we just need to refresh local data
            // In a full implementation, you'd sync the circle data from the server here

            if AppConfig.shared.isLoggingEnabled {
                print("Invite accepted: role=\(response.role), inviter=\(response.inviterName)")
            }

            clearPendingInvite()
            return true
        } catch APIError.notFound {
            error = "This invite has expired or is invalid"
            isLoading = false
            return false
        } catch APIError.forbidden {
            error = "You cannot accept this invite"
            isLoading = false
            return false
        } catch {
            self.error = "Failed to accept invite"
            isLoading = false
            return false
        }
    }

    /// Decline the pending invite
    func declineInvite() {
        clearPendingInvite()
    }

    /// Clear all pending invite state
    func clearPendingInvite() {
        pendingInviteCode = nil
        invitePreview = nil
        isLoading = false
        error = nil
        requiresAuth = false
    }
}
