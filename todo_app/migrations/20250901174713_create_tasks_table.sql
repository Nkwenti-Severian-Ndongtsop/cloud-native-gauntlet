-- migrations/YYYYMMDDHHMMSS_create_tasks_table.sql

-- Create the tasks table without a users table; user_id comes from Keycloak token
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    title VARCHAR(255) NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);