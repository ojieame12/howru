"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const crypto_1 = __importDefault(require("crypto"));
const auth_js_1 = require("../middleware/auth.js");
const index_js_1 = require("../db/index.js");
const resend_js_1 = require("../services/resend.js");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_js_1.authMiddleware);
// ============================================================================
// GET MY CIRCLE (people I'm checking on me)
// ============================================================================
router.get('/', async (req, res) => {
    try {
        const userId = req.userId;
        const supporters = await (0, index_js_1.getCircleLinks)(userId);
        res.json({
            success: true,
            circle: supporters.map((s) => ({
                id: s.id,
                supporterId: s.supporter_id,
                name: s.supporter_display_name || s.supporter_name,
                phone: s.supporter_phone,
                email: s.supporter_email,
                isAppUser: !!s.supporter_id,
                permissions: {
                    canSeeMood: s.can_see_mood,
                    canSeeLocation: s.can_see_location,
                    canSeeSelfie: s.can_see_selfie,
                    canPoke: s.can_poke,
                },
                alertPriority: s.alert_priority,
                alertPreferences: {
                    push: s.alert_via_push,
                    sms: s.alert_via_sms,
                    email: s.alert_via_email,
                },
                invitedAt: s.invited_at,
                acceptedAt: s.accepted_at,
            })),
        });
    }
    catch (error) {
        console.error('Get circle error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get circle',
        });
    }
});
// ============================================================================
// GET PEOPLE I'M SUPPORTING (checking on)
// ============================================================================
router.get('/supporting', async (req, res) => {
    try {
        const userId = req.userId;
        const checkers = await (0, index_js_1.getSupportedUsers)(userId);
        res.json({
            success: true,
            supporting: checkers.map((c) => ({
                id: c.id,
                checkerId: c.checker_id,
                name: c.checker_name,
                phone: c.checker_phone,
                lastKnownLocation: c.last_known_address,
                lastLocationAt: c.last_known_location_at,
                permissions: {
                    canSeeMood: c.can_see_mood,
                    canSeeLocation: c.can_see_location,
                    canSeeSelfie: c.can_see_selfie,
                    canPoke: c.can_poke,
                },
            })),
        });
    }
    catch (error) {
        console.error('Get supporting error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get supported users',
        });
    }
});
// ============================================================================
// ADD MEMBER TO CIRCLE (directly, for non-app users)
// ============================================================================
const addMemberSchema = zod_1.z.object({
    name: zod_1.z.string().min(1).max(100),
    phone: zod_1.z.string().min(10).max(20).optional(),
    email: zod_1.z.string().email().optional(),
    canSeeMood: zod_1.z.boolean().default(true),
    canSeeLocation: zod_1.z.boolean().default(false),
    canSeeSelfie: zod_1.z.boolean().default(false),
    canPoke: zod_1.z.boolean().default(true),
    alertPriority: zod_1.z.number().int().min(1).max(10).default(1),
    alertViaSms: zod_1.z.boolean().default(false),
    alertViaEmail: zod_1.z.boolean().default(false),
});
router.post('/members', async (req, res) => {
    try {
        const userId = req.userId;
        const data = addMemberSchema.parse(req.body);
        // Check if this phone/email belongs to an existing user
        let supporterId;
        if (data.phone) {
            const existingUser = await (0, index_js_1.getUserByPhone)(data.phone);
            if (existingUser) {
                supporterId = existingUser.id;
            }
        }
        const link = await (0, index_js_1.createCircleLink)({
            checkerId: userId,
            supporterId,
            supporterDisplayName: data.name,
            supporterPhone: data.phone,
            supporterEmail: data.email,
            canSeeMood: data.canSeeMood,
            canSeeLocation: data.canSeeLocation,
            canSeeSelfie: data.canSeeSelfie,
            canPoke: data.canPoke,
            alertPriority: data.alertPriority,
            alertViaSms: data.alertViaSms,
            alertViaEmail: data.alertViaEmail,
        });
        res.status(201).json({
            success: true,
            member: {
                id: link.id,
                name: data.name,
                phone: data.phone,
                email: data.email,
                isAppUser: !!supporterId,
            },
        });
    }
    catch (error) {
        console.error('Add member error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to add member',
        });
    }
});
// ============================================================================
// UPDATE CIRCLE MEMBER
// ============================================================================
const updateMemberSchema = zod_1.z.object({
    name: zod_1.z.string().min(1).max(100).optional(),
    canSeeMood: zod_1.z.boolean().optional(),
    canSeeLocation: zod_1.z.boolean().optional(),
    canSeeSelfie: zod_1.z.boolean().optional(),
    canPoke: zod_1.z.boolean().optional(),
    alertPriority: zod_1.z.number().int().min(1).max(10).optional(),
    alertViaPush: zod_1.z.boolean().optional(),
    alertViaSms: zod_1.z.boolean().optional(),
    alertViaEmail: zod_1.z.boolean().optional(),
});
router.patch('/members/:memberId', async (req, res) => {
    try {
        const userId = req.userId;
        const { memberId } = req.params;
        const data = updateMemberSchema.parse(req.body);
        const updated = await (0, index_js_1.updateCircleLink)(memberId, userId, {
            supporterDisplayName: data.name,
            canSeeMood: data.canSeeMood,
            canSeeLocation: data.canSeeLocation,
            canSeeSelfie: data.canSeeSelfie,
            canPoke: data.canPoke,
            alertPriority: data.alertPriority,
            alertViaPush: data.alertViaPush,
            alertViaSms: data.alertViaSms,
            alertViaEmail: data.alertViaEmail,
        });
        if (!updated) {
            return res.status(404).json({
                success: false,
                error: 'Member not found',
            });
        }
        res.json({
            success: true,
            member: {
                id: updated.id,
                name: updated.supporter_display_name,
            },
        });
    }
    catch (error) {
        console.error('Update member error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to update member',
        });
    }
});
// ============================================================================
// REMOVE CIRCLE MEMBER
// ============================================================================
router.delete('/members/:memberId', async (req, res) => {
    try {
        const userId = req.userId;
        const { memberId } = req.params;
        await (0, index_js_1.removeCircleLink)(memberId, userId);
        res.json({ success: true });
    }
    catch (error) {
        console.error('Remove member error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to remove member',
        });
    }
});
// ============================================================================
// CREATE INVITE LINK
// ============================================================================
const createInviteSchema = zod_1.z.object({
    role: zod_1.z.enum(['checker', 'supporter']),
    canSeeMood: zod_1.z.boolean().default(true),
    canSeeLocation: zod_1.z.boolean().default(false),
    canSeeSelfie: zod_1.z.boolean().default(false),
    canPoke: zod_1.z.boolean().default(true),
    expiresInHours: zod_1.z.number().int().min(1).max(168).default(48), // 1 hour to 7 days
});
router.post('/invites', async (req, res) => {
    try {
        const userId = req.userId;
        const data = createInviteSchema.parse(req.body);
        // Generate unique invite code
        const code = crypto_1.default.randomBytes(4).toString('hex').toUpperCase();
        const expiresAt = new Date(Date.now() + data.expiresInHours * 60 * 60 * 1000);
        const invite = await (0, index_js_1.createInvite)({
            inviterId: userId,
            code,
            role: data.role,
            canSeeMood: data.canSeeMood,
            canSeeLocation: data.canSeeLocation,
            canSeeSelfie: data.canSeeSelfie,
            canPoke: data.canPoke,
            expiresAt,
        });
        res.status(201).json({
            success: true,
            invite: {
                id: invite.id,
                code: invite.code,
                role: invite.role,
                expiresAt: invite.expires_at,
                link: `https://howru.app/invite?code=${code}`,
            },
        });
    }
    catch (error) {
        console.error('Create invite error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to create invite',
        });
    }
});
// ============================================================================
// SEND INVITE VIA EMAIL
// ============================================================================
const sendInviteSchema = zod_1.z.object({
    email: zod_1.z.string().email(),
    role: zod_1.z.enum(['checker', 'supporter']),
    canSeeMood: zod_1.z.boolean().default(true),
    canSeeLocation: zod_1.z.boolean().default(false),
    canSeeSelfie: zod_1.z.boolean().default(false),
    canPoke: zod_1.z.boolean().default(true),
});
router.post('/invites/send', async (req, res) => {
    try {
        const userId = req.userId;
        const data = sendInviteSchema.parse(req.body);
        const user = await (0, index_js_1.getUserById)(userId);
        if (!user) {
            return res.status(404).json({
                success: false,
                error: 'User not found',
            });
        }
        // Generate invite
        const code = crypto_1.default.randomBytes(4).toString('hex').toUpperCase();
        const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days
        const invite = await (0, index_js_1.createInvite)({
            inviterId: userId,
            code,
            role: data.role,
            canSeeMood: data.canSeeMood,
            canSeeLocation: data.canSeeLocation,
            canSeeSelfie: data.canSeeSelfie,
            canPoke: data.canPoke,
            expiresAt,
        });
        // Send email
        await (0, resend_js_1.sendCircleInviteEmail)(data.email, user.name, data.role, code);
        res.status(201).json({
            success: true,
            invite: {
                id: invite.id,
                code: invite.code,
                sentTo: data.email,
            },
        });
    }
    catch (error) {
        console.error('Send invite error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to send invite',
        });
    }
});
// ============================================================================
// GET INVITE DETAILS (public-ish, for invite preview)
// ============================================================================
router.get('/invites/:code', async (req, res) => {
    try {
        const { code } = req.params;
        const invite = await (0, index_js_1.getInviteByCode)(code);
        if (!invite) {
            return res.status(404).json({
                success: false,
                error: 'Invite not found or expired',
            });
        }
        res.json({
            success: true,
            invite: {
                inviterName: invite.inviter_name,
                role: invite.role,
                expiresAt: invite.expires_at,
                permissions: {
                    canSeeMood: invite.can_see_mood,
                    canSeeLocation: invite.can_see_location,
                    canSeeSelfie: invite.can_see_selfie,
                    canPoke: invite.can_poke,
                },
            },
        });
    }
    catch (error) {
        console.error('Get invite error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get invite',
        });
    }
});
// ============================================================================
// ACCEPT INVITE
// ============================================================================
router.post('/invites/:code/accept', async (req, res) => {
    try {
        const userId = req.userId;
        const { code } = req.params;
        const invite = await (0, index_js_1.getInviteByCode)(code);
        if (!invite) {
            return res.status(404).json({
                success: false,
                error: 'Invite not found or expired',
            });
        }
        // Accept the invite
        await (0, index_js_1.acceptInvite)(code, userId);
        // Create the circle link
        if (invite.role === 'supporter') {
            // Inviter wants this user to be their supporter
            await (0, index_js_1.createCircleLink)({
                checkerId: invite.inviter_id,
                supporterId: userId,
                supporterDisplayName: (await (0, index_js_1.getUserById)(userId))?.name || 'Unknown',
                canSeeMood: invite.can_see_mood,
                canSeeLocation: invite.can_see_location,
                canSeeSelfie: invite.can_see_selfie,
                canPoke: invite.can_poke,
            });
        }
        else {
            // Inviter wants to be this user's supporter (checker role)
            await (0, index_js_1.createCircleLink)({
                checkerId: userId,
                supporterId: invite.inviter_id,
                supporterDisplayName: invite.inviter_name,
                canSeeMood: invite.can_see_mood,
                canSeeLocation: invite.can_see_location,
                canSeeSelfie: invite.can_see_selfie,
                canPoke: invite.can_poke,
            });
        }
        res.json({
            success: true,
            message: 'Invite accepted',
            role: invite.role,
            inviterName: invite.inviter_name,
        });
    }
    catch (error) {
        console.error('Accept invite error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to accept invite',
        });
    }
});
// ============================================================================
// GET MY SENT INVITES
// ============================================================================
router.get('/invites', async (req, res) => {
    try {
        const userId = req.userId;
        const invites = await (0, index_js_1.getInvitesByUser)(userId);
        res.json({
            success: true,
            invites: invites.map((i) => ({
                id: i.id,
                code: i.code,
                role: i.role,
                expiresAt: i.expires_at,
                acceptedAt: i.accepted_at,
                createdAt: i.created_at,
            })),
        });
    }
    catch (error) {
        console.error('Get invites error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get invites',
        });
    }
});
exports.default = router;
//# sourceMappingURL=circle.js.map