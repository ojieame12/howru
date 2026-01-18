"use strict";
/**
 * Data Export Routes
 * Allows users to export their data for GDPR compliance
 *
 * Features:
 * - Async export generation (queued for large datasets)
 * - JSON and CSV formats
 * - Includes all user data: check-ins, circle, pokes, alerts
 */
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const auth_js_1 = require("../middleware/auth.js");
const index_js_1 = require("../db/index.js");
const storage_js_1 = require("../services/storage.js");
const resend_js_1 = require("../services/resend.js");
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_js_1.authMiddleware);
// ============================================================================
// REQUEST DATA EXPORT
// Queues an export job for async processing
// ============================================================================
const requestExportSchema = zod_1.z.object({
    format: zod_1.z.enum(['json', 'csv']).default('json'),
});
router.post('/', async (req, res) => {
    try {
        const userId = req.userId;
        const data = requestExportSchema.parse(req.body);
        // Check for existing pending export
        const existingExport = (await (0, index_js_1.sql) `
        SELECT id, status FROM data_exports
        WHERE user_id = ${userId} AND status IN ('queued', 'processing')
        ORDER BY created_at DESC
        LIMIT 1
      `)[0];
        if (existingExport) {
            return res.status(409).json({
                success: false,
                error: 'Export already in progress',
                exportId: existingExport.id,
            });
        }
        // Create export record
        const exportRecord = (await (0, index_js_1.sql) `
        INSERT INTO data_exports (user_id, format, status)
        VALUES (${userId}, ${data.format}, 'queued')
        RETURNING *
      `)[0];
        // For small datasets, process immediately
        // For large datasets, this would be handled by a worker
        processExportAsync(exportRecord.id, userId, data.format);
        res.status(202).json({
            success: true,
            exportId: exportRecord.id,
            status: 'queued',
            message: 'Export queued. You will be notified when ready.',
        });
    }
    catch (error) {
        console.error('Request export error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to request export',
        });
    }
});
// ============================================================================
// GET EXPORT STATUS
// ============================================================================
router.get('/:exportId', async (req, res) => {
    try {
        const userId = req.userId;
        const { exportId } = req.params;
        const exportRecord = (await (0, index_js_1.sql) `
        SELECT * FROM data_exports
        WHERE id = ${exportId} AND user_id = ${userId}
      `)[0];
        if (!exportRecord) {
            return res.status(404).json({
                success: false,
                error: 'Export not found',
            });
        }
        // Generate signed download URL if ready
        let downloadUrl;
        if (exportRecord.status === 'ready' && exportRecord.file_url) {
            const key = exportRecord.file_url.split('/').slice(-3).join('/');
            downloadUrl = await (0, storage_js_1.getSignedDownloadUrl)(key, 3600); // 1 hour validity
        }
        res.json({
            success: true,
            export: {
                id: exportRecord.id,
                status: exportRecord.status,
                format: exportRecord.format,
                createdAt: exportRecord.created_at,
                completedAt: exportRecord.completed_at,
                downloadUrl,
                fileSizeBytes: exportRecord.file_size_bytes,
            },
        });
    }
    catch (error) {
        console.error('Get export error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to get export status',
        });
    }
});
// ============================================================================
// LIST USER EXPORTS
// ============================================================================
router.get('/', async (req, res) => {
    try {
        const userId = req.userId;
        const exports = await (0, index_js_1.sql) `
      SELECT id, status, format, created_at, completed_at, file_size_bytes
      FROM data_exports
      WHERE user_id = ${userId}
      ORDER BY created_at DESC
      LIMIT 10
    `;
        res.json({
            success: true,
            exports: exports.map((e) => ({
                id: e.id,
                status: e.status,
                format: e.format,
                createdAt: e.created_at,
                completedAt: e.completed_at,
                fileSizeBytes: e.file_size_bytes,
            })),
        });
    }
    catch (error) {
        console.error('List exports error:', error);
        res.status(400).json({
            success: false,
            error: error.message || 'Failed to list exports',
        });
    }
});
// ============================================================================
// ASYNC EXPORT PROCESSOR
// ============================================================================
async function processExportAsync(exportId, userId, format) {
    try {
        // Update status to processing
        await (0, index_js_1.sql) `
      UPDATE data_exports SET status = 'processing' WHERE id = ${exportId}
    `;
        // Gather all user data
        const user = await (0, index_js_1.getUserById)(userId);
        const checkIns = await (0, index_js_1.getRecentCheckIns)(userId, 10000); // Get all
        const circle = await (0, index_js_1.getCircleLinks)(userId);
        const pokes = await (0, index_js_1.sql) `
      SELECT * FROM pokes
      WHERE from_user_id = ${userId} OR to_user_id = ${userId}
      ORDER BY sent_at DESC
    `;
        const alerts = await (0, index_js_1.sql) `
      SELECT * FROM alerts
      WHERE checker_id = ${userId}
      ORDER BY triggered_at DESC
    `;
        const schedules = await (0, index_js_1.sql) `
      SELECT * FROM schedules WHERE user_id = ${userId}
    `;
        // Build export data
        const exportData = {
            exportedAt: new Date().toISOString(),
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                phoneNumber: user.phone_number,
                address: user.address,
                createdAt: user.created_at,
            },
            schedules: schedules.map((s) => ({
                windowStartHour: s.window_start_hour,
                windowEndHour: s.window_end_hour,
                timezone: s.timezone_identifier,
                activeDays: s.active_days,
                gracePeriodMinutes: s.grace_period_minutes,
            })),
            checkIns: checkIns.map((c) => ({
                timestamp: c.timestamp,
                mentalScore: c.mental_score,
                bodyScore: c.body_score,
                moodScore: c.mood_score,
                locationName: c.location_name,
            })),
            circle: circle.map((c) => ({
                supporterName: c.supporter_display_name || c.supporter_name,
                addedAt: c.invited_at,
                permissions: {
                    canSeeMood: c.can_see_mood,
                    canSeeLocation: c.can_see_location,
                    canPoke: c.can_poke,
                },
            })),
            pokes: pokes.map((p) => ({
                direction: p.from_user_id === userId ? 'sent' : 'received',
                message: p.message,
                sentAt: p.sent_at,
            })),
            alerts: alerts.map((a) => ({
                type: a.type,
                status: a.status,
                triggeredAt: a.triggered_at,
                resolvedAt: a.resolved_at,
                resolution: a.resolution,
            })),
        };
        // Convert to requested format
        let fileContent;
        let contentType;
        let extension;
        if (format === 'json') {
            fileContent = JSON.stringify(exportData, null, 2);
            contentType = 'application/json';
            extension = 'json';
        }
        else {
            // CSV format - flatten check-ins as main data
            const headers = ['timestamp', 'mental_score', 'body_score', 'mood_score', 'location'];
            const rows = checkIns.map((c) => [c.timestamp, c.mental_score, c.body_score, c.mood_score, c.location_name || ''].join(','));
            fileContent = [headers.join(','), ...rows].join('\n');
            contentType = 'text/csv';
            extension = 'csv';
        }
        // Upload to R2
        const fileBuffer = Buffer.from(fileContent, 'utf8');
        const result = await (0, storage_js_1.uploadFile)('exports', userId, fileBuffer, contentType);
        // Update export record
        await (0, index_js_1.sql) `
      UPDATE data_exports
      SET
        status = 'ready',
        file_url = ${result.cdnUrl},
        file_size_bytes = ${fileBuffer.length},
        completed_at = NOW()
      WHERE id = ${exportId}
    `;
        // Send notification email
        if (user.email) {
            try {
                await (0, resend_js_1.sendExportReadyEmail)({
                    to: user.email,
                    userName: user.name,
                    exportId,
                    format,
                });
            }
            catch (e) {
                console.error('Failed to send export notification email:', e);
            }
        }
        console.log(`[export] Completed export ${exportId} for user ${userId}`);
    }
    catch (error) {
        console.error(`[export] Failed export ${exportId}:`, error);
        // Update status to failed
        await (0, index_js_1.sql) `
      UPDATE data_exports SET status = 'failed' WHERE id = ${exportId}
    `;
    }
}
exports.default = router;
//# sourceMappingURL=exports.js.map