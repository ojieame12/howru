/**
 * Apple Push Notification Service (APNs)
 * Uses HTTP/2 provider API for sending push notifications
 *
 * Features:
 * - JWT-based authentication
 * - Critical alerts for escalation
 * - Rich notifications with actions
 */

import http2 from 'http2';
import jwt from 'jsonwebtoken';
import { getPushTokensForUser } from '../db/index.js';

// APNs Configuration
const APNS_KEY_ID = process.env.APNS_KEY_ID;
const APNS_TEAM_ID = process.env.APNS_TEAM_ID;
const APNS_BUNDLE_ID = process.env.APNS_BUNDLE_ID || 'com.howru.app';
const APNS_KEY_BASE64 = process.env.APNS_KEY_BASE64;

// Production: api.push.apple.com
// Development: api.sandbox.push.apple.com
const APNS_HOST =
  process.env.NODE_ENV === 'production'
    ? 'api.push.apple.com'
    : 'api.sandbox.push.apple.com';

interface PushPayload {
  title: string;
  body: string;
  subtitle?: string;
  badge?: number;
  sound?: string | { critical: 1; name: string; volume: number };
  data?: Record<string, unknown>;
  category?: string;
  threadId?: string;
  targetContentId?: string;
  interruptionLevel?: 'passive' | 'active' | 'time-sensitive' | 'critical';
}

interface PushResult {
  success: boolean;
  token: string;
  apnsId?: string;
  error?: string;
}

// Cache the JWT token (valid for 1 hour, we'll refresh every 50 minutes)
let cachedToken: { token: string; expires: number } | null = null;

/**
 * Generate APNs JWT authentication token
 */
function generateAPNsToken(): string {
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
  const token = jwt.sign({}, privateKey, {
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
async function sendToToken(
  deviceToken: string,
  payload: PushPayload,
  priority: number = 10
): Promise<PushResult> {
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
      const client = http2.connect(`https://${APNS_HOST}`);

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
        const apnsId = headers['apns-id'] as string;

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
          } else {
            let errorReason = 'Unknown error';
            try {
              const errorBody = JSON.parse(responseBody);
              errorReason = errorBody.reason || errorReason;
            } catch {
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
    } catch (error: any) {
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
export async function sendPushNotification(
  userId: string,
  payload: PushPayload
): Promise<PushResult[]> {
  const tokens = await getPushTokensForUser(userId);

  if (!tokens || tokens.length === 0) {
    return [];
  }

  const results = await Promise.all(
    tokens.map((t: any) => sendToToken(t.token, payload))
  );

  return results;
}

/**
 * Send check-in reminder push
 */
export async function sendReminderPush(userId: string): Promise<PushResult[]> {
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
export async function sendPokePush(
  userId: string,
  fromName: string,
  message?: string
): Promise<PushResult[]> {
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
export async function sendAlertPush(
  supporterId: string,
  checkerName: string,
  alertLevel: 'soft' | 'hard' | 'escalation',
  alertId: string,
  hoursSinceMissed: number
): Promise<PushResult[]> {
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
export async function sendCheckInPush(
  supporterId: string,
  checkerName: string,
  scores: { mental: number; body: number; mood: number }
): Promise<PushResult[]> {
  const avgScore = (scores.mental + scores.body + scores.mood) / 3;
  const emoji = avgScore >= 4 ? 'great' : avgScore >= 3 ? 'good' : 'low';

  return sendPushNotification(supporterId, {
    title: `${checkerName} checked in`,
    body:
      emoji === 'great'
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
