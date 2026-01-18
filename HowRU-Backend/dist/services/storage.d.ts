/**
 * Cloud Storage Service (Cloudflare R2 / S3-compatible)
 * Handles selfie and avatar uploads with automatic expiry
 *
 * Features:
 * - S3-compatible API (works with R2, S3, Backblaze B2)
 * - Automatic selfie expiry after 24 hours
 * - Signed URL generation for secure access
 * - Image optimization placeholders
 */
type FileCategory = 'selfies' | 'avatars' | 'exports';
interface UploadResult {
    key: string;
    url: string;
    cdnUrl: string;
    expiresAt?: Date;
}
/**
 * Upload a file to R2/S3
 */
export declare function uploadFile(category: FileCategory, userId: string, data: Buffer, contentType?: string, expiryHours?: number): Promise<UploadResult>;
/**
 * Upload a selfie with 24-hour expiry
 */
export declare function uploadSelfie(userId: string, checkinId: string, imageData: Buffer, contentType?: string): Promise<UploadResult>;
/**
 * Upload an avatar (no expiry)
 */
export declare function uploadAvatar(userId: string, imageData: Buffer, contentType?: string): Promise<UploadResult>;
/**
 * Delete a file from R2/S3
 */
export declare function deleteFile(key: string): Promise<void>;
/**
 * Delete file by URL
 */
export declare function deleteFileByUrl(url: string): Promise<void>;
/**
 * Extract S3 key from CDN URL
 */
export declare function extractKeyFromUrl(url: string): string | null;
/**
 * Generate a signed URL for private file access
 */
export declare function getSignedDownloadUrl(key: string, expiresInSeconds?: number): Promise<string>;
/**
 * Generate a pre-signed URL for direct upload
 */
export declare function getSignedUploadUrl(category: FileCategory, userId: string, contentType?: string, expiresInSeconds?: number): Promise<{
    uploadUrl: string;
    key: string;
    cdnUrl: string;
}>;
/**
 * Check if storage is properly configured
 */
export declare function isStorageConfigured(): boolean;
export {};
//# sourceMappingURL=storage.d.ts.map