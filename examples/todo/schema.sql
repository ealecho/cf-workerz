-- Todo API Schema
-- Run: npx wrangler d1 execute DB --local --file=schema.sql

-- Todos table
CREATE TABLE IF NOT EXISTS todos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    completed INTEGER NOT NULL DEFAULT 0,
    priority TEXT NOT NULL DEFAULT 'medium',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

-- Index for listing by completion status
CREATE INDEX IF NOT EXISTS idx_todos_completed ON todos(completed);

-- Index for listing by priority
CREATE INDEX IF NOT EXISTS idx_todos_priority ON todos(priority);

-- Insert some sample data
INSERT INTO todos (title, description, completed, priority, created_at, updated_at)
VALUES 
    ('Learn Zig', 'Complete the Zig tutorial and build a project', 0, 'high', strftime('%s', 'now'), strftime('%s', 'now')),
    ('Build a Worker', 'Create a Cloudflare Worker with cf-workerz', 0, 'high', strftime('%s', 'now'), strftime('%s', 'now')),
    ('Write tests', 'Add unit tests for the API', 0, 'medium', strftime('%s', 'now'), strftime('%s', 'now')),
    ('Deploy to production', 'Deploy the worker to Cloudflare', 0, 'low', strftime('%s', 'now'), strftime('%s', 'now'));
