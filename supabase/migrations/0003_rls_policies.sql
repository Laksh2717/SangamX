-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================
-- Get current user's college_id without triggering RLS recursion
CREATE OR REPLACE FUNCTION get_user_college_id(user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT college_id FROM users WHERE id = user_id LIMIT 1;
$$;

-- Get user's organization IDs (for non-recursive RLS checks)
CREATE OR REPLACE FUNCTION get_user_organization_ids(user_id uuid)
RETURNS TABLE (organization_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT om.organization_id FROM organization_members om
  WHERE om.user_id = user_id AND om.status = 'active';
$$;

-- ============================================================================
-- ENABLE ROW LEVEL SECURITY ON ALL TABLES
-- ============================================================================
ALTER TABLE colleges ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE recruitments ENABLE ROW LEVEL SECURITY;
ALTER TABLE applications ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- COLLEGES TABLE POLICIES
-- ============================================================================
-- All authenticated users can view colleges
CREATE POLICY "Colleges: All authenticated users can view"
  ON colleges
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- College admins can update their own college
CREATE POLICY "Colleges: Admin can update own college"
  ON colleges
  FOR UPDATE
  USING (
    admin_user_id = auth.uid()
  )
  WITH CHECK (
    admin_user_id = auth.uid()
  );

-- ============================================================================
-- USERS TABLE POLICIES
-- ============================================================================
-- Users can view other users in their college and their own profile
CREATE POLICY "Users: Can view users in own college"
  ON users
  FOR SELECT
  USING (
    college_id = get_user_college_id(auth.uid())
  );

-- Users can insert their own profile during registration
CREATE POLICY "Users: Can insert own profile"
  ON users
  FOR INSERT
  WITH CHECK (
    id = auth.uid()
  );

-- Users can update only their own profile
CREATE POLICY "Users: Can update own profile"
  ON users
  FOR UPDATE
  USING (
    id = auth.uid()
  )
  WITH CHECK (
    id = auth.uid()
  );

-- ============================================================================
-- ORGANIZATIONS TABLE POLICIES
-- ============================================================================
-- Users can view organizations in their college
CREATE POLICY "Organizations: Can view organizations in own college"
  ON organizations
  FOR SELECT
  USING (
    college_id = get_user_college_id(auth.uid())
  );

-- College admin can create organizations in their college
CREATE POLICY "Organizations: College admin can create"
  ON organizations
  FOR INSERT
  WITH CHECK (
    college_id = get_user_college_id(auth.uid()) AND
    EXISTS (
      SELECT 1 FROM users WHERE id = auth.uid() AND role = 'college_admin'
    )
  );

-- Organization admin can update their organization
CREATE POLICY "Organizations: Admin can update own organization"
  ON organizations
  FOR UPDATE
  USING (
    id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    )
  )
  WITH CHECK (
    id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    )
  );

-- College admin can delete organizations in their college
CREATE POLICY "Organizations: College admin can delete"
  ON organizations
  FOR DELETE
  USING (
    college_id = get_user_college_id(auth.uid()) AND
    EXISTS (
      SELECT 1 FROM users WHERE id = auth.uid() AND role = 'college_admin'
    )
  );

-- ============================================================================
-- ORGANIZATION_TEAMS TABLE POLICIES
-- ============================================================================
-- Users can view teams of organizations in their college
CREATE POLICY "Teams: Can view teams from college organizations"
  ON organization_teams
  FOR SELECT
  USING (
    organization_id IN (
      SELECT id FROM organizations WHERE college_id = get_user_college_id(auth.uid())
    )
  );

-- Organization admin can create teams
CREATE POLICY "Teams: Org admin can create"
  ON organization_teams
  FOR INSERT
  WITH CHECK (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    )
  );

-- Organization admin can update teams
CREATE POLICY "Teams: Org admin can update"
  ON organization_teams
  FOR UPDATE
  USING (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    )
  )
  WITH CHECK (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    )
  );

-- ============================================================================
-- ORGANIZATION_MEMBERS TABLE POLICIES
-- ============================================================================
-- All college users can view admin/member roles (public members)
CREATE POLICY "Members: All can view admin and member roles"
  ON organization_members
  FOR SELECT
  USING (
    role IN ('admin', 'member') AND
    status = 'active' AND
    organization_id IN (
      SELECT id FROM organizations WHERE college_id = get_user_college_id(auth.uid())
    )
  );

-- Organization members can view all roles (including volunteer/spoc) in their org
CREATE POLICY "Members: Org members can view all roles in their org"
  ON organization_members
  FOR SELECT
  USING (
    organization_id IN (
      SELECT organization_id FROM get_user_organization_ids(auth.uid())
    )
  );

-- Organization admin can add members
CREATE POLICY "Members: Org admin can add members"
  ON organization_members
  FOR INSERT
  WITH CHECK (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    ) OR
    -- College admin can add core members
    (
      role = 'admin' AND
      team_id = (
        SELECT id FROM organization_teams
        WHERE organization_id = organization_members.organization_id AND name = 'Core' LIMIT 1
      ) AND
      EXISTS (
        SELECT 1 FROM users WHERE id = auth.uid() AND role = 'college_admin'
      )
    )
  );

