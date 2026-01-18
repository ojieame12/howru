// Jest test setup file

// Mock environment variables for tests
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-jwt-secret';
process.env.JWT_REFRESH_SECRET = 'test-jwt-refresh-secret';
process.env.REVENUECAT_WEBHOOK_SECRET = 'test-revenuecat-secret';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
