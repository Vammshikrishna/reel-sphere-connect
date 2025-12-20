import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = "https://zugtdutimulibaxwnlbs.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp1Z3RkdXRpbXVsaWJheHdubGJzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0NjA5MzQsImV4cCI6MjA4MTAzNjkzNH0.NRKEzG3QbbQ7r1R0kHVqS1YctfYUv7VbezcFZ3ti8ek";

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function checkQueries() {
    console.log('--- Checking Projects ---');
    try {
        const start = Date.now();
        const { data: projects, error: pError } = await supabase
            .from('projects')
            .select(`*, profiles:creator_id (full_name, username, avatar_url)`)
            .limit(5);

        console.log('Projects query took:', Date.now() - start, 'ms');
        if (pError) console.error('Projects Error:', pError);
        else console.log('Projects found:', projects?.length);
    } catch (e) {
        console.error('Projects Exception:', e);
    }

    console.log('\n--- Checking Jobs ---');
    try {
        const start = Date.now();
        const { data: jobs, error: jError } = await supabase
            .from('jobs')
            .select(`*, profiles:posted_by (full_name, avatar_url, username)`)
            .eq('is_active', true)
            .limit(5);

        console.log('Jobs query took:', Date.now() - start, 'ms');
        if (jError) console.error('Jobs Error:', jError);
        else console.log('Jobs found:', jobs?.length);
    } catch (e) {
        console.error('Jobs Exception:', e);
    }
}

checkQueries();
