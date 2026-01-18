"use strict";
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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.uploadFile = uploadFile;
exports.uploadSelfie = uploadSelfie;
exports.uploadAvatar = uploadAvatar;
exports.deleteFile = deleteFile;
exports.deleteFileByUrl = deleteFileByUrl;
exports.extractKeyFromUrl = extractKeyFromUrl;
exports.getSignedDownloadUrl = getSignedDownloadUrl;
exports.getSignedUploadUrl = getSignedUploadUrl;
exports.isStorageConfigured = isStorageConfigured;
const client_s3_1 = require("@aws-sdk/client-s3");
const s3_request_presigner_1 = require("@aws-sdk/s3-request-presigner");
const crypto_1 = __importDefault(require("crypto"));
// R2/S3 Configuration
const R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID;
const R2_ACCESS_KEY = process.env.R2_ACCESS_KEY_ID;
const R2_SECRET_KEY = process.env.R2_SECRET_ACCESS_KEY;
const R2_BUCKET = process.env.R2_BUCKET || 'howru-media';
const CDN_URL = process.env.CDN_URL || `https://${R2_BUCKET}.r2.dev`;
// Create S3 client for R2
const s3Client = new client_s3_1.S3Client({
    region: 'auto',
    endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
        accessKeyId: R2_ACCESS_KEY || '',
        secretAccessKey: R2_SECRET_KEY || '',
    },
});
/**
 * Generate a unique file key
 */
function generateFileKey(category, userId, extension = 'jpg') {
    const timestamp = Date.now();
    const random = crypto_1.default.randomBytes(4).toString('hex');
    return `${category}/${userId}/${timestamp}-${random}.${extension}`;
}
/**
 * Upload a file to R2/S3
 */
async function uploadFile(category, userId, data, contentType = 'image/jpeg', expiryHours) {
    const extension = contentType.split('/')[1] || 'jpg';
    const key = generateFileKey(category, userId, extension);
    // Calculate expiry if provided
    const expiresAt = expiryHours
        ? new Date(Date.now() + expiryHours * 60 * 60 * 1000)
        : undefined;
    await s3Client.send(new client_s3_1.PutObjectCommand({
        Bucket: R2_BUCKET,
        Key: key,
        Body: data,
        ContentType: contentType,
        // Optional: Set cache control
        CacheControl: expiryHours ? `max-age=${expiryHours * 3600}` : 'max-age=31536000',
        // Optional: Custom metadata
        Metadata: {
            'user-id': userId,
            ...(expiresAt && { 'expires-at': expiresAt.toISOString() }),
        },
    }));
    return {
        key,
        url: `${CDN_URL}/${key}`,
        cdnUrl: `${CDN_URL}/${key}`,
        expiresAt,
    };
}
/**
 * Upload a selfie with 24-hour expiry
 */
async function uploadSelfie(userId, checkinId, imageData, contentType = 'image/jpeg') {
    // Selfies expire after 24 hours per privacy policy
    const result = await uploadFile('selfies', userId, imageData, contentType, 24);
    return {
        ...result,
        expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
    };
}
/**
 * Upload an avatar (no expiry)
 */
async function uploadAvatar(userId, imageData, contentType = 'image/jpeg') {
    return uploadFile('avatars', userId, imageData, contentType);
}
/**
 * Delete a file from R2/S3
 */
async function deleteFile(key) {
    await s3Client.send(new client_s3_1.DeleteObjectCommand({
        Bucket: R2_BUCKET,
        Key: key,
    }));
}
/**
 * Delete file by URL
 */
async function deleteFileByUrl(url) {
    const key = extractKeyFromUrl(url);
    if (key) {
        await deleteFile(key);
    }
}
/**
 * Extract S3 key from CDN URL
 */
function extractKeyFromUrl(url) {
    if (!url)
        return null;
    // Handle various URL formats
    const patterns = [
        // CDN URL: https://cdn.howru.app/selfies/user-id/file.jpg
        /(?:selfies|avatars|exports)\/[\w-]+\/[\w.-]+$/,
        // R2 direct URL
        /\.r2\.dev\/([\w-]+\/[\w-]+\/[\w.-]+)$/,
    ];
    for (const pattern of patterns) {
        const match = url.match(pattern);
        if (match) {
            return match[0];
        }
    }
    return null;
}
/**
 * Generate a signed URL for private file access
 */
async function getSignedDownloadUrl(key, expiresInSeconds = 3600) {
    const command = new client_s3_1.GetObjectCommand({
        Bucket: R2_BUCKET,
        Key: key,
    });
    return (0, s3_request_presigner_1.getSignedUrl)(s3Client, command, { expiresIn: expiresInSeconds });
}
/**
 * Generate a pre-signed URL for direct upload
 */
async function getSignedUploadUrl(category, userId, contentType = 'image/jpeg', expiresInSeconds = 300) {
    const extension = contentType.split('/')[1] || 'jpg';
    const key = generateFileKey(category, userId, extension);
    const command = new client_s3_1.PutObjectCommand({
        Bucket: R2_BUCKET,
        Key: key,
        ContentType: contentType,
    });
    const uploadUrl = await (0, s3_request_presigner_1.getSignedUrl)(s3Client, command, {
        expiresIn: expiresInSeconds,
    });
    return {
        uploadUrl,
        key,
        cdnUrl: `${CDN_URL}/${key}`,
    };
}
/**
 * Check if storage is properly configured
 */
function isStorageConfigured() {
    return !!(R2_ACCOUNT_ID && R2_ACCESS_KEY && R2_SECRET_KEY);
}
//# sourceMappingURL=storage.js.map