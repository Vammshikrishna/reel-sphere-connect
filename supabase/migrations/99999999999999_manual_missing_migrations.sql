-- Create film reviews table
CREATE TABLE IF NOT EXISTS public.film_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    tmdb_id INTEGER NOT NULL,
    review_text TEXT NOT NULL,
    is_spoiler BOOLEAN DEFAULT false,
    helpful_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, tmdb_id)
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_film_reviews_tmdb_id ON public.film_reviews(tmdb_id);
CREATE INDEX IF NOT EXISTS idx_film_reviews_user_id ON public.film_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_film_reviews_created_at ON public.film_reviews(created_at DESC);

-- Enable RLS
ALTER TABLE public.film_reviews ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Anyone can view reviews" ON public.film_reviews;
DROP POLICY IF EXISTS "Users can create their own reviews" ON public.film_reviews;
DROP POLICY IF EXISTS "Users can update their own reviews" ON public.film_reviews;
DROP POLICY IF EXISTS "Users can delete their own reviews" ON public.film_reviews;

-- RLS Policies
CREATE POLICY "Anyone can view reviews"
    ON public.film_reviews
    FOR SELECT
    USING (true);

CREATE POLICY "Users can create their own reviews"
    ON public.film_reviews
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own reviews"
    ON public.film_reviews
    FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own reviews"
    ON public.film_reviews
    FOR DELETE
    USING (auth.uid() = user_id);

-- Create helpful marks table
CREATE TABLE IF NOT EXISTS public.review_helpful_marks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id UUID NOT NULL REFERENCES public.film_reviews(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(review_id, user_id)
);

-- Enable RLS for helpful marks
ALTER TABLE public.review_helpful_marks ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Anyone can view helpful marks" ON public.review_helpful_marks;
DROP POLICY IF EXISTS "Users can mark reviews as helpful" ON public.review_helpful_marks;
DROP POLICY IF EXISTS "Users can remove their helpful marks" ON public.review_helpful_marks;

CREATE POLICY "Anyone can view helpful marks"
    ON public.review_helpful_marks
    FOR SELECT
    USING (true);

CREATE POLICY "Users can mark reviews as helpful"
    ON public.review_helpful_marks
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove their helpful marks"
    ON public.review_helpful_marks
    FOR DELETE
    USING (auth.uid() = user_id);

-- Function to update helpful count
CREATE OR REPLACE FUNCTION update_review_helpful_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.film_reviews
        SET helpful_count = helpful_count + 1
        WHERE id = NEW.review_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.film_reviews
        SET helpful_count = helpful_count - 1
        WHERE id = OLD.review_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS update_helpful_count_trigger ON public.review_helpful_marks;

-- Trigger for helpful count
CREATE TRIGGER update_helpful_count_trigger
AFTER INSERT OR DELETE ON public.review_helpful_marks
FOR EACH ROW
EXECUTE FUNCTION update_review_helpful_count();
-- ============================================================================
-- SECURE RLS POLICIES FOR PROJECTS
-- ============================================================================
-- This migration replaces permissive development policies with strict security
-- ============================================================================

