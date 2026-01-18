/**
 * Apple Push Notification Service (APNs)
 * Uses HTTP/2 provider API for sending push notifications
 *
 * Features:
 * - JWT-based authentication
 * - Critical alerts for escalation
 * - Rich notifications with actions
 */
interface PushPayload {
    title: string;
    body: string;
    subtitle?: string;
    badge?: number;
    sound?: string | {
        critical: 1;
        name: string;
        volume: number;
    };
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
/**
 * Send push notification to a user (all their registered devices)
 */
export declare function sendPushNotification(userId: string, payload: PushPayload): Promise<PushResult[]>;
/**
 * Send check-in reminder push
 */
export declare function sendReminderPush(userId: string): Promise<PushResult[]>;
/**
 * Send poke notification
 */
export declare function sendPokePush(userId: string, fromName: string, message?: string): Promise<PushResult[]>;
/**
 * Send alert notification to supporter
 */
export declare function sendAlertPush(supporterId: string, checkerName: string, alertLevel: 'soft' | 'hard' | 'escalation', alertId: string, hoursSinceMissed: number): Promise<PushResult[]>;
/**
 * Send check-in notification to supporters
 */
export declare function sendCheckInPush(supporterId: string, checkerName: string, scores: {
    mental: number;
    body: number;
    mood: number;
}): Promise<PushResult[]>;
export {};
//# sourceMappingURL=apns.d.ts.map