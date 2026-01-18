import XCTest
@testable import HowRU

/// Tests for Environment and AppConfig
final class EnvironmentTests: XCTestCase {

    // MARK: - Environment Enum Tests

    func testEnvironment_rawValues() {
        XCTAssertEqual(Environment.development.rawValue, "development")
        XCTAssertEqual(Environment.staging.rawValue, "staging")
        XCTAssertEqual(Environment.production.rawValue, "production")
    }

    func testEnvironment_allCases() {
        // Verify all expected environments exist
        let environments: [Environment] = [.development, .staging, .production]
        XCTAssertEqual(environments.count, 3)
    }

    // MARK: - AppConfig API Base URL Tests

    func testAppConfig_development_usesLocalhost() {
        let config = AppConfig(environment: .development)

        XCTAssertEqual(config.apiBaseURL.scheme, "http")
        XCTAssertEqual(config.apiBaseURL.host, "localhost")
        XCTAssertEqual(config.apiBaseURL.port, 3000)
    }

    func testAppConfig_staging_usesRailwayURL() {
        let config = AppConfig(environment: .staging)

        XCTAssertEqual(config.apiBaseURL.scheme, "https")
        XCTAssertTrue(config.apiBaseURL.absoluteString.contains("staging"))
        XCTAssertTrue(config.apiBaseURL.absoluteString.contains("railway"))
    }

    func testAppConfig_production_usesProductionURL() {
        let config = AppConfig(environment: .production)

        XCTAssertEqual(config.apiBaseURL.scheme, "https")
        XCTAssertEqual(config.apiBaseURL.absoluteString, "https://api.howru.app")
    }

    func testAppConfig_development_notHTTPS() {
        // Development uses HTTP for local testing
        let config = AppConfig(environment: .development)
        XCTAssertEqual(config.apiBaseURL.scheme, "http")
    }

    func testAppConfig_staging_usesHTTPS() {
        let config = AppConfig(environment: .staging)
        XCTAssertEqual(config.apiBaseURL.scheme, "https")
    }

    func testAppConfig_production_usesHTTPS() {
        let config = AppConfig(environment: .production)
        XCTAssertEqual(config.apiBaseURL.scheme, "https")
    }

    // MARK: - Request Timeout Tests

    func testAppConfig_development_hasLongerTimeout() {
        let config = AppConfig(environment: .development)

        // Development has longer timeout for debugging
        XCTAssertEqual(config.requestTimeout, 30)
    }

    func testAppConfig_staging_hasStandardTimeout() {
        let config = AppConfig(environment: .staging)

        XCTAssertEqual(config.requestTimeout, 15)
    }

    func testAppConfig_production_hasStandardTimeout() {
        let config = AppConfig(environment: .production)

        XCTAssertEqual(config.requestTimeout, 15)
    }

    func testAppConfig_resourceTimeout_sameAcrossEnvironments() {
        let dev = AppConfig(environment: .development)
        let staging = AppConfig(environment: .staging)
        let prod = AppConfig(environment: .production)

        // Resource timeout should be consistent
        XCTAssertEqual(dev.resourceTimeout, 60)
        XCTAssertEqual(staging.resourceTimeout, 60)
        XCTAssertEqual(prod.resourceTimeout, 60)
    }

    // MARK: - Logging Tests

    func testAppConfig_development_enablesLogging() {
        let config = AppConfig(environment: .development)

        XCTAssertTrue(config.isLoggingEnabled)
    }

    func testAppConfig_staging_enablesLogging() {
        let config = AppConfig(environment: .staging)

        XCTAssertTrue(config.isLoggingEnabled)
    }

    func testAppConfig_production_disablesLogging() {
        let config = AppConfig(environment: .production)

        XCTAssertFalse(config.isLoggingEnabled)
    }

    // MARK: - RevenueCat API Key Tests

    func testAppConfig_development_usesSandboxKey() {
        let config = AppConfig(environment: .development)

        XCTAssertTrue(config.revenueCatAPIKey.contains("sandbox"))
    }

    func testAppConfig_staging_usesSandboxKey() {
        let config = AppConfig(environment: .staging)

        XCTAssertTrue(config.revenueCatAPIKey.contains("sandbox"))
    }

