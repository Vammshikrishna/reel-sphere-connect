-- Just enable RLS on direct_messages (policies already exist)
ALTER TABLE public.direct_messages ENABLE ROW LEVEL SECURITY;