/**
 * Data Export Routes
 * Allows users to export their data for GDPR compliance
 *
 * Features:
 * - Async export generation (queued for large datasets)
 * - JSON and CSV formats
 * - Includes all user data: check-ins, circle, pokes, alerts
 */

import { Router, Response } from 'express';
import { z } from 'zod';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';
import { sql, getUserById, getRecentCheckIns, getCircleLinks } from '../db/index.js';
import { uploadFile, getSignedDownloadUrl } from '../services/storage.js';
import { sendExportReadyEmail } from '../services/resend.js';

const router = Router();

// All routes require authentication
router.use(authMiddleware);

// ============================================================================
// REQUEST DATA EXPORT
// Queues an export job for async processing
// ============================================================================

const requestExportSchema = z.object({
  format: z.enum(['json', 'csv']).default('json'),
});

router.post('/', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const data = requestExportSchema.parse(req.body);

    // Check for existing pending export
    const existingExport = (
      await sql`
        SELECT id, status FROM data_exports
        WHERE user_id = ${userId} AND status IN ('queued', 'processing')
        ORDER BY created_at DESC
        LIMIT 1
      `
    )[0];

    if (existingExport) {
      return res.status(409).json({
        success: false,
        error: 'Export already in progress',
        exportId: existingExport.id,
      });
    }

    // Create export record
    const exportRecord = (
      await sql`
        INSERT INTO data_exports (user_id, format, status)
        VALUES (${userId}, ${data.format}, 'queued')
        RETURNING *
      `
    )[0];

    // For small datasets, process immediately
    // For large datasets, this would be handled by a worker
    processExportAsync(exportRecord.id, userId, data.format);

    res.status(202).json({
      success: true,
      exportId: exportRecord.id,
      status: 'queued',
      message: 'Export queued. You will be notified when ready.',
    });
  } catch (error: any) {
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

router.get('/:exportId', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;
    const { exportId } = req.params;

    const exportRecord = (
      await sql`
        SELECT * FROM data_exports
        WHERE id = ${exportId} AND user_id = ${userId}
      `
    )[0];

    if (!exportRecord) {
      return res.status(404).json({
        success: false,
        error: 'Export not found',
      });
    }

    // Generate signed download URL if ready
    let downloadUrl: string | undefined;
    if (exportRecord.status === 'ready' && exportRecord.file_url) {
      const key = exportRecord.file_url.split('/').slice(-3).join('/');
      downloadUrl = await getSignedDownloadUrl(key, 3600); // 1 hour validity
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
  } catch (error: any) {
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

router.get('/', async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId!;

    const exports = await sql`
      SELECT id, status, format, created_at, completed_at, file_size_bytes
      FROM data_exports
      WHERE user_id = ${userId}
      ORDER BY created_at DESC
      LIMIT 10
    `;

    res.json({
      success: true,
      exports: exports.map((e: any) => ({
        id: e.id,
        status: e.status,
        format: e.format,
        createdAt: e.created_at,
        completedAt: e.completed_at,
        fileSizeBytes: e.file_size_bytes,
      })),
    });
  } catch (error: any) {
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

async function processExportAsync(
  exportId: string,
  userId: string,
  format: 'json' | 'csv'
) {
  try {
    // Update status to processing
    await sql`
      UPDATE data_exports SET status = 'processing' WHERE id = ${exportId}
    `;

    // Gather all user data
    const user = await getUserById(userId);
    const checkIns = await getRecentCheckIns(userId, 10000); // Get all
    const circle = await getCircleLinks(userId);

    const pokes = await sql`
      SELECT * FROM pokes
      WHERE from_user_id = ${userId} OR to_user_id = ${userId}
      ORDER BY sent_at DESC
    `;

    const alerts = await sql`
      SELECT * FROM alerts
      WHERE checker_id = ${userId}
      ORDER BY triggered_at DESC
    `;

    const schedules = await sql`
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
      schedules: schedules.map((s: any) => ({
        windowStartHour: s.window_start_hour,
        windowEndHour: s.window_end_hour,
        timezone: s.timezone_identifier,
        activeDays: s.active_days,
        gracePeriodMinutes: s.grace_period_minutes,
      })),
      checkIns: checkIns.map((c: any) => ({
        timestamp: c.timestamp,
        mentalScore: c.mental_score,
        bodyScore: c.body_score,
        moodScore: c.mood_score,
        locationName: c.location_name,
      })),
      circle: circle.map((c: any) => ({
        supporterName: c.supporter_display_name || c.supporter_name,
        addedAt: c.invited_at,
        permissions: {
          canSeeMood: c.can_see_mood,
          canSeeLocation: c.can_see_location,
          canPoke: c.can_poke,
        },
      })),
      pokes: pokes.map((p: any) => ({
        direction: p.from_user_id === userId ? 'sent' : 'received',
        message: p.message,
        sentAt: p.sent_at,
      })),
      alerts: alerts.map((a: any) => ({
        type: a.type,
        status: a.status,
        triggeredAt: a.triggered_at,
        resolvedAt: a.resolved_at,
        resolution: a.resolution,
      })),
    };

    // Convert to requested format
    let fileContent: string;
    let contentType: string;
    let extension: string;

    if (format === 'json') {
      fileContent = JSON.stringify(exportData, null, 2);
      contentType = 'application/json';
      extension = 'json';
    } else {
      // CSV format - flatten check-ins as main data
      const headers = ['timestamp', 'mental_score', 'body_score', 'mood_score', 'location'];
      const rows = checkIns.map((c: any) =>
        [c.timestamp, c.mental_score, c.body_score, c.mood_score, c.location_name || ''].join(',')
      );
      fileContent = [headers.join(','), ...rows].join('\n');
      contentType = 'text/csv';
      extension = 'csv';
    }

    // Upload to R2
    const fileBuffer = Buffer.from(fileContent, 'utf8');
    const result = await uploadFile('exports', userId, fileBuffer, contentType);

    // Update export record
    await sql`
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
        await sendExportReadyEmail({
          to: user.email,
          userName: user.name,
          exportId,
          format,
        });
      } catch (e) {
        console.error('Failed to send export notification email:', e);
      }
    }

    console.log(`[export] Completed export ${exportId} for user ${userId}`);
  } catch (error) {
    console.error(`[export] Failed export ${exportId}:`, error);

    // Update status to failed
    await sql`
      UPDATE data_exports SET status = 'failed' WHERE id = ${exportId}
    `;
  }
}

export default router;
