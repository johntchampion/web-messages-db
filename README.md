# Web Messages - Database

PostgreSQL database schema and initialization scripts for a messaging application that supports user authentication, conversations, and real-time messaging.

## Overview

This database provides the complete data layer for a messaging application, including:

- User accounts with email verification and password reset
- Conversations with automatic 30-day expiration
- Messages with text and image support
- Session management for refresh tokens
- Automatic timestamp management via triggers

## Features

- **User Management**: Email/username authentication with bcrypt password hashing
- **Conversation System**: Link-based conversations with automatic cleanup
- **Message Storage**: Text and image messages with sender tracking
- **Session Tracking**: Refresh token management for secure authentication
- **CITEXT Support**: Case-insensitive email/username lookups
- **UUID Primary Keys**: Globally unique identifiers for all entities
- **Automatic Timestamps**: Database triggers maintain `created_at` and `updated_at` fields
- **Token Versioning**: Automatic invalidation of tokens on password change

## Database Schema

### Tables

**users**

- `user_id` (UUID, Primary Key)
- `email` (CITEXT, Unique) - Case-insensitive email
- `username` (CITEXT, Unique) - Case-insensitive username
- `password` (VARCHAR) - bcrypt hashed password
- `verified` (BOOLEAN) - Email verification status
- `verify_token` (VARCHAR) - 6-digit verification code
- `verify_token_timestamp` (TIMESTAMP) - Token expiry tracking
- `reset_password_token` (VARCHAR) - Password reset token
- `reset_password_token_timestamp` (TIMESTAMP) - Reset token expiry
- `token_version` (INTEGER) - Increments on password change to invalidate all tokens
- `socket_id` (VARCHAR) - Current Socket.IO connection ID
- `created_at` (TIMESTAMP)
- `updated_at` (TIMESTAMP)

**conversations**

- `convo_id` (UUID, Primary Key)
- `name` (VARCHAR) - Conversation display name
- `created_by` (UUID, Foreign Key) - User who created the conversation
- `created_at` (TIMESTAMP)
- `updated_at` (TIMESTAMP) - Used for 30-day expiration

**messages**

- `message_id` (UUID, Primary Key)
- `convo_id` (UUID, Foreign Key) - Parent conversation
- `sender_id` (UUID, Foreign Key, Nullable) - Authenticated user sender
- `sender_name` (VARCHAR, Nullable) - Anonymous sender name
- `sender_avatar` (INTEGER, Nullable) - Anonymous sender avatar ID
- `content` (TEXT) - Message content (max 4096 bytes)
- `type` (VARCHAR) - 'text' or 'image'
- `created_at` (TIMESTAMP)
- `updated_at` (TIMESTAMP)

**sessions**

- `session_id` (UUID, Primary Key)
- `user_id` (UUID, Foreign Key) - Associated user
- `token_version` (INTEGER) - Token version at creation time
- `created_at` (TIMESTAMP)
- `updated_at` (TIMESTAMP)

### Database Triggers

- `update_updated_at_timestamp` - Automatically updates `updated_at` on row changes
- `update_token_timestamp` - Updates token timestamps when verification/reset tokens are set

## Prerequisites

- Docker and Docker Compose (for containerized setup)
- OR PostgreSQL 12+ (for local installation)

## Environment Variables

Configure these environment variables before running the database:

| Variable          | Description                    | Default     | Required |
| ----------------- | ------------------------------ | ----------- | -------- |
| POSTGRES_USER     | PostgreSQL database user       | user        | Yes      |
| POSTGRES_PASSWORD | Password for the database user | password1   | Yes      |
| POSTGRES_DB       | Database name                  | messages_db | Yes      |

## Running with Docker

### Development Setup

Build the Docker image:

```bash
docker build -t messages-db .
```

Run the container:

```bash
docker run -p 5432:5432 --name messages-db -d \
    -e POSTGRES_USER=user \
    -e POSTGRES_PASSWORD=password1 \
    -e POSTGRES_DB=messages_db \
    messages-db
```

### Access the Database

Connect to the running container:

```bash
docker exec -it messages-db bash
```

Access PostgreSQL CLI:

```bash
psql -U user -d messages_db
```

### Useful PostgreSQL Commands

```sql
-- List all tables
\dt

-- Describe table structure
\d users
\d conversations
\d messages
\d sessions

-- View all users
SELECT user_id, email, username, verified, created_at FROM users;

-- View recent conversations
SELECT convo_id, name, created_at, updated_at FROM conversations ORDER BY updated_at DESC LIMIT 10;

-- Count messages per conversation
SELECT c.name, COUNT(m.message_id) as message_count
FROM conversations c
LEFT JOIN messages m ON c.convo_id = m.convo_id
GROUP BY c.convo_id, c.name;
```

## Running Without Docker

If you have PostgreSQL installed locally:

1. Create a database:

   ```bash
   createdb -U postgres messages_db
   ```

2. Run the setup script:
   ```bash
   psql -U postgres -d messages_db -f setup.sql
   ```

## Data Persistence

When running with Docker, database data is stored in a Docker volume. To persist data between container restarts:

```bash
docker run -p 5432:5432 --name messages-db -d \
    -e POSTGRES_USER=user \
    -e POSTGRES_PASSWORD=password1 \
    -e POSTGRES_DB=messages_db \
    -v postgres_data:/var/lib/postgresql/data \
    messages-db
```

## Troubleshooting

### Port Already in Use

If port 5432 is already in use:

```bash
# Check what's using the port
lsof -i :5432

# Use a different port
docker run -p 5433:5432 --name messages-db -d ...
```

### Connection Refused

Ensure the container is running and healthy:

```bash
docker ps
docker logs messages-db
```

### Schema Changes

To apply schema changes:

1. Stop and remove the existing container:

   ```bash
   docker stop messages-db
   docker rm messages-db
   ```

2. Rebuild the image and run a new container:
   ```bash
   docker build -t messages-db .
   docker run -p 5432:5432 --name messages-db -d ...
   ```

### Reset Database

To start fresh:

```bash
docker stop messages-db
docker rm messages-db
docker volume rm postgres_data  # If using named volume
```

## Security Considerations

- Change default passwords in production
- Use strong passwords for `POSTGRES_PASSWORD`
- Restrict network access to database port
- Use SSL/TLS connections in production
- Regularly backup database data
- Keep PostgreSQL updated to latest version

## Schema Maintenance

The `setup.sql` file contains the complete database schema including:

- Table definitions with constraints
- Foreign key relationships with CASCADE deletes
- Indexes for performance optimization
- Database triggers for automatic field management
- CITEXT extension for case-insensitive fields

Any modifications to the schema should be made in `setup.sql` and tested thoroughly before deployment.
