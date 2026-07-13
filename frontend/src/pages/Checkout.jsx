import { useState, useEffect, useCallback, useMemo } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useCart } from "@/context/CartContext";
import { useAuth } from "@/context/AuthContext";
import { supabase } from "@/lib/supabaseClient";
import { orderService } from "@/services/orderService";
import { checkoutService } from "@/services/checkoutService";
import { addressService } from "@/services/addressService";
import { paymentService } from "@/services/paymentService";
import { validateCheckoutPayment } from "@/services/paymentValidation";
import { formatCurrency } from "@/utils/helpers";
import { DELIVERY_TYPES } from "@/utils/constants";
import { DELIVERY_FEE } from "@/utils/orderStatus";
import { validateCheckoutForm, buildDeliveryAddressPayload } from "@/utils/orderValidation";
import {
  addressToCheckoutDelivery,
  validateAddressInput,
  getDefaultAddress,
  EMPTY_ADDRESS_FORM,
} from "@/models/address";
import CheckoutDeliverySection, { emptyCheckoutAddress } from "@/components/checkout/CheckoutDeliverySection";
import ExpressCheckoutPanel from "@/components/checkout/ExpressCheckoutPanel";
import PaymentMethodSelector from "@/components/checkout/PaymentMethodSelector";
import MpesaPaymentPanel from "@/components/checkout/MpesaPaymentPanel";
import CheckoutRewardsPanel, { useCheckoutRewardsState } from "@/components/checkout/CheckoutRewardsPanel";
import { checkoutRewardsService } from "@/services/checkoutRewardsService";
import toast from "react-hot-toast";
import { GiBee } from "react-icons/gi";
import Button from "@/components/ui/Button";
import { isOutOfStock } from "@/constants/inventory";

