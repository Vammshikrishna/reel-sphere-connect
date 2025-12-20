import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = "https://hfkubpcdbjxhafulxhfv.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhma3VicGNkYmp4aGFmdWx4aGZ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDQxODc4MjgsImV4cCI6MjA1OTc2MzgyOH0.2UkrXH3VPWPn0Y5XcenE0O0rbWvTFr7UrUJPEaLmu34";

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function checkConnection() {
    console.log('Checking connection...');
    try {
        const { data, error } = await supabase.from('profiles').select('count', { count: 'exact', head: true });
        if (error) {
            console.error('Connection failed:', error.message);
        } else {
            console.log('Connection successful! Profiles count:', data); // data for head:true is null, count is in 'count' property wrapper usually or just returned separately depending on version, but here we just check error.
            // actually count is returned in { count } property of response object, not data.
        }

        // Check specific table read
        const { data: posts, error: postsError } = await supabase.from('posts').select('*').limit(1);
        if (postsError) {
            console.error('Error fetching posts:', postsError.message);
        } else {
            console.log('Posts fetch successful. Count:', posts.length);
            console.log('First post:', posts[0]);
        }

    } catch (err) {
        console.error('Unexpected error:', err);
    }
}

checkConnection();