    func testAppConfig_production_usesProductionKey() {
        let config = AppConfig(environment: .production)

        XCTAssertTrue(config.revenueCatAPIKey.contains("production"))
    }

    func testAppConfig_revenueCatKey_notEmpty() {
        let dev = AppConfig(environment: .development)
        let staging = AppConfig(environment: .staging)
        let prod = AppConfig(environment: .production)

        XCTAssertFalse(dev.revenueCatAPIKey.isEmpty)
        XCTAssertFalse(staging.revenueCatAPIKey.isEmpty)
        XCTAssertFalse(prod.revenueCatAPIKey.isEmpty)
    }

    // MARK: - Keychain Service Tests

    func testAppConfig_keychainService_uniquePerEnvironment() {
        let dev = AppConfig(environment: .development)
        let staging = AppConfig(environment: .staging)
        let prod = AppConfig(environment: .production)

        // Each environment should have unique keychain service
        XCTAssertNotEqual(dev.keychainService, staging.keychainService)
        XCTAssertNotEqual(staging.keychainService, prod.keychainService)
        XCTAssertNotEqual(dev.keychainService, prod.keychainService)
    }

    func testAppConfig_keychainService_containsEnvironmentName() {
        let dev = AppConfig(environment: .development)
        let staging = AppConfig(environment: .staging)
        let prod = AppConfig(environment: .production)

        XCTAssertTrue(dev.keychainService.contains("development"))
        XCTAssertTrue(staging.keychainService.contains("staging"))
        XCTAssertTrue(prod.keychainService.contains("production"))
    }

    func testAppConfig_keychainService_containsBundleIdentifier() {
        let config = AppConfig(environment: .development)

        XCTAssertTrue(config.keychainService.contains("com.howru.app"))
    }

    // MARK: - Shared Instance Tests

    func testAppConfig_sharedInstance_exists() {
        let shared = AppConfig.shared

        XCTAssertNotNil(shared)
    }

    func testAppConfig_sharedInstance_hasValidURL() {
        let shared = AppConfig.shared

        XCTAssertNotNil(shared.apiBaseURL)
        XCTAssertNotNil(shared.apiBaseURL.host)
    }

    // MARK: - URL Path Building Tests

    func testAppConfig_urlPathBuilding() {
        let config = AppConfig(environment: .development)

        let fullURL = config.apiBaseURL.appendingPathComponent("/auth/login")

        XCTAssertTrue(fullURL.absoluteString.contains("auth"))
        XCTAssertTrue(fullURL.absoluteString.contains("login"))
    }

    func testAppConfig_urlPathBuilding_production() {
        let config = AppConfig(environment: .production)

        let fullURL = config.apiBaseURL.appendingPathComponent("/checkins")

        XCTAssertEqual(fullURL.absoluteString, "https://api.howru.app/checkins")
    }

    // MARK: - Environment Detection Tests

    func testEnvironment_current_returnsValidEnvironment() {
        let current = Environment.current

        // Should be one of the valid environments
        let validEnvironments: [Environment] = [.development, .staging, .production]
        XCTAssertTrue(validEnvironments.contains(current))
    }

    // MARK: - Edge Cases

    func testAppConfig_apiBaseURL_notNil() {
        // Verify URLs are always valid (not nil)
        let environments: [Environment] = [.development, .staging, .production]

        for env in environments {
            let config = AppConfig(environment: env)
            XCTAssertNotNil(config.apiBaseURL, "API URL should not be nil for \(env)")
        }
    }

    func testAppConfig_timeouts_positive() {
        let environments: [Environment] = [.development, .staging, .production]

        for env in environments {
            let config = AppConfig(environment: env)
            XCTAssertGreaterThan(config.requestTimeout, 0, "Request timeout should be positive for \(env)")
            XCTAssertGreaterThan(config.resourceTimeout, 0, "Resource timeout should be positive for \(env)")
        }
    }

    func testAppConfig_resourceTimeout_greaterThanRequestTimeout() {
        let environments: [Environment] = [.development, .staging, .production]

        for env in environments {
            let config = AppConfig(environment: env)
            XCTAssertGreaterThanOrEqual(
                config.resourceTimeout,
                config.requestTimeout,
                "Resource timeout should be >= request timeout for \(env)"
            )
        }
    }
}
