-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create colleges table
CREATE TABLE colleges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  slug text NOT NULL UNIQUE,
  address text,
  contact_no text,
  description text,
  website_url text,
  logo_url text,
  admin_user_id uuid,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

CREATE INDEX idx_colleges_slug ON colleges(slug);
CREATE INDEX idx_colleges_admin_user_id ON colleges(admin_user_id);

-- Create users table
CREATE TABLE users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  email text NOT NULL UNIQUE,
  college_id uuid NOT NULL REFERENCES colleges(id) ON DELETE RESTRICT,
  role text NOT NULL DEFAULT 'student' CHECK (role IN ('student', 'college_admin')),
  roll_no text,
  bio text,
  avatar_url text,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_college_id ON users(college_id);

-- Set up foreign key for colleges.admin_user_id
ALTER TABLE colleges
ADD CONSTRAINT fk_colleges_admin_user_id
FOREIGN KEY (admin_user_id) REFERENCES users(id) ON DELETE SET NULL;

-- Create organizations table
CREATE TABLE organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  college_id uuid NOT NULL REFERENCES colleges(id) ON DELETE CASCADE,
  name text NOT NULL,
  slug text NOT NULL,
  description text,
  logo_url text,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW(),
  UNIQUE(college_id, slug)
);

CREATE INDEX idx_organizations_college_id ON organizations(college_id);

-- Create organization_teams table
CREATE TABLE organization_teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

CREATE INDEX idx_organization_teams_organization_id ON organization_teams(organization_id);

-- Create organization_members table
CREATE TABLE organization_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  team_id uuid REFERENCES organization_teams(id) ON DELETE SET NULL,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('admin', 'member', 'volunteer', 'spoc')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'removed')),
  ended_at timestamptz,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW(),
  UNIQUE(user_id, organization_id, team_id),
  CHECK (
    (role IN ('admin', 'member') AND team_id IS NOT NULL) OR
    (role IN ('volunteer', 'spoc') AND team_id IS NULL)
  )
);

CREATE INDEX idx_organization_members_organization_id ON organization_members(organization_id);
CREATE INDEX idx_organization_members_user_id ON organization_members(user_id);
CREATE INDEX idx_organization_members_team_id ON organization_members(team_id);

-- Create posts table
CREATE TABLE posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  college_id uuid NOT NULL REFERENCES colleges(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  title text NOT NULL,
  content text NOT NULL,
  author_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  images text[] DEFAULT ARRAY[]::text[],
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

CREATE INDEX idx_posts_college_id ON posts(college_id);
CREATE INDEX idx_posts_organization_id ON posts(organization_id);
CREATE INDEX idx_posts_author_id ON posts(author_id);

-- Create recruitments table
CREATE TABLE recruitments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  college_id uuid NOT NULL REFERENCES colleges(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  recruitment_type text NOT NULL CHECK (recruitment_type IN ('core', 'team', 'volunteer', 'spoc')),
  title text NOT NULL,
  description text,
  deadline timestamptz,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

CREATE INDEX idx_recruitments_college_id ON recruitments(college_id);
CREATE INDEX idx_recruitments_organization_id ON recruitments(organization_id);
CREATE INDEX idx_recruitments_status ON recruitments(status);

-- Create applications table
CREATE TABLE applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recruitment_id uuid NOT NULL REFERENCES recruitments(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  team_id uuid REFERENCES organization_teams(id) ON DELETE CASCADE,
  reviewed_by uuid REFERENCES users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'selected', 'rejected')),
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW(),
  UNIQUE(student_id, recruitment_id, team_id)
);

CREATE INDEX idx_applications_recruitment_id ON applications(recruitment_id);
CREATE INDEX idx_applications_student_id ON applications(student_id);
CREATE INDEX idx_applications_team_id ON applications(team_id);
CREATE INDEX idx_applications_status ON applications(status);
