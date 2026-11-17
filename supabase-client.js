(function () {
  const config = window.FAMILJEAVENTYRET_SUPABASE;
  if (!config || !window.supabase?.createClient) {
    window.supabaseClient = null;
    window.supabaseConnectionError = 'Supabase-klienten kunde inte laddas.';
    return;
  }
  window.supabaseClient = window.supabase.createClient(config.url, config.publishableKey, {
    auth: { autoRefreshToken: true, persistSession: true, detectSessionInUrl: true }
  });
})();
