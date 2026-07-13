import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/context/AuthContext';
import { useCart } from '@/context/CartContext';
import { orderService } from '@/services/orderService';
import { summarizeReorderResult } from '@/models/fasterCheckout';
import Button from '@/components/ui/Button';
import toast from 'react-hot-toast';
import { FiRefreshCw } from 'react-icons/fi';

/**
 * Add all items from a prior order to the cart.
 */
export default function ReorderButton({ orderId, variant = 'secondary', className = '' }) {
  const { user } = useAuth();
  const { reloadCart } = useCart();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);

  const handleReorder = async () => {
    if (!user?.id) {
      toast.error('Please sign in to reorder');
      return;
    }

    setLoading(true);
    try {
      const result = await orderService.reorder(orderId, user.id);
      const summary = summarizeReorderResult(result);

      if (!summary.success) {
        toast.error(summary.message);
        return;
      }

      await reloadCart();
      toast.success(summary.message);
      navigate('/cart');
    } catch (err) {
      console.error(err);
      toast.error(err.message || 'Reorder failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Button
      variant={variant}
      onClick={handleReorder}
      loading={loading}
      disabled={loading}
      className={`text-sm flex items-center gap-2 ${className}`}
    >
      <FiRefreshCw size={14} />
      Reorder
    </Button>
  );
}
