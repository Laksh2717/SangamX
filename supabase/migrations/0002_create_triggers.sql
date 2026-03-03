-- Generic function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to all tables
CREATE TRIGGER trigger_update_colleges_updated_at
BEFORE UPDATE ON colleges
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_update_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_update_organizations_updated_at
BEFORE UPDATE ON organizations
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_update_organization_teams_updated_at
BEFORE UPDATE ON organization_teams
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_update_organization_members_updated_at
BEFORE UPDATE ON organization_members
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_update_posts_updated_at
BEFORE UPDATE ON posts
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_update_recruitments_updated_at
BEFORE UPDATE ON recruitments
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_update_applications_updated_at
BEFORE UPDATE ON applications
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Function to auto-create Core team for new organizations
CREATE OR REPLACE FUNCTION create_core_team()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO organization_teams (organization_id, name, description)
  VALUES (NEW.id, 'Core', 'Core team for organization');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_create_core_team
AFTER INSERT ON organizations
FOR EACH ROW
EXECUTE FUNCTION create_core_team();

-- Function to handle application selection (add user to organization_members)
CREATE OR REPLACE FUNCTION handle_application_selection()
RETURNS TRIGGER AS $$
DECLARE
  v_recruitment_type text;
  v_organization_id uuid;
  v_team_id uuid;
  v_role text;
BEGIN
  -- Only process when status changes to 'selected' (UPDATE trigger, so OLD is never null)
  IF NEW.status = 'selected' AND OLD.status IS DISTINCT FROM 'selected' THEN
    
    -- Get recruitment details
    SELECT recruitment_type, organization_id INTO v_recruitment_type, v_organization_id
    FROM recruitments
    WHERE id = NEW.recruitment_id;
    
    -- Determine team_id and role based on recruitment type
    IF v_recruitment_type = 'core' THEN
      -- Get Core team ID
      SELECT id INTO v_team_id
      FROM organization_teams
      WHERE organization_id = v_organization_id AND name = 'Core'
      LIMIT 1;
      v_role := 'admin';
    ELSIF v_recruitment_type = 'team' THEN
      -- For team recruitment, team_id must be present on the application
      IF NEW.team_id IS NULL THEN
        RAISE EXCEPTION 'Team recruitment application must have team_id';
      END IF;
      v_team_id := NEW.team_id;
      v_role := 'member';
    ELSIF v_recruitment_type = 'volunteer' THEN
      v_team_id := NULL;
      v_role := 'volunteer';
    ELSE -- spoc
      v_team_id := NULL;
      v_role := 'spoc';
    END IF;
    
    -- For admin/member roles, use ON CONFLICT (team_id is NOT NULL, so unique constraint works)
    IF v_recruitment_type IN ('core', 'team') THEN
      INSERT INTO organization_members (organization_id, team_id, user_id, role, status)
      VALUES (v_organization_id, v_team_id, NEW.student_id, v_role, 'active')
      ON CONFLICT (user_id, organization_id, team_id) DO UPDATE
      SET status = 'active', role = EXCLUDED.role, ended_at = NULL;
    ELSE
      -- For volunteer/spoc, team_id is NULL; NULL != NULL in unique constraints
      -- so we must manually check and upsert to avoid duplicates
      UPDATE organization_members
      SET status = 'active', role = v_role, ended_at = NULL
      WHERE user_id = NEW.student_id
        AND organization_id = v_organization_id
        AND team_id IS NULL;
      
      IF NOT FOUND THEN
        INSERT INTO organization_members (organization_id, team_id, user_id, role, status)
        VALUES (v_organization_id, NULL, NEW.student_id, v_role, 'active');
      END IF;
    END IF;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

CREATE TRIGGER trigger_handle_application_selection
AFTER UPDATE ON applications
FOR EACH ROW
EXECUTE FUNCTION handle_application_selection();

-- Function to handle application rejection (mark membership as removed)
CREATE OR REPLACE FUNCTION handle_application_rejection()
RETURNS TRIGGER AS $$
DECLARE
  v_organization_id uuid;
  v_team_id uuid;
  v_recruitment_type text;
BEGIN
  -- Only process when status changes to 'rejected' from 'selected'
  IF NEW.status = 'rejected' AND OLD.status = 'selected' THEN
    
    -- Get recruitment details
    SELECT organization_id, recruitment_type INTO v_organization_id, v_recruitment_type
    FROM recruitments
    WHERE id = NEW.recruitment_id;
    
    -- Determine team_id based on recruitment type (must match selection logic)
    IF v_recruitment_type = 'core' THEN
      SELECT id INTO v_team_id
      FROM organization_teams
      WHERE organization_id = v_organization_id AND name = 'Core'
      LIMIT 1;
    ELSIF v_recruitment_type = 'team' THEN
      v_team_id := NEW.team_id;
    ELSE
      -- For volunteer and spoc, team_id is null
      v_team_id := NULL;
    END IF;
    
    -- Mark the corresponding membership as removed and set ended_at
    UPDATE organization_members
    SET status = 'removed', ended_at = NOW()
    WHERE user_id = NEW.student_id
      AND organization_id = v_organization_id
      AND team_id IS NOT DISTINCT FROM v_team_id;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

CREATE TRIGGER trigger_handle_application_rejection
AFTER UPDATE ON applications
FOR EACH ROW
EXECUTE FUNCTION handle_application_rejection();