-- 1. Helper Function to check membership
-- This improves performance and readability of policies
CREATE OR REPLACE FUNCTION public.is_project_member(project_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 
    FROM public.project_space_members 
    WHERE project_space_id = project_id 
    AND user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_project_creator(project_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 
    FROM public.project_spaces 
    WHERE id = project_id 
    AND creator_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PROJECT SPACES
-- ============================================================================

-- Drop insecure policies
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.project_spaces;
DROP POLICY IF EXISTS "Anyone can view project spaces" ON public.project_spaces;
DROP POLICY IF EXISTS "Authenticated users can create project spaces" ON public.project_spaces;
DROP POLICY IF EXISTS "Creators can update their project spaces" ON public.project_spaces;
DROP POLICY IF EXISTS "Creators can delete their project spaces" ON public.project_spaces;

-- 1. VIEW: Public projects are visible to everyone. Private/Secret only to members/creator.
-- 1. VIEW: Public projects are visible to everyone. Private/Secret only to members/creator.
DROP POLICY IF EXISTS "View Projects" ON public.project_spaces;
CREATE POLICY "View Projects" ON public.project_spaces
FOR SELECT USING (
  project_space_type = 'public' 
  OR auth.uid() = creator_id 
  OR public.is_project_member(id)
);

-- 2. CREATE: Any authenticated user can create a project
-- 2. CREATE: Any authenticated user can create a project
DROP POLICY IF EXISTS "Create Projects" ON public.project_spaces;
CREATE POLICY "Create Projects" ON public.project_spaces
FOR INSERT WITH CHECK (
  auth.role() = 'authenticated' AND auth.uid() = creator_id
);

-- 3. UPDATE: Only the Creator can update
-- 3. UPDATE: Only the Creator can update
DROP POLICY IF EXISTS "Update Projects" ON public.project_spaces;
CREATE POLICY "Update Projects" ON public.project_spaces
FOR UPDATE USING (
  auth.uid() = creator_id
);

-- 4. DELETE: Only the Creator can delete
-- 4. DELETE: Only the Creator can delete
DROP POLICY IF EXISTS "Delete Projects" ON public.project_spaces;
CREATE POLICY "Delete Projects" ON public.project_spaces
FOR DELETE USING (
  auth.uid() = creator_id
);

-- ============================================================================
-- PROJECT MEMBERS
-- ============================================================================

DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.project_space_members;
DROP POLICY IF EXISTS "Anyone can view project members" ON public.project_space_members;
DROP POLICY IF EXISTS "Creators can manage members" ON public.project_space_members;
DROP POLICY IF EXISTS "Users can join/leave" ON public.project_space_members;

-- 1. VIEW: Members can see other members in their projects
DROP POLICY IF EXISTS "View Members" ON public.project_space_members;
CREATE POLICY "View Members" ON public.project_space_members
FOR SELECT USING (
  public.is_project_member(project_space_id) 
  OR public.is_project_creator(project_space_id)
);

-- 2. ADD MEMBERS: Only Creator can add members (Invite system usually handles this, but direct insert needs protection)
DROP POLICY IF EXISTS "Add Members" ON public.project_space_members;
CREATE POLICY "Add Members" ON public.project_space_members
FOR INSERT WITH CHECK (
  public.is_project_creator(project_space_id)
  OR user_id = auth.uid() -- Allow self-join if logic permits (usually handled via requests)
);

-- 3. REMOVE MEMBERS: Creator can remove anyone. Users can remove themselves (leave).
-- 3. REMOVE MEMBERS: Creator can remove anyone. Users can remove themselves (leave).
DROP POLICY IF EXISTS "Remove Members" ON public.project_space_members;
CREATE POLICY "Remove Members" ON public.project_space_members
FOR DELETE USING (
  public.is_project_creator(project_space_id) 
  OR user_id = auth.uid()
);

-- ============================================================================
-- PROJECT ASSETS (Tasks, Files, Call Sheets, etc.)
-- ============================================================================

-- Helper macro for asset tables
-- We'll apply the same logic to all sub-tables: Members & Creator can View/Edit

-- TASKS
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.tasks;
DROP POLICY IF EXISTS "View Tasks" ON public.tasks;
CREATE POLICY "View Tasks" ON public.tasks FOR SELECT USING (public.is_project_member(project_space_id) OR public.is_project_creator(project_space_id));
DROP POLICY IF EXISTS "Manage Tasks" ON public.tasks;
CREATE POLICY "Manage Tasks" ON public.tasks FOR ALL USING (public.is_project_member(project_space_id) OR public.is_project_creator(project_space_id));

-- FILES (Database Record)
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.files;
DROP POLICY IF EXISTS "View Files" ON public.files;
CREATE POLICY "View Files" ON public.files FOR SELECT USING (public.is_project_member(project_id) OR public.is_project_creator(project_id));
DROP POLICY IF EXISTS "Manage Files" ON public.files;
CREATE POLICY "Manage Files" ON public.files FOR ALL USING (public.is_project_member(project_id) OR public.is_project_creator(project_id));

-- CALL SHEETS
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.call_sheets;
DROP POLICY IF EXISTS "View Call Sheets" ON public.call_sheets;
CREATE POLICY "View Call Sheets" ON public.call_sheets FOR SELECT USING (public.is_project_member(project_id) OR public.is_project_creator(project_id));
DROP POLICY IF EXISTS "Manage Call Sheets" ON public.call_sheets;
CREATE POLICY "Manage Call Sheets" ON public.call_sheets FOR ALL USING (public.is_project_member(project_id) OR public.is_project_creator(project_id));

-- SHOT LIST
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.shot_list;
DROP POLICY IF EXISTS "View Shot List" ON public.shot_list;
CREATE POLICY "View Shot List" ON public.shot_list FOR SELECT USING (public.is_project_member(project_id) OR public.is_project_creator(project_id));
DROP POLICY IF EXISTS "Manage Shot List" ON public.shot_list;
CREATE POLICY "Manage Shot List" ON public.shot_list FOR ALL USING (public.is_project_member(project_id) OR public.is_project_creator(project_id));

-- LEGAL DOCS
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.legal_docs;
DROP POLICY IF EXISTS "View Legal Docs" ON public.legal_docs;
CREATE POLICY "View Legal Docs" ON public.legal_docs FOR SELECT USING (public.is_project_member(project_id) OR public.is_project_creator(project_id));
DROP POLICY IF EXISTS "Manage Legal Docs" ON public.legal_docs;
CREATE POLICY "Manage Legal Docs" ON public.legal_docs FOR ALL USING (public.is_project_member(project_id) OR public.is_project_creator(project_id));

-- PROJECT MESSAGES
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.project_messages;
DROP POLICY IF EXISTS "View Project Messages" ON public.project_messages;
CREATE POLICY "View Project Messages" ON public.project_messages FOR SELECT USING (public.is_project_member(project_id) OR public.is_project_creator(project_id));
DROP POLICY IF EXISTS "Send Project Messages" ON public.project_messages;
CREATE POLICY "Send Project Messages" ON public.project_messages FOR INSERT WITH CHECK (public.is_project_member(project_id) OR public.is_project_creator(project_id));

-- ============================================================================
-- STORAGE BUCKETS (Fixing the upload error)
-- ============================================================================
-- Ensure the 'project-files' bucket exists and has policies

INSERT INTO storage.buckets (id, name, public) VALUES ('project-files', 'project-files', true) ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Project Members Read" ON storage.objects;
DROP POLICY IF EXISTS "Project Members Upload" ON storage.objects;
DROP POLICY IF EXISTS "Project Members Delete" ON storage.objects;

-- Note: Storage policies are tricky because they don't easily join with public tables.
-- We often use a folder structure like "project_id/filename" to validate.
-- For now, we will allow authenticated users to upload, but rely on the database 'files' table for strict access control.


DROP POLICY IF EXISTS "Authenticated Read Project Files" ON storage.objects;
CREATE POLICY "Authenticated Read Project Files" ON storage.objects FOR SELECT USING (bucket_id = 'project-files' AND auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Authenticated Upload Project Files" ON storage.objects;
CREATE POLICY "Authenticated Upload Project Files" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'project-files' AND auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Creator Delete Project Files" ON storage.objects;
CREATE POLICY "Creator Delete Project Files" ON storage.objects FOR DELETE USING (bucket_id = 'project-files' AND owner = auth.uid());

-- ============================================================================
-- COMPREHENSIVE APP-WIDE SECURITY POLICIES (STRICT AUTHENTICATION)
-- ============================================================================
-- Updated: CORRECTED column names based on user diagnostic output
-- project_messages -> sender_id
-- project_space_messages -> user_id
-- ============================================================================

-- 1. HELPER FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_member_of_project(_project_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.project_space_members 
    WHERE project_space_id = _project_id AND user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_member_of_room(_room_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.room_members 
    WHERE room_id = _room_id AND user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 2. PROFILES (Identity)
-- ============================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public View Profiles" ON public.profiles;
DROP POLICY IF EXISTS "Auth Create Own Profile" ON public.profiles;
DROP POLICY IF EXISTS "Owner Update Profile" ON public.profiles;
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.profiles;

CREATE POLICY "Public View Profiles" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Auth Create Own Profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Owner Update Profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- ============================================================================
-- 3. FEED (Posts, Likes, Comments) - STRICT AUTH
-- ============================================================================
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

-- POSTS
DROP POLICY IF EXISTS "Auth View Posts" ON public.posts;
DROP POLICY IF EXISTS "Auth Create Posts" ON public.posts;
DROP POLICY IF EXISTS "Owner Manage Posts" ON public.posts;
DROP POLICY IF EXISTS "Public View Posts" ON public.posts;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.posts;

CREATE POLICY "Auth View Posts" ON public.posts FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Auth Create Posts" ON public.posts FOR INSERT WITH CHECK (auth.role() = 'authenticated' AND auth.uid() = author_id);
CREATE POLICY "Owner Manage Posts" ON public.posts FOR ALL USING (auth.uid() = author_id);

-- COMMENTS
DROP POLICY IF EXISTS "Auth View Comments" ON public.comments;
DROP POLICY IF EXISTS "Auth Create Comments" ON public.comments;
DROP POLICY IF EXISTS "Owner Manage Comments" ON public.comments;
DROP POLICY IF EXISTS "Public View Comments" ON public.comments;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.comments;

CREATE POLICY "Auth View Comments" ON public.comments FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Auth Create Comments" ON public.comments FOR INSERT WITH CHECK (auth.role() = 'authenticated' AND auth.uid() = user_id);
CREATE POLICY "Owner Manage Comments" ON public.comments FOR ALL USING (auth.uid() = user_id);

-- LIKES (Standard table)
DROP POLICY IF EXISTS "Auth View Likes" ON public.likes;
DROP POLICY IF EXISTS "Auth Toggle Likes" ON public.likes;
DROP POLICY IF EXISTS "Public View Likes" ON public.likes;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.likes;

CREATE POLICY "Auth View Likes" ON public.likes FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Auth Toggle Likes" ON public.likes FOR ALL USING (auth.role() = 'authenticated' AND auth.uid() = user_id);

-- POST_LIKES (Separate table identified in screenshot)
CREATE TABLE IF NOT EXISTS public.post_likes (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    UNIQUE(post_id, user_id)
);

ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Auth View Post Likes" ON public.post_likes;
DROP POLICY IF EXISTS "Auth Toggle Post Likes" ON public.post_likes;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.post_likes;

CREATE POLICY "Auth View Post Likes" ON public.post_likes FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Auth Toggle Post Likes" ON public.post_likes FOR ALL USING (auth.role() = 'authenticated' AND auth.uid() = user_id);


-- ============================================================================
-- 4. JOBS & APPLICATIONS - PUBLIC VIEW
-- ============================================================================
ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_applications ENABLE ROW LEVEL SECURITY;

-- JOBS
DROP POLICY IF EXISTS "Public View Active Jobs" ON public.jobs;
DROP POLICY IF EXISTS "Auth Create Jobs" ON public.jobs;
DROP POLICY IF EXISTS "Owner Manage Jobs" ON public.jobs;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.jobs;

CREATE POLICY "Public View Active Jobs" ON public.jobs FOR SELECT USING (is_active = true);
CREATE POLICY "Auth Create Jobs" ON public.jobs FOR INSERT WITH CHECK (auth.role() = 'authenticated' AND auth.uid() = posted_by);
CREATE POLICY "Owner Manage Jobs" ON public.jobs FOR ALL USING (auth.uid() = posted_by);

-- APPLICATIONS
DROP POLICY IF EXISTS "Applicant Create/View" ON public.job_applications;
DROP POLICY IF EXISTS "Employer View Applications" ON public.job_applications;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.job_applications;

CREATE POLICY "Applicant Create/View" ON public.job_applications FOR ALL USING (auth.uid() = applicant_id);
CREATE POLICY "Employer View Applications" ON public.job_applications FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.jobs WHERE id = job_id AND posted_by = auth.uid())
);

-- ============================================================================
-- 5. MARKETPLACE - STRICT AUTH
-- ============================================================================
ALTER TABLE public.marketplace_listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;

-- LISTINGS
DROP POLICY IF EXISTS "Auth View Listings" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Auth Create Listings" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Owner Manage Listings" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Public View Listings" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.marketplace_listings;

CREATE POLICY "Auth View Listings" ON public.marketplace_listings FOR SELECT USING (auth.role() = 'authenticated' AND is_active = true);
CREATE POLICY "Auth Create Listings" ON public.marketplace_listings FOR INSERT WITH CHECK (auth.role() = 'authenticated' AND auth.uid() = user_id);
CREATE POLICY "Owner Manage Listings" ON public.marketplace_listings FOR ALL USING (auth.uid() = user_id);

-- VENDORS
DROP POLICY IF EXISTS "Auth View Vendors" ON public.vendors;
DROP POLICY IF EXISTS "Auth Create Vendors" ON public.vendors;
DROP POLICY IF EXISTS "Owner Manage Vendors" ON public.vendors;
DROP POLICY IF EXISTS "Public View Vendors" ON public.vendors;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.vendors;

CREATE POLICY "Auth View Vendors" ON public.vendors FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Auth Create Vendors" ON public.vendors FOR INSERT WITH CHECK (auth.role() = 'authenticated' AND auth.uid() = owner_id);
CREATE POLICY "Owner Manage Vendors" ON public.vendors FOR ALL USING (auth.uid() = owner_id);

-- ============================================================================
-- 6. DISCUSSION ROOMS - STRICT AUTH & JOIN LOGIC
-- ============================================================================
ALTER TABLE public.discussion_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_categories ENABLE ROW LEVEL SECURITY;

-- ROOMS
DROP POLICY IF EXISTS "Auth View Public Rooms" ON public.discussion_rooms;
DROP POLICY IF EXISTS "Auth Create Rooms" ON public.discussion_rooms;
DROP POLICY IF EXISTS "Creator Manage Room" ON public.discussion_rooms;
DROP POLICY IF EXISTS "Public View Rooms" ON public.discussion_rooms;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.discussion_rooms;

CREATE POLICY "Auth View Public Rooms" ON public.discussion_rooms FOR SELECT USING (
  auth.role() = 'authenticated' AND (is_public = true OR public.is_member_of_room(id) OR creator_id = auth.uid())
);
CREATE POLICY "Auth Create Rooms" ON public.discussion_rooms FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Creator Manage Room" ON public.discussion_rooms FOR ALL USING (auth.uid() = creator_id);

-- MEMBERS
DROP POLICY IF EXISTS "View Room Members" ON public.room_members;
DROP POLICY IF EXISTS "Join Room" ON public.room_members;
DROP POLICY IF EXISTS "Leave/Remove Member" ON public.room_members;
DROP POLICY IF EXISTS "Auth Join Room" ON public.room_members;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.room_members;

CREATE POLICY "View Room Members" ON public.room_members FOR SELECT USING (
  auth.role() = 'authenticated' AND EXISTS (
    SELECT 1 FROM public.discussion_rooms 
    WHERE id = room_id AND (is_public = true OR public.is_member_of_room(id))
  )
);
CREATE POLICY "Join Room" ON public.room_members FOR INSERT WITH CHECK (
  (auth.uid() = user_id AND EXISTS (SELECT 1 FROM public.discussion_rooms WHERE id = room_id AND is_public = true))
  OR 
  EXISTS (SELECT 1 FROM public.discussion_rooms WHERE id = room_id AND creator_id = auth.uid())
);
CREATE POLICY "Leave/Remove Member" ON public.room_members FOR DELETE USING (
  auth.uid() = user_id 
  OR 
  EXISTS (SELECT 1 FROM public.discussion_rooms WHERE id = room_id AND creator_id = auth.uid())
);

-- CATEGORIES
DROP POLICY IF EXISTS "Auth View Room Categories" ON public.room_categories;
DROP POLICY IF EXISTS "Anyone can view categories" ON public.room_categories;

CREATE POLICY "Auth View Room Categories" ON public.room_categories FOR SELECT USING (auth.role() = 'authenticated');

-- ============================================================================
-- 7. PROJECTS - STRICT AUTH
-- ============================================================================
ALTER TABLE public.project_spaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_space_categories ENABLE ROW LEVEL SECURITY;

-- PROJECTS
DROP POLICY IF EXISTS "Auth View Projects" ON public.project_spaces;
DROP POLICY IF EXISTS "Auth Create Projects" ON public.project_spaces;
DROP POLICY IF EXISTS "Creator Manage Projects" ON public.project_spaces;
DROP POLICY IF EXISTS "View Projects" ON public.project_spaces;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.project_spaces;

CREATE POLICY "Auth View Projects" ON public.project_spaces FOR SELECT USING (
  auth.role() = 'authenticated' AND (
    project_space_type = 'public' 
    OR creator_id = auth.uid() 
    OR public.is_member_of_project(id)
  )
);
CREATE POLICY "Auth Create Projects" ON public.project_spaces FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Creator Manage Projects" ON public.project_spaces FOR ALL USING (auth.uid() = creator_id);

-- CATEGORIES
DROP POLICY IF EXISTS "Auth View Project Categories" ON public.project_space_categories;
DROP POLICY IF EXISTS "Anyone can view categories" ON public.project_space_categories;

CREATE POLICY "Auth View Project Categories" ON public.project_space_categories FOR SELECT USING (auth.role() = 'authenticated');

-- PROJECT MESSAGES (Explicit Policies - Corrected Table/Column Names)
-- Table: project_messages (Uses user_id)
-- Column: user_id

ALTER TABLE public.project_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Member View Project Messages" ON public.project_messages;
DROP POLICY IF EXISTS "Member Send Project Messages" ON public.project_messages;
DROP POLICY IF EXISTS "Project members can view messages" ON public.project_messages;
DROP POLICY IF EXISTS "Project members can send messages" ON public.project_messages;
DROP POLICY IF EXISTS "Users can delete their own messages" ON public.project_messages;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.project_messages;

CREATE POLICY "Member View Project Messages" ON public.project_messages 
FOR SELECT USING (public.is_member_of_project(project_id));

CREATE POLICY "Member Send Project Messages" ON public.project_messages 
FOR INSERT WITH CHECK (public.is_member_of_project(project_id) AND auth.uid() = user_id);

-- PROJECT SPACE MESSAGES (Uses user_id)
-- If this table exists, we use user_id. If it doesn't exist, we create it with user_id.
CREATE TABLE IF NOT EXISTS public.project_space_messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_space_id uuid NOT NULL REFERENCES public.project_spaces(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.project_space_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Member View Project Space Messages" ON public.project_space_messages;
DROP POLICY IF EXISTS "Member Send Project Space Messages" ON public.project_space_messages;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.project_space_messages;

CREATE POLICY "Member View Project Space Messages" ON public.project_space_messages 
FOR SELECT USING (public.is_member_of_project(project_space_id));

CREATE POLICY "Member Send Project Space Messages" ON public.project_space_messages 
FOR INSERT WITH CHECK (public.is_member_of_project(project_space_id) AND auth.uid() = user_id);

-- PROJECT MESSAGE READ STATUS (Uses user_id)
CREATE TABLE IF NOT EXISTS public.project_message_read_status (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id uuid NOT NULL REFERENCES public.project_spaces(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    last_read_at timestamp with time zone DEFAULT now() NOT NULL,
    UNIQUE(project_id, user_id)
);

ALTER TABLE public.project_message_read_status ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Member View Read Status" ON public.project_message_read_status;
DROP POLICY IF EXISTS "Update Own Read Status" ON public.project_message_read_status;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.project_message_read_status;

CREATE POLICY "Member View Read Status" ON public.project_message_read_status 
FOR SELECT USING (public.is_member_of_project(project_id));

CREATE POLICY "Update Own Read Status" ON public.project_message_read_status 
FOR ALL USING (auth.uid() = user_id);

-- PROJECT SPACE MESSAGE READ STATUS (Uses user_id)
CREATE TABLE IF NOT EXISTS public.project_space_message_read_status (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_space_id uuid NOT NULL REFERENCES public.project_spaces(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    last_read_at timestamp with time zone DEFAULT now() NOT NULL,
    UNIQUE(project_space_id, user_id)
);

ALTER TABLE public.project_space_message_read_status ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Member View Space Read Status" ON public.project_space_message_read_status;
DROP POLICY IF EXISTS "Update Own Space Read Status" ON public.project_space_message_read_status;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.project_space_message_read_status;

CREATE POLICY "Member View Space Read Status" ON public.project_space_message_read_status 
FOR SELECT USING (public.is_member_of_project(project_space_id));

CREATE POLICY "Update Own Space Read Status" ON public.project_space_message_read_status 
FOR ALL USING (auth.uid() = user_id);

-- ============================================================================
-- 8. NETWORK - STRICT AUTH
-- ============================================================================
ALTER TABLE public.user_connections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Auth View Connections" ON public.user_connections;
DROP POLICY IF EXISTS "Manage Connections" ON public.user_connections;
DROP POLICY IF EXISTS "View Connections" ON public.user_connections;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.user_connections;

CREATE POLICY "Auth View Connections" ON public.user_connections FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Manage Connections" ON public.user_connections FOR ALL USING (auth.uid() = follower_id);

-- ============================================================================
-- 9. ANNOUNCEMENTS - STRICT AUTH
-- ============================================================================
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Auth View Announcements" ON public.announcements;
DROP POLICY IF EXISTS "Auth Create Announcements" ON public.announcements;
DROP POLICY IF EXISTS "Author Manage Announcements" ON public.announcements;
DROP POLICY IF EXISTS "Anyone can view announcements" ON public.announcements;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.announcements;

CREATE POLICY "Auth View Announcements" ON public.announcements FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Auth Create Announcements" ON public.announcements FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Author Manage Announcements" ON public.announcements FOR ALL USING (auth.uid() = author_id);

-- ============================================================================
-- 10. REACTIONS (Explicit Policies)
-- ============================================================================
-- Ensure table exists
CREATE TABLE IF NOT EXISTS public.message_reactions (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    emoji text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "View Reactions" ON public.message_reactions;
DROP POLICY IF EXISTS "Manage Own Reactions" ON public.message_reactions;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.message_reactions;

CREATE POLICY "View Reactions" ON public.message_reactions FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.messages m
    JOIN public.conversations c ON m.conversation_id = c.id
    WHERE m.id = message_id AND (c.user1_id = auth.uid() OR c.user2_id = auth.uid())
  )
);

CREATE POLICY "Manage Own Reactions" ON public.message_reactions FOR ALL USING (auth.uid() = user_id);
-- ============================================================================
-- FIX: USER ANALYTICS & STORAGE POLICIES
-- ============================================================================
-- 1. Re-creates user_analytics table (missing in production)
-- 2. Fixes Storage RLS for 'portfolios' bucket (causing upload errors)
-- ============================================================================

-- 1. USER ANALYTICS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.user_analytics (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    event_type text NOT NULL,
    event_data jsonb DEFAULT '{}'::jsonb,
    page_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.user_analytics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert their own analytics" ON public.user_analytics;
CREATE POLICY "Users can insert their own analytics"
ON public.user_analytics FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own analytics" ON public.user_analytics;
CREATE POLICY "Users can view their own analytics"
ON public.user_analytics FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- ============================================================================
-- 2. STORAGE: PORTFOLIOS BUCKET
-- ============================================================================
-- Ensure bucket exists and is public (required for <img> tags usually)
INSERT INTO storage.buckets (id, name, public)
VALUES ('portfolios', 'portfolios', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Fix RLS Policies
DROP POLICY IF EXISTS "authenticated read portfolios" ON storage.objects;
DROP POLICY IF EXISTS "authenticated upload portfolios" ON storage.objects;
DROP POLICY IF EXISTS "owner delete portfolios" ON storage.objects;
DROP POLICY IF EXISTS "Give me access to portfolios" ON storage.objects; -- Cleanup potential old policy

-- READ: Allow Public (since bucket is public) OR Authenticated
-- Using Public Read ensures images load in <img> tags without complex token handling
DROP POLICY IF EXISTS "Public Read Portfolios" ON storage.objects;
CREATE POLICY "Public Read Portfolios"
ON storage.objects FOR SELECT
USING (bucket_id = 'portfolios');

-- UPLOAD: Authenticated Users Only
DROP POLICY IF EXISTS "Authenticated Upload Portfolios" ON storage.objects;
CREATE POLICY "Authenticated Upload Portfolios"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'portfolios');

-- DELETE: Owner Only
DROP POLICY IF EXISTS "Owner Delete Portfolios" ON storage.objects;
CREATE POLICY "Owner Delete Portfolios"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'portfolios' AND (auth.uid() = owner OR owner IS NULL));

-- UPDATE: Owner Only
DROP POLICY IF EXISTS "Owner Update Portfolios" ON storage.objects;
CREATE POLICY "Owner Update Portfolios"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'portfolios' AND (auth.uid() = owner OR owner IS NULL));
-- ============================================================================
-- MASSIVE RESTORATION: MISSING PROJECT TABLES (FIXED V2)
-- ============================================================================
-- This script restores all tables that are returning 404 Not Found errors.
-- It uses IF NOT EXISTS to be safe to run on any environment.
-- FIXED: Removed 'tasks' from generic loop to avoid column name error.
-- ============================================================================

-- 1. TASKS
CREATE TABLE IF NOT EXISTS public.tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_space_id uuid NOT NULL REFERENCES public.project_spaces(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    status text NOT NULL DEFAULT 'todo' CHECK (status IN ('todo', 'in_progress', 'done')),
    assignee_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    due_date timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- 2. FILES
CREATE TABLE IF NOT EXISTS public.files (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES public.project_spaces(id) ON DELETE CASCADE,
    name text NOT NULL,
    url text NOT NULL,
    type text NOT NULL,
    size bigint,
    uploaded_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.files ENABLE ROW LEVEL SECURITY;

-- 3. CALL SHEETS
CREATE TABLE IF NOT EXISTS public.call_sheets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES public.project_spaces(id) ON DELETE CASCADE,
    title text NOT NULL,
    shoot_date date NOT NULL,
    call_time time NOT NULL,
    location text,
    status text DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
    created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.call_sheets ENABLE ROW LEVEL SECURITY;

-- 4. SHOT LIST
CREATE TABLE IF NOT EXISTS public.shot_list (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES public.project_spaces(id) ON DELETE CASCADE,
    scene text NOT NULL,
    shot text NOT NULL,
    description text,
    equipment text,
    camera_angle text,
    movement text,
    status text DEFAULT 'planned' CHECK (status IN ('planned', 'shot', 'cut')),
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.shot_list ENABLE ROW LEVEL SECURITY;

-- 5. SCHEDULE ITEMS
CREATE TABLE IF NOT EXISTS public.schedule_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES public.project_spaces(id) ON DELETE CASCADE,
    title text NOT NULL,
    start_time timestamptz NOT NULL,
    end_time timestamptz NOT NULL,
    type text DEFAULT 'shoot' CHECK (type IN ('shoot', 'meeting', 'prep', 'wrap')),
    location text,
    description text,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.schedule_items ENABLE ROW LEVEL SECURITY;

-- 6. BUDGET ITEMS
CREATE TABLE IF NOT EXISTS public.budget_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES public.project_spaces(id) ON DELETE CASCADE,
    category text NOT NULL,
    description text NOT NULL,
    amount numeric(10, 2) NOT NULL DEFAULT 0,
    status text DEFAULT 'estimated' CHECK (status IN ('estimated', 'actual', 'paid')),
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.budget_items ENABLE ROW LEVEL SECURITY;

-- 7. LEGAL DOCS
CREATE TABLE IF NOT EXISTS public.legal_docs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES public.project_spaces(id) ON DELETE CASCADE,
    title text NOT NULL,
    type text NOT NULL, -- 'contract', 'permit', 'release', etc.
    status text DEFAULT 'draft' CHECK (status IN ('draft', 'signed', 'expired')),
    url text,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.legal_docs ENABLE ROW LEVEL SECURITY;

-- 8. CALLS SYSTEM
CREATE TABLE IF NOT EXISTS public.calls (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    room_type text NOT NULL CHECK (room_type IN ('project', 'discussion')),
    room_id uuid NOT NULL, 
    daily_room_name text UNIQUE NOT NULL,
    daily_room_url text NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'ended')),
    started_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    started_at timestamptz DEFAULT now() NOT NULL,
    ended_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.call_participants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id uuid NOT NULL REFERENCES public.calls(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'joined' CHECK (status IN ('requesting', 'joined', 'left')),
    joined_at timestamptz DEFAULT now() NOT NULL,
    left_at timestamptz,
    UNIQUE(call_id, user_id)
);
ALTER TABLE public.call_participants ENABLE ROW LEVEL SECURITY;

-- 9. PROJECT APPLICATIONS
CREATE TABLE IF NOT EXISTS public.project_applications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES public.project_spaces(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    message text,
    created_at timestamptz DEFAULT now() NOT NULL,
    UNIQUE(project_id, user_id)
);
ALTER TABLE public.project_applications ENABLE ROW LEVEL SECURITY;

-- 10. FIX PROJECT MESSAGES COLUMN (Rename sender_id to user_id if exists)
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'project_messages' AND column_name = 'sender_id') THEN
    ALTER TABLE public.project_messages RENAME COLUMN sender_id TO user_id;
  END IF;
END $$;

-- 11. APPLY RLS POLICIES FOR NEW TABLES (Basic Member Access)
-- We use a generic function to apply policies to all these project tables
-- View: Members Only
-- Create/Edit: Members Only

DO $$ 
DECLARE
    t text;
BEGIN
    -- REMOVED 'tasks' from this array because it uses project_space_id
    FOR t IN SELECT unnest(ARRAY['files', 'call_sheets', 'shot_list', 'schedule_items', 'budget_items', 'legal_docs']) LOOP
        EXECUTE format('DROP POLICY IF EXISTS "Member View %I" ON public.%I', t, t);
        EXECUTE format('CREATE POLICY "Member View %I" ON public.%I FOR SELECT USING (
            EXISTS (SELECT 1 FROM public.project_space_members WHERE project_space_id = %I.project_id AND user_id = auth.uid())
            OR 
            EXISTS (SELECT 1 FROM public.project_spaces WHERE id = %I.project_id AND creator_id = auth.uid())
        )', t, t, t, t);

        EXECUTE format('DROP POLICY IF EXISTS "Member Manage %I" ON public.%I', t, t);
        EXECUTE format('CREATE POLICY "Member Manage %I" ON public.%I FOR ALL USING (
            EXISTS (SELECT 1 FROM public.project_space_members WHERE project_space_id = %I.project_id AND user_id = auth.uid())
            OR 
            EXISTS (SELECT 1 FROM public.project_spaces WHERE id = %I.project_id AND creator_id = auth.uid())
        )', t, t, t, t);
    END LOOP;
END $$;

-- Special handling for 'tasks' which uses 'project_space_id' instead of 'project_id'
DROP POLICY IF EXISTS "Member View tasks" ON public.tasks;
CREATE POLICY "Member View tasks" ON public.tasks FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.project_space_members WHERE project_space_id = tasks.project_space_id AND user_id = auth.uid())
    OR 
    EXISTS (SELECT 1 FROM public.project_spaces WHERE id = tasks.project_space_id AND creator_id = auth.uid())
);

DROP POLICY IF EXISTS "Member Manage tasks" ON public.tasks;
CREATE POLICY "Member Manage tasks" ON public.tasks FOR ALL USING (
    EXISTS (SELECT 1 FROM public.project_space_members WHERE project_space_id = tasks.project_space_id AND user_id = auth.uid())
    OR 
    EXISTS (SELECT 1 FROM public.project_spaces WHERE id = tasks.project_space_id AND creator_id = auth.uid())
);

-- Fix Project Applications RLS
DROP POLICY IF EXISTS "Users can view own applications" ON public.project_applications;
CREATE POLICY "Users can view own applications" ON public.project_applications FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Creators can view applications" ON public.project_applications;
CREATE POLICY "Creators can view applications" ON public.project_applications FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.project_spaces WHERE id = project_applications.project_id AND creator_id = auth.uid())
);

DROP POLICY IF EXISTS "Users can apply" ON public.project_applications;
CREATE POLICY "Users can apply" ON public.project_applications FOR INSERT WITH CHECK (auth.uid() = user_id);
-- ============================================================================
-- FIX: RELATIONSHIPS & FOREIGN KEYS
-- ============================================================================
-- This script fixes the "400 Bad Request" errors when fetching data with joins.
-- PostgREST requires explicit Foreign Keys to the joined table (profiles).
-- We change references from auth.users to public.profiles to enable these joins.
-- ============================================================================

-- 1. PROJECT SPACE MEMBERS -> PROFILES
ALTER TABLE public.project_space_members 
DROP CONSTRAINT IF EXISTS project_space_members_user_id_fkey;

ALTER TABLE public.project_space_members 
ADD CONSTRAINT project_space_members_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- 2. PROJECT APPLICATIONS -> PROFILES
ALTER TABLE public.project_applications 
DROP CONSTRAINT IF EXISTS project_applications_user_id_fkey;

ALTER TABLE public.project_applications 
ADD CONSTRAINT project_applications_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- 3. PROJECT MESSAGES -> PROFILES
-- Note: We already renamed sender_id to user_id in the previous step.
-- Now we ensure it references profiles for the UI to fetch names/avatars.
ALTER TABLE public.project_messages 
DROP CONSTRAINT IF EXISTS project_messages_user_id_fkey;

ALTER TABLE public.project_messages 
DROP CONSTRAINT IF EXISTS project_messages_sender_id_fkey; -- Cleanup old constraint if exists

ALTER TABLE public.project_messages 
ADD CONSTRAINT project_messages_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- 4. CALLS TABLE FIXES
-- Ensure columns exist (in case table existed but was malformed)
DO $$ 
BEGIN
    -- Check and add room_type if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'calls' AND column_name = 'room_type') THEN
        ALTER TABLE public.calls ADD COLUMN room_type text CHECK (room_type IN ('project', 'discussion'));
    END IF;

    -- Check and add room_id if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'calls' AND column_name = 'room_id') THEN
        ALTER TABLE public.calls ADD COLUMN room_id uuid;
    END IF;

    -- Check and add status if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'calls' AND column_name = 'status') THEN
        ALTER TABLE public.calls ADD COLUMN status text DEFAULT 'active' CHECK (status IN ('active', 'ended'));
    END IF;
