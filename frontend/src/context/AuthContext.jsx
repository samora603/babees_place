import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import toast from 'react-hot-toast';
import { supabase } from '@/lib/supabaseClient';
import * as authService from '@/services/authService';

const AuthContext = createContext(null);

const AUTH_PAGES = ['/login', '/register'];

export function isAdminRole(role) {
  return role === 'admin';
}

export function resolvePostLoginPath(role) {
  return isAdminRole(role) ? '/admin/dashboard' : '/shop';
}

export const AuthProvider = ({ children }) => {
  const navigate = useNavigate();
  const location = useLocation();

  const [user, setUser] = useState(null);
  const [profile, setProfile] = useState(null);
  const [initializing, setInitializing] = useState(true);

  const manualAuthRef = useRef(false);
  const profileRequestRef = useRef(0);

  const fetchProfile = useCallback(async (userId) => {
    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .maybeSingle();

    if (error) {
      console.error('Profile fetch error:', error);
      return null;
    }

    return data;
  }, []);

  const ensureProfile = useCallback(async (authUser) => {
    if (!authUser?.id) return null;

    const existing = await fetchProfile(authUser.id);
    if (existing) return existing;

    const { data, error } = await supabase
      .from('profiles')
      .insert({
        id: authUser.id,
        email: authUser.email,
        full_name: authUser.user_metadata?.full_name || '',
        phone: authUser.user_metadata?.phone || '',
        role: 'customer',
      })
      .select()
      .single();

    if (error) {
      // Race with handle_new_user trigger — re-fetch instead of failing hard
      console.error('Profile bootstrap error:', error);
      return fetchProfile(authUser.id);
    }

    return data;
  }, [fetchProfile]);

  const clearAuthState = useCallback(() => {
    setUser(null);
    setProfile(null);
  }, []);

  const applyAuthSession = useCallback(async (authUser) => {
    if (!authUser) {
      clearAuthState();
      return { user: null, profile: null };
    }

    const requestId = ++profileRequestRef.current;
    const prof = await ensureProfile(authUser);

    if (requestId !== profileRequestRef.current) {
      return { user: authUser, profile: prof };
    }

    if (!prof) {
      // Do not leave a half-authenticated session in React state
      clearAuthState();
      return { user: authUser, profile: null };
    }

    setUser(authUser);
    setProfile(prof);
    return { user: authUser, profile: prof };
  }, [ensureProfile, clearAuthState]);

  const refreshProfile = async () => {
    if (!user?.id) return null;
    const prof = await fetchProfile(user.id);
    setProfile(prof);
    return prof;
  };

  const login = async (email, password) => {
    manualAuthRef.current = true;

    try {
      const { data, error } = await authService.signInWithPassword(email, password);
      if (error) throw error;

      const authUser = data?.user;
      if (!authUser) {
        throw new Error('Login succeeded but no user was returned.');
      }

      const result = await applyAuthSession(authUser);
      if (!result.profile) {
        await authService.signOut().catch(() => {});
        clearAuthState();
        throw new Error(
          'Signed in, but your profile could not be loaded. Contact support or try again.',
        );
      }

      return data;
    } finally {
      manualAuthRef.current = false;
    }
  };

  const signup = async (email, password, fullName, phone = null) => {
    manualAuthRef.current = true;

    try {
      const { data, error } = await authService.signUp(email, password, {
        fullName,
        phone: phone || '',
      });

      if (error) throw error;

      const authUser = data?.user;
      if (!authUser) {
        throw new Error('Signup failed. Check your email for confirmation.');
      }

      if (data.session?.user) {
        const result = await applyAuthSession(data.session.user);
        if (!result.profile) {
          await authService.signOut().catch(() => {});
          clearAuthState();
          throw new Error(
            'Account created, but your profile could not be loaded. Try signing in.',
          );
        }
      }

      return { user: authUser, session: data.session || null };
    } finally {
      manualAuthRef.current = false;
    }
  };

  const updateProfile = async (payload) => {
    if (!user?.id) throw new Error('Not authenticated');

    const {
      full_name,
      name,
      email,
      role,
      is_admin,
      id,
      created_at,
      ...rest
    } = payload;
    void role;
    void is_admin;
    void id;
    void created_at;
    const update = { ...rest };

    if (full_name !== undefined || name !== undefined) {
      update.full_name = full_name ?? name;
    }
    if (email !== undefined) {
      update.email = email;
    }

    const { data, error } = await supabase
      .from('profiles')
      .update(update)
      .eq('id', user.id)
      .select()
      .single();

    if (error) throw error;

    setProfile(data);
    return data;
  };

  const logout = async () => {
    try {
      await authService.signOut();
    } catch (err) {
      console.error('Logout error:', err);
      toast.error('Sign out failed. Please try again.');
      return;
    }
    clearAuthState();
    navigate('/login', { replace: true });
  };

  useEffect(() => {
    let mounted = true;

    const bootstrap = async () => {
      try {
        const { data } = await authService.getSession();
        if (!mounted) return;

        if (data?.session?.user) {
          await applyAuthSession(data.session.user);
        } else {
          clearAuthState();
        }
      } finally {
        if (mounted) setInitializing(false);
      }
    };

    bootstrap();

    const {
      data: { subscription },
    } = authService.onAuthStateChange((event, session) => {
      if (!mounted) return;

      if (event === 'SIGNED_OUT' || !session?.user) {
        clearAuthState();
        return;
      }

      if (manualAuthRef.current) {
        return;
      }

      if (event === 'TOKEN_REFRESHED') {
        setUser(session.user);
        return;
      }

      if (event === 'SIGNED_IN') {
        queueMicrotask(() => {
          if (!mounted || manualAuthRef.current) return;
          void applyAuthSession(session.user);
        });
      }
    });

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, [applyAuthSession, clearAuthState]);

  useEffect(() => {
    if (initializing || !user || !profile) return;

    const path = location.pathname;
    if (!AUTH_PAGES.includes(path)) return;

    const from = location.state?.from?.pathname;
    const safeFrom =
      from && !AUTH_PAGES.includes(from) && !from.startsWith('/login')
        ? from
        : null;

    navigate(safeFrom || resolvePostLoginPath(profile.role), { replace: true });
  }, [user, profile, initializing, navigate, location.pathname, location.state]);

  return (
    <AuthContext.Provider
      value={{
        user,
        profile,
        loading: initializing,
        login,
        signup,
        logout,
        refreshProfile,
        updateProfile,
        isAuthenticated: !!user && !!profile,
        isAdmin: isAdminRole(profile?.role),
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => useContext(AuthContext);
