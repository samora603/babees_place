import { lazy, Suspense, useCallback, useEffect, useState } from 'react';
import { analyticsService } from '@/services/analyticsService';
import { isDashboardEmpty, kpisToCardValues } from '@/models/dashboard';
import KPICard from '@/components/admin/dashboard/KPICard';
import DashboardLoadingState from '@/components/admin/dashboard/DashboardLoadingState';
import DashboardEmptyState from '@/components/admin/dashboard/DashboardEmptyState';
import DashboardErrorState from '@/components/admin/dashboard/DashboardErrorState';
import DashboardPageHeader from '@/components/admin/dashboard/DashboardPageHeader';
import DashboardWidgetCard from '@/components/admin/dashboard/DashboardWidgetCard';
import DashboardWidgetSkeleton from '@/components/admin/dashboard/DashboardWidgetSkeleton';
import RevenueSummaryCard from '@/components/admin/dashboard/RevenueSummaryCard';
import SalesSummaryCard from '@/components/admin/dashboard/SalesSummaryCard';
import RecentOrdersWidget from '@/components/admin/dashboard/RecentOrdersWidget';
import LowStockWidget from '@/components/admin/dashboard/LowStockWidget';
import TopProductsWidget from '@/components/admin/dashboard/TopProductsWidget';
import TopCategoriesWidget from '@/components/admin/dashboard/TopCategoriesWidget';
import RecentActivityWidget from '@/components/admin/dashboard/RecentActivityWidget';

const RevenueTrendChart = lazy(() => import('@/components/admin/dashboard/RevenueTrendChart'));
const OrdersStatusChart = lazy(() => import('@/components/admin/dashboard/OrdersStatusChart'));
const FulfillmentChart = lazy(() => import('@/components/admin/dashboard/FulfillmentChart'));
const PaymentStatusChart = lazy(() => import('@/components/admin/dashboard/PaymentStatusChart'));

function ChartSuspenseFallback({ title }) {
  return (
    <DashboardWidgetCard title={title}>
      <DashboardWidgetSkeleton rows={6} />
    </DashboardWidgetCard>
  );
}

