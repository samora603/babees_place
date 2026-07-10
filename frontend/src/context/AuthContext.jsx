import {
  createContext,
  useContext,
  useEffect,
  useState,
} from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/lib/supabaseClient";

const AuthContext = createContext(null);

export const AuthProvider = ({ children }) => {
  const navigate = useNavigate();

  const [user, setUser] = useState(null);
  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);

  const fetchProfile = async (userId) => {
    const { data, error } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", userId)
      .maybeSingle();

    if (error) {
      console.error("Profile fetch error:", error);
      return null;
    }

    return data;
  };

  const refreshProfile = async () => {
    if (!user?.id) return null;
    const prof = await fetchProfile(user.id);
    setProfile(prof);
    return prof;
  };

  const login = async (email, password) => {
    setLoading(true);

    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      setLoading(false);
      throw error;
    }

    const authUser = data?.user;

    if (authUser) {
      const prof = await fetchProfile(authUser.id);

      setUser(authUser);
      setProfile(prof);
    }

    setLoading(false);

    return data;
  };

  const signup = async (email, password, fullName, phone = null) => {
    setLoading(true);

    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          full_name: fullName,
          phone: phone || "",
        },
      },
    });

    if (error) {
      setLoading(false);
      throw error;
    }

    setLoading(false);

    return data?.user;
  };

  const updateProfile = async (payload) => {
    if (!user?.id) throw new Error("Not authenticated");

    const { full_name, name, email, ...rest } = payload;
    const update = { ...rest };

    if (full_name !== undefined || name !== undefined) {
      update.full_name = full_name ?? name;
    }
    if (email !== undefined) {
      update.email = email;
    }

    const { data, error } = await supabase
      .from("profiles")
      .update(update)
      .eq("id", user.id)
      .select()
      .single();

    if (error) throw error;

    setProfile(data);
    return data;
  };

  const logout = async () => {
    await supabase.auth.signOut();

    setUser(null);
    setProfile(null);

    navigate("/login", { replace: true });
  };

  useEffect(() => {
    let mounted = true;

    const initAuth = async () => {
      setLoading(true);

      const { data } = await supabase.auth.getSession();
      const session = data?.session;

      if (!mounted) return;

      if (!session?.user) {
        setUser(null);
        setProfile(null);
        setLoading(false);
        return;
      }

      const authUser = session.user;
      const prof = await fetchProfile(authUser.id);

      if (!mounted) return;

      setUser(authUser);
      setProfile(prof);
      setLoading(false);
    };

    initAuth();

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(async (_event, session) => {
      if (!mounted) return;

      if (!session?.user) {
        setUser(null);
        setProfile(null);
        setLoading(false);
        return;
      }

      const authUser = session.user;
      const prof = await fetchProfile(authUser.id);

      if (!mounted) return;

      setUser(authUser);
      setProfile(prof);
      setLoading(false);
    });

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, []);

  // Redirect only after login/register — allow cart, checkout, orders, profile
  useEffect(() => {
    if (loading) return;
    if (!user || !profile) return;

    const path = window.location.pathname;
    const authPages = ["/login", "/register"];

    if (!authPages.includes(path)) return;

    if (profile.role === "admin") {
      navigate("/admin/dashboard", { replace: true });
    } else {
      navigate("/shop", { replace: true });
    }
  }, [user, profile, loading, navigate]);

  return (
    <AuthContext.Provider
      value={{
        user,
        profile,
        loading,
        login,
        signup,
        logout,
        refreshProfile,
        updateProfile,
        isAuthenticated: !!user,
        isAdmin: profile?.role === "admin",
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => useContext(AuthContext);
