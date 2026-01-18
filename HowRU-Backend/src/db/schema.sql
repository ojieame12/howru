-- HowRU Database Schema
-- Run this in Neon SQL Editor to create all tables

-- ============================================================================
-- USERS
-- ============================================================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number VARCHAR(20) UNIQUE,
    email VARCHAR(255) UNIQUE,
    name VARCHAR(100) NOT NULL,
    is_checker BOOLEAN DEFAULT true,
    profile_image_url TEXT,
    address TEXT,
    -- Cached location (from most recent check-in)
    last_known_latitude DOUBLE PRECISION,
    last_known_longitude DOUBLE PRECISION,
    last_known_address TEXT,
    last_known_location_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone_number);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- ============================================================================
-- SCHEDULES
-- ============================================================================
CREATE TABLE IF NOT EXISTS schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    window_start_hour SMALLINT NOT NULL DEFAULT 7,
    window_start_minute SMALLINT NOT NULL DEFAULT 0,
    window_end_hour SMALLINT NOT NULL DEFAULT 10,
    window_end_minute SMALLINT NOT NULL DEFAULT 0,
    timezone_identifier VARCHAR(50) NOT NULL DEFAULT 'UTC',
    active_days SMALLINT[] DEFAULT '{0,1,2,3,4,5,6}',
    grace_period_minutes SMALLINT DEFAULT 30,
    reminder_enabled BOOLEAN DEFAULT true,
    reminder_minutes_before SMALLINT DEFAULT 30,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_schedules_user ON schedules(user_id);

-- ============================================================================
-- CHECK-INS
-- ============================================================================
CREATE TABLE IF NOT EXISTS checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    mental_score SMALLINT NOT NULL CHECK (mental_score BETWEEN 1 AND 5),
    body_score SMALLINT NOT NULL CHECK (body_score BETWEEN 1 AND 5),
    mood_score SMALLINT NOT NULL CHECK (mood_score BETWEEN 1 AND 5),
    -- Location
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    location_name VARCHAR(255),
    address TEXT,
    -- Selfie (ephemeral)
    selfie_url TEXT,
    selfie_expires_at TIMESTAMPTZ,
    is_manual BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_checkins_user_timestamp ON checkins(user_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_checkins_selfie_expires ON checkins(selfie_expires_at) WHERE selfie_expires_at IS NOT NULL;

-- ============================================================================
-- CIRCLE LINKS
-- ============================================================================
CREATE TABLE IF NOT EXISTS circle_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    checker_id UUID REFERENCES users(id) ON DELETE CASCADE,
    supporter_id UUID REFERENCES users(id) ON DELETE CASCADE,
    supporter_display_name VARCHAR(100),
    -- Supporter contact info (for non-app users)
    supporter_phone VARCHAR(20),
    supporter_email VARCHAR(255),
    -- Permissions
    can_see_mood BOOLEAN DEFAULT true,
    can_see_location BOOLEAN DEFAULT false,
    can_see_selfie BOOLEAN DEFAULT false,
    can_poke BOOLEAN DEFAULT true,
    alert_priority SMALLINT DEFAULT 1,
    -- Alert delivery preferences
    alert_via_push BOOLEAN DEFAULT true,
    alert_via_sms BOOLEAN DEFAULT false,
    alert_via_email BOOLEAN DEFAULT false,
    -- Status
    is_active BOOLEAN DEFAULT true,
    invited_at TIMESTAMPTZ DEFAULT NOW(),
    accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(checker_id, supporter_id)
);

CREATE INDEX IF NOT EXISTS idx_circle_links_checker ON circle_links(checker_id);
CREATE INDEX IF NOT EXISTS idx_circle_links_supporter ON circle_links(supporter_id);

-- ============================================================================
-- INVITES
-- ============================================================================
CREATE TABLE IF NOT EXISTS invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(20) UNIQUE NOT NULL,
    inviter_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL,
    can_see_mood BOOLEAN DEFAULT true,
    can_see_location BOOLEAN DEFAULT false,
    can_see_selfie BOOLEAN DEFAULT false,
    can_poke BOOLEAN DEFAULT true,
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    accepted_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invites_code ON invites(code);

-- ============================================================================
-- POKES
-- ============================================================================
CREATE TABLE IF NOT EXISTS pokes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    to_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    message TEXT,
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    seen_at TIMESTAMPTZ,
    responded_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_pokes_to_user ON pokes(to_user_id, sent_at DESC);

-- ============================================================================
-- ALERTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    checker_id UUID REFERENCES users(id) ON DELETE CASCADE,
    checker_name VARCHAR(100) NOT NULL,
    type VARCHAR(20) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    triggered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    missed_window_at TIMESTAMPTZ NOT NULL,
    -- Context
    last_checkin_at TIMESTAMPTZ,
    last_known_location VARCHAR(255),
    -- Resolution
    acknowledged_at TIMESTAMPTZ,
    acknowledged_by UUID REFERENCES users(id),
    resolved_at TIMESTAMPTZ,
    resolved_by UUID REFERENCES users(id),
    resolution VARCHAR(50),
    resolution_notes TEXT,
    notified_supporter_ids UUID[] DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_alerts_checker_status ON alerts(checker_id, status);
CREATE INDEX IF NOT EXISTS idx_alerts_status ON alerts(status) WHERE status = 'pending';

-- ============================================================================
-- PUSH TOKENS
-- ============================================================================
CREATE TABLE IF NOT EXISTS push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform VARCHAR(10) NOT NULL,
    device_id VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, token)
);

-- ============================================================================
-- SUBSCRIPTIONS (synced from RevenueCat)
-- ============================================================================
CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    plan VARCHAR(20) DEFAULT 'free',
    status VARCHAR(20) DEFAULT 'active',
    product_id VARCHAR(100),
    expires_at TIMESTAMPTZ,
    revenue_cat_id VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- REFRESH TOKENS (for JWT auth)
-- ============================================================================
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens(token_hash);