export default function AdminDashboard() {
  const [snapshot, setSnapshot] = useState(null);
  const [revenueSummary, setRevenueSummary] = useState(null);
  const [salesSummary, setSalesSummary] = useState(null);
  const [ordersByStatus, setOrdersByStatus] = useState([]);
  const [ordersByFulfillment, setOrdersByFulfillment] = useState([]);
  const [ordersByPayment, setOrdersByPayment] = useState([]);
  const [recentOrders, setRecentOrders] = useState([]);
  const [lowStockProducts, setLowStockProducts] = useState([]);
  const [topProducts, setTopProducts] = useState([]);
  const [topCategories, setTopCategories] = useState([]);
  const [activityEvents, setActivityEvents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [snapshotError, setSnapshotError] = useState(null);
  const [revenueError, setRevenueError] = useState(null);
  const [salesError, setSalesError] = useState(null);
  const [statusChartError, setStatusChartError] = useState(null);
  const [fulfillmentChartError, setFulfillmentChartError] = useState(null);
  const [paymentChartError, setPaymentChartError] = useState(null);
  const [ordersError, setOrdersError] = useState(null);
  const [lowStockError, setLowStockError] = useState(null);
  const [topProductsError, setTopProductsError] = useState(null);
  const [topCategoriesError, setTopCategoriesError] = useState(null);
  const [activityError, setActivityError] = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    setSnapshotError(null);
    setRevenueError(null);
    setSalesError(null);
    setStatusChartError(null);
    setFulfillmentChartError(null);
    setPaymentChartError(null);
    setOrdersError(null);
    setLowStockError(null);
    setTopProductsError(null);
    setTopCategoriesError(null);
    setActivityError(null);

    const [
      snapshotResult,
      revenueResult,
      salesResult,
      statusResult,
      fulfillmentResult,
      paymentResult,
      ordersResult,
      lowStockResult,
      topProductsResult,
      topCategoriesResult,
      activityResult,
    ] = await Promise.all([
      analyticsService.getDashboardSnapshot(),
      analyticsService.getRevenueSummary(),
      analyticsService.getSalesSummary(),
      analyticsService.getOrdersByStatus(),
      analyticsService.getOrdersByFulfillment(),
      analyticsService.getOrdersByPaymentStatus(),
      analyticsService.getRecentOrders(10),
      analyticsService.getLowStockProducts(),
      analyticsService.getTopSellingProducts(10),
      analyticsService.getTopCategories(10),
      analyticsService.getDashboardActivity(15),
    ]);

    setSnapshot(snapshotResult.data);
    setSnapshotError(snapshotResult.error || null);
    setRevenueSummary(revenueResult.data);
    setRevenueError(revenueResult.error || null);
    setSalesSummary(salesResult.data);
    setSalesError(salesResult.error || null);
    setOrdersByStatus(statusResult.data);
    setStatusChartError(statusResult.error || null);
    setOrdersByFulfillment(fulfillmentResult.data);
    setFulfillmentChartError(fulfillmentResult.error || null);
    setOrdersByPayment(paymentResult.data);
    setPaymentChartError(paymentResult.error || null);
    setRecentOrders(ordersResult.data);
    setOrdersError(ordersResult.error || null);
    setLowStockProducts(lowStockResult.data);
    setLowStockError(lowStockResult.error || null);
    setTopProducts(topProductsResult.data);
    setTopProductsError(topProductsResult.error || null);
    setTopCategories(topCategoriesResult.data);
    setTopCategoriesError(topCategoriesResult.error || null);
    setActivityEvents(activityResult.data);
    setActivityError(activityResult.error || null);
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  if (loading) return <DashboardLoadingState />;

  const kpis = snapshot?.kpis;
  const cards = kpis ? kpisToCardValues(kpis) : [];
  const kpiSectionFailed = Boolean(snapshotError);

  return (
    <div className="space-y-8 bg-[#0B0B0B] min-h-full text-slate-200 p-6">
      <DashboardPageHeader />

      {kpiSectionFailed ? (
        <DashboardErrorState
          message={snapshotError?.message || 'Unable to load dashboard KPIs.'}
          onRetry={load}
        />
      ) : kpis && isDashboardEmpty(kpis) ? (
        <DashboardEmptyState />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6">
          {cards.map((kpi) => (
            <KPICard key={kpi.key} kpi={kpi} />
          ))}
        </div>
      )}

      <RevenueSummaryCard
        summary={revenueSummary}
        loading={false}
        error={revenueError}
        onRetry={load}
      />

      <Suspense fallback={<ChartSuspenseFallback title="Revenue Trend" />}>
        <RevenueTrendChart
          summary={revenueSummary}
          loading={false}
          error={revenueError}
          onRetry={load}
        />
      </Suspense>

      <SalesSummaryCard
        summary={salesSummary}
        loading={false}
        error={salesError}
        onRetry={load}
      />

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        <Suspense fallback={<ChartSuspenseFallback title="Orders by Status" />}>
          <OrdersStatusChart
            statusCounts={ordersByStatus}
            loading={false}
            error={statusChartError}
            onRetry={load}
          />
        </Suspense>
        <Suspense fallback={<ChartSuspenseFallback title="Fulfillment Distribution" />}>
          <FulfillmentChart
            fulfillmentCounts={ordersByFulfillment}
            loading={false}
            error={fulfillmentChartError}
            onRetry={load}
          />
        </Suspense>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        <Suspense fallback={<ChartSuspenseFallback title="Payment Status" />}>
          <PaymentStatusChart
            paymentCounts={ordersByPayment}
            loading={false}
            error={paymentChartError}
            onRetry={load}
          />
        </Suspense>
        <TopCategoriesWidget
          categories={topCategories}
          loading={false}
          error={topCategoriesError}
          onRetry={load}
        />
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        <RecentOrdersWidget
          orders={recentOrders}
          loading={false}
          error={ordersError}
          onRetry={load}
        />
        <LowStockWidget
          products={lowStockProducts}
          loading={false}
          error={lowStockError}
          onRetry={load}
        />
      </div>

      <TopProductsWidget
        products={topProducts}
        loading={false}
        error={topProductsError}
        onRetry={load}
      />

      <RecentActivityWidget
        events={activityEvents}
        loading={false}
        error={activityError}
        onRetry={load}
      />
    </div>
  );
}
