"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
const index_js_1 = require("../db/index.js");
const resend_js_1 = require("../services/resend.js");
const twilio_js_1 = require("../services/twilio.js");
async function checkMissedCheckins() {
    console.log('[check-missed-checkins] Starting job...');
    try {
        // Find users who should have checked in but haven't
        const missedUsers = await (0, index_js_1.sql) `
      SELECT
        u.id,
        u.name,
        u.phone_number,
        s.timezone_identifier as timezone,
        s.window_end_hour,
        s.window_end_minute,
        s.grace_period_minutes,
        u.last_known_address,
        (
          SELECT MAX(timestamp) FROM checkins
          WHERE user_id = u.id
        ) as last_checkin_at
      FROM users u
      JOIN schedules s ON s.user_id = u.id AND s.is_active = true
      WHERE
        u.is_checker = true
        -- Window + grace has passed today
        AND (
          EXTRACT(HOUR FROM NOW() AT TIME ZONE COALESCE(s.timezone_identifier, 'UTC')) * 60 +
          EXTRACT(MINUTE FROM NOW() AT TIME ZONE COALESCE(s.timezone_identifier, 'UTC'))
        ) > (s.window_end_hour * 60 + s.window_end_minute + s.grace_period_minutes)
        -- Today is an active day
        AND EXTRACT(DOW FROM NOW() AT TIME ZONE COALESCE(s.timezone_identifier, 'UTC'))::int = ANY(s.active_days)
        -- No check-in today
        AND NOT EXISTS (
          SELECT 1 FROM checkins c
          WHERE c.user_id = u.id
          AND DATE(c.timestamp AT TIME ZONE COALESCE(s.timezone_identifier, 'UTC')) =
              DATE(NOW() AT TIME ZONE COALESCE(s.timezone_identifier, 'UTC'))
        )
        -- No pending alert today
        AND NOT EXISTS (
          SELECT 1 FROM alerts a
          WHERE a.checker_id = u.id
          AND a.status IN ('pending', 'sent')
          AND DATE(a.missed_window_at) = DATE(NOW())
        )
    `;
        console.log(`[check-missed-checkins] Found ${missedUsers.length} users who missed check-in`);
        for (const user of missedUsers) {
            // Create initial reminder alert
            await (0, index_js_1.sql) `
        INSERT INTO alerts (
          checker_id, checker_name, type, status,
          triggered_at, missed_window_at,
          last_checkin_at, last_known_location
        )
        VALUES (
          ${user.id}, ${user.name}, 'reminder', 'pending',
          NOW(), NOW(),
          ${user.last_checkin_at}, ${user.last_known_address}
        )
      `;
            console.log(`[check-missed-checkins] Created reminder alert for ${user.name}`);
            // TODO: Send push notification to checker
            // await sendPushNotification(user.id, {
            //   title: 'Check-in Reminder',
            //   body: "Don't forget to check in today!",
            //   data: { type: 'reminder' }
            // });
        }
        // Now escalate existing alerts based on time elapsed
        await escalateAlerts();
        console.log('[check-missed-checkins] Job completed');
    }
    catch (error) {
        console.error('[check-missed-checkins] Error:', error);
        throw error;
    }
}
async function escalateAlerts() {
    console.log('[escalate-alerts] Checking for alerts to escalate...');
    // Get all pending alerts with hours since missed
    const pendingAlerts = await (0, index_js_1.sql) `
    SELECT
      a.*,
      EXTRACT(EPOCH FROM (NOW() - a.missed_window_at)) / 3600 as hours_since_missed
    FROM alerts a
    WHERE a.status IN ('pending', 'sent')
    AND a.resolved_at IS NULL
  `;
    for (const alert of pendingAlerts) {
        const hours = alert.hours_since_missed;
        // Escalation thresholds
        if (hours >= 48 && alert.type !== 'escalation') {
            await escalateToLevel(alert, 'escalation');
        }
        else if (hours >= 36 && alert.type === 'soft') {
            await escalateToLevel(alert, 'hard');
        }
        else if (hours >= 24 && alert.type === 'reminder') {
            await escalateToLevel(alert, 'soft');
        }
    }
}
async function escalateToLevel(alert, newLevel) {
    console.log(`[escalate-alerts] Escalating alert ${alert.id} from ${alert.type} to ${newLevel}`);
    // Update alert type
    await (0, index_js_1.sql) `
    UPDATE alerts
    SET type = ${newLevel}, status = 'sent'
    WHERE id = ${alert.id}
  `;
    // Get checker info
    const checker = (await (0, index_js_1.sql) `SELECT * FROM users WHERE id = ${alert.checker_id}`)[0];
    // Get supporters to notify
    const supporters = await (0, index_js_1.sql) `
    SELECT cl.*, u.name, u.phone_number, u.email
    FROM circle_links cl
    LEFT JOIN users u ON cl.supporter_id = u.id
    WHERE cl.checker_id = ${alert.checker_id}
    AND cl.is_active = true
    ${newLevel === 'soft' ? (0, index_js_1.sql) `AND cl.alert_priority = 1` : (0, index_js_1.sql) ``}
    ORDER BY cl.alert_priority ASC
  `;
    console.log(`[escalate-alerts] Notifying ${supporters.length} supporters for ${newLevel} alert`);
    // Get last check-in for context
    const lastCheckIn = (await (0, index_js_1.sql) `
      SELECT * FROM checkins
      WHERE user_id = ${alert.checker_id}
      ORDER BY timestamp DESC
      LIMIT 1
    `)[0];
    const lastMood = lastCheckIn
        ? {
            mental: lastCheckIn.mental_score,
            body: lastCheckIn.body_score,
            mood: lastCheckIn.mood_score,
        }
        : undefined;
    for (const supporter of supporters) {
        const supporterEmail = supporter.email || supporter.supporter_email;
        const supporterPhone = supporter.phone_number || supporter.supporter_phone;
        // Email notification
        if (supporter.alert_via_email && supporterEmail) {
            try {
                await (0, resend_js_1.sendAlertEmail)({
                    to: supporterEmail,
                    checkerName: supporter.supporter_display_name || supporter.name || 'Someone',
                    userName: checker.name,
                    alertLevel: newLevel,
                    lastCheckIn: lastCheckIn?.timestamp
                        ? new Date(lastCheckIn.timestamp)
                        : undefined,
                    lastLocation: checker.last_known_address,
                    lastMood,
                });
                console.log(`[escalate-alerts] Sent email to ${supporterEmail}`);
            }
            catch (e) {
                console.error(`[escalate-alerts] Failed to send email:`, e);
            }
        }
        // SMS notification (for hard and escalation only)
        if (supporter.alert_via_sms &&
            supporterPhone &&
            (newLevel === 'hard' || newLevel === 'escalation')) {
            try {
                await (0, twilio_js_1.sendAlertSMS)({
                    to: supporterPhone,
                    checkerName: checker.name,
                    level: newLevel,
                    address: checker.last_known_address,
                    phone: checker.phone_number,
                    lastCheckInTime: lastCheckIn?.timestamp
                        ? new Date(lastCheckIn.timestamp).toLocaleString()
                        : undefined,
                });
                console.log(`[escalate-alerts] Sent SMS to ${supporterPhone}`);
            }
            catch (e) {
                console.error(`[escalate-alerts] Failed to send SMS:`, e);
            }
        }
        // TODO: Voice call for hard alerts
        // if (newLevel === 'hard' && supporterPhone) {
        //   await initiateAlertCall(supporter, checker, alert);
        // }
        // TODO: Push notification
        // if (supporter.alert_via_push && supporter.supporter_id) {
        //   await sendPushNotification(supporter.supporter_id, {
        //     title: `Alert: ${checker.name} hasn't checked in`,
        //     body: `It's been ${Math.round(alert.hours_since_missed)} hours`,
        //     data: { alertId: alert.id, type: 'alert' }
        //   });
        // }
    }
    // Track notified supporters
    const supporterIds = supporters
        .filter((s) => s.supporter_id)
        .map((s) => s.supporter_id);
    await (0, index_js_1.sql) `
    UPDATE alerts
    SET notified_supporter_ids = ${supporterIds}
    WHERE id = ${alert.id}
  `;
}
// Run the job
checkMissedCheckins()
    .then(() => {
    console.log('[check-missed-checkins] Completed successfully');
    process.exit(0);
})
    .catch((error) => {
    console.error('[check-missed-checkins] Failed:', error);
    process.exit(1);
});
//# sourceMappingURL=check-missed-checkins.js.map