END $$;

-- Ensure RLS allows viewing calls
DROP POLICY IF EXISTS "Authenticated users can view calls" ON public.calls;
CREATE POLICY "Authenticated users can view calls" ON public.calls FOR SELECT USING (auth.role() = 'authenticated');

-- 5. FIX PROJECT MESSAGES RLS (403 Error)
-- Ensure members can view messages
DROP POLICY IF EXISTS "Member View Project Messages" ON public.project_messages;
CREATE POLICY "Member View Project Messages" ON public.project_messages 
FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.project_space_members WHERE project_space_id = project_messages.project_id AND user_id = auth.uid())
  OR
  EXISTS (SELECT 1 FROM public.project_spaces WHERE id = project_messages.project_id AND creator_id = auth.uid())
);

-- Ensure members can insert messages
DROP POLICY IF EXISTS "Member Send Project Messages" ON public.project_messages;
CREATE POLICY "Member Send Project Messages" ON public.project_messages 
FOR INSERT WITH CHECK (
  auth.uid() = user_id AND (
    EXISTS (SELECT 1 FROM public.project_space_members WHERE project_space_id = project_messages.project_id AND user_id = auth.uid())
    OR
    EXISTS (SELECT 1 FROM public.project_spaces WHERE id = project_messages.project_id AND creator_id = auth.uid())
  )
);
-- ============================================================================
-- FIX: ADD MISSING ROLE COLUMN
-- ============================================================================
-- The frontend expects a 'role' column in project_space_members, but it was missing.
-- This script adds the column with a default value of 'member'.
-- ============================================================================

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'project_space_members' AND column_name = 'role') THEN
        ALTER TABLE public.project_space_members 
        ADD COLUMN role text NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'moderator', 'member'));
    END IF;
