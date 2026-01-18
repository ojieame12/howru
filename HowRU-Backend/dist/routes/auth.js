"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const crypto_1 = __importDefault(require("crypto"));
const zod_1 = require("zod");
const jwks_rsa_1 = __importDefault(require("jwks-rsa"));
const twilio_js_1 = require("../services/twilio.js");
const index_js_1 = require("../db/index.js");
const router = (0, express_1.Router)();
const JWT_SECRET = process.env.JWT_SECRET;
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';
// Helper to sign JWT with proper typing
function signJWT(payload) {
    return jsonwebtoken_1.default.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}
// ============================================================================
// REQUEST OTP
// ============================================================================
const requestOTPSchema = zod_1.z.object({
    phoneNumber: zod_1.z.string().min(10).max(20),
    countryCode: zod_1.z.string().length(2).default('US'),
});
router.post('/otp/request', async (req, res) => {
    try {
        const { phoneNumber, countryCode } = requestOTPSchema.parse(req.body);
        // Format to E.164
        const formattedPhone = (0, twilio_js_1.formatPhoneE164)(phoneNumber, countryCode);
        // Send OTP via Twilio Verify
        const result = await (0, twilio_js_1.sendOTP)(formattedPhone);
        res.json({
            success: true,
            status: result.status,
            message: 'Verification code sent',
        });
    }
    catch (error) {
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
const verifyOTPSchema = zod_1.z.object({
    phoneNumber: zod_1.z.string().min(10).max(20),
    countryCode: zod_1.z.string().length(2).default('US'),
    code: zod_1.z.string().length(6),
    name: zod_1.z.string().min(1).max(100).optional(), // Required for new users
});
router.post('/otp/verify', async (req, res) => {
    try {
        const { phoneNumber, countryCode, code, name } = verifyOTPSchema.parse(req.body);
        const formattedPhone = (0, twilio_js_1.formatPhoneE164)(phoneNumber, countryCode);
        // Verify OTP with Twilio
        const isValid = await (0, twilio_js_1.verifyOTP)(formattedPhone, code);
        if (!isValid) {
            return res.status(401).json({
                success: false,
                error: 'Invalid or expired verification code',
            });
        }
        // Check if user exists
        let user = await (0, index_js_1.getUserByPhone)(formattedPhone);
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
            user = await (0, index_js_1.createUser)({
                phoneNumber: formattedPhone,
                name,
            });
            isNewUser = true;
        }
        // Generate tokens
        const accessToken = signJWT({ userId: user.id, phone: user.phone_number });
        const refreshToken = crypto_1.default.randomBytes(32).toString('hex');
        const refreshTokenHash = crypto_1.default.createHash('sha256').update(refreshToken).digest('hex');
        const refreshExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days
        await (0, index_js_1.saveRefreshToken)(user.id, refreshTokenHash, refreshExpiresAt);
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
    }
    catch (error) {
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
const refreshTokenSchema = zod_1.z.object({
    refreshToken: zod_1.z.string().min(1),
});
router.post('/refresh', async (req, res) => {
    try {
        const { refreshToken } = refreshTokenSchema.parse(req.body);
        const tokenHash = crypto_1.default.createHash('sha256').update(refreshToken).digest('hex');
        const storedToken = await (0, index_js_1.getRefreshToken)(tokenHash);
        if (!storedToken) {
            return res.status(401).json({
                success: false,
                error: 'Invalid or expired refresh token',
            });
        }
        // Generate new access token
        const accessToken = signJWT({ userId: storedToken.user_id });
        // Optionally rotate refresh token
        const newRefreshToken = crypto_1.default.randomBytes(32).toString('hex');
        const newRefreshTokenHash = crypto_1.default.createHash('sha256').update(newRefreshToken).digest('hex');
        const newRefreshExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
        await (0, index_js_1.deleteRefreshToken)(tokenHash);
        await (0, index_js_1.saveRefreshToken)(storedToken.user_id, newRefreshTokenHash, newRefreshExpiresAt);
        res.json({
            success: true,
            tokens: {
                accessToken,
                refreshToken: newRefreshToken,
                expiresIn: JWT_EXPIRES_IN,
            },
        });
    }
    catch (error) {
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
router.post('/logout', async (req, res) => {
    try {
        const { refreshToken } = req.body;
        if (refreshToken) {
            const tokenHash = crypto_1.default.createHash('sha256').update(refreshToken).digest('hex');
            await (0, index_js_1.deleteRefreshToken)(tokenHash);
        }
        res.json({ success: true });
    }
    catch (error) {
        res.json({ success: true }); // Always succeed logout
    }
});
// ============================================================================
// APPLE SIGN-IN
// ============================================================================
const appleSignInSchema = zod_1.z.object({
    identityToken: zod_1.z.string().min(1),
    fullName: zod_1.z
        .object({
        givenName: zod_1.z.string().optional(),
        familyName: zod_1.z.string().optional(),
    })
        .optional(),
    email: zod_1.z.string().email().optional(),
});
// Apple's JWKS client for verifying identity tokens
const appleJwksClient = (0, jwks_rsa_1.default)({
    jwksUri: 'https://appleid.apple.com/auth/keys',
    cache: true,
    cacheMaxAge: 86400000, // 24 hours
});
async function getAppleSigningKey(kid) {
    return new Promise((resolve, reject) => {
        appleJwksClient.getSigningKey(kid, (err, key) => {
            if (err) {
                reject(err);
            }
            else {
                resolve(key?.getPublicKey() || '');
            }
        });
    });
}
router.post('/apple', async (req, res) => {
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
        const decoded = jsonwebtoken_1.default.verify(identityToken, publicKey, {
            algorithms: ['RS256'],
            issuer: 'https://appleid.apple.com',
            audience: process.env.APPLE_CLIENT_ID || 'com.howru.app',
        });
        const appleUserId = decoded.sub;
        const userEmail = email || decoded.email;
        // Check if user already exists by Apple ID
        let user = (await (0, index_js_1.sql) `
        SELECT * FROM users WHERE apple_id = ${appleUserId}
      `)[0];
        let isNewUser = false;
        if (!user && userEmail) {
            // Check if user exists by email
            user = await (0, index_js_1.getUserByEmail)(userEmail);
            if (user) {
                // Link existing user to Apple ID
                await (0, index_js_1.sql) `
          UPDATE users SET apple_id = ${appleUserId} WHERE id = ${user.id}
        `;
            }
        }
        if (!user) {
            // Create new user
            const name = fullName?.givenName && fullName?.familyName
                ? `${fullName.givenName} ${fullName.familyName}`
                : fullName?.givenName || 'User';
            const result = await (0, index_js_1.sql) `
        INSERT INTO users (name, email, apple_id, is_checker)
        VALUES (${name}, ${userEmail || null}, ${appleUserId}, true)
        RETURNING *
      `;
            user = result[0];
            isNewUser = true;
        }
        // Generate tokens
        const accessToken = signJWT({ userId: user.id, email: user.email });
        const refreshToken = crypto_1.default.randomBytes(32).toString('hex');
        const refreshTokenHash = crypto_1.default
            .createHash('sha256')
            .update(refreshToken)
            .digest('hex');
        const refreshExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
        await (0, index_js_1.saveRefreshToken)(user.id, refreshTokenHash, refreshExpiresAt);
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
    }
    catch (error) {
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
exports.default = router;
//# sourceMappingURL=auth.js.map