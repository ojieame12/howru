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
// SEND POKE
// ============================================================================
const sendPokeSchema = zod_1.z.object({
    toUserId: zod_1.z.string().uuid(),
    message: zod_1.z.string().max(500).optional(),
});
router.post('/', async (req, res) => {
    try {
        const userId = req.userId;
        const data = sendPokeSchema.parse(req.body);
        // Verify the sender can poke this user (must be in their circle)
        const supportedUsers = await (0, index_js_1.getSupportedUsers)(userId);
        const canPoke = supportedUsers.some((u) => u.checker_id === data.toUserId && u.can_poke);
        if (!canPoke) {
            return res.status(403).json({
                success: false,
                error: 'You cannot poke this user',
            });
        }
        // Create the poke
        const poke = await (0, index_js_1.createPoke)({
            fromUserId: userId,
            toUserId: data.toUserId,
            message: data.message,
        });
        // Get sender info for notifications
        const sender = await (0, index_js_1.getUserById)(userId);
        const recipient = await (0, index_js_1.getUserById)(data.toUserId);
        // Send notifications (email/SMS based on preferences)
        // Get recipient's circle link to check notification preferences
        const recipientCircle = await (0, index_js_1.getCircleLinks)(data.toUserId);
        const linkToSender = recipientCircle.find((l) => l.supporter_id === userId);
        if (linkToSender && recipient) {
            // Send email notification
            if (linkToSender.alert_via_email && recipient.email) {
                try {
                    await (0, resend_js_1.sendPokeEmail)(recipient.email, recipient.name, sender?.name || 'Someone', data.message);
                }
                catch (e) {
                    console.error('Failed to send poke email:', e);
                }
            }
            // Send SMS notification
            if (linkToSender.alert_via_sms && recipient.phone_number) {
                try {
                    await (0, twilio_js_1.sendPokeSMS)({
                        to: recipient.phone_number,
                        fromName: sender?.name || 'Someone',
                        message: data.message,
                    });
                }
                catch (e) {
                    console.error('Failed to send poke SMS:', e);
                }
            }
        }
        res.status(201).json({
            success: true,
            poke: {
                id: poke.id,
                toUserId: poke.to_user_id,
                message: poke.message,
                sentAt: poke.sent_at,
            },
        });
    }
    catch (error) {
        console.error('Send poke error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to send poke',
        });
    }
});
// ============================================================================
// GET MY POKES (received)
// ============================================================================
router.get('/', async (req, res) => {
    try {
        const userId = req.userId;
        const limit = Math.min(parseInt(req.query.limit) || 20, 50);
        const pokes = await (0, index_js_1.getPokesForUser)(userId, limit);
        res.json({
            success: true,
            pokes: pokes.map((p) => ({
                id: p.id,
                fromUserId: p.from_user_id,
                fromName: p.from_name,
                message: p.message,
                sentAt: p.sent_at,
                seenAt: p.seen_at,
                respondedAt: p.responded_at,
            })),
        });
    }
    catch (error) {
        console.error('Get pokes error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get pokes',
        });
    }
});
// ============================================================================
// GET UNSEEN POKES COUNT
// ============================================================================
router.get('/unseen/count', async (req, res) => {
    try {
        const userId = req.userId;
        const count = await (0, index_js_1.getUnseenPokesCount)(userId);
        res.json({
            success: true,
            count,
        });
    }
    catch (error) {
        console.error('Get unseen count error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get unseen count',
        });
    }
});
// ============================================================================
// MARK POKE AS SEEN
// ============================================================================
router.post('/:pokeId/seen', async (req, res) => {
    try {
        const userId = req.userId;
        const { pokeId } = req.params;
        await (0, index_js_1.markPokeSeen)(pokeId, userId);
        res.json({ success: true });
    }
    catch (error) {
        console.error('Mark seen error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to mark as seen',
        });
    }
});
// ============================================================================
// MARK POKE AS RESPONDED (e.g., user checked in after poke)
// ============================================================================
router.post('/:pokeId/responded', async (req, res) => {
    try {
        const userId = req.userId;
        const { pokeId } = req.params;
        await (0, index_js_1.markPokeResponded)(pokeId, userId);
        res.json({ success: true });
    }
    catch (error) {
        console.error('Mark responded error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to mark as responded',
        });
    }
});
// ============================================================================
// MARK ALL POKES AS SEEN
// ============================================================================
router.post('/seen/all', async (req, res) => {
    try {
        const userId = req.userId;
        const pokes = await (0, index_js_1.getPokesForUser)(userId, 100);
        for (const poke of pokes) {
            if (!poke.seen_at) {
                await (0, index_js_1.markPokeSeen)(poke.id, userId);
            }
        }
        res.json({ success: true });
    }
    catch (error) {
        console.error('Mark all seen error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to mark all as seen',
        });
    }
});
exports.default = router;
//# sourceMappingURL=pokes.js.map