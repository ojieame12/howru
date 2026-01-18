/**
 * Cron Job: Daily Stats
 * Runs daily at midnight UTC to aggregate statistics
 *
 * Collects:
 * - Active users count
 * - Total check-ins
 * - Average scores (mental, body, mood)
 * - Missed check-ins count
 * - Alerts triggered count
 */

import { sql } from '../db/index.js';

async function generateDailyStats() {
  console.log('[daily-stats] Starting job...');

  try {
    // Calculate stats for yesterday
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const dateStr = yesterday.toISOString().split('T')[0];

    console.log(`[daily-stats] Generating stats for ${dateStr}`);

    // Get check-in stats
    const checkInStats = await sql`
      SELECT
        COUNT(DISTINCT user_id) as active_users,
        COUNT(*) as total_checkins,
        AVG(mental_score) as avg_mental,
        AVG(body_score) as avg_body,
        AVG(mood_score) as avg_mood
      FROM checkins
      WHERE DATE(timestamp) = ${dateStr}
    `;

    // Get alert stats
    const alertStats = await sql`
      SELECT COUNT(*) as alerts_triggered
      FROM alerts
      WHERE DATE(triggered_at) = ${dateStr}
    `;

    // Get missed check-in count (users with schedules who didn't check in)
    const missedStats = await sql`
      SELECT COUNT(*) as missed_checkins
      FROM users u
      JOIN schedules s ON s.user_id = u.id AND s.is_active = true
      WHERE u.is_checker = true
      AND EXTRACT(DOW FROM ${dateStr}::date)::int = ANY(s.active_days)
      AND NOT EXISTS (
        SELECT 1 FROM checkins c
        WHERE c.user_id = u.id
        AND DATE(c.timestamp) = ${dateStr}
      )
    `;

    const stats = {
      date: dateStr,
      activeUsers: parseInt(checkInStats[0]?.active_users || '0'),
      totalCheckins: parseInt(checkInStats[0]?.total_checkins || '0'),
      avgMental: parseFloat(checkInStats[0]?.avg_mental || '0').toFixed(2),
      avgBody: parseFloat(checkInStats[0]?.avg_body || '0').toFixed(2),
      avgMood: parseFloat(checkInStats[0]?.avg_mood || '0').toFixed(2),
      missedCheckins: parseInt(missedStats[0]?.missed_checkins || '0'),
      alertsTriggered: parseInt(alertStats[0]?.alerts_triggered || '0'),
    };

    console.log('[daily-stats] Stats:', stats);

    // Upsert into daily_stats table
    await sql`
      INSERT INTO daily_stats (
        date, active_users, total_checkins,
        avg_mental, avg_body, avg_mood,
        missed_checkins, alerts_triggered
      )
      VALUES (
        ${stats.date},
        ${stats.activeUsers},
        ${stats.totalCheckins},
        ${stats.avgMental},
        ${stats.avgBody},
        ${stats.avgMood},
        ${stats.missedCheckins},
        ${stats.alertsTriggered}
      )
      ON CONFLICT (date) DO UPDATE
      SET
        active_users = EXCLUDED.active_users,
        total_checkins = EXCLUDED.total_checkins,
        avg_mental = EXCLUDED.avg_mental,
        avg_body = EXCLUDED.avg_body,
        avg_mood = EXCLUDED.avg_mood,
        missed_checkins = EXCLUDED.missed_checkins,
        alerts_triggered = EXCLUDED.alerts_triggered
    `;

    console.log('[daily-stats] Stats saved successfully');
  } catch (error) {
    console.error('[daily-stats] Error:', error);
    throw error;
  }
}

// Run the job
generateDailyStats()
  .then(() => {
    console.log('[daily-stats] Completed successfully');
    process.exit(0);
  })
  .catch((error) => {
    console.error('[daily-stats] Failed:', error);
    process.exit(1);
  });
