import express, { Express } from 'express';
import request from 'supertest';
import crypto from 'crypto';

// Mock the database
jest.mock('../db/index.js', () => ({
  getUserByPhone: jest.fn(),
  getUserByEmail: jest.fn(),
  createUser: jest.fn(),
  saveRefreshToken: jest.fn(),
  getRefreshToken: jest.fn(),
  deleteRefreshToken: jest.fn(),
  sql: jest.fn(),
}));

// Mock Twilio service
jest.mock('../services/twilio.js', () => ({
  sendOTP: jest.fn(),
  verifyOTP: jest.fn(),
  formatPhoneE164: jest.fn((phone, countryCode) => `+1${phone.replace(/\D/g, '')}`),
}));

// Mock jwks-rsa for Apple Sign-In
jest.mock('jwks-rsa', () => {
  return jest.fn().mockImplementation(() => ({
    getSigningKey: jest.fn((kid, callback) => {
      callback(null, {
        getPublicKey: () => 'mock-public-key',
      });
    }),
  }));
});

// Mock jsonwebtoken
jest.mock('jsonwebtoken', () => ({
  sign: jest.fn().mockReturnValue('mock-access-token'),
  verify: jest.fn(),
}));

import {
  getUserByPhone,
  getUserByEmail,
  createUser,
  saveRefreshToken,
  getRefreshToken,
  deleteRefreshToken,
  sql,
} from '../db/index.js';
import { sendOTP, verifyOTP } from '../services/twilio.js';
import jwt from 'jsonwebtoken';
import authRouter from '../routes/auth.js';