export default function Checkout() {
  const { cart, subtotal, reloadCart, getItemPrice, getItemImage, loading: cartLoading } = useCart();
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const [submitting, setSubmitting] = useState(false);
  const [pickupLocations, setPickupLocations] = useState([]);
  const [savedAddresses, setSavedAddresses] = useState([]);
  const [loadingLocations, setLoadingLocations] = useState(true);
  const [errors, setErrors] = useState({});
  const [addressMode, setAddressMode] = useState("once");
  const [selectedAddressId, setSelectedAddressId] = useState("");
  const [newAddressForm, setNewAddressForm] = useState({ ...EMPTY_ADDRESS_FORM });
  const [saveNewAddress, setSaveNewAddress] = useState(true);
  const [checkoutPreferences, setCheckoutPreferences] = useState(null);
  const [paymentMethod, setPaymentMethod] = useState("cod");
  const [mpesaPhone, setMpesaPhone] = useState("");
  const [paymentStatusMessage, setPaymentStatusMessage] = useState("");
  const rewards = useCheckoutRewardsState();
  const [form, setForm] = useState({
    deliveryType: "pickup",
    pickupLocationId: "",
    deliveryAddress: { ...emptyCheckoutAddress },
    customerNote: "",
  });

  const bootstrapCheckout = useCallback(async () => {
    setLoadingLocations(true);
    try {
      const { pickupLocations: locations, addresses, preferences } =
        await checkoutService.getCheckoutBootstrap();
      setPickupLocations(locations);
      setSavedAddresses(addresses);
      setCheckoutPreferences(preferences);

      const defaultAddr = getDefaultAddress(addresses);
      const preferredType = preferences?.preferredFulfillment || "pickup";
      const preferredPickup = preferences?.preferredPickupLocationId || "";
      const phone = profile?.phone || defaultAddr?.phone || "";

      setForm((f) => ({
        ...f,
        deliveryType: preferredType,
        pickupLocationId: preferredType === "pickup" ? preferredPickup : "",
        deliveryAddress: defaultAddr
          ? addressToCheckoutDelivery(defaultAddr)
          : {
            ...emptyCheckoutAddress,
            phone: phone || "",
          },
      }));

      if (phone) setMpesaPhone(phone);

      if (addresses.length > 0) {
        setAddressMode("saved");
        setSelectedAddressId(defaultAddr?.id || addresses[0].id);
      }

      setNewAddressForm({
        ...EMPTY_ADDRESS_FORM,
        recipientName: profile?.full_name || "",
        phone: profile?.phone || "",
      });
    } catch {
      toast.error("Failed to load checkout options");
    } finally {
      setLoadingLocations(false);
    }
  }, [profile]);

  useEffect(() => {
    bootstrapCheckout();
  }, [bootstrapCheckout]);

  const cartBlocked = cart.some((item) => {
    const p = item.product || {};
    return p.is_active === false || isOutOfStock(p.stock ?? 0)
      || Number(item.quantity) > (p.stock ?? 0);
  });

  const expressStatus = useMemo(
    () => checkoutService.getExpressCheckoutStatus({
      preferences: checkoutPreferences,
      addresses: savedAddresses,
      pickupLocations,
      cartValid: cart.length > 0 && !cartBlocked,
    }),
    [checkoutPreferences, savedAddresses, pickupLocations, cart.length, cartBlocked],
  );

  const cartLines = useMemo(() => cart.map((item) => {
    const product = item.product || {};
    return {
      id: item.id,
      productId: product.id || item.product_id,
      categoryId: product.category_id || product.categoryId || null,
      price: getItemPrice(item),
      quantity: Number(item.quantity || 1),
      name: product.name,
    };
  }), [cart, getItemPrice]);

  const refreshRewardsPreview = useCallback(async () => {
    if (!cartLines.length) {
      rewards.setPreview(null);
      return;
    }
    try {
      const { data: { user: authUser } } = await supabase.auth.getUser();
      const preview = await checkoutRewardsService.buildCheckoutRewardPreview({
        cartLines,
        userId: authUser?.id || user?.id,
        deliveryType: form.deliveryType,
        couponCode: rewards.appliedCouponCode,
        loyaltyPointsToRedeem: rewards.loyaltyPoints,
        giftCardCode: rewards.appliedGiftCardCode,
      });
      rewards.setPreview(preview);
    } catch (err) {
      console.warn('rewards preview:', err);
    }
  }, [
    cartLines,
    form.deliveryType,
    rewards.appliedCouponCode,
    rewards.loyaltyPoints,
    rewards.appliedGiftCardCode,
    user?.id,
  ]);

  useEffect(() => {
    refreshRewardsPreview();
  }, [refreshRewardsPreview]);

  const deliveryFee = rewards.preview
    ? rewards.preview.deliveryFee
    : (form.deliveryType === "delivery" ? DELIVERY_FEE : 0);
  const total = rewards.preview ? rewards.preview.total : (subtotal + deliveryFee);

  const handleApplyCoupon = async () => {
    rewards.setCouponError('');
    rewards.setCouponMessage('');
    if (!rewards.couponCode.trim()) {
      rewards.setAppliedCouponCode('');
      rewards.setCouponMessage('Coupon cleared');
      return;
    }
    rewards.setAppliedCouponCode(rewards.couponCode.trim());
    // preview refresh via effect
    setTimeout(async () => {
      try {
        const { data: { user: authUser } } = await supabase.auth.getUser();
        const preview = await checkoutRewardsService.buildCheckoutRewardPreview({
          cartLines,
          userId: authUser?.id,
          deliveryType: form.deliveryType,
          couponCode: rewards.couponCode.trim(),
          loyaltyPointsToRedeem: rewards.loyaltyPoints,
          giftCardCode: rewards.appliedGiftCardCode,
        });
        rewards.setPreview(preview);
        if (preview.couponValid === false) {
          rewards.setCouponError(preview.couponErrors?.[0] || 'Invalid coupon');
          rewards.setAppliedCouponCode('');
        } else {
          rewards.setCouponMessage('Coupon applied');
        }
      } catch {
        rewards.setCouponError('Could not validate coupon');
      }
    }, 0);
  };

  const handleApplyGiftCard = async () => {
    rewards.setGiftCardError('');
    rewards.setGiftCardMessage('');
    if (!rewards.giftCardCode.trim()) {
      rewards.setAppliedGiftCardCode('');
      rewards.setGiftCardMessage('Gift card cleared');
      return;
    }
    rewards.setAppliedGiftCardCode(rewards.giftCardCode.trim());
    rewards.setGiftCardMessage('Gift card applied');
  };

  const handleSelectSavedAddress = (addressId) => {
    setSelectedAddressId(addressId);
    const address = savedAddresses.find((a) => a.id === addressId);
    if (address) {
      setForm((f) => ({ ...f, deliveryAddress: addressToCheckoutDelivery(address) }));
      if (address.phone) setMpesaPhone(address.phone);
    }
  };

  const handleAddressModeChange = (mode) => {
    setAddressMode(mode);
    if (mode === "saved" && selectedAddressId) {
      handleSelectSavedAddress(selectedAddressId);
    }
  };

  const resolveDeliveryAddress = () => {
    if (addressMode === "saved") {
      const address = savedAddresses.find((a) => a.id === selectedAddressId);
      return address ? addressToCheckoutDelivery(address) : form.deliveryAddress;
    }
    if (addressMode === "new") {
      return addressToCheckoutDelivery({
        streetAddress: newAddressForm.streetAddress,
        town: newAddressForm.town,
        county: newAddressForm.county,
        phone: newAddressForm.phone,
        recipientName: newAddressForm.recipientName,
        additionalDirections: newAddressForm.additionalDirections,
      });
    }
    return form.deliveryAddress;
  };

  const handleExpressCheckout = async () => {
    if (!expressStatus.eligible || cartBlocked) return;

    setSubmitting(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        toast.error("Please login first");
        return;
      }

      // Express checkout remains COD to preserve the fast path.
      const { order } = await checkoutService.placeExpressOrder(
        user.id,
        expressStatus,
        form.customerNote,
        "cod",
      );
      await reloadCart();
      toast.success("Order placed successfully!");
      navigate(`/orders/${order.id}/confirmation`);
    } catch (err) {
      console.error(err);
      toast.error(err.message || "Express checkout failed");
    } finally {
      setSubmitting(false);
    }
  };

  const handleCheckout = async () => {
    const deliveryAddress = form.deliveryType === "delivery" ? resolveDeliveryAddress() : null;

    if (form.deliveryType === "delivery" && addressMode === "saved" && !selectedAddressId) {
      setErrors({ selectedAddress: "Select a saved address" });
      toast.error("Please select a delivery address");
      return;
    }

    if (form.deliveryType === "delivery" && addressMode === "new") {
      const addrValidation = validateAddressInput(newAddressForm);
      if (!addrValidation.valid) {
        setErrors(addrValidation.errors);
        toast.error("Please complete the new address form");
        return;
      }
    }

    const validation = validateCheckoutForm({
      ...form,
      deliveryAddress: deliveryAddress || form.deliveryAddress,
    });
    if (!validation.valid) {
      setErrors(validation.errors);
      toast.error("Please complete all required fields");
      return;
    }

    const payValidation = validateCheckoutPayment({
      method: paymentMethod,
      phone: mpesaPhone,
      amount: total,
    });
    if (!payValidation.valid) {
      setErrors((prev) => ({ ...prev, ...payValidation.errors }));
      toast.error(Object.values(payValidation.errors)[0] || "Check payment details");
      return;
    }

    setErrors({});
    setSubmitting(true);
    setPaymentStatusMessage("");
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        toast.error("Please login first");
        return;
      }
      if (!cart.length) {
        toast.error("Cart is empty");
        return;
      }
      if (cartBlocked) {
        toast.error("Fix cart issues before checkout");
        return;
      }

      if (form.deliveryType === "delivery" && addressMode === "new" && saveNewAddress) {
        const { error: saveError } = await addressService.createAddress(newAddressForm);
        if (saveError) {
          console.warn("Could not save address:", saveError);
        }
      }

      const rewardPayload = checkoutRewardsService.buildPlaceOrderRewardPayload(
        rewards.preview || { merchandiseDiscount: 0, loyaltyDiscount: 0, loyaltyPoints: 0, giftCardAmount: 0, freeDelivery: false, applied: [], couponValid: false },
        {
          couponCode: rewards.appliedCouponCode,
          giftCardCode: rewards.appliedGiftCardCode,
        },
      );

      const fulfillment = {
        deliveryType: form.deliveryType,
        pickupLocationId: form.deliveryType === "pickup" ? form.pickupLocationId : null,
        deliveryAddress: form.deliveryType === "delivery"
          ? buildDeliveryAddressPayload(deliveryAddress)
          : null,
        customerNote: form.customerNote?.trim() || null,
        paymentMethod,
        couponCode: rewardPayload.p_coupon_code,
        loyaltyPoints: rewardPayload.p_loyalty_points,
        giftCardCode: rewardPayload.p_gift_card_code,
        giftCardAmount: rewardPayload.p_gift_card_amount,
        discountAmount: rewardPayload.p_discount_amount,
        freeDelivery: rewardPayload.p_free_delivery,
        promotionsApplied: rewardPayload.p_promotions_applied,
        amount: total,
      };

      const { order } = await orderService.placeOrder(user.id, fulfillment);
      await reloadCart();

      // COD path: still award loyalty for paid-on-delivery later; award on place for COD convenience
      if (paymentMethod === "cod") {
        import("@/services/loyaltyService")
          .then(({ loyaltyService }) => loyaltyService.awardPointsForOrder(order.id))
          .catch(() => {});
      }

      if (paymentMethod === "mpesa") {
        setPaymentStatusMessage("Sending M-Pesa STK Push…");
        const result = await paymentService.createPaymentForOrder({
          orderId: order.id,
          method: "mpesa",
          phone: mpesaPhone,
          amount: total,
        });
        toast.success("Check your phone for the M-Pesa prompt");
        navigate(`/orders/${order.id}/pay/${result.payment.id}`);
        return;
      }

      toast.success("Order placed successfully!");
      navigate(`/orders/${order.id}/confirmation`);
    } catch (err) {
      console.error(err);
      toast.error(err.message || "Checkout failed");
    } finally {
      setSubmitting(false);
      setPaymentStatusMessage("");
    }
  };

  if (cartLoading || loadingLocations) {
    return (
      <div className="bg-[#0B0B0B] min-h-screen flex items-center justify-center text-slate-400">
        Loading checkout...
      </div>
    );
  }

  if (!cart.length) {
    return (
      <div className="bg-[#0B0B0B] min-h-[70vh] flex flex-col items-center justify-center p-6 text-center">
        <h2 className="font-display font-bold text-2xl text-white mb-4">Nothing to checkout</h2>
        <p className="text-slate-400 mb-6">Your cart is empty.</p>
        <Link to="/shop" className="btn-primary">Browse Collection</Link>
      </div>
    );
  }

  return (
    <div className="bg-[#0B0B0B] min-h-screen text-slate-200 py-12">
      <div className="section-container max-w-4xl">
        <div className="flex items-center gap-4 mb-10 pb-4 border-b border-brand-500/20">
          <GiBee className="text-brand-500 text-4xl opacity-80" />
          <h1 className="font-display font-bold text-4xl text-white uppercase tracking-wide">Secure Checkout</h1>
        </div>

        {cartBlocked && (
          <div className="mb-6 p-4 rounded-xl bg-red-500/10 border border-red-500/30 text-red-300 text-sm">
            Some items in your cart are unavailable or exceed stock. <Link to="/cart" className="underline">Return to cart</Link> to fix.
          </div>
        )}

        {expressStatus.eligible && !cartBlocked && (
          <div className="mb-8">
            <ExpressCheckoutPanel
              summary={`${expressStatus.summary} · Cash on Delivery`}
              totalLabel={formatCurrency(total)}
              onExpressCheckout={handleExpressCheckout}
              disabled={submitting || cartBlocked}
            />
          </div>
        )}

        <div className="grid lg:grid-cols-3 gap-10">
          <div className="lg:col-span-2 space-y-6">
            <div className="card p-6 space-y-4">
              <h2 className="font-display font-semibold text-lg text-white uppercase tracking-widest">Fulfillment</h2>
              <div className="flex gap-3">
                {Object.entries(DELIVERY_TYPES).map(([key, { label, icon }]) => (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setForm((f) => ({ ...f, deliveryType: key }))}
                    className={`flex-1 p-4 rounded-xl border text-sm transition-all ${
                      form.deliveryType === key
                        ? "border-brand-500 bg-brand-500/10 text-brand-400"
                        : "border-surface-border text-slate-400 hover:border-slate-500"
                    }`}
                  >
                    <span className="text-xl block mb-1">{icon}</span>
                    {label}
                  </button>
                ))}
              </div>
              {errors.deliveryType && <p className="text-xs text-red-400">{errors.deliveryType}</p>}

              {form.deliveryType === "pickup" && (
                <div>
                  <label className="text-sm text-slate-400 block mb-1.5">Pickup location *</label>
                  {pickupLocations.length === 0 ? (
                    <p className="text-sm text-amber-400">No pickup locations available. Contact support.</p>
                  ) : (
                    <select
                      value={form.pickupLocationId}
                      onChange={(e) => setForm((f) => ({ ...f, pickupLocationId: e.target.value }))}
                      className="input w-full"
                    >
                      <option value="">Select location…</option>
                      {pickupLocations.map((loc) => (
                        <option key={loc.id} value={loc.id}>{loc.name} — {loc.building}</option>
                      ))}
                    </select>
                  )}
                  {errors.pickupLocationId && <p className="text-xs text-red-400 mt-1">{errors.pickupLocationId}</p>}
                </div>
              )}

              {form.deliveryType === "delivery" && (
                <CheckoutDeliverySection
                  savedAddresses={savedAddresses}
                  addressMode={addressMode}
                  onAddressModeChange={handleAddressModeChange}
                  selectedAddressId={selectedAddressId}
                  onSelectSavedAddress={handleSelectSavedAddress}
                  deliveryAddress={form.deliveryAddress}
                  onDeliveryAddressChange={(field, value) => setForm((f) => ({
                    ...f,
                    deliveryAddress: { ...f.deliveryAddress, [field]: value },
                  }))}
                  newAddressForm={newAddressForm}
                  onNewAddressFieldChange={(field, value) => setNewAddressForm((prev) => ({ ...prev, [field]: value }))}
                  saveNewAddress={saveNewAddress}
                  onSaveNewAddressChange={setSaveNewAddress}
                  newAddressErrors={addressMode === "new" ? errors : {}}
                  errors={addressMode === "once" || savedAddresses.length === 0 ? errors : {}}
                />
              )}
              {errors.selectedAddress && <p className="text-xs text-red-400">{errors.selectedAddress}</p>}

              <div>
                <label className="text-sm text-slate-400 block mb-1.5">Order note (optional)</label>
                <textarea className="input w-full" rows={2} value={form.customerNote}
                  onChange={(e) => setForm((f) => ({ ...f, customerNote: e.target.value }))} />
              </div>
            </div>

            <div className="card p-6 space-y-4">
              <PaymentMethodSelector
                value={paymentMethod}
                onChange={setPaymentMethod}
                disabled={submitting}
                error={errors.method}
              />
              {paymentMethod === "mpesa" && (
                <MpesaPaymentPanel
                  phone={mpesaPhone}
                  onPhoneChange={setMpesaPhone}
                  disabled={submitting}
                  error={errors.phone}
                  statusMessage={paymentStatusMessage}
                />
              )}
            </div>

            <CheckoutRewardsPanel
              couponCode={rewards.couponCode}
              onCouponCodeChange={rewards.setCouponCode}
              onApplyCoupon={handleApplyCoupon}
              couponMessage={rewards.couponMessage}
              couponError={rewards.couponError}
              loyaltyBalance={rewards.preview?.loyaltyBalance || 0}
              loyaltyPoints={rewards.loyaltyPoints}
              onLoyaltyPointsChange={rewards.setLoyaltyPoints}
              giftCardCode={rewards.giftCardCode}
              onGiftCardCodeChange={rewards.setGiftCardCode}
              onApplyGiftCard={handleApplyGiftCard}
              giftCardMessage={rewards.giftCardMessage}
              giftCardError={rewards.giftCardError}
              preview={rewards.preview}
              disabled={submitting}
            />

            <div className="space-y-4">
              <h2 className="font-display font-semibold text-lg text-white uppercase tracking-widest">Order Review</h2>
              {cart.map((item) => {
                const product = item.product || {};
                const price = getItemPrice(item);
                const image = getItemImage(item);
                return (
                  <div key={item.id} className="p-4 rounded-2xl bg-[#111] border border-brand-500/10 flex gap-4">
                    <img src={image} alt={product.name} className="w-20 h-20 object-cover rounded-xl border border-brand-500/20" />
                    <div className="flex-1">
                      <p className="font-medium text-white">{product.name}</p>
                      <p className="text-sm text-slate-400">Qty: {item.quantity}</p>
                    </div>
                    <p className="font-display font-bold text-brand-400">{formatCurrency(price * item.quantity)}</p>
                  </div>
                );
              })}
            </div>
          </div>

          <div className="lg:col-span-1">
            <div className="bg-[#111] p-8 rounded-2xl border border-brand-500/20 shadow-[0_10px_40px_rgba(0,0,0,0.5)] sticky top-28">
              <h2 className="font-display font-semibold text-xl text-white uppercase tracking-widest mb-6 pb-4 border-b border-brand-500/20">
                Summary
              </h2>
              <div className="space-y-3 mb-6 text-sm">
                <div className="flex justify-between">
                  <span className="text-slate-400">Subtotal</span>
                  <span className="text-white">{formatCurrency(subtotal)}</span>
                </div>
                {(rewards.preview?.merchandiseDiscount || 0) > 0 && (
                  <div className="flex justify-between text-brand-400">
                    <span>Discounts</span>
                    <span>−{formatCurrency(rewards.preview.merchandiseDiscount)}</span>
                  </div>
                )}
                {(rewards.preview?.giftCardAmount || 0) > 0 && (
                  <div className="flex justify-between text-brand-400">
                    <span>Gift card</span>
                    <span>−{formatCurrency(rewards.preview.giftCardAmount)}</span>
                  </div>
                )}
                <div className="flex justify-between">
                  <span className="text-slate-400">Delivery</span>
                  <span className="text-white">
                    {form.deliveryType === "delivery"
                      ? (rewards.preview?.freeDelivery ? "Free" : formatCurrency(deliveryFee || DELIVERY_FEE))
                      : "Free (pickup)"}
                  </span>
                </div>
                {(rewards.preview?.savings || 0) > 0 && (
                  <div className="flex justify-between text-xs text-slate-500">
                    <span>You save</span>
                    <span>{formatCurrency(rewards.preview.savings)}</span>
                  </div>
                )}
                <div className="flex justify-between">
                  <span className="text-slate-400">Payment</span>
                  <span className="text-white uppercase tracking-wide text-xs">
                    {paymentMethod === "mpesa" ? "M-Pesa" : "COD"}
                  </span>
                </div>
              </div>
              <div className="border-t border-brand-500/20 pt-4 mb-8 flex justify-between items-end">
                <span className="text-sm uppercase tracking-widest text-slate-400">Total</span>
                <span className="font-display font-bold text-3xl text-brand-400">{formatCurrency(total)}</span>
              </div>
              <Button onClick={handleCheckout} loading={submitting} disabled={cartBlocked} className="w-full py-4 uppercase tracking-widest">
                {paymentMethod === "mpesa" ? "Pay with M-Pesa" : "Place Order"}
              </Button>
              <Link to="/cart" className="block text-center text-sm text-slate-400 hover:text-brand-400 mt-4">
                Back to cart
              </Link>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
