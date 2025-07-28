-- Migration script to add new columns to existing galaxy_comment table
-- Run this on existing databases to add the new fields

-- Add galaxy_class column if it doesn't exist
ALTER TABLE galaxy_comment ADD COLUMN galaxy_class INTEGER DEFAULT 0;

-- Add checkboxes column if it doesn't exist  
ALTER TABLE galaxy_comment ADD COLUMN checkboxes INTEGER DEFAULT 0;

-- Update any existing NULL values to defaults
UPDATE galaxy_comment SET galaxy_class = 0 WHERE galaxy_class IS NULL;
UPDATE galaxy_comment SET checkboxes = 0 WHERE checkboxes IS NULL;