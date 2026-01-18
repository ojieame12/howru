import Foundation

/// Environment configuration for different build targets
enum Environment: String {
    case development
    case staging
    case production

    /// Current active environment based on build configuration
    static var current: Environment {
        #if DEBUG
        return .development
        #else
        // Check for staging flag or default to production
        if Bundle.main.object(forInfoDictionaryKey: "IS_STAGING") as? Bool == true {
            return .staging
        }
        return .production
        #endif
    }
}

/// App configuration containing environment-specific values
struct AppConfig {
    let environment: Environment

    /// Base URL for API requests
    var apiBaseURL: URL {
        switch environment {
        case .development:
            // Local development server
            return URL(string: "http://localhost:3000")!
        case .staging:
            // Staging server (Railway preview)
            return URL(string: "https://howru-staging.railway.app")!
        case .production:
            // Production server
            return URL(string: "https://api.howru.app")!
        }
    }

    /// Request timeout interval
    var requestTimeout: TimeInterval {
        switch environment {
        case .development:
            return 30 // Longer timeout for debugging
        case .staging, .production:
            return 15
        }
    }

    /// Resource timeout interval for uploads/downloads
    var resourceTimeout: TimeInterval {
        return 60
    }

    /// Whether to enable verbose logging
    var isLoggingEnabled: Bool {
        switch environment {
        case .development, .staging:
            return true
        case .production:
            return false
        }
    }

    /// RevenueCat API key
    var revenueCatAPIKey: String {
        switch environment {
        case .development, .staging:
            return "appl_sandbox_key" // Replace with actual sandbox key
        case .production:
            return "appl_production_key" // Replace with actual production key
        }
    }

    /// Keychain service name for token storage
    var keychainService: String {
        return "com.howru.app.\(environment.rawValue)"
    }

    /// Shared instance using current environment
    static let shared = AppConfig(environment: .current)
}
