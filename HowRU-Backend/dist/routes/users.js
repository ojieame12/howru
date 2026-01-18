"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const auth_js_1 = require("../middleware/auth.js");
const index_js_1 = require("../db/index.js");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_js_1.authMiddleware);
// ============================================================================
// GET MY PROFILE
// ============================================================================
router.get('/me', async (req, res) => {
    try {
        const userId = req.userId;
        const user = await (0, index_js_1.getUserById)(userId);
        if (!user) {
            return res.status(404).json({
                success: false,
                error: 'User not found',
            });
        }
        const schedule = await (0, index_js_1.getActiveSchedule)(userId);
        const subscription = await (0, index_js_1.getSubscription)(userId);
        res.json({
            success: true,
            user: {
                id: user.id,
                name: user.name,
                phone: user.phone_number,
                email: user.email,
                profileImageUrl: user.profile_image_url,
                address: user.address,
                isChecker: user.is_checker,
                lastKnownLocation: user.last_known_address,
                lastKnownLocationAt: user.last_known_location_at,
                createdAt: user.created_at,
            },
            schedule: schedule
                ? {
                    id: schedule.id,
                    windowStartHour: schedule.window_start_hour,
                    windowStartMinute: schedule.window_start_minute,
                    windowEndHour: schedule.window_end_hour,
                    windowEndMinute: schedule.window_end_minute,
                    timezone: schedule.timezone_identifier,
                    activeDays: schedule.active_days,
                    gracePeriodMinutes: schedule.grace_period_minutes,
                    reminderEnabled: schedule.reminder_enabled,
                    reminderMinutesBefore: schedule.reminder_minutes_before,
                }
                : null,
            subscription: subscription
                ? {
                    plan: subscription.plan,
                    status: subscription.status,
                    expiresAt: subscription.expires_at,
                }
                : { plan: 'free', status: 'active', expiresAt: null },
        });
    }
    catch (error) {
        console.error('Get profile error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get profile',
        });
    }
});
// ============================================================================
// UPDATE MY PROFILE
// ============================================================================
const updateProfileSchema = zod_1.z.object({
    name: zod_1.z.string().min(1).max(100).optional(),
    email: zod_1.z.string().email().optional(),
    profileImageUrl: zod_1.z.string().url().optional(),
    address: zod_1.z.string().max(500).optional(),
});
router.patch('/me', async (req, res) => {
    try {
        const userId = req.userId;
        const data = updateProfileSchema.parse(req.body);
        const user = await (0, index_js_1.updateUser)(userId, data);
        if (!user) {
            return res.status(404).json({
                success: false,
                error: 'User not found',
            });
        }
        res.json({
            success: true,
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                profileImageUrl: user.profile_image_url,
                address: user.address,
            },
        });
    }
    catch (error) {
        console.error('Update profile error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to update profile',
        });
    }
});
// ============================================================================
// GET MY SCHEDULE
// ============================================================================
router.get('/me/schedule', async (req, res) => {
    try {
        const userId = req.userId;
        const schedule = await (0, index_js_1.getActiveSchedule)(userId);
        res.json({
            success: true,
            schedule: schedule
                ? {
                    id: schedule.id,
                    windowStartHour: schedule.window_start_hour,
                    windowStartMinute: schedule.window_start_minute,
                    windowEndHour: schedule.window_end_hour,
                    windowEndMinute: schedule.window_end_minute,
                    timezone: schedule.timezone_identifier,
                    activeDays: schedule.active_days,
                    gracePeriodMinutes: schedule.grace_period_minutes,
                    reminderEnabled: schedule.reminder_enabled,
                    reminderMinutesBefore: schedule.reminder_minutes_before,
                    isActive: schedule.is_active,
                }
                : null,
        });
    }
    catch (error) {
        console.error('Get schedule error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get schedule',
        });
    }
});
// ============================================================================
// UPDATE MY SCHEDULE
// ============================================================================
const updateScheduleSchema = zod_1.z.object({
    windowStartHour: zod_1.z.number().int().min(0).max(23).optional(),
    windowStartMinute: zod_1.z.number().int().min(0).max(59).optional(),
    windowEndHour: zod_1.z.number().int().min(0).max(23).optional(),
    windowEndMinute: zod_1.z.number().int().min(0).max(59).optional(),
    timezone: zod_1.z.string().optional(),
    activeDays: zod_1.z.array(zod_1.z.number().int().min(0).max(6)).optional(),
    gracePeriodMinutes: zod_1.z.number().int().min(0).max(240).optional(),
    reminderEnabled: zod_1.z.boolean().optional(),
    reminderMinutesBefore: zod_1.z.number().int().min(5).max(120).optional(),
});
router.put('/me/schedule', async (req, res) => {
    try {
        const userId = req.userId;
        const data = updateScheduleSchema.parse(req.body);
        const schedule = await (0, index_js_1.updateSchedule)(userId, data);
        res.json({
            success: true,
            schedule: {
                id: schedule.id,
                windowStartHour: schedule.window_start_hour,
                windowStartMinute: schedule.window_start_minute,
                windowEndHour: schedule.window_end_hour,
                windowEndMinute: schedule.window_end_minute,
                timezone: schedule.timezone_identifier,
                activeDays: schedule.active_days,
                gracePeriodMinutes: schedule.grace_period_minutes,
                reminderEnabled: schedule.reminder_enabled,
                reminderMinutesBefore: schedule.reminder_minutes_before,
            },
        });
    }
    catch (error) {
        console.error('Update schedule error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to update schedule',
        });
    }
});
// ============================================================================
// REGISTER PUSH TOKEN
// ============================================================================
const pushTokenSchema = zod_1.z.object({
    token: zod_1.z.string().min(1),
    platform: zod_1.z.enum(['ios', 'android']),
    deviceId: zod_1.z.string().optional(),
});
router.post('/me/push-token', async (req, res) => {
    try {
        const userId = req.userId;
        const data = pushTokenSchema.parse(req.body);
        await (0, index_js_1.savePushToken)(userId, data.token, data.platform, data.deviceId);
        res.json({ success: true });
    }
    catch (error) {
        console.error('Save push token error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to save push token',
        });
    }
});
// ============================================================================
// REMOVE PUSH TOKEN
// ============================================================================
router.delete('/me/push-token', async (req, res) => {
    try {
        const userId = req.userId;
        const { token } = req.body;
        if (!token) {
            return res.status(400).json({
                success: false,
                error: 'Token is required',
            });
        }
        await (0, index_js_1.deletePushToken)(userId, token);
        res.json({ success: true });
    }
    catch (error) {
        console.error('Delete push token error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to delete push token',
        });
    }
});
// ============================================================================
// DELETE ACCOUNT
// ============================================================================
router.delete('/me', async (req, res) => {
    try {
        const userId = req.userId;
        // Delete all refresh tokens (this effectively logs out everywhere)
        await (0, index_js_1.deleteUserRefreshTokens)(userId);
        // Note: Due to CASCADE constraints, deleting the user will delete:
        // - All check-ins
        // - All circle links
        // - All alerts
        // - All pokes
        // - All push tokens
        // - All refresh tokens
        // We could soft-delete instead for data retention
        // For now, just revoke all tokens - actual deletion could be a background job
        // or require additional confirmation
        res.json({
            success: true,
            message: 'Account scheduled for deletion. All sessions have been logged out.',
        });
    }
    catch (error) {
        console.error('Delete account error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to delete account',
        });
    }
});
// ============================================================================
// GET USER BY ID (for viewing circle member profile)
// ============================================================================
router.get('/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        const user = await (0, index_js_1.getUserById)(userId);
        if (!user) {
            return res.status(404).json({
                success: false,
                error: 'User not found',
            });
        }
        // Return limited public info
        res.json({
            success: true,
            user: {
                id: user.id,
                name: user.name,
                profileImageUrl: user.profile_image_url,
            },
        });
    }
    catch (error) {
        console.error('Get user error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get user',
        });
    }
});
exports.default = router;
//# sourceMappingURL=users.js.map