-- migrations/YYYYMMDDHHMMSS_create_tasks_table.sql

-- Create the users table first, as tasks will reference it.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE TABLE users (
    id UUID PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE
);

-- Create the tasks table with a foreign key constraint.
CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id), -- This enforces the relationship
    title VARCHAR(255) NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- IMPORTANT: Insert the hardcoded test user that our application code uses.
INSERT INTO users (id, username) VALUES ('d34cf7ec-2278-422b-87f0-98de79c06bcd', 'testuser');