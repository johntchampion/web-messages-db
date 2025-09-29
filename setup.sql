-- ============================================
-- Extensions
-- ============================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS citext;  -- case-insensitive text

-- ============================================
-- Custom Types
-- ============================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'content_type') THEN
        CREATE TYPE content_type AS ENUM ('text', 'image');
    END IF;
END$$;

-- ============================================
-- Utility functions & triggers
-- ============================================
-- Set updated_at automatically on real changes
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    -- Avoid touching updated_at if nothing but updated_at changed
    IF (to_jsonb(NEW) - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'updated_at') THEN
        NEW.updated_at := NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Bump a conversation's updated_at when messages change
CREATE OR REPLACE FUNCTION touch_conversation_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    -- Use NEW on INSERT/UPDATE and OLD on DELETE
    UPDATE conversations
       SET updated_at = NOW()
     WHERE convo_id = COALESCE(NEW.convo_id, OLD.convo_id);
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Maintain token timestamps only when tokens actually change
CREATE OR REPLACE FUNCTION set_auth_token_timestamps()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- On insert, set timestamps only if token is non-null
        IF NEW.verify_token IS NOT NULL THEN
            NEW.verify_token_timestamp := NOW();
        ELSE
            NEW.verify_token_timestamp := NULL;
        END IF;

        IF NEW.reset_password_token IS NOT NULL THEN
            NEW.reset_password_token_timestamp := NOW();
        ELSE
            NEW.reset_password_token_timestamp := NULL;
        END IF;

        RETURN NEW;
    END IF;

    -- On update, bump timestamps iff value actually changed
    IF NEW.verify_token IS DISTINCT FROM OLD.verify_token THEN
        NEW.verify_token_timestamp := CASE WHEN NEW.verify_token IS NULL THEN NULL ELSE NOW() END;
    END IF;

    IF NEW.reset_password_token IS DISTINCT FROM OLD.reset_password_token THEN
        NEW.reset_password_token_timestamp := CASE WHEN NEW.reset_password_token IS NULL THEN NULL ELSE NOW() END;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Tables
-- ============================================

-- USERS
CREATE TABLE IF NOT EXISTS users (
    user_id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Identity
    display_name              VARCHAR(64) NOT NULL,
    username                  CITEXT      NOT NULL,
    email                     CITEXT      NOT NULL,

    profile_pic_url           VARCHAR(512),

    -- Auth
    hashed_password           TEXT        NOT NULL, -- allow Argon2/bcrypt variants
    verified                 BOOLEAN     NOT NULL DEFAULT FALSE,
    verify_token            TEXT,
    verify_token_timestamp  TIMESTAMPTZ,
    reset_password_token      TEXT,
    reset_password_token_timestamp TIMESTAMPTZ,

    -- Constraints
    CONSTRAINT users_username_uk UNIQUE (username),
    CONSTRAINT users_email_uk    UNIQUE (email),
    CONSTRAINT users_username_chk CHECK (username ~ '^[A-Za-z0-9_.-]{3,32}$'),
    CONSTRAINT users_email_chk    CHECK (position('@' IN email) > 1)
);

-- CONVERSATIONS
CREATE TABLE IF NOT EXISTS conversations (
    convo_id    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    name        VARCHAR(128) NOT NULL
);

-- MESSAGES
CREATE TABLE IF NOT EXISTS messages (
    message_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    convo_id     UUID        NOT NULL,
    sender_id    UUID,  -- nullable if you want to allow system messages
    type         content_type NOT NULL,

    -- Use TEXT + optional length check instead of VARCHAR(N)
    content      TEXT        NOT NULL,
    sender_name  VARCHAR(64),  -- optional denormalized snapshot
    sender_avatar VARCHAR(256),

    CONSTRAINT messages_convo_fk
        FOREIGN KEY (convo_id) REFERENCES conversations (convo_id)
        ON DELETE CASCADE,

    CONSTRAINT messages_sender_fk
        FOREIGN KEY (sender_id) REFERENCES users (user_id)
        ON DELETE SET NULL,

    -- If you want to cap message size, keep this:
    CONSTRAINT messages_content_len_chk CHECK (octet_length(content) <= 4096)
);

-- Optional: Session/socket table instead of embedding socket_id on users
-- Keeps users table purely identity/auth and moves volatile connection data out.
CREATE TABLE IF NOT EXISTS user_sessions (
    session_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id      UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    socket_id    TEXT NOT NULL UNIQUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- Indexes for common access patterns
-- ============================================
-- Foreign keys (Postgres doesn't auto-create these)
CREATE INDEX IF NOT EXISTS idx_messages_convo_id_created_at ON messages (convo_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON messages (sender_id);

-- Quick lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_username ON users (username);

-- ============================================
-- Triggers
-- ============================================
-- updated_at maintenance
DROP TRIGGER IF EXISTS trg_users_set_updated_at ON users;
CREATE TRIGGER trg_users_set_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_conversations_set_updated_at ON conversations;
CREATE TRIGGER trg_conversations_set_updated_at
BEFORE UPDATE ON conversations
FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_messages_set_updated_at ON messages;
CREATE TRIGGER trg_messages_set_updated_at
BEFORE UPDATE ON messages
FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

-- token timestamps
DROP TRIGGER IF EXISTS trg_users_token_timestamps ON users;
CREATE TRIGGER trg_users_token_timestamps
BEFORE INSERT OR UPDATE ON users
FOR EACH ROW EXECUTE PROCEDURE set_auth_token_timestamps();

-- bump conversation updated_at when messages are inserted/updated/deleted
DROP TRIGGER IF EXISTS trg_messages_touch_convo_ins ON messages;
CREATE TRIGGER trg_messages_touch_convo_ins
AFTER INSERT ON messages
FOR EACH ROW EXECUTE PROCEDURE touch_conversation_updated_at();

DROP TRIGGER IF EXISTS trg_messages_touch_convo_upd ON messages;
CREATE TRIGGER trg_messages_touch_convo_upd
AFTER UPDATE ON messages
FOR EACH ROW EXECUTE PROCEDURE touch_conversation_updated_at();

DROP TRIGGER IF EXISTS trg_messages_touch_convo_del ON messages;
CREATE TRIGGER trg_messages_touch_convo_del
AFTER DELETE ON messages
FOR EACH ROW EXECUTE PROCEDURE touch_conversation_updated_at();
