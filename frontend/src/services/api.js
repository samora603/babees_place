import axios from 'axios';

// Legacy api client neutralized.
// The project has migrated to Supabase for most data access. Keep a minimal axios instance
// here for backward compatibility if any third-party libraries still import it.
const api = axios.create({
    // no baseURL to prevent accidental '/api' network calls in a backend-less environment
    headers: { 'Content-Type': 'application/json' },
    timeout: 15000,
});

export default api;
