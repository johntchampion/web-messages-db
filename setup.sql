CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE content_type AS ENUM ('text', 'image');

CREATE TABLE users (
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    socket_id VARCHAR(32),
    display_name VARCHAR(64) NOT NULL,
    username VARCHAR(64) NOT NULL,
    email VARCHAR(128) NOT NULL,
    profile_pic_url VARCHAR(256),
    hashed_password VARCHAR(128) NOT NULL,
    activated BOOLEAN NOT NULL DEFAULT false,
    activate_token VARCHAR(128),
    activate_token_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    reset_password_token VARCHAR(128),
    reset_password_token_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    user_id UUID PRIMARY KEY NOT NULL DEFAULT uuid_generate_v4(),
    UNIQUE(email),
    UNIQUE(username)
);

CREATE TABLE conversations (
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    convo_id UUID PRIMARY KEY NOT NULL DEFAULT uuid_generate_v4(),
    name VARCHAR(128) NOT NULL
);

CREATE TABLE messages (
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    message_id UUID PRIMARY KEY NOT NULL DEFAULT uuid_generate_v4(),
    convo_id UUID,
    content VARCHAR(4096) NOT NULL,
    type content_type NOT NULL,
    sender_name VARCHAR(32),
    sender_avatar VARCHAR(16),
    FOREIGN KEY (convo_id) REFERENCES conversations (convo_id) ON DELETE CASCADE
);

CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.* IS DISTINCT FROM OLD.* THEN
        NEW.updated_at = NOW(); 
        RETURN NEW;
    ELSE
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations
    SET updated_at = NOW()
    WHERE convo_id = NEW.convo_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_auth_timestamps()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.activate_token IS DISTINCT FROM OLD.activate_token THEN
        NEW.activate_token_timestamp = NOW();
    END IF;

    IF NEW.reset_password_token IS DISTINCT FROM OLD.reset_password_token THEN
        NEW.reset_password_token_timestamp = NOW();
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_auth_timestamps BEFORE INSERT OR UPDATE ON users
FOR EACH ROW EXECUTE PROCEDURE update_auth_timestamps();

CREATE TRIGGER update_timestamp BEFORE UPDATE ON users
FOR EACH ROW EXECUTE PROCEDURE update_timestamp();

CREATE TRIGGER update_timestamp_messages BEFORE UPDATE ON messages
FOR EACH ROW EXECUTE PROCEDURE update_timestamp();

CREATE TRIGGER update_timestamp_conversations BEFORE UPDATE ON conversations
FOR EACH ROW EXECUTE PROCEDURE update_timestamp();

CREATE TRIGGER update_conversation_timestamp_trigger AFTER INSERT ON messages
FOR EACH ROW EXECUTE PROCEDURE update_conversation_timestamp();