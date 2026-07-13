import { useEffect, useState } from 'react';
import { checkoutService } from '@/services/checkoutService';
import ExpressCheckoutBanner from '@/components/checkout/ExpressCheckoutBanner';

/**
 * Loads express checkout eligibility for the cart sidebar.
 */
export default function CartExpressHint({ cartValid }) {
  const [summary, setSummary] = useState(null);

  useEffect(() => {
    if (!cartValid) {
      setSummary(null);
      return;
    }

    let mounted = true;

    checkoutService.getCheckoutBootstrap()
      .then(({ pickupLocations, addresses, preferences }) => {
        if (!mounted) return;
        const status = checkoutService.getExpressCheckoutStatus({
          preferences,
          addresses,
          pickupLocations,
          cartValid: true,
        });
        setSummary(status.eligible ? status.summary : null);
      })
      .catch(() => {
        if (mounted) setSummary(null);
      });

    return () => {
      mounted = false;
    };
  }, [cartValid]);

  return <ExpressCheckoutBanner summary={summary} />;
}
