import { Router, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { z } from 'zod';
import jwksClient from 'jwks-rsa';
import { sendOTP, verifyOTP, formatPhoneE164 } from '../services/twilio.js';
import {
  getUserByPhone,
  getUserByEmail,
  createUser,
  saveRefreshToken,
  getRefreshToken,
  deleteRefreshToken,
  sql,
} from '../db/index.js';

const router = Router();

const JWT_SECRET = process.env.JWT_SECRET!;
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';

// Helper to sign JWT with proper typing
function signJWT(payload: object): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN as jwt.SignOptions['expiresIn'] });
}

// ============================================================================
// REQUEST OTP
// ============================================================================

const requestOTPSchema = z.object({
  phoneNumber: z.string().min(10).max(20),
  countryCode: z.string().length(2).default('US'),
});

router.post('/otp/request', async (req: Request, res: Response) => {
  try {
    const { phoneNumber, countryCode } = requestOTPSchema.parse(req.body);

    // Format to E.164
    const formattedPhone = formatPhoneE164(phoneNumber, countryCode);

    // Send OTP via Twilio Verify
    const result = await sendOTP(formattedPhone);

    res.json({
      success: true,
      status: result.status,
      message: 'Verification code sent',
    });
  } catch (error: any) {
    console.error('OTP request error:', error);
    res.status(400).json({
      success: false,
      error: error.message || 'Failed to send verification code',
    });
  }
});

// ============================================================================
// VERIFY OTP
// ============================================================================

const verifyOTPSchema = z.object({
  phoneNumber: z.string().min(10).max(20),
  countryCode: z.string().length(2).default('US'),
  code: z.string().length(6),
  name: z.string().min(1).max(100).optional(), // Required for new users
});

router.post('/otp/verify', async (req: Request, res: Response) => {
  try {
    const { phoneNumber, countryCode, code, name } = verifyOTPSchema.parse(req.body);

    const formattedPhone = formatPhoneE164(phoneNumber, countryCode);

    // Verify OTP with Twilio
    const isValid = await verifyOTP(formattedPhone, code);

    if (!isValid) {
      return res.status(401).json({
        success: false,
        error: 'Invalid or expired verification code',
      });
    }

    // Check if user exists
    let user = await getUserByPhone(formattedPhone);
    let isNewUser = false;

    if (!user) {
      // Create new user
      if (!name) {
        return res.status(400).json({
          success: false,
          error: 'Name is required for new users',
          isNewUser: true,
        });
      }

      user = await createUser({
        phoneNumber: formattedPhone,
        name,
      });
      isNewUser = true;
    }

    // Generate tokens
    const accessToken = signJWT({ userId: user.id, phone: user.phone_number });

    const refreshToken = crypto.randomBytes(32).toString('hex');
    const refreshTokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex');
    const refreshExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days

    await saveRefreshToken(user.id, refreshTokenHash, refreshExpiresAt);

    res.json({
      success: true,
      isNewUser,
      user: {
        id: user.id,
        name: user.name,
        phoneNumber: user.phone_number,
        isChecker: user.is_checker,
      },
      tokens: {
        accessToken,
        refreshToken,
        expiresIn: JWT_EXPIRES_IN,
      },
    });
  } catch (error: any) {
    console.error('OTP verify error:', error);
    res.status(400).json({
      success: false,
      error: error.message || 'Verification failed',
    });
  }
});

// ============================================================================
// REFRESH TOKEN
// ============================================================================

const refreshTokenSchema = z.object({
  refreshToken: z.string().min(1),
});

router.post('/refresh', async (req: Request, res: Response) => {
  try {
    const { refreshToken } = refreshTokenSchema.parse(req.body);

    const tokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex');
    const storedToken = await getRefreshToken(tokenHash);

    if (!storedToken) {
      return res.status(401).json({
        success: false,
        error: 'Invalid or expired refresh token',
      });
    }

    // Generate new access token
    const accessToken = signJWT({ userId: storedToken.user_id });

    // Optionally rotate refresh token
    const newRefreshToken = crypto.randomBytes(32).toString('hex');
    const newRefreshTokenHash = crypto.createHash('sha256').update(newRefreshToken).digest('hex');
    const newRefreshExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

    await deleteRefreshToken(tokenHash);
    await saveRefreshToken(storedToken.user_id, newRefreshTokenHash, newRefreshExpiresAt);

    res.json({
      success: true,
      tokens: {
        accessToken,
        refreshToken: newRefreshToken,
        expiresIn: JWT_EXPIRES_IN,
      },
    });
  } catch (error: any) {
    console.error('Refresh token error:', error);
    res.status(400).json({
      success: false,
      error: error.message || 'Token refresh failed',
    });
  }
});

