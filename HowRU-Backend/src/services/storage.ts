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

import {
  S3Client,
  PutObjectCommand,
  DeleteObjectCommand,
  GetObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import crypto from 'crypto';

// R2/S3 Configuration
const R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID;
const R2_ACCESS_KEY = process.env.R2_ACCESS_KEY_ID;
const R2_SECRET_KEY = process.env.R2_SECRET_ACCESS_KEY;
const R2_BUCKET = process.env.R2_BUCKET || 'howru-media';
const CDN_URL = process.env.CDN_URL || `https://${R2_BUCKET}.r2.dev`;

// Create S3 client for R2
const s3Client = new S3Client({
  region: 'auto',
  endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: R2_ACCESS_KEY || '',
    secretAccessKey: R2_SECRET_KEY || '',
  },
});

// File type definitions
type FileCategory = 'selfies' | 'avatars' | 'exports';

interface UploadResult {
  key: string;
  url: string;
  cdnUrl: string;
  expiresAt?: Date;
}

/**
 * Generate a unique file key
 */
function generateFileKey(
  category: FileCategory,
  userId: string,
  extension: string = 'jpg'
): string {
  const timestamp = Date.now();
  const random = crypto.randomBytes(4).toString('hex');
  return `${category}/${userId}/${timestamp}-${random}.${extension}`;
}

/**
 * Upload a file to R2/S3
 */
export async function uploadFile(
  category: FileCategory,
  userId: string,
  data: Buffer,
  contentType: string = 'image/jpeg',
  expiryHours?: number
): Promise<UploadResult> {
  const extension = contentType.split('/')[1] || 'jpg';
  const key = generateFileKey(category, userId, extension);

  // Calculate expiry if provided
  const expiresAt = expiryHours
    ? new Date(Date.now() + expiryHours * 60 * 60 * 1000)
    : undefined;

  await s3Client.send(
    new PutObjectCommand({
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
    })
  );

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
export async function uploadSelfie(
  userId: string,
  checkinId: string,
  imageData: Buffer,
  contentType: string = 'image/jpeg'
): Promise<UploadResult> {
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
export async function uploadAvatar(
  userId: string,
  imageData: Buffer,
  contentType: string = 'image/jpeg'
): Promise<UploadResult> {
  return uploadFile('avatars', userId, imageData, contentType);
}

/**
 * Delete a file from R2/S3
 */
export async function deleteFile(key: string): Promise<void> {
  await s3Client.send(
    new DeleteObjectCommand({
      Bucket: R2_BUCKET,
      Key: key,
    })
  );
}

/**
 * Delete file by URL
 */
export async function deleteFileByUrl(url: string): Promise<void> {
  const key = extractKeyFromUrl(url);
  if (key) {
    await deleteFile(key);
  }
}

/**
 * Extract S3 key from CDN URL
 */
export function extractKeyFromUrl(url: string): string | null {
  if (!url) return null;

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
export async function getSignedDownloadUrl(
  key: string,
  expiresInSeconds: number = 3600
): Promise<string> {
  const command = new GetObjectCommand({
    Bucket: R2_BUCKET,
    Key: key,
  });

  return getSignedUrl(s3Client, command, { expiresIn: expiresInSeconds });
}

/**
 * Generate a pre-signed URL for direct upload
 */
export async function getSignedUploadUrl(
  category: FileCategory,
  userId: string,
  contentType: string = 'image/jpeg',
  expiresInSeconds: number = 300
): Promise<{ uploadUrl: string; key: string; cdnUrl: string }> {
  const extension = contentType.split('/')[1] || 'jpg';
  const key = generateFileKey(category, userId, extension);

  const command = new PutObjectCommand({
    Bucket: R2_BUCKET,
    Key: key,
    ContentType: contentType,
  });

  const uploadUrl = await getSignedUrl(s3Client, command, {
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
export function isStorageConfigured(): boolean {
  return !!(R2_ACCOUNT_ID && R2_ACCESS_KEY && R2_SECRET_KEY);
}