describe('Auth Routes', () => {
  let app: Express;

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/auth', authRouter);
    jest.clearAllMocks();
  });

  // ===========================================================================
  // POST /auth/otp/request
  // ===========================================================================
  describe('POST /auth/otp/request', () => {
    it('should send OTP successfully', async () => {
      (sendOTP as jest.Mock).mockResolvedValue({ status: 'pending' });

      const response = await request(app)
        .post('/auth/otp/request')
        .send({ phoneNumber: '5551234567', countryCode: 'US' })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.status).toBe('pending');
      expect(response.body.message).toBe('Verification code sent');
      expect(sendOTP).toHaveBeenCalled();
    });

    it('should default countryCode to US if not provided', async () => {
      (sendOTP as jest.Mock).mockResolvedValue({ status: 'pending' });

      const response = await request(app)
        .post('/auth/otp/request')
        .send({ phoneNumber: '5551234567' })
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should return 400 for invalid phone number (too short)', async () => {
      const response = await request(app)
        .post('/auth/otp/request')
        .send({ phoneNumber: '123' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for invalid phone number (too long)', async () => {
      const response = await request(app)
        .post('/auth/otp/request')
        .send({ phoneNumber: '123456789012345678901' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for invalid country code', async () => {
      const response = await request(app)
        .post('/auth/otp/request')
        .send({ phoneNumber: '5551234567', countryCode: 'USA' })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should handle Twilio errors gracefully', async () => {
      (sendOTP as jest.Mock).mockRejectedValue(new Error('Twilio error'));

      const response = await request(app)
        .post('/auth/otp/request')
        .send({ phoneNumber: '5551234567', countryCode: 'US' })
        .expect(400);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Twilio error');
    });
  });

  // ===========================================================================
  // POST /auth/otp/verify
  // ===========================================================================
  describe('POST /auth/otp/verify', () => {
    const existingUser = {
      id: 'user-123',
      name: 'John Doe',
      phone_number: '+15551234567',
      is_checker: true,
    };

    it('should login existing user with valid OTP', async () => {
      (verifyOTP as jest.Mock).mockResolvedValue(true);
      (getUserByPhone as jest.Mock).mockResolvedValue(existingUser);
      (saveRefreshToken as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/auth/otp/verify')
        .send({
          phoneNumber: '5551234567',
          countryCode: 'US',
          code: '123456',
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.isNewUser).toBe(false);
      expect(response.body.user.id).toBe('user-123');
      expect(response.body.user.name).toBe('John Doe');
      expect(response.body.tokens.accessToken).toBeDefined();
      expect(response.body.tokens.refreshToken).toBeDefined();
    });

    it('should create new user when name provided and user does not exist', async () => {
      (verifyOTP as jest.Mock).mockResolvedValue(true);
      (getUserByPhone as jest.Mock).mockResolvedValue(null);
      (createUser as jest.Mock).mockResolvedValue({
        id: 'new-user-456',
        name: 'Jane Doe',
        phone_number: '+15551234567',
        is_checker: true,
      });
      (saveRefreshToken as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/auth/otp/verify')
        .send({
          phoneNumber: '5551234567',
          countryCode: 'US',
          code: '123456',
          name: 'Jane Doe',
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.isNewUser).toBe(true);
      expect(response.body.user.name).toBe('Jane Doe');
      expect(createUser).toHaveBeenCalledWith({
        phoneNumber: '+15551234567',
        name: 'Jane Doe',
      });
    });

    it('should return 400 when name missing for new user', async () => {
      (verifyOTP as jest.Mock).mockResolvedValue(true);
      (getUserByPhone as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .post('/auth/otp/verify')
        .send({
          phoneNumber: '5551234567',
          countryCode: 'US',
          code: '123456',
        })
        .expect(400);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Name is required for new users');
      expect(response.body.isNewUser).toBe(true);
    });

    it('should return 401 for invalid OTP code', async () => {
      (verifyOTP as jest.Mock).mockResolvedValue(false);

      const response = await request(app)
        .post('/auth/otp/verify')
        .send({
          phoneNumber: '5551234567',
          countryCode: 'US',
          code: '000000',
        })
        .expect(401);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Invalid or expired verification code');
    });

    it('should return 400 for invalid code format (not 6 digits)', async () => {
      const response = await request(app)
        .post('/auth/otp/verify')
        .send({
          phoneNumber: '5551234567',
          countryCode: 'US',
          code: '12345', // Only 5 digits
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should return 400 for name exceeding max length', async () => {
      (verifyOTP as jest.Mock).mockResolvedValue(true);
      (getUserByPhone as jest.Mock).mockResolvedValue(null);

      const longName = 'A'.repeat(101);
      const response = await request(app)
        .post('/auth/otp/verify')
        .send({
          phoneNumber: '5551234567',
          countryCode: 'US',
          code: '123456',
          name: longName,
        })
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should save refresh token on successful login', async () => {
      (verifyOTP as jest.Mock).mockResolvedValue(true);
      (getUserByPhone as jest.Mock).mockResolvedValue(existingUser);
      (saveRefreshToken as jest.Mock).mockResolvedValue(undefined);

      await request(app)
        .post('/auth/otp/verify')
        .send({
          phoneNumber: '5551234567',
          countryCode: 'US',
          code: '123456',
        })
        .expect(200);

      expect(saveRefreshToken).toHaveBeenCalledWith(
        'user-123',
        expect.any(String),
        expect.any(Date)
      );
    });
  });

  // ===========================================================================
  // POST /auth/refresh
  // ===========================================================================
  describe('POST /auth/refresh', () => {
    it('should refresh tokens successfully', async () => {
      const mockRefreshToken = crypto.randomBytes(32).toString('hex');
      const tokenHash = crypto.createHash('sha256').update(mockRefreshToken).digest('hex');

      (getRefreshToken as jest.Mock).mockResolvedValue({
        user_id: 'user-123',
        token_hash: tokenHash,
        expires_at: new Date(Date.now() + 86400000), // Future date
      });
      (deleteRefreshToken as jest.Mock).mockResolvedValue(undefined);
      (saveRefreshToken as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/auth/refresh')
        .send({ refreshToken: mockRefreshToken })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.tokens.accessToken).toBeDefined();
      expect(response.body.tokens.refreshToken).toBeDefined();
      expect(response.body.tokens.refreshToken).not.toBe(mockRefreshToken); // Rotated
    });

    it('should return 401 for invalid refresh token', async () => {
      (getRefreshToken as jest.Mock).mockResolvedValue(null);

      const response = await request(app)
        .post('/auth/refresh')
        .send({ refreshToken: 'invalid-token' })
        .expect(401);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Invalid or expired refresh token');
    });

    it('should return 400 for missing refresh token', async () => {
      const response = await request(app)
        .post('/auth/refresh')
        .send({})
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should delete old refresh token after use', async () => {
      const mockRefreshToken = crypto.randomBytes(32).toString('hex');
      const tokenHash = crypto.createHash('sha256').update(mockRefreshToken).digest('hex');

      (getRefreshToken as jest.Mock).mockResolvedValue({
        user_id: 'user-123',
        token_hash: tokenHash,
      });
      (deleteRefreshToken as jest.Mock).mockResolvedValue(undefined);
      (saveRefreshToken as jest.Mock).mockResolvedValue(undefined);

      await request(app)
        .post('/auth/refresh')
        .send({ refreshToken: mockRefreshToken })
        .expect(200);

      expect(deleteRefreshToken).toHaveBeenCalledWith(tokenHash);
    });

    it('should save new refresh token after rotation', async () => {
      const mockRefreshToken = crypto.randomBytes(32).toString('hex');
      const tokenHash = crypto.createHash('sha256').update(mockRefreshToken).digest('hex');

      (getRefreshToken as jest.Mock).mockResolvedValue({
        user_id: 'user-123',
        token_hash: tokenHash,
      });
      (deleteRefreshToken as jest.Mock).mockResolvedValue(undefined);
      (saveRefreshToken as jest.Mock).mockResolvedValue(undefined);

      await request(app)
        .post('/auth/refresh')
        .send({ refreshToken: mockRefreshToken })
        .expect(200);

      expect(saveRefreshToken).toHaveBeenCalledWith(
        'user-123',
        expect.any(String),
        expect.any(Date)
      );
    });
  });

  // ===========================================================================
  // POST /auth/logout
  // ===========================================================================
  describe('POST /auth/logout', () => {
    it('should logout successfully with refresh token', async () => {
      const mockRefreshToken = crypto.randomBytes(32).toString('hex');
      (deleteRefreshToken as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/auth/logout')
        .send({ refreshToken: mockRefreshToken })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(deleteRefreshToken).toHaveBeenCalled();
    });

    it('should succeed even without refresh token', async () => {
      const response = await request(app)
        .post('/auth/logout')
        .send({})
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(deleteRefreshToken).not.toHaveBeenCalled();
    });

    it('should always succeed even on database error', async () => {
      const mockRefreshToken = crypto.randomBytes(32).toString('hex');
      (deleteRefreshToken as jest.Mock).mockRejectedValue(new Error('DB error'));

      const response = await request(app)
        .post('/auth/logout')
        .send({ refreshToken: mockRefreshToken })
        .expect(200);

      expect(response.body.success).toBe(true);
    });
  });

  // ===========================================================================
  // POST /auth/apple
  // ===========================================================================
  describe('POST /auth/apple', () => {
    const validTokenPayload = {
      sub: 'apple-user-123',
      email: 'test@example.com',
    };

    // Create a mock identity token (header.payload.signature)
    const mockIdentityToken = [
      Buffer.from(JSON.stringify({ kid: 'test-kid' })).toString('base64'),
      Buffer.from(JSON.stringify(validTokenPayload)).toString('base64'),
      'mock-signature',
    ].join('.');

    beforeEach(() => {
      (jwt.verify as jest.Mock).mockReturnValue(validTokenPayload);
    });

    it('should create new user with Apple Sign-In', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // No existing user by apple_id
      (getUserByEmail as jest.Mock).mockResolvedValue(null);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([
        {
          id: 'new-apple-user',
          name: 'John Apple',
          email: 'test@example.com',
          apple_id: 'apple-user-123',
          is_checker: true,
        },
      ]);
      (saveRefreshToken as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/auth/apple')
        .send({
          identityToken: mockIdentityToken,
          fullName: { givenName: 'John', familyName: 'Apple' },
          email: 'test@example.com',
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.isNewUser).toBe(true);
      expect(response.body.user.name).toBe('John Apple');
      expect(response.body.tokens.accessToken).toBeDefined();
    });

    it('should login existing Apple user', async () => {
      const existingAppleUser = {
        id: 'existing-apple-user',
        name: 'Jane Apple',
        email: 'jane@example.com',
        apple_id: 'apple-user-123',
        is_checker: true,
      };
      (sql as unknown as jest.Mock).mockResolvedValueOnce([existingAppleUser]);
      (saveRefreshToken as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/auth/apple')
        .send({
          identityToken: mockIdentityToken,
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.isNewUser).toBe(false);
      expect(response.body.user.id).toBe('existing-apple-user');
    });

    it('should link existing email user to Apple ID', async () => {
      const existingEmailUser = {
        id: 'email-user-123',
        name: 'Email User',
        email: 'test@example.com',
        apple_id: null,
        is_checker: true,
      };
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // No user by apple_id
      (getUserByEmail as jest.Mock).mockResolvedValue(existingEmailUser);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // UPDATE query
      (saveRefreshToken as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/auth/apple')
        .send({
          identityToken: mockIdentityToken,
          email: 'test@example.com',
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.isNewUser).toBe(false);
      expect(response.body.user.id).toBe('email-user-123');
    });

    it('should return 400 for invalid token format', async () => {
      const response = await request(app)
        .post('/auth/apple')
        .send({
          identityToken: 'invalid-token-no-dots',
        })
        .expect(400);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Invalid identity token format');
    });

    it('should return 401 for invalid Apple identity token', async () => {
      (jwt.verify as jest.Mock).mockImplementation(() => {
        const error = new Error('Invalid token');
        (error as any).name = 'JsonWebTokenError';
        throw error;
      });

      const response = await request(app)
        .post('/auth/apple')
        .send({
          identityToken: mockIdentityToken,
        })
        .expect(401);

      expect(response.body.success).toBe(false);
      expect(response.body.error).toBe('Invalid Apple identity token');
    });

    it('should return 400 for missing identity token', async () => {
      const response = await request(app)
        .post('/auth/apple')
        .send({})
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('should use givenName only if familyName is missing', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // No existing user
      (getUserByEmail as jest.Mock).mockResolvedValue(null);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([
        {
          id: 'new-user',
          name: 'John',
          email: 'test@example.com',
          is_checker: true,
        },
      ]);
      (saveRefreshToken as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/auth/apple')
        .send({
          identityToken: mockIdentityToken,
          fullName: { givenName: 'John' },
          email: 'test@example.com',
        })
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should default name to "User" if no name provided', async () => {
      (sql as unknown as jest.Mock).mockResolvedValueOnce([]); // No existing user
      (getUserByEmail as jest.Mock).mockResolvedValue(null);
      (sql as unknown as jest.Mock).mockResolvedValueOnce([
        {
          id: 'new-user',
          name: 'User',
          email: 'test@example.com',
          is_checker: true,
        },
      ]);
      (saveRefreshToken as jest.Mock).mockResolvedValue(undefined);

      const response = await request(app)
        .post('/auth/apple')
        .send({
          identityToken: mockIdentityToken,
          email: 'test@example.com',
        })
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.user.name).toBe('User');
    });
  });
});
