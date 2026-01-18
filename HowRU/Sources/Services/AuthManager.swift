import Foundation
import Security
import SwiftData

/// Manages authentication state and JWT token storage
@MainActor
@Observable
final class AuthManager {
    // MARK: - Singleton

    static let shared = AuthManager()

    // MARK: - State

    private(set) var isAuthenticated = false
    private(set) var isRefreshing = false
    private(set) var isLoading = false
    var authError: String?

    /// Cached user ID from last successful auth
    private(set) var currentUserId: String?

    // MARK: - Token Keys

    private let accessTokenKey = "howru_access_token"
    private let refreshTokenKey = "howru_refresh_token"
    private let userIdKey = "howru_user_id"

    // MARK: - Initialization

    private init() {
        // Check if we have valid tokens on launch
        isAuthenticated = accessToken != nil
        currentUserId = getKeychainItem(key: userIdKey)
    }

    // MARK: - Token Getters

    /// Current access token for API requests
    var accessToken: String? {
        return getKeychainItem(key: accessTokenKey)
    }

    /// Refresh token for obtaining new access tokens
    var refreshToken: String? {
        return getKeychainItem(key: refreshTokenKey)
    }

    // MARK: - Token Management

    /// Store tokens after successful authentication
    func setTokens(accessToken: String, refreshToken: String, userId: String? = nil) {
        setKeychainItem(key: accessTokenKey, value: accessToken)
        setKeychainItem(key: refreshTokenKey, value: refreshToken)
        if let userId = userId {
            setKeychainItem(key: userIdKey, value: userId)
            currentUserId = userId
        }
        isAuthenticated = true
        authError = nil
    }

    /// Clear all stored tokens (logout)
    func clearTokens() {
        deleteKeychainItem(key: accessTokenKey)
        deleteKeychainItem(key: refreshTokenKey)
        deleteKeychainItem(key: userIdKey)
        currentUserId = nil
        isAuthenticated = false
    }

    // MARK: - OTP Authentication

