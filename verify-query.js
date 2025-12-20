import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = "https://zugtdutimulibaxwnlbs.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp1Z3RkdXRpbXVsaWJheHdubGJzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0NjA5MzQsImV4cCI6MjA4MTAzNjkzNH0.NRKEzG3QbbQ7r1R0kHVqS1YctfYUv7VbezcFZ3ti8ek";

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function checkComplexQuery() {
    console.log('Testing complex query...');
    try {
        const { data, error } = await supabase
            .from('posts')
            .select('*, profiles:author_id(id, full_name, username, avatar_url, craft)')
            .limit(5);

        if (error) {
            console.error('Complex query FAILED:', error);
        } else {
            console.log('Complex query SUCCESS. Rows:', data.length);
            if (data.length > 0) {
                console.log('First row profiles:', data[0].profiles);
            }
        }
    } catch (err) {
        console.error('Script crashed:', err);
    }
}

checkComplexQuery();
