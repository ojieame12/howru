/**
 * Cron Job: Check Missed Check-ins
 * Runs every 15 minutes to find users who missed their check-in window
 * and creates alerts accordingly.
 *
 * Alert timeline:
 * - +0h (after grace): Reminder push to checker
 * - +24h: Soft alert to priority 1 supporters
 * - +36h: Hard alert to ALL supporters (push + SMS + voice)
 * - +48h: Escalation to emergency contacts
 */
export {};
//# sourceMappingURL=check-missed-checkins.d.ts.map