    /// Request OTP code to be sent to the phone number
    /// - Parameters:
    ///   - phone: Phone number to send OTP to
    ///   - countryCode: Country code (default: "US")
    /// - Returns: True if OTP was sent successfully
    func requestOTP(phone: String, countryCode: String = "US") async throws -> Bool {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        let body = OTPRequestBody(phoneNumber: phone, countryCode: countryCode)
        let url = AppConfig.shared.apiBaseURL.appendingPathComponent("/auth/otp/request")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            let otpResponse = try decoder.decode(OTPRequestResponse.self, from: data)
            return otpResponse.success
        } else {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponseBody.self, from: data) {
                authError = errorResponse.error ?? "Failed to send OTP"
            } else {
                authError = "Failed to send OTP (status: \(httpResponse.statusCode))"
            }
            throw AuthError.otpRequestFailed
        }
    }

    /// Verify OTP code and complete authentication
    /// - Parameters:
    ///   - phone: Phone number that received the OTP
    ///   - code: OTP code entered by user
    ///   - name: User's name (for new users)
    ///   - countryCode: Country code (default: "US")
    /// - Returns: OTPVerifyResponse with tokens and user info
    func verifyOTP(phone: String, code: String, name: String? = nil, countryCode: String = "US") async throws -> OTPVerifyResponse {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        let body = OTPVerifyBody(phoneNumber: phone, code: code, name: name, countryCode: countryCode)
        let url = AppConfig.shared.apiBaseURL.appendingPathComponent("/auth/otp/verify")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if AppConfig.shared.isLoggingEnabled {
            print("[OTP Verify] Status: \(httpResponse.statusCode)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[OTP Verify] Response: \(jsonString)")
            }
        }

        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let verifyResponse = try decoder.decode(OTPVerifyResponse.self, from: data)

            // Store tokens
            setTokens(
                accessToken: verifyResponse.tokens.accessToken,
                refreshToken: verifyResponse.tokens.refreshToken,
                userId: verifyResponse.user.id
            )

            return verifyResponse
        } else {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponseBody.self, from: data) {
                authError = errorResponse.error ?? "Invalid OTP code"
            } else {
                authError = "Invalid OTP code"
            }
            throw AuthError.otpVerifyFailed
        }
    }

    // MARK: - Delete Account

    /// Delete the user's account on the server and clear all local data
    /// - Parameter modelContext: SwiftData context to clear local data from
    /// - Throws: AuthError if the request fails
    func deleteAccount(modelContext: ModelContext? = nil) async throws {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        // Call server to delete account
        do {
            let _: SuccessResponse = try await APIClient.shared.delete("/users/me")

            if AppConfig.shared.isLoggingEnabled {
                print("[Auth] Account deleted successfully")
            }
        } catch APIError.unauthorized {
            // Already logged out on server side, continue with local cleanup
            if AppConfig.shared.isLoggingEnabled {
                print("[Auth] Unauthorized during delete - continuing with local cleanup")
            }
        } catch {
            // For other errors, still clean up locally but log the error
            if AppConfig.shared.isLoggingEnabled {
                print("[Auth] Error deleting account: \(error)")
            }
            // Don't throw - proceed with local cleanup
        }

        // Clear all local data
        await logout(modelContext: modelContext)
    }

    // MARK: - Logout

    /// Logout and clear all local data
    /// - Parameter modelContext: SwiftData context to clear local data from
    func logout(modelContext: ModelContext? = nil) async {
        // Clear tokens first
        clearTokens()

        // Clear local SwiftData if context provided
        if let context = modelContext {
            do {
                // Delete all local data
                try context.delete(model: User.self)
                try context.delete(model: CheckIn.self)
                try context.delete(model: CircleLink.self)
                try context.delete(model: Poke.self)
                try context.delete(model: AlertEvent.self)
                try context.delete(model: Schedule.self)
                try context.save()
            } catch {
                if AppConfig.shared.isLoggingEnabled {
                    print("Failed to clear local data on logout: \(error)")
                }
            }
        }

        authError = nil
    }

    // MARK: - Token Refresh

    /// Refresh the access token using the refresh token
    /// Returns the new access token if successful, nil if refresh failed
    func refreshAccessToken() async -> String? {
        guard let currentRefreshToken = refreshToken else {
            clearTokens()
            return nil
        }

        guard !isRefreshing else {
            // Wait for ongoing refresh
            while isRefreshing {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return accessToken
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let url = AppConfig.shared.apiBaseURL.appendingPathComponent("/auth/refresh")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = ["refreshToken": currentRefreshToken]
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            if httpResponse.statusCode == 200 {
                let tokenResponse = try JSONDecoder().decode(AuthTokenRefreshResponse.self, from: data)
                setTokens(accessToken: tokenResponse.tokens.accessToken, refreshToken: tokenResponse.tokens.refreshToken)
                return tokenResponse.tokens.accessToken
            } else if httpResponse.statusCode == 401 {
                // Refresh token is invalid/expired - force logout
                clearTokens()
                authError = "Session expired. Please sign in again."
                return nil
            } else {
                throw AuthError.refreshFailed
            }
        } catch {
            if AppConfig.shared.isLoggingEnabled {
                print("Token refresh failed: \(error)")
            }
            // Don't clear tokens on network errors - might be temporary
            return nil
        }
    }

    // MARK: - Keychain Helpers

    private func getKeychainItem(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.shared.keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func setKeychainItem(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // First, try to delete any existing item
        deleteKeychainItem(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.shared.keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteKeychainItem(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.shared.keychainService,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Supporting Types

enum AuthError: Error, LocalizedError {
    case invalidResponse
    case refreshFailed
    case unauthorized
    case otpRequestFailed
    case otpVerifyFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .refreshFailed:
            return "Failed to refresh session"
        case .unauthorized:
            return "Authentication required"
        case .otpRequestFailed:
            return "Failed to send verification code"
        case .otpVerifyFailed:
            return "Invalid verification code"
        }
    }
}

/// Error response body from API
private struct ErrorResponseBody: Decodable {
    let success: Bool
    let error: String?
}

/// Response from POST /auth/refresh - nested tokens object
private struct AuthTokenRefreshResponse: Decodable {
    let success: Bool
    let tokens: AuthTokens
}

private struct AuthTokens: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: String?
}