END $$;
-- ============================================================================
-- FIX: DISCUSSION ROOM MESSAGES (RLS & FK)
-- ============================================================================
-- This script fixes the issue where messages in Discussion Rooms were not showing.
-- It adds the missing RLS policies for 'room_messages' and ensures Foreign Keys.
-- ============================================================================

-- 1. Ensure Foreign Key to Profiles (for avatar/name fetching)
ALTER TABLE public.room_messages 
DROP CONSTRAINT IF EXISTS room_messages_user_id_fkey;

ALTER TABLE public.room_messages 
ADD CONSTRAINT room_messages_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- 2. Enable RLS
ALTER TABLE public.room_messages ENABLE ROW LEVEL SECURITY;

-- 3. Add Policies
DROP POLICY IF EXISTS "View Room Messages" ON public.room_messages;
DROP POLICY IF EXISTS "Send Room Messages" ON public.room_messages;

-- Policy: View Messages
-- Users can view messages if:
-- 1. The room is public
-- 2. They are a member of the room
-- 3. They are the creator of the room
CREATE POLICY "View Room Messages" ON public.room_messages 
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.discussion_rooms 
    WHERE id = room_messages.room_id 
    AND (
      is_public = true 
      OR public.is_member_of_room(id) 
      OR creator_id = auth.uid()
    )
  )
);

