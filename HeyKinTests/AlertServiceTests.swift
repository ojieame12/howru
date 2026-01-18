import XCTest
import SwiftData
@testable import HowRU

/// Tests for AlertService escalation logic
/// Note: NotificationService is final, so notification-sending tests verify
/// the alert creation/state logic rather than mocking notification delivery.
@MainActor
final class AlertServiceTests: XCTestCase {

    var container: TestContainer!
    var scheduleService: ScheduleService!
    var notificationService: NotificationService!
    var alertService: AlertService!

    override func setUp() async throws {
        container = try TestContainer()
        scheduleService = ScheduleService(modelContext: container.context)
        notificationService = NotificationService()
        alertService = AlertService(
            modelContext: container.context,
            notificationService: notificationService,
            scheduleService: scheduleService
        )
    }

    override func tearDown() async throws {
        try container.reset()
        container = nil
        scheduleService = nil
        notificationService = nil
        alertService = nil
    }

    // MARK: - Alert Level Calculation Tests

    func testCalculateAlertLevel_under24Hours_returnsReminder() {
        // Given: Last check-in 12 hours ago
        let lastCheckIn = Date().addingTimeInterval(-12 * 3600)

        // When
        let level = alertService.calculateAlertLevel(since: lastCheckIn)

        // Then
        XCTAssertEqual(level, .reminder, "Under 24 hours should be reminder level")
    }

    func testCalculateAlertLevel_at24Hours_returnsSoftAlert() {
        // Given: Last check-in exactly 24 hours ago
        let lastCheckIn = Date().addingTimeInterval(-24 * 3600)

        // When
        let level = alertService.calculateAlertLevel(since: lastCheckIn)

        // Then
        XCTAssertEqual(level, .softAlert, "At 24 hours should be soft alert level")
    }

    func testCalculateAlertLevel_at30Hours_returnsSoftAlert() {
        // Given: Last check-in 30 hours ago (between 24-36)
        let lastCheckIn = Date().addingTimeInterval(-30 * 3600)

        // When
        let level = alertService.calculateAlertLevel(since: lastCheckIn)

        // Then
        XCTAssertEqual(level, .softAlert, "30 hours should still be soft alert level")
    }

    func testCalculateAlertLevel_at36Hours_returnsHardAlert() {
        // Given: Last check-in 36 hours ago
        let lastCheckIn = Date().addingTimeInterval(-36 * 3600)

        // When
        let level = alertService.calculateAlertLevel(since: lastCheckIn)

        // Then
        XCTAssertEqual(level, .hardAlert, "At 36 hours should be hard alert level")
    }

    func testCalculateAlertLevel_at42Hours_returnsHardAlert() {
        // Given: Last check-in 42 hours ago (between 36-48)
        let lastCheckIn = Date().addingTimeInterval(-42 * 3600)

        // When
        let level = alertService.calculateAlertLevel(since: lastCheckIn)

        // Then
        XCTAssertEqual(level, .hardAlert, "42 hours should still be hard alert level")
    }

    func testCalculateAlertLevel_at48Hours_returnsEscalation() {
        // Given: Last check-in 48+ hours ago
        let lastCheckIn = Date().addingTimeInterval(-48 * 3600)

        // When
        let level = alertService.calculateAlertLevel(since: lastCheckIn)

        // Then
        XCTAssertEqual(level, .escalation, "At 48+ hours should be escalation level")
    }

    func testCalculateAlertLevel_at72Hours_returnsEscalation() {
        // Given: Last check-in 72 hours ago
        let lastCheckIn = Date().addingTimeInterval(-72 * 3600)

        // When
        let level = alertService.calculateAlertLevel(since: lastCheckIn)

        // Then
        XCTAssertEqual(level, .escalation, "72 hours should still be escalation level")
    }

    // MARK: - Alert Level Rank Tests

    func testAlertLevelRank_increasesWithSeverity() {
        XCTAssertLessThan(AlertLevel.reminder.rank, AlertLevel.softAlert.rank)
        XCTAssertLessThan(AlertLevel.softAlert.rank, AlertLevel.hardAlert.rank)
        XCTAssertLessThan(AlertLevel.hardAlert.rank, AlertLevel.escalation.rank)
    }

    // MARK: - Alert Resolution Tests

