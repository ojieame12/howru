"use strict";
/**
 * Upload Routes
 * Handles file uploads for selfies and avatars
 *
 * Two approaches supported:
 * 1. Direct upload: Client sends base64 data, server uploads to R2
 * 2. Pre-signed URL: Server generates URL, client uploads directly to R2
 */
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const auth_js_1 = require("../middleware/auth.js");
const storage_js_1 = require("../services/storage.js");
const index_js_1 = require("../db/index.js");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_js_1.authMiddleware);
// ============================================================================
// GET PRE-SIGNED UPLOAD URL
// Returns a URL for direct client-to-R2 upload
// ============================================================================
const getUploadUrlSchema = zod_1.z.object({
    category: zod_1.z.enum(['selfie', 'avatar']),
    contentType: zod_1.z.string().default('image/jpeg'),
});
router.post('/url', async (req, res) => {
    try {
        if (!(0, storage_js_1.isStorageConfigured)()) {
            return res.status(503).json({
                success: false,
                error: 'Storage service not configured',
            });
        }
        const userId = req.userId;
        const data = getUploadUrlSchema.parse(req.body);
        const category = data.category === 'selfie' ? 'selfies' : 'avatars';
        const result = await (0, storage_js_1.getSignedUploadUrl)(category, userId, data.contentType);
        res.json({
            success: true,
            uploadUrl: result.uploadUrl,
            key: result.key,
            cdnUrl: result.cdnUrl,
            expiresIn: 300, // 5 minutes to complete upload
        });
    }
    catch (error) {
        console.error('Get upload URL error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to generate upload URL',
        });
    }
});
// ============================================================================
// UPLOAD SELFIE (direct)
// Client sends base64 image data
// ============================================================================
const uploadSelfieSchema = zod_1.z.object({
    checkinId: zod_1.z.string().uuid(),
    imageData: zod_1.z.string().min(1), // Base64 encoded image
    contentType: zod_1.z.string().default('image/jpeg'),
});
router.post('/selfie', async (req, res) => {
    try {
        if (!(0, storage_js_1.isStorageConfigured)()) {
            return res.status(503).json({
                success: false,
                error: 'Storage service not configured',
            });
        }
        const userId = req.userId;
        const data = uploadSelfieSchema.parse(req.body);
        // Verify the check-in belongs to this user
        const checkin = (await (0, index_js_1.sql) `
        SELECT id FROM checkins WHERE id = ${data.checkinId} AND user_id = ${userId}
      `)[0];
        if (!checkin) {
            return res.status(404).json({
                success: false,
                error: 'Check-in not found',
            });
        }
        // Decode base64 image
        const imageBuffer = Buffer.from(data.imageData, 'base64');
        // Upload to R2 with 24-hour expiry
        const result = await (0, storage_js_1.uploadSelfie)(userId, data.checkinId, imageBuffer, data.contentType);
        // Update check-in with selfie URL
        await (0, index_js_1.sql) `
      UPDATE checkins
      SET selfie_url = ${result.cdnUrl}, selfie_expires_at = ${result.expiresAt?.toISOString()}
      WHERE id = ${data.checkinId}
    `;
        res.json({
            success: true,
            url: result.cdnUrl,
            expiresAt: result.expiresAt,
        });
    }
    catch (error) {
        console.error('Upload selfie error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to upload selfie',
        });
    }
});
// ============================================================================
// CONFIRM SELFIE UPLOAD (for pre-signed URL flow)
// Called after client uploads directly to R2
// ============================================================================
const confirmSelfieSchema = zod_1.z.object({
    checkinId: zod_1.z.string().uuid(),
    key: zod_1.z.string().min(1),
    cdnUrl: zod_1.z.string().url(),
});
router.post('/selfie/confirm', async (req, res) => {
    try {
        const userId = req.userId;
        const data = confirmSelfieSchema.parse(req.body);
        // Verify the check-in belongs to this user
        const checkin = (await (0, index_js_1.sql) `
        SELECT id FROM checkins WHERE id = ${data.checkinId} AND user_id = ${userId}
      `)[0];
        if (!checkin) {
            return res.status(404).json({
                success: false,
                error: 'Check-in not found',
            });
        }
        // Set expiry for 24 hours
        const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
        // Update check-in with selfie URL
        await (0, index_js_1.sql) `
      UPDATE checkins
      SET selfie_url = ${data.cdnUrl}, selfie_expires_at = ${expiresAt.toISOString()}
      WHERE id = ${data.checkinId}
    `;
        res.json({
            success: true,
            url: data.cdnUrl,
            expiresAt,
        });
    }
    catch (error) {
        console.error('Confirm selfie error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to confirm selfie upload',
        });
    }
});
// ============================================================================
// UPLOAD AVATAR (direct)
// ============================================================================
const uploadAvatarSchema = zod_1.z.object({
    imageData: zod_1.z.string().min(1), // Base64 encoded image
    contentType: zod_1.z.string().default('image/jpeg'),
});
router.post('/avatar', async (req, res) => {
    try {
        if (!(0, storage_js_1.isStorageConfigured)()) {
            return res.status(503).json({
                success: false,
                error: 'Storage service not configured',
            });
        }
        const userId = req.userId;
        const data = uploadAvatarSchema.parse(req.body);
        // Decode base64 image
        const imageBuffer = Buffer.from(data.imageData, 'base64');
        // Delete old avatar if exists
        const user = (await (0, index_js_1.sql) `SELECT profile_image_url FROM users WHERE id = ${userId}`)[0];
        if (user?.profile_image_url) {
            try {
                await (0, storage_js_1.deleteFileByUrl)(user.profile_image_url);
            }
            catch (e) {
                console.error('Failed to delete old avatar:', e);
            }
        }
        // Upload new avatar
        const result = await (0, storage_js_1.uploadAvatar)(userId, imageBuffer, data.contentType);
        // Update user profile
        await (0, index_js_1.sql) `
      UPDATE users SET profile_image_url = ${result.cdnUrl} WHERE id = ${userId}
    `;
        res.json({
            success: true,
            url: result.cdnUrl,
        });
    }
    catch (error) {
        console.error('Upload avatar error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to upload avatar',
        });
    }
});
// ============================================================================
// CONFIRM AVATAR UPLOAD (for pre-signed URL flow)
// ============================================================================
const confirmAvatarSchema = zod_1.z.object({
    key: zod_1.z.string().min(1),
    cdnUrl: zod_1.z.string().url(),
});
router.post('/avatar/confirm', async (req, res) => {
    try {
        const userId = req.userId;
        const data = confirmAvatarSchema.parse(req.body);
        // Delete old avatar if exists
        const user = (await (0, index_js_1.sql) `SELECT profile_image_url FROM users WHERE id = ${userId}`)[0];
        if (user?.profile_image_url) {
            try {
                await (0, storage_js_1.deleteFileByUrl)(user.profile_image_url);
            }
            catch (e) {
                console.error('Failed to delete old avatar:', e);
            }
        }
        // Update user profile
        await (0, index_js_1.sql) `
      UPDATE users SET profile_image_url = ${data.cdnUrl} WHERE id = ${userId}
    `;
        res.json({
            success: true,
            url: data.cdnUrl,
        });
    }
    catch (error) {
        console.error('Confirm avatar error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to confirm avatar upload',
        });
    }
});
// ============================================================================
// DELETE AVATAR
// ============================================================================
router.delete('/avatar', async (req, res) => {
    try {
        const userId = req.userId;
        // Get current avatar
        const user = (await (0, index_js_1.sql) `SELECT profile_image_url FROM users WHERE id = ${userId}`)[0];
        if (user?.profile_image_url) {
            // Delete from storage
            try {
                await (0, storage_js_1.deleteFileByUrl)(user.profile_image_url);
            }
            catch (e) {
                console.error('Failed to delete avatar from storage:', e);
            }
            // Clear URL in database
            await (0, index_js_1.sql) `
        UPDATE users SET profile_image_url = NULL WHERE id = ${userId}
      `;
        }
        res.json({ success: true });
    }
    catch (error) {
        console.error('Delete avatar error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to delete avatar',
        });
    }
});
exports.default = router;
//# sourceMappingURL=uploads.js.map