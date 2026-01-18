"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sql = void 0;
exports.getUserByPhone = getUserByPhone;
exports.getUserById = getUserById;
exports.getUserByEmail = getUserByEmail;
exports.createUser = createUser;
exports.updateUserLocation = updateUserLocation;
exports.createCheckIn = createCheckIn;
exports.getTodayCheckIn = getTodayCheckIn;
exports.getRecentCheckIns = getRecentCheckIns;
exports.getActiveSchedule = getActiveSchedule;
exports.createSchedule = createSchedule;
exports.getCircleLinks = getCircleLinks;
exports.getSupportedUsers = getSupportedUsers;
exports.createAlert = createAlert;
exports.getActiveAlerts = getActiveAlerts;
exports.resolveAlerts = resolveAlerts;
exports.saveRefreshToken = saveRefreshToken;
exports.getRefreshToken = getRefreshToken;
exports.deleteRefreshToken = deleteRefreshToken;
exports.deleteUserRefreshTokens = deleteUserRefreshTokens;
exports.createCircleLink = createCircleLink;
exports.updateCircleLink = updateCircleLink;
exports.removeCircleLink = removeCircleLink;
exports.getCircleLinkById = getCircleLinkById;
exports.createInvite = createInvite;
exports.getInviteByCode = getInviteByCode;
exports.acceptInvite = acceptInvite;
exports.getInvitesByUser = getInvitesByUser;
exports.createPoke = createPoke;
exports.getPokesForUser = getPokesForUser;
exports.getUnseenPokesCount = getUnseenPokesCount;
exports.markPokeSeen = markPokeSeen;
exports.markPokeResponded = markPokeResponded;
exports.getAlertsForSupporter = getAlertsForSupporter;
exports.acknowledgeAlert = acknowledgeAlert;
exports.resolveAlert = resolveAlert;
exports.escalateAlert = escalateAlert;
exports.updateUser = updateUser;
exports.updateSchedule = updateSchedule;
exports.savePushToken = savePushToken;
exports.getPushTokensForUser = getPushTokensForUser;
exports.deletePushToken = deletePushToken;
exports.getSubscription = getSubscription;
const serverless_1 = require("@neondatabase/serverless");
// Enable connection caching for serverless
serverless_1.neonConfig.fetchConnectionCache = true;
const sql = (0, serverless_1.neon)(process.env.DATABASE_URL);
exports.sql = sql;
// ============================================================================
// USER QUERIES
// ============================================================================
async function getUserByPhone(phone) {
    const result = await sql `
    SELECT * FROM users WHERE phone_number = ${phone}
  `;
    return result[0] || null;
}
async function getUserById(id) {
    const result = await sql `
    SELECT * FROM users WHERE id = ${id}
  `;
    return result[0] || null;
}
async function getUserByEmail(email) {
    const result = await sql `
    SELECT * FROM users WHERE email = ${email}
  `;
    return result[0] || null;
}
async function createUser(data) {
    const result = await sql `
    INSERT INTO users (phone_number, name, is_checker)
    VALUES (${data.phoneNumber}, ${data.name}, ${data.isChecker ?? true})
    RETURNING *
  `;
    return result[0];
}
async function updateUserLocation(userId, latitude, longitude, address, locationAt) {
    await sql `
    UPDATE users
    SET last_known_latitude = ${latitude},
        last_known_longitude = ${longitude},
        last_known_address = ${address},
        last_known_location_at = ${locationAt.toISOString()},
        updated_at = NOW()
    WHERE id = ${userId}
  `;
}
// ============================================================================
// CHECK-IN QUERIES
// ============================================================================
async function createCheckIn(data) {
    const result = await sql `
    INSERT INTO checkins (
      user_id, mental_score, body_score, mood_score,
      latitude, longitude, location_name, address,
      is_manual, timestamp
    )
    VALUES (
      ${data.userId}, ${data.mentalScore}, ${data.bodyScore}, ${data.moodScore},
      ${data.latitude ?? null}, ${data.longitude ?? null},
      ${data.locationName ?? null}, ${data.address ?? null},
      ${data.isManual ?? true}, ${(data.timestamp ?? new Date()).toISOString()}
    )
    RETURNING *
  `;
    const checkIn = result[0];
    // Update user's cached location
    if (data.latitude && data.longitude) {
        await updateUserLocation(data.userId, data.latitude, data.longitude, data.address || data.locationName || null, data.timestamp ?? new Date());
    }
    return checkIn;
}
async function getTodayCheckIn(userId, timezone = 'UTC') {
    const result = await sql `
    SELECT * FROM checkins
    WHERE user_id = ${userId}
      AND timestamp::date = (NOW() AT TIME ZONE ${timezone})::date
    ORDER BY timestamp DESC
    LIMIT 1
  `;
    return result[0] || null;
}
async function getRecentCheckIns(userId, limit = 30) {
    return sql `
    SELECT * FROM checkins
    WHERE user_id = ${userId}
    ORDER BY timestamp DESC
    LIMIT ${limit}
  `;
}
// ============================================================================
// SCHEDULE QUERIES
// ============================================================================
async function getActiveSchedule(userId) {
    const result = await sql `
    SELECT * FROM schedules
    WHERE user_id = ${userId} AND is_active = true
    ORDER BY created_at DESC
    LIMIT 1
  `;
    return result[0] || null;
}
async function createSchedule(data) {
    const result = await sql `
    INSERT INTO schedules (
      user_id, window_start_hour, window_end_hour,
      timezone_identifier, grace_period_minutes
    )
    VALUES (
      ${data.userId},
      ${data.windowStartHour ?? 8},
      ${data.windowEndHour ?? 20},
      ${data.timezone ?? 'UTC'},
      ${data.gracePeriodMinutes ?? 60}
    )
    RETURNING *
  `;
    return result[0];
}
// ============================================================================
// CIRCLE LINK QUERIES
// ============================================================================
async function getCircleLinks(checkerId) {
    return sql `
    SELECT cl.*, u.name as supporter_name, u.phone_number as supporter_phone_from_user
    FROM circle_links cl
    LEFT JOIN users u ON cl.supporter_id = u.id
    WHERE cl.checker_id = ${checkerId} AND cl.is_active = true
  `;
}
async function getSupportedUsers(supporterId) {
    return sql `
    SELECT cl.*, u.name as checker_name, u.phone_number as checker_phone,
           u.last_known_location_at, u.last_known_address
    FROM circle_links cl
    JOIN users u ON cl.checker_id = u.id
    WHERE cl.supporter_id = ${supporterId} AND cl.is_active = true
  `;
}
// ============================================================================
// ALERT QUERIES
// ============================================================================
async function createAlert(data) {
    const result = await sql `
    INSERT INTO alerts (
      checker_id, checker_name, type, missed_window_at,
      last_checkin_at, last_known_location, notified_supporter_ids
    )
    VALUES (
      ${data.checkerId}, ${data.checkerName}, ${data.type},
      ${data.missedWindowAt.toISOString()},
      ${data.lastCheckinAt?.toISOString() ?? null},
      ${data.lastKnownLocation ?? null},
      ${data.notifiedSupporterIds ?? []}
    )
    RETURNING *
  `;
    return result[0];
}
async function getActiveAlerts(checkerId) {
    return sql `
    SELECT * FROM alerts
    WHERE checker_id = ${checkerId} AND resolved_at IS NULL
    ORDER BY triggered_at DESC
  `;
}
async function resolveAlerts(checkerId) {
    await sql `
    UPDATE alerts
    SET status = 'resolved', resolved_at = NOW()
    WHERE checker_id = ${checkerId} AND resolved_at IS NULL
  `;
}
// ============================================================================
// REFRESH TOKEN QUERIES
// ============================================================================
async function saveRefreshToken(userId, tokenHash, expiresAt) {
    await sql `
    INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
    VALUES (${userId}, ${tokenHash}, ${expiresAt.toISOString()})
  `;
}
async function getRefreshToken(tokenHash) {
    const result = await sql `
    SELECT * FROM refresh_tokens
    WHERE token_hash = ${tokenHash} AND expires_at > NOW()
  `;
    return result[0] || null;
}
async function deleteRefreshToken(tokenHash) {
    await sql `
    DELETE FROM refresh_tokens WHERE token_hash = ${tokenHash}
  `;
}
async function deleteUserRefreshTokens(userId) {
    await sql `
    DELETE FROM refresh_tokens WHERE user_id = ${userId}
  `;
}
// ============================================================================
// CIRCLE LINK QUERIES (Extended)
// ============================================================================
async function createCircleLink(data) {
    const result = await sql `
    INSERT INTO circle_links (
      checker_id, supporter_id, supporter_display_name,
      supporter_phone, supporter_email,
      can_see_mood, can_see_location, can_see_selfie, can_poke,
      alert_priority, alert_via_push, alert_via_sms, alert_via_email
    )
    VALUES (
      ${data.checkerId}, ${data.supporterId ?? null}, ${data.supporterDisplayName},
      ${data.supporterPhone ?? null}, ${data.supporterEmail ?? null},
      ${data.canSeeMood ?? true}, ${data.canSeeLocation ?? false},
      ${data.canSeeSelfie ?? false}, ${data.canPoke ?? true},
      ${data.alertPriority ?? 1}, ${data.alertViaPush ?? true},
      ${data.alertViaSms ?? false}, ${data.alertViaEmail ?? false}
    )
    RETURNING *
  `;
    return result[0];
}
async function updateCircleLink(linkId, checkerId, data) {
    const result = await sql `
    UPDATE circle_links
    SET
      supporter_display_name = COALESCE(${data.supporterDisplayName ?? null}, supporter_display_name),
      can_see_mood = COALESCE(${data.canSeeMood ?? null}, can_see_mood),
      can_see_location = COALESCE(${data.canSeeLocation ?? null}, can_see_location),
      can_see_selfie = COALESCE(${data.canSeeSelfie ?? null}, can_see_selfie),
      can_poke = COALESCE(${data.canPoke ?? null}, can_poke),
      alert_priority = COALESCE(${data.alertPriority ?? null}, alert_priority),
      alert_via_push = COALESCE(${data.alertViaPush ?? null}, alert_via_push),
      alert_via_sms = COALESCE(${data.alertViaSms ?? null}, alert_via_sms),
      alert_via_email = COALESCE(${data.alertViaEmail ?? null}, alert_via_email)
    WHERE id = ${linkId} AND checker_id = ${checkerId}
    RETURNING *
  `;
    return result[0] || null;
}
async function removeCircleLink(linkId, checkerId) {
    await sql `
    UPDATE circle_links
    SET is_active = false
    WHERE id = ${linkId} AND checker_id = ${checkerId}
  `;
}
async function getCircleLinkById(linkId) {
    const result = await sql `
    SELECT * FROM circle_links WHERE id = ${linkId}
  `;
    return result[0] || null;
}
// ============================================================================
// INVITE QUERIES
// ============================================================================
async function createInvite(data) {
    const result = await sql `
    INSERT INTO invites (
      inviter_id, code, role,
      can_see_mood, can_see_location, can_see_selfie, can_poke,
      expires_at
    )
    VALUES (
      ${data.inviterId}, ${data.code}, ${data.role},
      ${data.canSeeMood ?? true}, ${data.canSeeLocation ?? false},
      ${data.canSeeSelfie ?? false}, ${data.canPoke ?? true},
      ${data.expiresAt.toISOString()}
    )
    RETURNING *
  `;
    return result[0];
}
async function getInviteByCode(code) {
    const result = await sql `
    SELECT i.*, u.name as inviter_name, u.phone_number as inviter_phone
    FROM invites i
    JOIN users u ON i.inviter_id = u.id
    WHERE i.code = ${code} AND i.expires_at > NOW() AND i.accepted_at IS NULL
  `;
    return result[0] || null;
}
async function acceptInvite(code, acceptedById) {
    const result = await sql `
    UPDATE invites
    SET accepted_at = NOW(), accepted_by = ${acceptedById}
    WHERE code = ${code} AND accepted_at IS NULL
    RETURNING *
  `;
    return result[0] || null;
}
async function getInvitesByUser(userId) {
    return sql `
    SELECT * FROM invites
    WHERE inviter_id = ${userId}
    ORDER BY created_at DESC
    LIMIT 20
  `;
}
// ============================================================================
// POKE QUERIES
// ============================================================================
async function createPoke(data) {
    const result = await sql `
    INSERT INTO pokes (from_user_id, to_user_id, message)
    VALUES (${data.fromUserId}, ${data.toUserId}, ${data.message ?? null})
    RETURNING *
  `;
    return result[0];
}
async function getPokesForUser(userId, limit = 20) {
    return sql `
    SELECT p.*, u.name as from_name
    FROM pokes p
    JOIN users u ON p.from_user_id = u.id
    WHERE p.to_user_id = ${userId}
    ORDER BY p.sent_at DESC
    LIMIT ${limit}
  `;
}
async function getUnseenPokesCount(userId) {
    const result = await sql `
    SELECT COUNT(*) as count FROM pokes
    WHERE to_user_id = ${userId} AND seen_at IS NULL
  `;
    return parseInt(result[0]?.count || '0', 10);
}
async function markPokeSeen(pokeId, userId) {
    await sql `
    UPDATE pokes
    SET seen_at = NOW()
    WHERE id = ${pokeId} AND to_user_id = ${userId}
  `;
}
async function markPokeResponded(pokeId, userId) {
    await sql `
    UPDATE pokes
    SET responded_at = NOW()
    WHERE id = ${pokeId} AND to_user_id = ${userId}
  `;
}
// ============================================================================
// ALERT QUERIES (Extended)
// ============================================================================
async function getAlertsForSupporter(supporterId) {
    return sql `
    SELECT a.*, u.name as checker_name, u.last_known_address
    FROM alerts a
    JOIN users u ON a.checker_id = u.id
    JOIN circle_links cl ON cl.checker_id = a.checker_id
    WHERE cl.supporter_id = ${supporterId}
      AND cl.is_active = true
      AND a.resolved_at IS NULL
    ORDER BY a.triggered_at DESC
  `;
}
async function acknowledgeAlert(alertId, supporterId) {
    const result = await sql `
    UPDATE alerts
    SET acknowledged_at = NOW(), acknowledged_by = ${supporterId}
    WHERE id = ${alertId} AND acknowledged_at IS NULL
    RETURNING *
  `;
    return result[0] || null;
}
async function resolveAlert(alertId, supporterId, resolution, notes) {
    const result = await sql `
    UPDATE alerts
    SET
      status = 'resolved',
      resolved_at = NOW(),
      resolved_by = ${supporterId},
      resolution = ${resolution},
      resolution_notes = ${notes ?? null}
    WHERE id = ${alertId}
    RETURNING *
  `;
    return result[0] || null;
}
async function escalateAlert(alertId, newType) {
    const result = await sql `
    UPDATE alerts
    SET type = ${newType}
    WHERE id = ${alertId}
    RETURNING *
  `;
    return result[0] || null;
}
// ============================================================================
// USER QUERIES (Extended)
// ============================================================================
async function updateUser(userId, data) {
    const result = await sql `
    UPDATE users
    SET
      name = COALESCE(${data.name ?? null}, name),
      email = COALESCE(${data.email ?? null}, email),
      profile_image_url = COALESCE(${data.profileImageUrl ?? null}, profile_image_url),
      address = COALESCE(${data.address ?? null}, address),
      updated_at = NOW()
    WHERE id = ${userId}
    RETURNING *
  `;
    return result[0] || null;
}
async function updateSchedule(userId, data) {
    // First try to update existing active schedule
    const existing = await getActiveSchedule(userId);
    if (existing) {
        const result = await sql `
      UPDATE schedules
      SET
        window_start_hour = COALESCE(${data.windowStartHour ?? null}, window_start_hour),
        window_start_minute = COALESCE(${data.windowStartMinute ?? null}, window_start_minute),
        window_end_hour = COALESCE(${data.windowEndHour ?? null}, window_end_hour),
        window_end_minute = COALESCE(${data.windowEndMinute ?? null}, window_end_minute),
        timezone_identifier = COALESCE(${data.timezone ?? null}, timezone_identifier),
        active_days = COALESCE(${data.activeDays ?? null}, active_days),
        grace_period_minutes = COALESCE(${data.gracePeriodMinutes ?? null}, grace_period_minutes),
        reminder_enabled = COALESCE(${data.reminderEnabled ?? null}, reminder_enabled),
        reminder_minutes_before = COALESCE(${data.reminderMinutesBefore ?? null}, reminder_minutes_before)
      WHERE id = ${existing.id}
      RETURNING *
    `;
        return result[0];
    }
    else {
        // Create new schedule
        return createSchedule({
            userId,
            windowStartHour: data.windowStartHour,
            windowEndHour: data.windowEndHour,
            timezone: data.timezone,
            gracePeriodMinutes: data.gracePeriodMinutes,
        });
    }
}
// ============================================================================
// PUSH TOKEN QUERIES
// ============================================================================
async function savePushToken(userId, token, platform, deviceId) {
    await sql `
    INSERT INTO push_tokens (user_id, token, platform, device_id)
    VALUES (${userId}, ${token}, ${platform}, ${deviceId ?? null})
    ON CONFLICT (user_id, token) DO UPDATE
    SET updated_at = NOW(), device_id = EXCLUDED.device_id
  `;
}
async function getPushTokensForUser(userId) {
    return sql `
    SELECT * FROM push_tokens WHERE user_id = ${userId}
  `;
}
async function deletePushToken(userId, token) {
    await sql `
    DELETE FROM push_tokens WHERE user_id = ${userId} AND token = ${token}
  `;
}
// ============================================================================
// SUBSCRIPTION QUERIES
// ============================================================================
async function getSubscription(userId) {
    const result = await sql `
    SELECT * FROM subscriptions WHERE user_id = ${userId}
  `;
    return result[0] || null;
}
//# sourceMappingURL=index.js.map