// ============================================================================
// LOGOUT
// ============================================================================

router.post('/logout', async (req: Request, res: Response) => {
  try {
    const { refreshToken } = req.body;

    if (refreshToken) {
      const tokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex');
      await deleteRefreshToken(tokenHash);
    }

    res.json({ success: true });
  } catch (error) {
    res.json({ success: true }); // Always succeed logout
  }
});

// ============================================================================
// APPLE SIGN-IN
// ============================================================================

const appleSignInSchema = z.object({
  identityToken: z.string().min(1),
  fullName: z
    .object({
      givenName: z.string().optional(),
      familyName: z.string().optional(),
    })
    .optional(),
  email: z.string().email().optional(),
});

// Apple's JWKS client for verifying identity tokens
const appleJwksClient = jwksClient({
  jwksUri: 'https://appleid.apple.com/auth/keys',
  cache: true,
  cacheMaxAge: 86400000, // 24 hours
});

async function getAppleSigningKey(kid: string): Promise<string> {
  return new Promise((resolve, reject) => {
    appleJwksClient.getSigningKey(kid, (err, key) => {
      if (err) {
        reject(err);
      } else {
        resolve(key?.getPublicKey() || '');
      }
    });
  });
}

router.post('/apple', async (req: Request, res: Response) => {
  try {
    const { identityToken, fullName, email } = appleSignInSchema.parse(req.body);

    // Decode the token header to get the key ID
    const tokenParts = identityToken.split('.');
    if (tokenParts.length !== 3) {
      return res.status(400).json({
        success: false,
        error: 'Invalid identity token format',
      });
    }

    const header = JSON.parse(Buffer.from(tokenParts[0], 'base64').toString());
    const kid = header.kid;

    // Get Apple's public key and verify the token
    const publicKey = await getAppleSigningKey(kid);

    const decoded = jwt.verify(identityToken, publicKey, {
      algorithms: ['RS256'],
      issuer: 'https://appleid.apple.com',
      audience: process.env.APPLE_CLIENT_ID || 'com.howru.app',
    }) as {
      sub: string; // Apple user ID
      email?: string;
      email_verified?: string;
    };

    const appleUserId = decoded.sub;
    const userEmail = email || decoded.email;

    // Check if user already exists by Apple ID
    let user = (
      await sql`
        SELECT * FROM users WHERE apple_id = ${appleUserId}
      `
    )[0];

    let isNewUser = false;

    if (!user && userEmail) {
      // Check if user exists by email
      user = await getUserByEmail(userEmail);

      if (user) {
        // Link existing user to Apple ID
        await sql`
          UPDATE users SET apple_id = ${appleUserId} WHERE id = ${user.id}
        `;
      }
    }

    if (!user) {
      // Create new user
      const name =
        fullName?.givenName && fullName?.familyName
          ? `${fullName.givenName} ${fullName.familyName}`
          : fullName?.givenName || 'User';

      const result = await sql`
        INSERT INTO users (name, email, apple_id, is_checker)
        VALUES (${name}, ${userEmail || null}, ${appleUserId}, true)
        RETURNING *
      `;
      user = result[0];
      isNewUser = true;
    }

    // Generate tokens
    const accessToken = signJWT({ userId: user.id, email: user.email });

    const refreshToken = crypto.randomBytes(32).toString('hex');
    const refreshTokenHash = crypto
      .createHash('sha256')
      .update(refreshToken)
      .digest('hex');
    const refreshExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

    await saveRefreshToken(user.id, refreshTokenHash, refreshExpiresAt);

    res.json({
      success: true,
      isNewUser,
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        phoneNumber: user.phone_number,
        isChecker: user.is_checker,
      },
      tokens: {
        accessToken,
        refreshToken,
        expiresIn: JWT_EXPIRES_IN,
      },
    });
  } catch (error: any) {
    console.error('Apple Sign-In error:', error);

    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({
        success: false,
        error: 'Invalid Apple identity token',
      });
    }

    res.status(400).json({
      success: false,
      error: error.message || 'Apple Sign-In failed',
    });
  }
});

export default router;
