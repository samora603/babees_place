import { lazy, Suspense } from "react";
import { Routes, Route, Navigate } from "react-router-dom";

import Spinner from "@/components/ui/Spinner";
import StorefrontLayout from "@/components/layout/StorefrontLayout";
import SeoHead from "@/components/SeoHead";

import ProtectedRoute from "@/components/layout/ProtectedRoute";
import AdminRoute from "@/components/layout/AdminRoute";
import AdminLayout from "@/components/layout/AdminLayout";

// Pages
const Home = lazy(() => import("@/pages/Home"));
const Shop = lazy(() => import("@/pages/Shop"));
const ProductDetail = lazy(() => import("@/pages/ProductDetail"));
const Cart = lazy(() => import("@/pages/Cart"));
const Wishlist = lazy(() => import("@/pages/Wishlist"));
const Checkout = lazy(() => import("@/pages/Checkout"));
const OrderConfirmation = lazy(() => import("@/pages/OrderConfirmation"));
const Orders = lazy(() => import("@/pages/Orders"));
const OrderDetail = lazy(() => import("@/pages/OrderDetail"));
const PaymentPending = lazy(() => import("@/pages/PaymentPending"));
const PaymentSuccess = lazy(() => import("@/pages/PaymentSuccess"));
const PaymentFailed = lazy(() => import("@/pages/PaymentFailed"));
const Profile = lazy(() => import("@/pages/Profile"));
const Rewards = lazy(() => import("@/pages/Rewards"));
const Notifications = lazy(() => import("@/pages/Notifications"));
const Login = lazy(() => import("@/pages/Login"));
const Register = lazy(() => import("@/pages/Register"));
const NotFound = lazy(() => import("@/pages/NotFound"));

// Admin
const AdminDashboard = lazy(() => import("@/pages/admin/AdminDashboard"));
const AdminProducts = lazy(() => import("@/pages/admin/AdminProducts"));
const AdminProductForm = lazy(() => import("@/pages/admin/AdminProductForm"));
const AdminOrders = lazy(() => import("@/pages/admin/AdminOrders"));
const AdminOrderDetail = lazy(() => import("@/pages/admin/AdminOrderDetail"));
const AdminNotifications = lazy(() => import("@/pages/admin/AdminNotifications"));
const AdminPromotions = lazy(() => import("@/pages/admin/AdminPromotions"));
const AdminCoupons = lazy(() => import("@/pages/admin/AdminCoupons"));
const AdminGiftCards = lazy(() => import("@/pages/admin/AdminGiftCards"));
const AdminLoyalty = lazy(() => import("@/pages/admin/AdminLoyalty"));
const AdminHealth = lazy(() => import("@/pages/admin/AdminHealth"));
const AdminUsers = lazy(() => import("@/pages/admin/AdminUsers"));
const AdminInventory = lazy(() => import("@/pages/admin/AdminInventory"));
const AdminCategories = lazy(() => import("@/pages/admin/AdminCategories"));
const AdminPickupLocations = lazy(() => import("@/pages/admin/AdminPickupLocations"));
const AdminSettings = lazy(() => import("@/pages/admin/AdminSettings"));

const PageLoader = () => (
  <div className="min-h-screen flex items-center justify-center">
    <Spinner size="lg" />
  </div>
);

function App() {
  return (
    <Suspense fallback={<PageLoader />}>
      <SeoHead />
      <Routes>
        {/* ADMIN first — avoids storefront splat stealing /admin/* */}
        <Route element={<AdminRoute />}>
          <Route path="/admin" element={<AdminLayout />}>
            <Route index element={<Navigate to="/admin/dashboard" replace />} />
            <Route path="dashboard" element={<AdminDashboard />} />
            <Route path="products" element={<AdminProducts />} />
            <Route path="products/new" element={<AdminProductForm />} />
            <Route path="products/:id/edit" element={<AdminProductForm />} />
            <Route path="categories" element={<AdminCategories />} />
            <Route path="orders" element={<AdminOrders />} />
            <Route path="orders/:id" element={<AdminOrderDetail />} />
            <Route path="notifications" element={<AdminNotifications />} />
            <Route path="promotions" element={<AdminPromotions />} />
            <Route path="coupons" element={<AdminCoupons />} />
            <Route path="gift-cards" element={<AdminGiftCards />} />
            <Route path="loyalty" element={<AdminLoyalty />} />
            <Route path="health" element={<AdminHealth />} />
            <Route path="users" element={<AdminUsers />} />
            <Route path="inventory" element={<AdminInventory />} />
            <Route path="pickup-locations" element={<AdminPickupLocations />} />
            <Route path="settings" element={<AdminSettings />} />
          </Route>
        </Route>

        {/* CUSTOMER STOREFRONT — shared Navbar / Footer / floating cart */}
        <Route element={<StorefrontLayout />}>
          <Route path="/" element={<Home />} />
          <Route path="/shop" element={<Shop />} />
          <Route path="/shop/:idOrSlug" element={<ProductDetail />} />
          <Route path="/login" element={<Login />} />
          <Route path="/register" element={<Register />} />

          <Route element={<ProtectedRoute />}>
            <Route path="/cart" element={<Cart />} />
            <Route path="/wishlist" element={<Wishlist />} />
            <Route path="/checkout" element={<Checkout />} />
            <Route path="/orders" element={<Orders />} />
            <Route path="/orders/:id" element={<OrderDetail />} />
            <Route path="/orders/:id/confirmation" element={<OrderConfirmation />} />
            <Route path="/orders/:id/pay/:paymentId" element={<PaymentPending />} />
            <Route path="/payment/success/:orderId" element={<PaymentSuccess />} />
            <Route path="/payment/failed/:orderId" element={<PaymentFailed />} />
            <Route path="/profile" element={<Profile />} />
            <Route path="/rewards" element={<Rewards />} />
            <Route path="/notifications" element={<Notifications />} />
          </Route>

          <Route path="*" element={<NotFound />} />
        </Route>
      </Routes>
    </Suspense>
  );
}

export default App;
