// deno-lint-ignore-file
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  const startTime = Date.now();
  
  // Check for Authorization header - only return detailed info if authenticated
  const authHeader = req.headers.get('Authorization');
  const isAuthenticated = !!authHeader;

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  
  if (!supabaseUrl || !supabaseKey) {
    // Return minimal error for unauthenticated, detailed for authenticated
    return new Response(
      JSON.stringify({ status: 'unhealthy' }),
      { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseKey, { auth: { persistSession: false } });
    
    // Perform health checks
    let isHealthy = true;

    // Database check - simple ping
    try {
      const { error } = await supabase.from('profiles').select('id').limit(1);
      if (error) isHealthy = false;
    } catch {
      isHealthy = false;
    }

    // Storage check - simple ping
    try {
      const { error } = await supabase.storage.listBuckets();
      if (error) isHealthy = false;
    } catch {
      isHealthy = false;
    }

    // For unauthenticated requests, return only status
    if (!isAuthenticated) {
      return new Response(
        JSON.stringify({ 
          status: isHealthy ? 'healthy' : 'unhealthy',
          timestamp: new Date().toISOString()
        }),
        { 
          status: isHealthy ? 200 : 503, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }

    // For authenticated requests, return detailed info
    const checks: Record<string, unknown> = {
      timestamp: new Date().toISOString(),
      status: isHealthy ? 'healthy' : 'unhealthy',
      responseTime: Date.now() - startTime,
      checks: {
        database: { status: isHealthy ? 'healthy' : 'unhealthy' },
        storage: { status: isHealthy ? 'healthy' : 'unhealthy' }
      }
    };

    return new Response(JSON.stringify(checks), {
      status: isHealthy ? 200 : 503,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch {
    return new Response(
      JSON.stringify({ status: 'unhealthy' }),
      { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