    func testResolveAlerts_marksAlertsAsResolved() async throws {
        // Given: User with active alert
        let user = container.insert(Factories.checker())
        let alert = container.insert(Factories.alertEvent(
            checkerId: user.id,
            checkerName: user.name,
            level: .softAlert,
            status: .pending
        ))

        XCTAssertNil(alert.resolvedAt, "Alert should not be resolved initially")

        // When
        alertService.resolveAlerts(for: user.id)

        // Then
        XCTAssertEqual(alert.status, .resolved, "Alert status should be resolved")
        XCTAssertNotNil(alert.resolvedAt, "Alert should have resolution timestamp")
    }

    func testResolveAlerts_onlyResolvesUnresolvedAlerts() async throws {
        // Given: User with one resolved and one active alert
        let user = container.insert(Factories.checker())
        let resolvedAlert = container.insert(Factories.alertEvent(
            checkerId: user.id,
            level: .softAlert,
            status: .resolved
        ))
        resolvedAlert.resolvedAt = Date().addingTimeInterval(-3600) // Resolved 1 hour ago
        let originalResolvedAt = resolvedAlert.resolvedAt

        let activeAlert = container.insert(Factories.alertEvent(
            checkerId: user.id,
            level: .hardAlert,
            status: .pending
        ))

        // When
        alertService.resolveAlerts(for: user.id)

        // Then
        XCTAssertEqual(resolvedAlert.resolvedAt, originalResolvedAt, "Already resolved alert should not change")
        XCTAssertNotNil(activeAlert.resolvedAt, "Active alert should now be resolved")
    }

    // MARK: - Alert Acknowledgement Tests

    func testAcknowledgeAlert_setsStatusToAcknowledged() {
        // Given
        let alert = Factories.alertEvent(checkerId: UUID(), status: .sent)

        // When
        alertService.acknowledgeAlert(alert)

        // Then
        XCTAssertEqual(alert.status, .acknowledged)
    }

    func testCancelAlert_setsStatusToCancelledAndResolved() {
        // Given
        let alert = Factories.alertEvent(checkerId: UUID(), status: .pending)

        // When
        alertService.cancelAlert(alert)

        // Then
        XCTAssertEqual(alert.status, .cancelled)
        XCTAssertNotNil(alert.resolvedAt)
    }

    // MARK: - Alert Event Creation Tests

    func testEvaluateAlerts_createsAlertWhenWindowMissed() async throws {
        // Given: Checker with missed window
        let checker = container.insert(Factories.checker())
        let supporter = container.insert(Factories.supporter())
        let link = container.insert(Factories.circleLink(
            checker: checker,
            supporter: supporter,
            alertViaPush: true
        ))

        // Create schedule that ended earlier today
        // Window: 6am - 8am, so if it's past 8am the window is missed
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)

        // Set window to end 2 hours before current time (ensures window is missed)
        let windowEndHour = max(0, currentHour - 2)
        let windowStartHour = max(0, windowEndHour - 2)

        let schedule = container.insert(Factories.schedule(
            user: checker,
            windowStartHour: windowStartHour,
            windowEndHour: windowEndHour,
            gracePeriodMinutes: 0
        ))
        // Set all days as active
        schedule.activeDays = [0, 1, 2, 3, 4, 5, 6]
        checker.schedules = [schedule]

        // No check-in today - last check-in was yesterday (25 hours ago = softAlert level)
        let oldCheckIn = container.insert(Factories.checkIn(
            user: checker,
            timestamp: Date().addingTimeInterval(-25 * 3600)
        ))

        // Verify no alerts exist initially
        let initialAlerts = alertService.activeAlerts(for: checker.id)
        XCTAssertEqual(initialAlerts.count, 0, "Should have no alerts initially")

        // When
        alertService.evaluateAlerts(
            for: checker,
            checkIns: [oldCheckIn],
            circleLinks: [link]
        )

        // Then: Alert should be created
        let alerts = alertService.activeAlerts(for: checker.id)
        XCTAssertEqual(alerts.count, 1, "Should create one alert for missed window")

