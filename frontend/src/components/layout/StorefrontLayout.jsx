import { Outlet } from 'react-router-dom';
import Navbar from '@/components/layout/Navbar';
import Footer from '@/components/layout/Footer';
import FloatingCartButton from '@/components/layout/FloatingCartButton';

/**
 * Shared chrome for all customer-facing routes.
 * Admin routes use AdminLayout separately and must not nest here.
 */
export default function StorefrontLayout() {
  return (
    <div className="min-h-screen flex flex-col bg-[#0B0B0B]">
      <Navbar />
      <main className="flex-1">
        <Outlet />
      </main>
      <Footer />
      <FloatingCartButton />
    </div>
  );
}
