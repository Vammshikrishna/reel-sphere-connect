// deno-lint-ignore-file
import { corsHeaders } from "../_shared/cors.ts";

const TMDB_BASE_URL = 'https://api.themoviedb.org/3';

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const TMDB_API_KEY = Deno.env.get('TMDB_API_KEY');
    
    if (!TMDB_API_KEY) {
      return new Response(
        JSON.stringify({ error: 'TMDB API key not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const { path, params = '' } = await req.json();

    if (!path || typeof path !== 'string') {
      return new Response(
        JSON.stringify({ error: 'Invalid path parameter' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate path to prevent SSRF
    if (!path.startsWith('/')) {
      return new Response(
        JSON.stringify({ error: 'Invalid path format' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const url = `${TMDB_BASE_URL}${path}?api_key=${TMDB_API_KEY}&language=en-US${params}`;
    
    const response = await fetch(url);
    const data = await response.json();

    return new Response(JSON.stringify(data), {
      status: response.status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('TMDB proxy error:', error);
    return new Response(
      JSON.stringify({ error: 'Failed to fetch from TMDB' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
