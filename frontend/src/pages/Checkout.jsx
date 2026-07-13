import { useState, useEffect, useCallback } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useCart } from "@/context/CartContext";
import { useAuth } from "@/context/AuthContext";
import { supabase } from "@/lib/supabaseClient";
import { orderService } from "@/services/orderService";
import { addressService } from "@/services/addressService";
import { customerProfileService } from "@/services/customerProfileService";
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
import toast from "react-hot-toast";
import { GiBee } from "react-icons/gi";
import Button from "@/components/ui/Button";
import { isOutOfStock } from "@/constants/inventory";

export default function Checkout() {
  const { cart, subtotal, reloadCart, getItemPrice, getItemImage, loading: cartLoading } = useCart();
  const { profile } = useAuth();
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
  const [form, setForm] = useState({
    deliveryType: "pickup",
    pickupLocationId: "",
    deliveryAddress: { ...emptyCheckoutAddress },
    customerNote: "",
  });

  const bootstrapCheckout = useCallback(async () => {
    setLoadingLocations(true);
    try {
      const [locationsResult, bundleResult] = await Promise.all([
        orderService.getActivePickupLocations(),
        customerProfileService.getProfileBundle(),
      ]);
      setPickupLocations(locationsResult.data || []);
      const addresses = bundleResult.data?.addresses || [];
      const preferences = bundleResult.data?.preferences;
      setSavedAddresses(addresses);

      const defaultAddr = getDefaultAddress(addresses);
      const preferredType = preferences?.preferredFulfillment || "pickup";
      const preferredPickup = preferences?.preferredPickupLocationId || "";

      setForm((f) => ({
        ...f,
        deliveryType: preferredType,
        pickupLocationId: preferredType === "pickup" ? preferredPickup : "",
        deliveryAddress: defaultAddr
          ? addressToCheckoutDelivery(defaultAddr)
          : {
            ...emptyCheckoutAddress,
            phone: profile?.phone || "",
          },
      }));

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

  const deliveryFee = form.deliveryType === "delivery" ? DELIVERY_FEE : 0;
  const total = subtotal + deliveryFee;

  const handleSelectSavedAddress = (addressId) => {
    setSelectedAddressId(addressId);
    const address = savedAddresses.find((a) => a.id === addressId);
    if (address) {
      setForm((f) => ({ ...f, deliveryAddress: addressToCheckoutDelivery(address) }));
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
    setErrors({});
    setSubmitting(true);
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

      const fulfillment = {
        deliveryType: form.deliveryType,
        pickupLocationId: form.deliveryType === "pickup" ? form.pickupLocationId : null,
        deliveryAddress: form.deliveryType === "delivery"
          ? buildDeliveryAddressPayload(deliveryAddress)
          : null,
        customerNote: form.customerNote?.trim() || null,
      };

      const { order } = await orderService.placeOrder(user.id, fulfillment);
      await reloadCart();
      toast.success("Order placed successfully!");
      navigate(`/orders/${order.id}/confirmation`);
    } catch (err) {
      console.error(err);
      toast.error(err.message || "Checkout failed");
    } finally {
      setSubmitting(false);
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
                <div className="flex justify-between">
                  <span className="text-slate-400">Delivery</span>
                  <span className="text-white">
                    {form.deliveryType === "delivery" ? formatCurrency(DELIVERY_FEE) : "Free (pickup)"}
                  </span>
                </div>
              </div>
              <div className="border-t border-brand-500/20 pt-4 mb-8 flex justify-between items-end">
                <span className="text-sm uppercase tracking-widest text-slate-400">Total</span>
                <span className="font-display font-bold text-3xl text-brand-400">{formatCurrency(total)}</span>
              </div>
              <p className="text-xs text-slate-500 mb-4">Payment: Cash on delivery / pickup (COD). Pay when you receive your order.</p>
              <Button onClick={handleCheckout} loading={submitting} disabled={cartBlocked} className="w-full py-4 uppercase tracking-widest">
                Place Order
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
