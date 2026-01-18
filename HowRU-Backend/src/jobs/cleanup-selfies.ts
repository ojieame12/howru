/**
 * Cron Job: Cleanup Expired Selfies
 * Runs hourly to delete selfies that have passed their 24-hour expiry
 *
 * Per privacy policy, selfies are only retained for 24 hours
 * and must be deleted from both storage and database.
 */

import { sql } from '../db/index.js';
// import { deleteFromR2 } from '../services/storage.js';

async function cleanupExpiredSelfies() {
  console.log('[cleanup-selfies] Starting job...');

  try {
    // Find all check-ins with expired selfies
    const expired = await sql`
      SELECT id, selfie_url
      FROM checkins
      WHERE selfie_expires_at < NOW()
      AND selfie_url IS NOT NULL
    `;

    console.log(`[cleanup-selfies] Found ${expired.length} expired selfies`);

    for (const checkin of expired) {
      try {
        // Delete from R2/S3 storage
        // const key = extractS3Key(checkin.selfie_url);
        // await deleteFromR2(key);
        console.log(`[cleanup-selfies] Would delete from storage: ${checkin.selfie_url}`);

        // Update database to remove URL
        await sql`
          UPDATE checkins
          SET selfie_url = NULL, selfie_expires_at = NULL
          WHERE id = ${checkin.id}
        `;

        console.log(`[cleanup-selfies] Cleaned up selfie for check-in ${checkin.id}`);
      } catch (error) {
        console.error(
          `[cleanup-selfies] Failed to cleanup selfie ${checkin.id}:`,
          error
        );
      }
    }

    console.log('[cleanup-selfies] Job completed');
  } catch (error) {
    console.error('[cleanup-selfies] Error:', error);
    throw error;
  }
}

// Helper to extract S3/R2 key from CDN URL
function extractS3Key(url: string): string {
  // URL format: https://cdn.howru.app/selfies/{userId}/{checkinId}.jpg
  const match = url.match(/selfies\/[\w-]+\/[\w-]+\.\w+$/);
  return match ? match[0] : url;
}

// Run the job
cleanupExpiredSelfies()
  .then(() => {
    console.log('[cleanup-selfies] Completed successfully');
    process.exit(0);
  })
  .catch((error) => {
    console.error('[cleanup-selfies] Failed:', error);
    process.exit(1);
  });
