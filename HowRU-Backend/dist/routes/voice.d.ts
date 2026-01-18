/**
 * TwiML Voice Routes
 * Handles automated voice calls for alert escalation
 *
 * Features:
 * - Polly neural voice for natural speech
 * - DTMF gathering for acknowledgment
 * - Call status tracking
 */
declare const router: import("express-serve-static-core").Router;
export default router;
export declare function initiateAlertCall(supporterPhone: string, alertId: string): Promise<string | null>;
//# sourceMappingURL=voice.d.ts.map