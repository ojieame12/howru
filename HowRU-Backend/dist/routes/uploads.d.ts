/**
 * Upload Routes
 * Handles file uploads for selfies and avatars
 *
 * Two approaches supported:
 * 1. Direct upload: Client sends base64 data, server uploads to R2
 * 2. Pre-signed URL: Server generates URL, client uploads directly to R2
 */
declare const router: import("express-serve-static-core").Router;
export default router;
//# sourceMappingURL=uploads.d.ts.map