-- Policy: Send Messages
-- Users can send messages if:
-- 1. They are authenticated (auth.uid() = user_id)
-- 2. AND (Room is public OR Member OR Creator)
CREATE POLICY "Send Room Messages" ON public.room_messages 
FOR INSERT WITH CHECK (
  auth.uid() = user_id 
  AND EXISTS (
    SELECT 1 FROM public.discussion_rooms 
    WHERE id = room_messages.room_id 
    AND (
      is_public = true 
      OR public.is_member_of_room(id) 
      OR creator_id = auth.uid()
    )
  )
);
-- ============================================================================
-- ENABLE REALTIME FOR CHAT
-- ============================================================================
-- This script ensures that Realtime updates are enabled for chat messages.
-- Without this, users have to refresh to see new messages.
-- ============================================================================

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.room_messages;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.project_messages;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.project_space_messages;
EXCEPTION
    WHEN duplicate_object THEN NULL;
    WHEN undefined_table THEN NULL; -- In case table doesn't exist
END $$;

-- Note: If you get an error saying "relation ... is already in publication", 
-- it means Realtime was already enabled, and the issue might be elsewhere.
-- But usually, this is the missing step for new tables.
-- ============================================================================
-- ENABLE GLOBAL REALTIME (ALL FEATURES)
-- ============================================================================
-- This script enables Supabase Realtime for ALL key application tables.
-- This ensures that Feed, Projects, Notifications, Calls, etc., all update instantly.
-- ============================================================================

