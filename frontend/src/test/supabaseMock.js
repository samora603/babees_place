/**
 * Minimal chainable Supabase client mock for unit/smoke tests.
 * Every query-builder method returns the same thenable so calls can be
 * chained arbitrarily (e.g. .from().select().eq().maybeSingle()).
 */
export function makeQuery(result = { data: [], error: null }) {
  const q = {};
  const methods = [
    'select',
    'insert',
    'update',
    'upsert',
    'delete',
    'eq',
    'neq',
    'in',
    'is',
    'order',
    'limit',
    'range',
    'ilike',
    'like',
    'gte',
    'lte',
    'gt',
    'lt',
    'contains',
    'match',
    'or',
    'filter',
    'single',
    'maybeSingle',
    'textSearch',
  ];
  methods.forEach((m) => {
    q[m] = () => q;
  });
  q.then = (resolve) => resolve(result);
  return q;
}

export function makeChannel() {
  const ch = {
    on: () => ch,
    subscribe: () => ch,
    unsubscribe: () => ch,
  };
  return ch;
}

export function createSupabaseMock() {
  return {
    from: () => makeQuery({ data: [], error: null }),
    rpc: () => Promise.resolve({ data: null, error: null }),
    channel: () => makeChannel(),
    removeChannel: () => {},
    auth: {
      getSession: () => Promise.resolve({ data: { session: null }, error: null }),
      getUser: () => Promise.resolve({ data: { user: null }, error: null }),
      onAuthStateChange: () => ({
        data: { subscription: { unsubscribe() {} } },
      }),
      signInWithPassword: () => Promise.resolve({ data: { user: null }, error: null }),
      signUp: () => Promise.resolve({ data: { user: null }, error: null }),
      signOut: () => Promise.resolve({ error: null }),
    },
    storage: {
      from: () => ({
        upload: () => Promise.resolve({ data: null, error: null }),
        getPublicUrl: () => ({ data: { publicUrl: '' } }),
      }),
    },
  };
}
