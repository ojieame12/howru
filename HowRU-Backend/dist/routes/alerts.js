"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const auth_js_1 = require("../middleware/auth.js");
const index_js_1 = require("../db/index.js");
const resend_js_1 = require("../services/resend.js");
const twilio_js_1 = require("../services/twilio.js");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_js_1.authMiddleware);
// ============================================================================
// GET MY ACTIVE ALERTS (as checker - alerts about me)
// ============================================================================
router.get('/mine', async (req, res) => {
    try {
        const userId = req.userId;
        const alerts = await (0, index_js_1.getActiveAlerts)(userId);
        res.json({
            success: true,
            alerts: alerts.map((a) => ({
                id: a.id,
                type: a.type,
                status: a.status,
                triggeredAt: a.triggered_at,
                missedWindowAt: a.missed_window_at,
                lastCheckInAt: a.last_checkin_at,
                lastKnownLocation: a.last_known_location,
                acknowledgedAt: a.acknowledged_at,
            })),
        });
    }
    catch (error) {
        console.error('Get my alerts error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get alerts',
        });
    }
});
// ============================================================================
// GET ALERTS FOR PEOPLE I'M SUPPORTING
// ============================================================================
router.get('/', async (req, res) => {
    try {
        const userId = req.userId;
        const alerts = await (0, index_js_1.getAlertsForSupporter)(userId);
        res.json({
            success: true,
            alerts: alerts.map((a) => ({
                id: a.id,
                checkerId: a.checker_id,
                checkerName: a.checker_name,
                type: a.type,
                status: a.status,
                triggeredAt: a.triggered_at,
                missedWindowAt: a.missed_window_at,
                lastCheckInAt: a.last_checkin_at,
                lastKnownLocation: a.last_known_location || a.last_known_address,
                acknowledgedAt: a.acknowledged_at,
                acknowledgedBy: a.acknowledged_by,
            })),
        });
    }
    catch (error) {
        console.error('Get alerts error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get alerts',
        });
    }
});
// ============================================================================
// ACKNOWLEDGE ALERT
// ============================================================================
router.post('/:alertId/acknowledge', async (req, res) => {
    try {
        const userId = req.userId;
        const { alertId } = req.params;
        const alert = await (0, index_js_1.acknowledgeAlert)(alertId, userId);
        if (!alert) {
            return res.status(404).json({
                success: false,
                error: 'Alert not found or already acknowledged',
            });
        }
        res.json({
            success: true,
            alert: {
                id: alert.id,
                acknowledgedAt: alert.acknowledged_at,
            },
        });
    }
    catch (error) {
        console.error('Acknowledge alert error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to acknowledge alert',
        });
    }
});
// ============================================================================
// RESOLVE ALERT
// ============================================================================
const resolveAlertSchema = zod_1.z.object({
    resolution: zod_1.z.enum([
        'checked_in',
        'contacted',
        'safe_confirmed',
        'false_alarm',
        'other',
    ]),
    notes: zod_1.z.string().max(500).optional(),
});
router.post('/:alertId/resolve', async (req, res) => {
    try {
        const userId = req.userId;
        const { alertId } = req.params;
        const data = resolveAlertSchema.parse(req.body);
        const alert = await (0, index_js_1.resolveAlert)(alertId, userId, data.resolution, data.notes);
        if (!alert) {
            return res.status(404).json({
                success: false,
                error: 'Alert not found',
            });
        }
        res.json({
            success: true,
            alert: {
                id: alert.id,
                status: alert.status,
                resolvedAt: alert.resolved_at,
                resolution: alert.resolution,
            },
        });
    }
    catch (error) {
        console.error('Resolve alert error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to resolve alert',
        });
    }
});
// ============================================================================
// TRIGGER ALERT (internal/cron use, but can be called manually)
// ============================================================================
const triggerAlertSchema = zod_1.z.object({
    checkerId: zod_1.z.string().uuid(),
    type: zod_1.z.enum(['reminder', 'soft', 'hard', 'escalation']),
});
router.post('/trigger', async (req, res) => {
    try {
        const data = triggerAlertSchema.parse(req.body);
        const checker = await (0, index_js_1.getUserById)(data.checkerId);
        if (!checker) {
            return res.status(404).json({
                success: false,
                error: 'Checker not found',
            });
        }
        // Get last check-in
        const recentCheckIns = await (0, index_js_1.getRecentCheckIns)(data.checkerId, 1);
        const lastCheckIn = recentCheckIns[0];
        // Create the alert
        const alert = await (0, index_js_1.createAlert)({
            checkerId: data.checkerId,
            checkerName: checker.name,
            type: data.type,
            missedWindowAt: new Date(),
            lastCheckinAt: lastCheckIn?.timestamp ? new Date(lastCheckIn.timestamp) : undefined,
            lastKnownLocation: checker.last_known_address,
        });
        // Get circle members to notify
        const circle = await (0, index_js_1.getCircleLinks)(data.checkerId);
        // Notify supporters based on their preferences
        for (const supporter of circle) {
            if (!supporter.is_active)
                continue;
            const supporterUser = supporter.supporter_id
                ? await (0, index_js_1.getUserById)(supporter.supporter_id)
                : null;
            const lastMood = lastCheckIn
                ? {
                    mental: lastCheckIn.mental_score,
                    body: lastCheckIn.body_score,
                    mood: lastCheckIn.mood_score,
                }
                : undefined;
            // Email notification
            if (supporter.alert_via_email) {
                const email = supporterUser?.email || supporter.supporter_email;
                if (email) {
                    try {
                        await (0, resend_js_1.sendAlertEmail)({
                            to: email,
                            checkerName: supporter.supporter_display_name || supporterUser?.name || 'Someone',
                            userName: checker.name,
                            alertLevel: data.type,
                            lastCheckIn: lastCheckIn?.timestamp ? new Date(lastCheckIn.timestamp) : undefined,
                            lastLocation: checker.last_known_address,
                            lastMood,
                        });
                    }
                    catch (e) {
                        console.error('Failed to send alert email:', e);
                    }
                }
            }
            // SMS notification (only for soft, hard, escalation - not reminder)
            if (supporter.alert_via_sms && data.type !== 'reminder') {
                const phone = supporterUser?.phone_number || supporter.supporter_phone;
                if (phone) {
                    try {
                        await (0, twilio_js_1.sendAlertSMS)({
                            to: phone,
                            checkerName: checker.name,
                            level: data.type,
                            address: checker.last_known_address,
                            phone: checker.phone_number,
                            lastCheckInTime: lastCheckIn?.timestamp
                                ? new Date(lastCheckIn.timestamp).toLocaleString()
                                : undefined,
                        });
                    }
                    catch (e) {
                        console.error('Failed to send alert SMS:', e);
                    }
                }
            }
        }
        res.status(201).json({
            success: true,
            alert: {
                id: alert.id,
                type: alert.type,
                triggeredAt: alert.triggered_at,
            },
        });
    }
    catch (error) {
        console.error('Trigger alert error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to trigger alert',
        });
    }
});
exports.default = router;
//# sourceMappingURL=alerts.js.map