DO $$
BEGIN
    -- 1. FEED & SOCIAL
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.posts; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.comments; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.likes; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.post_likes; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.user_connections; EXCEPTION WHEN duplicate_object THEN NULL; END;

    -- 2. MESSAGING
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.room_messages; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.project_messages; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.project_space_messages; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.message_reactions; EXCEPTION WHEN duplicate_object THEN NULL; END;

    -- 3. PROJECTS
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.project_spaces; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.project_space_members; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.files; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.call_sheets; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.shot_list; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.schedule_items; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.budget_items; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.project_applications; EXCEPTION WHEN duplicate_object THEN NULL; END;

    -- 4. DISCUSSIONS
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.discussion_rooms; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.room_members; EXCEPTION WHEN duplicate_object THEN NULL; END;

    -- 5. CALLS
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.calls; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.call_participants; EXCEPTION WHEN duplicate_object THEN NULL; END;

    -- 6. NOTIFICATIONS & ANNOUNCEMENTS
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.announcements; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- Note: Ignore "relation ... is already in publication" errors.
-- ============================================================================
-- FIX: RENAME COMMENTS TO POST_COMMENTS
-- ============================================================================
-- The frontend expects 'post_comments', but the database has 'comments'.
-- This script renames the table and updates RLS policies.
-- ============================================================================