-- Organization admin can update members (change role, status)
CREATE POLICY "Members: Org admin can update members"
  ON organization_members
  FOR UPDATE
  USING (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    ) OR
    -- College admin can update core members
    (
      role = 'admin' AND
      team_id = (
        SELECT id FROM organization_teams
        WHERE organization_id = organization_members.organization_id AND name = 'Core' LIMIT 1
      ) AND
      EXISTS (
        SELECT 1 FROM users WHERE id = auth.uid() AND role = 'college_admin'
      )
    )
  )
  WITH CHECK (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    ) OR
    -- College admin can update core members
    (
      role = 'admin' AND
      team_id = (
        SELECT id FROM organization_teams
        WHERE organization_id = organization_members.organization_id AND name = 'Core' LIMIT 1
      ) AND
      EXISTS (
        SELECT 1 FROM users WHERE id = auth.uid() AND role = 'college_admin'
      )
    )
  );

-- Organization admin can delete members
CREATE POLICY "Members: Org admin can delete members"
  ON organization_members
  FOR DELETE
  USING (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    ) OR
    -- College admin can delete core members
    (
      role = 'admin' AND
      team_id = (
        SELECT id FROM organization_teams
        WHERE organization_id = organization_members.organization_id AND name = 'Core' LIMIT 1
      ) AND
      EXISTS (
        SELECT 1 FROM users WHERE id = auth.uid() AND role = 'college_admin'
      )
    )
  );

-- ============================================================================
-- POSTS TABLE POLICIES
-- ============================================================================
-- Users can view posts from organizations in their college
CREATE POLICY "Posts: Can view posts from college organizations"
  ON posts
  FOR SELECT
  USING (
    college_id = get_user_college_id(auth.uid())
  );

-- Organization admin or college admin can create posts
CREATE POLICY "Posts: Org admin or college admin can create"
  ON posts
  FOR INSERT
  WITH CHECK (
    college_id = get_user_college_id(auth.uid()) AND (
      -- Organization admin check
      organization_id IN (
        SELECT organization_id FROM organization_members
        WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
      ) OR
      -- College admin check
      EXISTS (
        SELECT 1 FROM users WHERE id = auth.uid() AND role = 'college_admin'
      )
    )
  );

-- College admin or post author can update
CREATE POLICY "Posts: Author or college admin can update"
  ON posts
  FOR UPDATE
  USING (
    author_id = auth.uid() OR (
      college_id = get_user_college_id(auth.uid()) AND
      EXISTS (
        SELECT 1 FROM users WHERE id = auth.uid() AND role = 'college_admin'
      )
    )
  )
  WITH CHECK (
    author_id = auth.uid() OR (
      college_id = get_user_college_id(auth.uid()) AND
      EXISTS (
        SELECT 1 FROM users WHERE id = auth.uid() AND role = 'college_admin'
      )
    )
  );

-- College admin or post author can delete
CREATE POLICY "Posts: Author or college admin can delete"
  ON posts
  FOR DELETE
  USING (
    author_id = auth.uid() OR (
      college_id = get_user_college_id(auth.uid()) AND
      EXISTS (
        SELECT 1 FROM users WHERE id = auth.uid() AND role = 'college_admin'
      )
    )
  );

-- ============================================================================
-- RECRUITMENTS TABLE POLICIES
-- ============================================================================
-- Users can view open/closed recruitments from organizations in their college
CREATE POLICY "Recruitments: Can view recruitments from college organizations"
  ON recruitments
  FOR SELECT
  USING (
    college_id = get_user_college_id(auth.uid())
  );

-- Organization admin can create recruitments
CREATE POLICY "Recruitments: Org admin can create"
  ON recruitments
  FOR INSERT
  WITH CHECK (
    college_id = get_user_college_id(auth.uid()) AND
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    )
  );

-- Organization admin can update recruitments
CREATE POLICY "Recruitments: Org admin can update"
  ON recruitments
  FOR UPDATE
  USING (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    )
  )
  WITH CHECK (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    )
  );

-- ============================================================================
-- APPLICATIONS TABLE POLICIES
-- ============================================================================
-- Students can view their own applications
CREATE POLICY "Applications: Students can view own applications"
  ON applications
  FOR SELECT
  USING (
    student_id = auth.uid()
  );

-- Organization admin can view applications for their organization
CREATE POLICY "Applications: Org admin can view applications"
  ON applications
  FOR SELECT
  USING (
    recruitment_id IN (
      SELECT id FROM recruitments WHERE organization_id IN (
        SELECT organization_id FROM organization_members
        WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
      )
    )
  );

-- Students can create applications
CREATE POLICY "Applications: Students can create applications"
  ON applications
  FOR INSERT
  WITH CHECK (
    student_id = auth.uid() AND recruitment_id IN (
      SELECT id FROM recruitments 
      WHERE college_id = get_user_college_id(auth.uid()) AND status = 'open'
    )
  );

-- Organization admin can update application status (for selection/rejection)
CREATE POLICY "Applications: Org admin can update application status"
  ON applications
  FOR UPDATE
  USING (
    recruitment_id IN (
      SELECT id FROM recruitments WHERE organization_id IN (
        SELECT organization_id FROM organization_members
        WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
      )
    )
  )
  WITH CHECK (
    recruitment_id IN (
      SELECT id FROM recruitments WHERE organization_id IN (
        SELECT organization_id FROM organization_members
        WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
      )
    )
  );
