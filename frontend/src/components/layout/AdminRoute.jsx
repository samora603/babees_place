import { Navigate, Outlet } from 'react-router-dom';
import { useAuth, isAdminRole } from '@/context/AuthContext';
import Spinner from '@/components/ui/Spinner';

const AdminRoute = () => {
  const { user, profile, loading } = useAuth();

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Spinner size="lg" />
      </div>
    );
  }

  if (!user) {
    return <Navigate to="/login" replace />;
  }

  if (!profile) {
    return <Navigate to="/shop" replace state={{ authNotice: 'Profile missing — admin access denied.' }} />;
  }

  if (!isAdminRole(profile.role)) {
    return <Navigate to="/shop" replace />;
  }

  return <Outlet />;
};

export default AdminRoute;