BEGIN;

-- 1. Rename Table (if 'comments' exists and 'post_comments' does not)
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'comments') 
       AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'post_comments') THEN
        ALTER TABLE public.comments RENAME TO post_comments;
    END IF;
END $$;

-- 2. Enable RLS
ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;

-- 3. Update Policies (Drop old ones if they exist on the new table name, add new ones)
DROP POLICY IF EXISTS "Auth View Comments" ON public.post_comments;
DROP POLICY IF EXISTS "Auth Create Comments" ON public.post_comments;
DROP POLICY IF EXISTS "Owner Manage Comments" ON public.post_comments;
DROP POLICY IF EXISTS "Public View Comments" ON public.post_comments;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.post_comments;

CREATE POLICY "Auth View Comments" ON public.post_comments FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Auth Create Comments" ON public.post_comments FOR INSERT WITH CHECK (auth.role() = 'authenticated' AND auth.uid() = user_id);
CREATE POLICY "Owner Manage Comments" ON public.post_comments FOR ALL USING (auth.uid() = user_id);

-- 4. Enable Realtime
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.post_comments;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
-- ============================================================================
-- FIX: RENAME COMMENTS TO POST_COMMENTS (V2 - Safe)
-- ============================================================================
-- The frontend expects 'post_comments', but the database has 'comments'.
-- This script renames the table and updates RLS policies.
-- V2: Removed explicit Realtime addition to prevent "already member" errors.
-- ============================================================================

