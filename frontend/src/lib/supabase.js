import { supabase } from './supabaseClient';

// Re-export the default client so modules importing from '@/lib/supabase'
// continue to work (some files use that path). This keeps imports
// consistent and avoids duplicate client creation.
export { supabase };
