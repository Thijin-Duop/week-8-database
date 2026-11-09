-- =========================================================================
-- MASTER ANSWER.SQL: COMBINED LABS & CAPSTONE SCRIPT
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. BACKUP & REPLICATION COMMANDS (Run in terminal, kept here as reference)
-- -------------------------------------------------------------------------
/*
  # Logical Backup:
  \! mkdir -p ~/backups
  \! pg_dump -Fc -f ~/backups/bootcamp.dump bootcamp
  
  # WAL Archiving / Base Backup:
  \! pg_basebackup -D ~/backups/base -Ft -z -Xs -P
*/

-- -------------------------------------------------------------------------
-- 2. AUDIT LOGGING SYSTEM
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tbl TEXT,
  op TEXT,
  old_row JSONB,
  new_row JSONB,
  changed_by TEXT DEFAULT current_user,
  at TIMESTAMPTZ DEFAULT now()
);

CREATE OR REPLACE FUNCTION audit() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log(tbl, op, old_row, new_row)
  VALUES (
    TG_TABLE_NAME,
    TG_OP,
    to_jsonb(OLD),
    to_jsonb(NEW)
  );
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS students (
  id SERIAL PRIMARY KEY,
  name TEXT
);

DROP TRIGGER IF EXISTS trg_audit ON students;
CREATE TRIGGER trg_audit
AFTER INSERT OR UPDATE OR DELETE
ON students
FOR EACH ROW
EXECUTE FUNCTION audit();

-- Test Audit Trail Data
INSERT INTO students (id, name) VALUES (1, 'Alice'), (3, 'Bob') ON CONFLICT DO NOTHING;
UPDATE students SET name = 'Kofi M.' WHERE id = 1;
DELETE FROM students WHERE id = 3;


-- -------------------------------------------------------------------------
-- 3. HIERARCHICAL CATEGORY TREE (Recursive CTE)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS categories (
  id SERIAL PRIMARY KEY,
  name TEXT,
  parent_id INT REFERENCES categories(id)
);

INSERT INTO categories (name, parent_id) VALUES
  ('Electronics', NULL),
  ('Computers', 1),
  ('Laptops', 2),
  ('Phones', 1)
ON CONFLICT DO NOTHING;

-- Query tree
WITH RECURSIVE tree AS (
  SELECT id, name, parent_id, 0 AS depth
  FROM categories
  WHERE parent_id IS NULL
  UNION ALL
  SELECT c.id, c.name, c.parent_id, t.depth + 1
  FROM categories c
  JOIN tree t ON c.parent_id = t.id
)
SELECT repeat('  ', depth) || name AS tree_view
FROM tree
ORDER BY depth, name;


-- -------------------------------------------------------------------------
-- 4. CAPSTONE CORE SCHEMA MIGRATIONS (V1 - V5)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    role TEXT NOT NULL DEFAULT 'member',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    status TEXT DEFAULT 'todo',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for Optimization
CREATE INDEX IF NOT EXISTS idx_users_org_id ON users(org_id);
CREATE INDEX IF NOT EXISTS idx_projects_org_id ON projects(org_id);
CREATE INDEX IF NOT EXISTS idx_tasks_project_id ON tasks(project_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to ON tasks(assigned_to);


-- -------------------------------------------------------------------------
-- 5. ROW-LEVEL SECURITY (RLS)
-- -------------------------------------------------------------------------
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_isolation_policy ON projects;
CREATE POLICY tenant_isolation_policy ON projects
    FOR ALL
    USING (org_id = nullif(current_setting('app.current_org_id', true), '')::uuid);


-- -------------------------------------------------------------------------
-- 6. LEAST-PRIVILEGE SECURITY ROLES & USERS
-- -------------------------------------------------------------------------
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_read') THEN
    CREATE ROLE app_read;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_write') THEN
    CREATE ROLE app_write;
  END IF;
END $$;

GRANT CONNECT ON DATABASE bootcamp TO app_read, app_write;
GRANT USAGE ON SCHEMA public TO app_read, app_write;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_read;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_write;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_read;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_write;

DO $$ 
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = 'api') THEN
    CREATE USER api LOGIN PASSWORD 'strong-secret' IN ROLE app_write;
  END IF;
END $$;
