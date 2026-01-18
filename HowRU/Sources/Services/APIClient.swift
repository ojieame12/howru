import Foundation

/// API error types
enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidRequest
    case invalidResponse
    case decodingError(Error)
    case networkError(Error)
    case httpError(statusCode: Int, message: String?)
    case unauthorized
    case forbidden
    case notFound
    case serverError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidRequest:
            return "Invalid request"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            return message ?? "HTTP error \(statusCode)"
        case .unauthorized:
            return "Authentication required"
        case .forbidden:
            return "Access denied"
        case .notFound:
            return "Resource not found"
        case .serverError:
            return "Server error. Please try again later."
        }
    }
}

/// Generic API response wrapper
struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        // Try to decode the entire response as T (since data is at root level)
        data = try? T(from: decoder)
    }
}

/// URLSession-based API client with automatic token refresh
@MainActor
final class APIClient {
    // MARK: - Singleton

    static let shared = APIClient()

    // MARK: - Properties

    private let session: URLSession
    private let config: AppConfig
    private let authManager: AuthManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // MARK: - Initialization

    private init() {
        self.config = AppConfig.shared
        self.authManager = AuthManager.shared

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.requestTimeout
        configuration.timeoutIntervalForResource = config.resourceTimeout
        session = URLSession(configuration: configuration)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    /// Internal initializer for testing
    init(session: URLSession, config: AppConfig, authManager: AuthManager) {
        self.session = session
        self.config = config
        self.authManager = authManager

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Public API Methods

    /// GET request
    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        return try await request(method: "GET", path: path, queryItems: queryItems)
    }

    /// POST request with body
    func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        return try await request(method: "POST", path: path, body: body)
    }

    /// POST request without body
    func post<T: Decodable>(_ path: String) async throws -> T {
        return try await request(method: "POST", path: path)
    }

    /// PATCH request with body
    func patch<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        return try await request(method: "PATCH", path: path, body: body)
    }

    /// PUT request with body
    func put<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        return try await request(method: "PUT", path: path, body: body)
    }

    /// DELETE request
    func delete<T: Decodable>(_ path: String) async throws -> T {
        return try await request(method: "DELETE", path: path)
    }

    /// DELETE request with body
    func delete<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        return try await request(method: "DELETE", path: path, body: body)
    }

    /// DELETE request with body and void response
    func delete<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: EmptyResponse = try await request(method: "DELETE", path: path, body: body)
    }

    /// DELETE request with void response
    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await request(method: "DELETE", path: path)
    }

    // MARK: - Upload

    /// Upload multipart form data
    func upload<T: Decodable>(
        _ path: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        additionalFields: [String: String]? = nil
    ) async throws -> T {
        let boundary = UUID().uuidString
        var body = Data()

        // Add additional fields
        if let fields = additionalFields {
            for (key, value) in fields {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            }
        }

        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        return try await request(
            method: "POST",
            path: path,
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    // MARK: - Core Request Implementation

    private func request<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> T {
        return try await performRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body,
            contentType: contentType,
            isRetry: false
        )
    }

    private func request<T: Decodable, Body: Encodable>(
        method: String,
        path: String,
        body: Body
    ) async throws -> T {
        let bodyData = try encoder.encode(body)
        return try await performRequest(
            method: method,
            path: path,
            body: bodyData,
            contentType: "application/json",
            isRetry: false
        )
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        return try await performRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            isRetry: false
        )
    }

    private func performRequest<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil,
        contentType: String = "application/json",
        isRetry: Bool
    ) async throws -> T {
        // Build URL
        var urlComponents = URLComponents(url: config.apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add auth header if available
        if let token = authManager.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add body if present
        if let body = body {
            request.httpBody = body
        }

        // Log request in debug
        if config.isLoggingEnabled {
            print("[\(method)] \(url.absoluteString)")
        }

        // Perform request
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Log response in debug
        if config.isLoggingEnabled {
            print("[\(httpResponse.statusCode)] \(url.absoluteString)")
        }

        // Handle status codes
        switch httpResponse.statusCode {
        case 200...299:
            // Success - decode response
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }

        case 401:
            // Unauthorized - try token refresh if not already retrying
            if !isRetry, authManager.isAuthenticated {
                if let _ = await authManager.refreshAccessToken() {
                    // Retry with new token
                    return try await performRequest(
                        method: method,
                        path: path,
                        queryItems: queryItems,
                        body: body,
                        contentType: contentType,
                        isRetry: true
                    )
                }
            }
            throw APIError.unauthorized

        case 403:
            throw APIError.forbidden

        case 404:
            throw APIError.notFound

        case 500...599:
            throw APIError.serverError

        default:
            // Try to extract error message from response
            let errorMessage = try? decoder.decode(ErrorResponse.self, from: data).error
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
    }
}

// MARK: - Supporting Types

private struct EmptyResponse: Decodable {}

private struct ErrorResponse: Decodable {
    let success: Bool
    let error: String?
}