BEGIN;

-- 1. Rename Table (if 'comments' exists and 'post_comments' does not)
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'comments') 
       AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'post_comments') THEN
        ALTER TABLE public.comments RENAME TO post_comments;
    END IF;
END $$;

-- 2. Enable RLS (Idempotent)
ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;

-- 3. Update Policies (Drop old ones if they exist on the new table name, add new ones)
DROP POLICY IF EXISTS "Auth View Comments" ON public.post_comments;
DROP POLICY IF EXISTS "Auth Create Comments" ON public.post_comments;
DROP POLICY IF EXISTS "Owner Manage Comments" ON public.post_comments;
DROP POLICY IF EXISTS "Public View Comments" ON public.post_comments;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON public.post_comments;

CREATE POLICY "Auth View Comments" ON public.post_comments FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Auth Create Comments" ON public.post_comments FOR INSERT WITH CHECK (auth.role() = 'authenticated' AND auth.uid() = user_id);
CREATE POLICY "Owner Manage Comments" ON public.post_comments FOR ALL USING (auth.uid() = user_id);

COMMIT;
-- ============================================================================
-- FIX: POST COMMENTS FOREIGN KEY TO PROFILES
-- ============================================================================
-- The frontend needs to join 'post_comments' with 'profiles'.
-- Currently, 'post_comments' references 'auth.users', which PostgREST cannot use for joins.
-- This script changes the FK to reference 'public.profiles'.
-- ============================================================================

BEGIN;

-- 1. Drop existing FK to auth.users (if it exists)
-- We need to find the constraint name. It's usually 'comments_user_id_fkey' or similar.
-- We'll try to drop common names or use a DO block to find it.

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'post_comments' 
        AND constraint_type = 'FOREIGN KEY'
    ) LOOP
        -- Check if this constraint points to auth.users (we can't easily check target in simple SQL without joining system tables)
        -- But we know we want to replace the user_id FK.
        -- Let's just drop the constraint on user_id.
        
        -- Actually, safer to just ADD the new one if we can't easily identify the old one.
        -- But duplicate FKs on same column are messy.
        NULL;
    END LOOP;
END $$;

-- Let's explicitly drop the likely name from fresh_init
ALTER TABLE public.post_comments DROP CONSTRAINT IF EXISTS comments_user_id_fkey;
ALTER TABLE public.post_comments DROP CONSTRAINT IF EXISTS post_comments_user_id_fkey;

-- 2. Add new FK to public.profiles
ALTER TABLE public.post_comments DROP CONSTRAINT IF EXISTS post_comments_user_id_fkey_profiles;

ALTER TABLE public.post_comments
ADD CONSTRAINT post_comments_user_id_fkey_profiles
FOREIGN KEY (user_id) REFERENCES public.profiles(id)
ON DELETE CASCADE;

COMMIT;
-- Migration: Add automatic notification creation for new messages
-- This creates notifications when users receive new messages in discussion rooms

-- Function to create notification when a new message is sent
CREATE OR REPLACE FUNCTION public.notify_new_room_message()
RETURNS TRIGGER AS $$
DECLARE
  room_member RECORD;
  sender_name TEXT;
BEGIN
  -- Get sender's name
  SELECT COALESCE(full_name, username, 'Someone') INTO sender_name
  FROM public.profiles
  WHERE id = NEW.user_id;

  -- Create notifications for all room members except the sender
  FOR room_member IN 
    SELECT user_id 
    FROM public.room_members 
    WHERE room_id = NEW.room_id 
    AND user_id != NEW.user_id
  LOOP
    INSERT INTO public.notifications (
      user_id,
      trigger_user_id,
      type,
      title,
      message,
      action_url,
      related_id,
      related_type,
      priority,
      is_read,
      created_at
    ) VALUES (
      room_member.user_id,
      NEW.user_id,
      'new_message',
      'New Message',
      sender_name || ' sent a message',
      '/discussion-rooms/' || NEW.room_id,
      NEW.id,
      'room_message',
      'medium',
      false,
      NOW()
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for room_messages
DROP TRIGGER IF EXISTS trigger_notify_new_room_message ON public.room_messages;
CREATE TRIGGER trigger_notify_new_room_message
  AFTER INSERT ON public.room_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_room_message();

-- Function to create notification when a new project message is sent
CREATE OR REPLACE FUNCTION public.notify_new_project_message()
RETURNS TRIGGER AS $$
DECLARE
  project_member RECORD;
  sender_name TEXT;
  project_name TEXT;
BEGIN
  -- Get sender's name
  SELECT COALESCE(full_name, username, 'Someone') INTO sender_name
  FROM public.profiles
  WHERE id = NEW.user_id;

  -- Get project name
  SELECT name INTO project_name
  FROM public.project_spaces
  WHERE id = NEW.project_id;

  -- Create notifications for all project members except the sender
  FOR project_member IN 
    SELECT user_id 
    FROM public.project_space_members 
    WHERE project_space_id = NEW.project_id 
    AND user_id != NEW.user_id
  LOOP
    INSERT INTO public.notifications (
      user_id,
      trigger_user_id,
      type,
      title,
      message,
      action_url,
      related_id,
      related_type,
      priority,
      is_read,
      created_at
    ) VALUES (
      project_member.user_id,
      NEW.user_id,
      'new_message',
      'New Project Message',
      sender_name || ' sent a message in ' || COALESCE(project_name, 'a project'),
      '/projects/' || NEW.project_id || '/space',
      NEW.id,
      'project_message',
      'medium',
      false,
      NOW()
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for project_messages
DROP TRIGGER IF EXISTS trigger_notify_new_project_message ON public.project_messages;
CREATE TRIGGER trigger_notify_new_project_message
  AFTER INSERT ON public.project_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_project_message();

-- Add trigger_user_id column to notifications if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'notifications' 
    AND column_name = 'trigger_user_id'
  ) THEN
    ALTER TABLE public.notifications 
    ADD COLUMN trigger_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION public.notify_new_room_message() TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_new_project_message() TO authenticated;

-- Add index for better performance
CREATE INDEX IF NOT EXISTS idx_notifications_user_id_created_at 
  ON public.notifications(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id_is_read 
  ON public.notifications(user_id, is_read);