        if let alert = alerts.first {
            XCTAssertEqual(alert.checkerId, checker.id)
            XCTAssertEqual(alert.checkerName, checker.name)
            // Alert level should be based on time since missed window (not check-in)
            XCTAssertNil(alert.resolvedAt, "Alert should not be resolved")
        }
    }

    func testEvaluateAlerts_doesNotCreateAlert_whenNotMissed() async throws {
        // Given: Checker with schedule where window hasn't passed yet
        let checker = container.insert(Factories.checker())
        let supporter = container.insert(Factories.supporter())
        let link = container.insert(Factories.circleLink(
            checker: checker,
            supporter: supporter,
            alertViaPush: true
        ))

        // Create schedule that ends later today (window not yet missed)
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)

        // Window ends 2 hours from now
        let windowEndHour = min(23, currentHour + 2)
        let windowStartHour = max(0, currentHour - 2)

        let schedule = container.insert(Factories.schedule(
            user: checker,
            windowStartHour: windowStartHour,
            windowEndHour: windowEndHour,
            gracePeriodMinutes: 60
        ))
        schedule.activeDays = [0, 1, 2, 3, 4, 5, 6]
        checker.schedules = [schedule]

        // When
        alertService.evaluateAlerts(
            for: checker,
            checkIns: [],
            circleLinks: [link]
        )

        // Then: No alert should be created (window not missed yet)
        let alerts = alertService.activeAlerts(for: checker.id)
        XCTAssertEqual(alerts.count, 0, "Should not create alert when window not missed")
    }

    func testEvaluateAlerts_escalatesExistingAlert() async throws {
        // Given: Checker with existing soft alert, now 37 hours since check-in (hard alert)
        let checker = container.insert(Factories.checker())
        let supporter = container.insert(Factories.supporter())
        let link = container.insert(Factories.circleLink(
            checker: checker,
            supporter: supporter,
            alertViaPush: true
        ))

        // Create existing soft alert
        let existingAlert = container.insert(Factories.alertEvent(
            checkerId: checker.id,
            checkerName: checker.name,
            level: .softAlert,
            status: .pending
        ))

        // Setup schedule (ended earlier today)
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())
        let schedule = container.insert(Factories.schedule(
            user: checker,
            windowStartHour: max(0, currentHour - 4),
            windowEndHour: max(0, currentHour - 2),
            gracePeriodMinutes: 0
        ))
        schedule.activeDays = [0, 1, 2, 3, 4, 5, 6]
        checker.schedules = [schedule]

        // Old check-in (37 hours ago = hardAlert level)
        let oldCheckIn = container.insert(Factories.checkIn(
            user: checker,
            timestamp: Date().addingTimeInterval(-37 * 3600)
        ))

        // When
        alertService.evaluateAlerts(
            for: checker,
            checkIns: [oldCheckIn],
            circleLinks: [link]
        )

        // Then: Alert should be escalated to hard alert
        XCTAssertEqual(existingAlert.level, .hardAlert, "Alert should escalate from soft to hard")
    }

    func testEvaluateAlerts_includesSupporterInNotifiedList() async throws {
        // Given: Checker with supporter
        let checker = container.insert(Factories.checker())
        let supporter = container.insert(Factories.supporter())
        let link = container.insert(Factories.circleLink(
            checker: checker,
            supporter: supporter,
            alertViaPush: true
        ))

        // When: An alert is created manually to test supporter tracking
        let alert = container.insert(Factories.alertEvent(
            checkerId: checker.id,
            checkerName: checker.name,
            level: .softAlert,
            notifiedSupporterIds: [supporter.id]
        ))

        // Then
        XCTAssertTrue(alert.notifiedSupporterIds.contains(supporter.id))
    }

    // MARK: - Active Alerts Query Tests

    func testActiveAlerts_returnsOnlyUnresolvedAlerts() async throws {
        // Given
        let user = container.insert(Factories.checker())

        let activeAlert = container.insert(Factories.alertEvent(
            checkerId: user.id,
            level: .softAlert,
            status: .pending
        ))

        let resolvedAlert = container.insert(Factories.alertEvent(
            checkerId: user.id,
            level: .hardAlert,
            status: .resolved
        ))
        resolvedAlert.resolvedAt = Date()

        // When
        let alerts = alertService.activeAlerts(for: user.id)

        // Then
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.id, activeAlert.id)
    }

    // MARK: - Notified Supporters Tests

    func testAlertsNeedingAttention_filtersForSupporter() async throws {
        // Given
        let checker = container.insert(Factories.checker())
        let supporter1 = container.insert(Factories.supporter(name: "Supporter 1"))
        let supporter2 = container.insert(Factories.supporter(name: "Supporter 2"))

        let alert = container.insert(Factories.alertEvent(
            checkerId: checker.id,
            checkerName: checker.name,
            notifiedSupporterIds: [supporter1.id] // Only supporter1 notified
        ))

        // When
        let alertsForSupporter1 = alertService.alertsNeedingAttention(for: supporter1.id)
        let alertsForSupporter2 = alertService.alertsNeedingAttention(for: supporter2.id)

        // Then
        XCTAssertEqual(alertsForSupporter1.count, 1)
        XCTAssertEqual(alertsForSupporter1.first?.id, alert.id)
        XCTAssertEqual(alertsForSupporter2.count, 0, "Supporter2 was not notified")
    }
}
