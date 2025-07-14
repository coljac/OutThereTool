-- PostgreSQL Database Schema for OutThereTool Backend

CREATE TABLE IF NOT EXISTS galaxy (
    id TEXT PRIMARY KEY,
    status INTEGER NOT NULL,
    redshift NUMERIC,
    filters INTEGER DEFAULT 1,
    field VARCHAR(255) NULL
);

CREATE TABLE IF NOT EXISTS galaxy_comment (
    galaxy_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    status INTEGER NOT NULL,
    redshift NUMERIC NULL,
    comment TEXT NULL,
    updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (galaxy_id, user_id),
    FOREIGN KEY (galaxy_id) REFERENCES galaxy(id) ON DELETE CASCADE
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_galaxy_comment_galaxy_id ON galaxy_comment(galaxy_id);
CREATE INDEX IF NOT EXISTS idx_galaxy_comment_user_id ON galaxy_comment(user_id);
CREATE INDEX IF NOT EXISTS idx_galaxy_comment_updated ON galaxy_comment(updated);