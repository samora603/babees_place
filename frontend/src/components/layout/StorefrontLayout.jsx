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
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[100] focus:rounded-lg focus:bg-brand-500 focus:px-4 focus:py-2 focus:text-sm focus:font-semibold focus:text-black focus:shadow-lg"
      >
        Skip to content
      </a>
      <Navbar />
      <main id="main-content" className="flex-1" tabIndex={-1}>
        <Outlet />
      </main>
      <Footer />
      <FloatingCartButton />
    </div>
  );
}
