"use strict";
/**
 * Apple Push Notification Service (APNs)
 * Uses HTTP/2 provider API for sending push notifications
 *
 * Features:
 * - JWT-based authentication
 * - Critical alerts for escalation
 * - Rich notifications with actions
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendPushNotification = sendPushNotification;
exports.sendReminderPush = sendReminderPush;
exports.sendPokePush = sendPokePush;
exports.sendAlertPush = sendAlertPush;
exports.sendCheckInPush = sendCheckInPush;
const http2_1 = __importDefault(require("http2"));
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const index_js_1 = require("../db/index.js");
// APNs Configuration
const APNS_KEY_ID = process.env.APNS_KEY_ID;
const APNS_TEAM_ID = process.env.APNS_TEAM_ID;
const APNS_BUNDLE_ID = process.env.APNS_BUNDLE_ID || 'com.howru.app';
const APNS_KEY_BASE64 = process.env.APNS_KEY_BASE64;
// Production: api.push.apple.com
// Development: api.sandbox.push.apple.com
const APNS_HOST = process.env.NODE_ENV === 'production'
    ? 'api.push.apple.com'
    : 'api.sandbox.push.apple.com';
// Cache the JWT token (valid for 1 hour, we'll refresh every 50 minutes)
let cachedToken = null;
/**
 * Generate APNs JWT authentication token
 */
function generateAPNsToken() {
    if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_KEY_BASE64) {
        throw new Error('APNs credentials not configured');
    }
    const now = Math.floor(Date.now() / 1000);
    // Check if cached token is still valid (with 10 min buffer)
    if (cachedToken && cachedToken.expires > now + 600) {
        return cachedToken.token;
    }
    // Decode the private key from base64
    const privateKey = Buffer.from(APNS_KEY_BASE64, 'base64').toString('utf8');
    // Generate new token
    const token = jsonwebtoken_1.default.sign({}, privateKey, {
        algorithm: 'ES256',
        keyid: APNS_KEY_ID,
        issuer: APNS_TEAM_ID,
        expiresIn: '1h',
    });
    // Cache for 50 minutes
    cachedToken = {
        token,
        expires: now + 3000,
    };
    return token;
}
/**
 * Send push notification to a single device token
 */
async function sendToToken(deviceToken, payload, priority = 10) {
    return new Promise((resolve) => {
        try {
            const authToken = generateAPNsToken();
            // Build APNs payload
            const apnsPayload = {
                aps: {
                    alert: {
                        title: payload.title,
                        body: payload.body,
                        ...(payload.subtitle && { subtitle: payload.subtitle }),
                    },
                    ...(payload.badge !== undefined && { badge: payload.badge }),
                    ...(payload.sound && { sound: payload.sound }),
                    ...(payload.category && { category: payload.category }),
                    ...(payload.threadId && { 'thread-id': payload.threadId }),
                    ...(payload.targetContentId && {
                        'target-content-id': payload.targetContentId,
                    }),
                    ...(payload.interruptionLevel && {
                        'interruption-level': payload.interruptionLevel,
                    }),
                },
                ...payload.data,
            };
            const payloadString = JSON.stringify(apnsPayload);
            // Create HTTP/2 session
            const client = http2_1.default.connect(`https://${APNS_HOST}`);
            client.on('error', (err) => {
                console.error('APNs connection error:', err);
                resolve({
                    success: false,
                    token: deviceToken,
                    error: err.message,
                });
            });
            // Send request
            const req = client.request({
                ':method': 'POST',
                ':path': `/3/device/${deviceToken}`,
                authorization: `bearer ${authToken}`,
                'apns-topic': APNS_BUNDLE_ID,
                'apns-push-type': 'alert',
                'apns-priority': priority.toString(),
                'content-type': 'application/json',
                'content-length': Buffer.byteLength(payloadString),
            });
            let responseBody = '';
            req.on('response', (headers) => {
                const status = headers[':status'];
                const apnsId = headers['apns-id'];
                req.on('data', (chunk) => {
                    responseBody += chunk;
                });
                req.on('end', () => {
                    client.close();
                    if (status === 200) {
                        resolve({
                            success: true,
                            token: deviceToken,
                            apnsId,
                        });
                    }
                    else {
                        let errorReason = 'Unknown error';
                        try {
                            const errorBody = JSON.parse(responseBody);
                            errorReason = errorBody.reason || errorReason;
                        }
                        catch {
                            // Ignore parse error
                        }
                        resolve({
                            success: false,
                            token: deviceToken,
                            error: `${status}: ${errorReason}`,
                        });
                    }
                });
            });
            req.on('error', (err) => {
                client.close();
                resolve({
                    success: false,
                    token: deviceToken,
                    error: err.message,
                });
            });
            req.write(payloadString);
            req.end();
        }
        catch (error) {
            resolve({
                success: false,
                token: deviceToken,
                error: error.message,
            });
        }
    });
}
/**
 * Send push notification to a user (all their registered devices)
 */
async function sendPushNotification(userId, payload) {
    const tokens = await (0, index_js_1.getPushTokensForUser)(userId);
    if (!tokens || tokens.length === 0) {
        return [];
    }
    const results = await Promise.all(tokens.map((t) => sendToToken(t.token, payload)));
    return results;
}
/**
 * Send check-in reminder push
 */
async function sendReminderPush(userId) {
    return sendPushNotification(userId, {
        title: 'Time to Check In',
        body: "Don't forget to log how you're feeling today!",
        sound: 'default',
        category: 'CHECKIN_REMINDER',
        interruptionLevel: 'time-sensitive',
        data: {
            type: 'reminder',
        },
    });
}
/**
 * Send poke notification
 */
async function sendPokePush(userId, fromName, message) {
    return sendPushNotification(userId, {
        title: `${fromName} sent you a poke`,
        body: message || 'Tap to check in and let them know you\'re okay',
        sound: 'default',
        category: 'POKE',
        interruptionLevel: 'time-sensitive',
        data: {
            type: 'poke',
            fromName,
        },
    });
}
/**
 * Send alert notification to supporter
 */
async function sendAlertPush(supporterId, checkerName, alertLevel, alertId, hoursSinceMissed) {
    const isCritical = alertLevel === 'escalation';
    return sendPushNotification(supporterId, {
        title: isCritical
            ? `URGENT: ${checkerName} needs help`
            : `Alert: ${checkerName} hasn't checked in`,
        body: `It's been ${Math.round(hoursSinceMissed)} hours since their last check-in`,
        sound: isCritical
            ? { critical: 1, name: 'alert.caf', volume: 1.0 }
            : 'default',
        category: 'ALERT',
        interruptionLevel: isCritical ? 'critical' : 'time-sensitive',
        data: {
            type: 'alert',
            alertId,
            alertLevel,
            checkerName,
        },
    });
}
/**
 * Send check-in notification to supporters
 */
async function sendCheckInPush(supporterId, checkerName, scores) {
    const avgScore = (scores.mental + scores.body + scores.mood) / 3;
    const emoji = avgScore >= 4 ? 'great' : avgScore >= 3 ? 'good' : 'low';
    return sendPushNotification(supporterId, {
        title: `${checkerName} checked in`,
        body: emoji === 'great'
            ? "They're feeling great today!"
            : emoji === 'good'
                ? "They're doing okay"
                : 'They could use some support',
        sound: 'default',
        category: 'CHECKIN',
        interruptionLevel: 'passive',
        data: {
            type: 'checkin',
            checkerName,
            scores,
        },
    });
}
//# sourceMappingURL=apns.js.map