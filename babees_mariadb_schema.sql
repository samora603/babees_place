-- =====================================================
-- Babees Place PostgreSQL -> MariaDB schema
-- Generated automatically. Review before execution.
-- =====================================================

SET FOREIGN_KEY_CHECKS = 0;
SET SQL_MODE = 'NO_AUTO_VALUE_ON_ZERO';

CREATE TABLE IF NOT EXISTS `admin_audit_logs` (
  `id` CHAR(36) NOT NULL,
  `actor_id` CHAR(36) NULL,
  `action` TEXT NOT NULL,
  `entity_type` TEXT NOT NULL,
  `entity_id` TEXT NULL,
  `summary` TEXT NULL,
  `metadata` JSON NOT NULL DEFAULT '{}',
  `ip_hint` TEXT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cart_items` (
  `id` CHAR(36) NOT NULL,
  `user_id` CHAR(36) NOT NULL,
  `product_id` CHAR(36) NULL,
  `quantity` SMALLINT NULL DEFAULT '1',
  `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `categories` (
  `id` CHAR(36) NOT NULL,
  `name` TEXT NOT NULL,
  `slug` TEXT NULL,
  `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `coupon_redemptions` (
  `id` CHAR(36) NOT NULL,
  `coupon_id` CHAR(36) NOT NULL,
  `user_id` CHAR(36) NOT NULL,
  `order_id` CHAR(36) NULL,
  `discount_amount` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `coupons` (
  `id` CHAR(36) NOT NULL,
  `code` TEXT NOT NULL,
  `name` TEXT NOT NULL,
  `description` TEXT NULL,
  `discount_type` TEXT NOT NULL,
  `percent_off` DECIMAL(5,2) NULL,
  `amount_off` DECIMAL(12,2) NULL,
  `free_delivery` TINYINT(1) NOT NULL DEFAULT 0,
  `min_order_amount` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `max_discount_amount` DECIMAL(12,2) NULL,
  `usage_limit` INT NULL,
  `usage_count` INT NOT NULL DEFAULT 0,
  `per_user_limit` INT NULL DEFAULT 1,
  `is_one_time` TINYINT(1) NOT NULL DEFAULT 0,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `starts_at` DATETIME NULL,
  `ends_at` DATETIME NULL,
  `promotion_id` CHAR(36) NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `customer_addresses` (
  `id` CHAR(36) NOT NULL,
  `user_id` CHAR(36) NOT NULL,
  `label` TEXT NOT NULL,
  `recipient_name` TEXT NOT NULL,
  `phone` TEXT NOT NULL,
  `county` TEXT NOT NULL,
  `town` TEXT NOT NULL,
  `street_address` TEXT NOT NULL,
  `additional_directions` TEXT NULL,
  `is_default` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `customer_preferences` (
  `user_id` CHAR(36) NOT NULL,
  `preferred_fulfillment` TEXT NULL,
  `preferred_pickup_location_id` CHAR(36) NULL,
  `marketing_emails` TINYINT(1) NOT NULL DEFAULT 0,
  `sms_notifications` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `email_notifications` TINYINT(1) NOT NULL DEFAULT 1,
  `order_updates` TINYINT(1) NOT NULL DEFAULT 1,
  `payment_updates` TINYINT(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `gift_card_transactions` (
  `id` CHAR(36) NOT NULL,
  `gift_card_id` CHAR(36) NOT NULL,
  `user_id` CHAR(36) NULL,
  `order_id` CHAR(36) NULL,
  `tx_type` TEXT NOT NULL,
  `amount` DECIMAL(12,2) NOT NULL,
  `balance_after` DECIMAL(12,2) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `gift_cards` (
  `id` CHAR(36) NOT NULL,
  `code` TEXT NOT NULL,
  `initial_balance` DECIMAL(12,2) NOT NULL,
  `balance` DECIMAL(12,2) NOT NULL,
  `currency` TEXT NOT NULL DEFAULT 'KES',
  `status` TEXT NOT NULL DEFAULT 'active',
  `purchased_by` CHAR(36) NULL,
  `recipient_email` TEXT NULL,
  `expires_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `loyalty_accounts` (
  `user_id` CHAR(36) NOT NULL,
  `points_balance` INT NOT NULL DEFAULT 0,
  `lifetime_earned` INT NOT NULL DEFAULT 0,
  `lifetime_redeemed` INT NOT NULL DEFAULT 0,
  `referral_code` TEXT NOT NULL,
  `tier` TEXT NOT NULL DEFAULT 'member',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `loyalty_rules` (
  `id` CHAR(36) NOT NULL,
  `code` TEXT NOT NULL,
  `name` TEXT NOT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `earn_points_per_currency` DECIMAL(12,4) NOT NULL DEFAULT 0.01,
  `redeem_points_per_currency` DECIMAL(12,4) NOT NULL DEFAULT 10,
  `free_delivery_points` INT NOT NULL DEFAULT 500,
  `min_redeem_points` INT NOT NULL DEFAULT 100,
  `max_redeem_percent` DECIMAL(5,2) NOT NULL DEFAULT 50,
  `metadata` JSON NOT NULL DEFAULT '{}',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `loyalty_transactions` (
  `id` CHAR(36) NOT NULL,
  `user_id` CHAR(36) NOT NULL,
  `tx_type` TEXT NOT NULL,
  `points` INT NOT NULL,
  `balance_after` INT NOT NULL,
  `order_id` CHAR(36) NULL,
  `description` TEXT NULL,
  `metadata` JSON NOT NULL DEFAULT '{}',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `notification_deliveries` (
  `id` CHAR(36) NOT NULL,
  `notification_id` CHAR(36) NULL,
  `user_id` CHAR(36) NOT NULL,
  `event_type` TEXT NOT NULL,
  `channel` TEXT NOT NULL,
  `provider` TEXT NOT NULL DEFAULT 'mock',
  `status` TEXT NOT NULL DEFAULT 'pending',
  `retry_count` INT NOT NULL DEFAULT 0,
  `max_retries` INT NOT NULL DEFAULT 3,
  `external_id` TEXT NULL,
  `error_message` TEXT NULL,
  `payload` JSON NOT NULL DEFAULT '{}',
  `response` JSON NOT NULL DEFAULT '{}',
  `scheduled_at` DATETIME NULL,
  `sent_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `notification_events` (
  `id` CHAR(36) NOT NULL,
  `event_type` TEXT NOT NULL,
  `user_id` CHAR(36) NULL,
  `payload` JSON NOT NULL DEFAULT '{}',
  `result` JSON NOT NULL DEFAULT '{}',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `notification_preferences` (
  `user_id` CHAR(36) NOT NULL,
  `email_enabled` TINYINT(1) NOT NULL DEFAULT 1,
  `sms_enabled` TINYINT(1) NOT NULL DEFAULT 0,
  `in_app_enabled` TINYINT(1) NOT NULL DEFAULT 1,
  `push_enabled` TINYINT(1) NOT NULL DEFAULT 0,
  `marketing_emails` TINYINT(1) NOT NULL DEFAULT 0,
  `order_updates` TINYINT(1) NOT NULL DEFAULT 1,
  `payment_updates` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `notification_templates` (
  `id` CHAR(36) NOT NULL,
  `code` TEXT NOT NULL,
  `channel` TEXT NOT NULL DEFAULT 'in_app',
  `subject` TEXT NULL,
  `body` TEXT NOT NULL,
  `description` TEXT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `notifications` (
  `id` CHAR(36) NOT NULL,
  `user_id` CHAR(36) NOT NULL,
  `event_type` TEXT NOT NULL,
  `channel` TEXT NOT NULL DEFAULT 'in_app',
  `title` TEXT NOT NULL,
  `body` TEXT NOT NULL,
  `link` TEXT NULL,
  `metadata` JSON NOT NULL DEFAULT '{}',
  `status` TEXT NOT NULL DEFAULT 'unread',
  `audience` TEXT NOT NULL DEFAULT 'customer',
  `read_at` DATETIME NULL,
  `archived_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `order_events` (
  `id` CHAR(36) NOT NULL,
  `order_id` CHAR(36) NOT NULL,
  `event_type` TEXT NOT NULL,
  `payload` JSON NOT NULL DEFAULT '{}',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `order_items` (
  `id` CHAR(36) NOT NULL,
  `order_id` CHAR(36) NOT NULL,
  `product_id` CHAR(36) NULL,
  `quantity` SMALLINT NULL,
  `price` DECIMAL(12,2) NULL,
  `name` TEXT NULL DEFAULT '',
  `image_url` TEXT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `orders` (
  `id` CHAR(36) NOT NULL,
  `user_id` CHAR(36) NOT NULL,
  `total` DECIMAL(12,2) NULL,
  `status` TEXT NULL DEFAULT 'pending',
  `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
  `payment_status` TEXT NOT NULL DEFAULT 'pending',
  `note` TEXT NULL,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `delivery_type` TEXT NULL,
  `pickup_location_id` CHAR(36) NULL,
  `delivery_address` JSON NULL,
  `delivery_fee` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `customer_note` TEXT NULL,
  `payment_method` TEXT NOT NULL DEFAULT 'cod',
  `mpesa_receipt_number` TEXT NULL,
  `discount_amount` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `coupon_code` TEXT NULL,
  `loyalty_points_redeemed` INT NOT NULL DEFAULT 0,
  `gift_card_amount` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `free_delivery` TINYINT(1) NOT NULL DEFAULT 0,
  `promotions_applied` JSON NOT NULL DEFAULT '[]',
  `referral_code` TEXT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `payment_events` (
  `id` CHAR(36) NOT NULL,
  `payment_id` CHAR(36) NOT NULL,
  `event_type` TEXT NOT NULL,
  `payload` JSON NOT NULL DEFAULT '{}',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `payments` (
  `id` CHAR(36) NOT NULL,
  `order_id` CHAR(36) NOT NULL,
  `user_id` CHAR(36) NOT NULL,
  `provider` TEXT NOT NULL DEFAULT 'mpesa',
  `method` TEXT NOT NULL DEFAULT 'mpesa',
  `status` TEXT NOT NULL DEFAULT 'pending',
  `amount` DECIMAL(12,2) NOT NULL,
  `currency` TEXT NOT NULL DEFAULT 'KES',
  `phone_number` TEXT NULL,
  `transaction_reference` TEXT NULL,
  `checkout_request_id` TEXT NULL,
  `merchant_request_id` TEXT NULL,
  `receipt_number` TEXT NULL,
  `failure_reason` TEXT NULL,
  `raw_request` JSON NOT NULL DEFAULT '{}',
  `raw_response` JSON NOT NULL DEFAULT '{}',
  `raw_callback` JSON NOT NULL DEFAULT '{}',
  `expires_at` DATETIME NULL,
  `paid_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pickup_locations` (
  `id` CHAR(36) NOT NULL,
  `name` TEXT NOT NULL,
  `building` TEXT NOT NULL DEFAULT '',
  `description` TEXT NULL,
  `operating_hours` JSON NOT NULL DEFAULT '{}',
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `products` (
  `id` CHAR(36) NOT NULL,
  `name` TEXT NOT NULL,
  `slug` TEXT NULL,
  `price` DECIMAL(12,2) NULL,
  `category` TEXT NULL,
  `category_id` CHAR(36) NULL,
  `featured` TINYINT(1) NULL DEFAULT 0,
  `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
  `description` TEXT NULL,
  `stock` INT NOT NULL DEFAULT 0,
  `discount_price` DECIMAL(12,2) NULL,
  `image_url` TEXT NULL,
  `images` JSON NOT NULL DEFAULT '[]',
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `profiles` (
  `id` CHAR(36) NOT NULL,
  `email` TEXT NULL,
  `role` TEXT NULL DEFAULT 'customer',
  `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
  `phone` TEXT NULL,
  `full_name` TEXT NULL,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `promotion_rules` (
  `id` CHAR(36) NOT NULL,
  `promotion_id` CHAR(36) NOT NULL,
  `rule_type` TEXT NOT NULL,
  `rule_value` JSON NOT NULL DEFAULT '{}',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `promotions` (
  `id` CHAR(36) NOT NULL,
  `code` TEXT NULL,
  `name` TEXT NOT NULL,
  `description` TEXT NULL,
  `promo_type` TEXT NOT NULL,
  `status` TEXT NOT NULL DEFAULT 'active',
  `priority` INT NOT NULL DEFAULT 100,
  `stackable` TINYINT(1) NOT NULL DEFAULT 0,
  `percent_off` DECIMAL(5,2) NULL,
  `amount_off` DECIMAL(12,2) NULL,
  `buy_quantity` INT NULL,
  `get_quantity` INT NULL,
  `category_id` CHAR(36) NULL,
  `product_id` CHAR(36) NULL,
  `min_order_amount` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `max_discount_amount` DECIMAL(12,2) NULL,
  `usage_limit` INT NULL,
  `usage_count` INT NOT NULL DEFAULT 0,
  `per_user_limit` INT NULL,
  `starts_at` DATETIME NULL,
  `ends_at` DATETIME NULL,
  `eligibility` JSON NOT NULL DEFAULT '{}',
  `metadata` JSON NOT NULL DEFAULT '{}',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `referrals` (
  `id` CHAR(36) NOT NULL,
  `referrer_user_id` CHAR(36) NOT NULL,
  `referred_user_id` CHAR(36) NULL,
  `referral_code` TEXT NOT NULL,
  `status` TEXT NOT NULL DEFAULT 'pending',
  `reward_points` INT NOT NULL DEFAULT 0,
  `referred_reward_points` INT NOT NULL DEFAULT 0,
  `order_id` CHAR(36) NULL,
  `rewarded_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `reward_events` (
  `id` CHAR(36) NOT NULL,
  `user_id` CHAR(36) NULL,
  `order_id` CHAR(36) NULL,
  `event_type` TEXT NOT NULL,
  `payload` JSON NOT NULL DEFAULT '{}',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `wishlists` (
  `id` CHAR(36) NOT NULL,
  `user_id` CHAR(36) NOT NULL,
  `product_id` CHAR(36) NULL,
  `created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- Ordinary indexes
-- =====================================================

CREATE INDEX `idx_admin_audit_logs_actor` ON `admin_audit_logs` (`actor_id`, `created_at`);
CREATE INDEX `idx_admin_audit_logs_created` ON `admin_audit_logs` (`created_at`);
CREATE INDEX `idx_admin_audit_logs_entity` ON `admin_audit_logs` (`entity_type`(191), `entity_id`(191));
-- SKIPPED UNIQUE INDEX (handled by constraint): cart_items.cart_items_user_product_key
CREATE INDEX `idx_cart_items_product_id` ON `cart_items` (`product_id`);
-- SKIPPED PARTIAL INDEX: categories.idx_categories_slug_unique
-- PostgreSQL: CREATE UNIQUE INDEX idx_categories_slug_unique ON public.categories USING btree (slug) WHERE ((slug IS NOT NULL) AND (TRIM(BOTH FROM slug) <> ''::text))

CREATE INDEX `idx_coupon_redemptions_coupon_user` ON `coupon_redemptions` (`coupon_id`, `user_id`);
CREATE INDEX `idx_coupon_redemptions_order` ON `coupon_redemptions` (`order_id`);
-- SKIPPED UNIQUE INDEX (handled by constraint): coupons.coupons_code_unique
CREATE INDEX `idx_coupons_active` ON `coupons` (`is_active`, `starts_at`, `ends_at`);
-- SKIPPED PARTIAL INDEX: customer_addresses.idx_customer_addresses_user_default
-- PostgreSQL: CREATE INDEX idx_customer_addresses_user_default ON public.customer_addresses USING btree (user_id, is_default) WHERE (is_default = true)

CREATE INDEX `idx_customer_addresses_user_id` ON `customer_addresses` (`user_id`);
CREATE INDEX `idx_gift_card_transactions_card` ON `gift_card_transactions` (`gift_card_id`, `created_at`);
-- SKIPPED UNIQUE INDEX (handled by constraint): gift_cards.gift_cards_code_key
CREATE INDEX `idx_gift_cards_status` ON `gift_cards` (`status`(191));
-- SKIPPED UNIQUE INDEX (handled by constraint): loyalty_accounts.loyalty_accounts_referral_code_unique
-- SKIPPED UNIQUE INDEX (handled by constraint): loyalty_rules.loyalty_rules_code_key
CREATE INDEX `idx_loyalty_transactions_user_created` ON `loyalty_transactions` (`user_id`, `created_at`);
CREATE INDEX `idx_notification_deliveries_notification_id` ON `notification_deliveries` (`notification_id`);
CREATE INDEX `idx_notification_deliveries_status` ON `notification_deliveries` (`status`(191));
CREATE INDEX `idx_notification_deliveries_user_created` ON `notification_deliveries` (`user_id`, `created_at`);
CREATE INDEX `idx_notification_events_type_created` ON `notification_events` (`event_type`(191), `created_at`);
CREATE INDEX `idx_notification_events_user_created` ON `notification_events` (`user_id`, `created_at`);
CREATE INDEX `idx_notification_templates_code` ON `notification_templates` (`code`(191));
-- SKIPPED UNIQUE INDEX (handled by constraint): notification_templates.notification_templates_code_channel_unique
-- SKIPPED PARTIAL INDEX: notifications.idx_notifications_audience_created
-- PostgreSQL: CREATE INDEX idx_notifications_audience_created ON public.notifications USING btree (audience, created_at DESC) WHERE (audience = 'admin'::text)

CREATE INDEX `idx_notifications_event_type` ON `notifications` (`event_type`(191));
CREATE INDEX `idx_notifications_user_created` ON `notifications` (`user_id`, `created_at`);
CREATE INDEX `idx_notifications_user_status` ON `notifications` (`user_id`, `status`(191));
CREATE INDEX `idx_order_events_order_id` ON `order_events` (`order_id`, `created_at`);
CREATE INDEX `idx_order_items_order_id` ON `order_items` (`order_id`);
CREATE INDEX `idx_order_items_product_id` ON `order_items` (`product_id`);
CREATE INDEX `idx_orders_created_at` ON `orders` (`created_at`);
CREATE INDEX `idx_orders_payment_method` ON `orders` (`payment_method`(191));
CREATE INDEX `idx_orders_payment_status` ON `orders` (`payment_status`(191));
-- SKIPPED PARTIAL INDEX: orders.idx_orders_pickup_location_id
-- PostgreSQL: CREATE INDEX idx_orders_pickup_location_id ON public.orders USING btree (pickup_location_id) WHERE (pickup_location_id IS NOT NULL)

CREATE INDEX `idx_orders_status` ON `orders` (`status`(191));
CREATE INDEX `idx_orders_user_id` ON `orders` (`user_id`);
CREATE INDEX `idx_payment_events_payment_id_created` ON `payment_events` (`payment_id`, `created_at`);
-- SKIPPED PARTIAL INDEX: payments.idx_payments_checkout_request_id_unique
-- PostgreSQL: CREATE UNIQUE INDEX idx_payments_checkout_request_id_unique ON public.payments USING btree (checkout_request_id) WHERE (checkout_request_id IS NOT NULL)

CREATE INDEX `idx_payments_created_at` ON `payments` (`created_at`);
-- SKIPPED PARTIAL INDEX: payments.idx_payments_merchant_request_id_unique
-- PostgreSQL: CREATE UNIQUE INDEX idx_payments_merchant_request_id_unique ON public.payments USING btree (merchant_request_id) WHERE (merchant_request_id IS NOT NULL)

CREATE INDEX `idx_payments_order_id` ON `payments` (`order_id`);
-- SKIPPED PARTIAL INDEX: payments.idx_payments_receipt_number_unique
-- PostgreSQL: CREATE UNIQUE INDEX idx_payments_receipt_number_unique ON public.payments USING btree (receipt_number) WHERE (receipt_number IS NOT NULL)

CREATE INDEX `idx_payments_status` ON `payments` (`status`(191));
CREATE INDEX `idx_payments_user_id` ON `payments` (`user_id`);
-- SKIPPED PARTIAL INDEX: pickup_locations.idx_pickup_locations_is_active
-- PostgreSQL: CREATE INDEX idx_pickup_locations_is_active ON public.pickup_locations USING btree (is_active) WHERE (is_active = true)

CREATE INDEX `idx_products_category_id` ON `products` (`category_id`);
CREATE INDEX `idx_products_is_active` ON `products` (`is_active`);
-- SKIPPED EXPRESSION INDEX: products.idx_products_search
-- PostgreSQL: CREATE INDEX idx_products_search ON public.products USING gin (to_tsvector('simple'::regconfig, ((COALESCE(name, ''::text) || ' '::text) || COALESCE(description, ''::text))))

-- SKIPPED PARTIAL INDEX: products.idx_products_slug_unique
-- PostgreSQL: CREATE UNIQUE INDEX idx_products_slug_unique ON public.products USING btree (slug) WHERE ((slug IS NOT NULL) AND (TRIM(BOTH FROM slug) <> ''::text))

CREATE INDEX `idx_promotion_rules_promotion_id` ON `promotion_rules` (`promotion_id`);
-- SKIPPED PARTIAL INDEX: promotions.idx_promotions_code_unique
-- PostgreSQL: CREATE UNIQUE INDEX idx_promotions_code_unique ON public.promotions USING btree (lower(code)) WHERE (code IS NOT NULL)

CREATE INDEX `idx_promotions_dates` ON `promotions` (`starts_at`, `ends_at`);
CREATE INDEX `idx_promotions_status_priority` ON `promotions` (`status`(191), `priority`);
CREATE INDEX `idx_referrals_code` ON `referrals` (`referral_code`(191));
-- SKIPPED PARTIAL INDEX: referrals.idx_referrals_referred_user
-- PostgreSQL: CREATE UNIQUE INDEX idx_referrals_referred_user ON public.referrals USING btree (referred_user_id) WHERE (referred_user_id IS NOT NULL)

CREATE INDEX `idx_referrals_referrer` ON `referrals` (`referrer_user_id`);
CREATE INDEX `idx_reward_events_user_created` ON `reward_events` (`user_id`, `created_at`);
CREATE INDEX `idx_wishlists_product_id` ON `wishlists` (`product_id`);
-- SKIPPED UNIQUE INDEX (handled by constraint): wishlists.wishlists_user_product_key

-- =====================================================
-- Foreign keys: public -> public only
-- =====================================================

ALTER TABLE `cart_items`
  ADD CONSTRAINT `cart_items_product_id_fkey`
  FOREIGN KEY (`product_id`)
  REFERENCES `products` (`id`)
  ON DELETE CASCADE
;

ALTER TABLE `coupon_redemptions`
  ADD CONSTRAINT `coupon_redemptions_coupon_id_fkey`
  FOREIGN KEY (`coupon_id`)
  REFERENCES `coupons` (`id`)
  ON DELETE CASCADE
;

ALTER TABLE `coupon_redemptions`
  ADD CONSTRAINT `coupon_redemptions_order_id_fkey`
  FOREIGN KEY (`order_id`)
  REFERENCES `orders` (`id`)
  ON DELETE SET NULL
;

ALTER TABLE `coupons`
  ADD CONSTRAINT `coupons_promotion_id_fkey`
  FOREIGN KEY (`promotion_id`)
  REFERENCES `promotions` (`id`)
  ON DELETE SET NULL
;

ALTER TABLE `customer_addresses`
  ADD CONSTRAINT `customer_addresses_user_id_fkey`
  FOREIGN KEY (`user_id`)
  REFERENCES `profiles` (`id`)
  ON DELETE CASCADE
;

ALTER TABLE `customer_preferences`
  ADD CONSTRAINT `customer_preferences_preferred_pickup_location_id_fkey`
  FOREIGN KEY (`preferred_pickup_location_id`)
  REFERENCES `pickup_locations` (`id`)
  ON DELETE SET NULL
;

ALTER TABLE `customer_preferences`
  ADD CONSTRAINT `customer_preferences_user_id_fkey`
  FOREIGN KEY (`user_id`)
  REFERENCES `profiles` (`id`)
  ON DELETE CASCADE
;

ALTER TABLE `gift_card_transactions`
  ADD CONSTRAINT `gift_card_transactions_gift_card_id_fkey`
  FOREIGN KEY (`gift_card_id`)
  REFERENCES `gift_cards` (`id`)
  ON DELETE CASCADE
;

ALTER TABLE `gift_card_transactions`
  ADD CONSTRAINT `gift_card_transactions_order_id_fkey`
  FOREIGN KEY (`order_id`)
  REFERENCES `orders` (`id`)
  ON DELETE SET NULL
;

ALTER TABLE `loyalty_transactions`
  ADD CONSTRAINT `loyalty_transactions_order_id_fkey`
  FOREIGN KEY (`order_id`)
  REFERENCES `orders` (`id`)
  ON DELETE SET NULL
;

ALTER TABLE `notification_deliveries`
  ADD CONSTRAINT `notification_deliveries_notification_id_fkey`
  FOREIGN KEY (`notification_id`)
  REFERENCES `notifications` (`id`)
  ON DELETE SET NULL
;

ALTER TABLE `order_events`
  ADD CONSTRAINT `order_events_order_id_fkey`
  FOREIGN KEY (`order_id`)
  REFERENCES `orders` (`id`)
  ON DELETE CASCADE
;

ALTER TABLE `order_items`
  ADD CONSTRAINT `order_items_order_id_fkey`
  FOREIGN KEY (`order_id`)
  REFERENCES `orders` (`id`)
  ON DELETE CASCADE
;

ALTER TABLE `order_items`
  ADD CONSTRAINT `order_items_product_id_fkey`
  FOREIGN KEY (`product_id`)
  REFERENCES `products` (`id`)
  ON DELETE SET NULL
;

ALTER TABLE `orders`
  ADD CONSTRAINT `orders_pickup_location_id_fkey`
  FOREIGN KEY (`pickup_location_id`)
  REFERENCES `pickup_locations` (`id`)
  ON DELETE SET NULL
;

ALTER TABLE `payment_events`
  ADD CONSTRAINT `payment_events_payment_id_fkey`
  FOREIGN KEY (`payment_id`)
  REFERENCES `payments` (`id`)
  ON DELETE CASCADE
;

ALTER TABLE `payments`
  ADD CONSTRAINT `payments_order_id_fkey`
  FOREIGN KEY (`order_id`)
  REFERENCES `orders` (`id`)
  ON DELETE CASCADE
;

ALTER TABLE `products`
  ADD CONSTRAINT `products_category_id_fkey`
  FOREIGN KEY (`category_id`)
  REFERENCES `categories` (`id`)
  ON DELETE SET NULL
;

ALTER TABLE `promotion_rules`
  ADD CONSTRAINT `promotion_rules_promotion_id_fkey`
  FOREIGN KEY (`promotion_id`)
  REFERENCES `promotions` (`id`)
  ON DELETE CASCADE
;

ALTER TABLE `promotions`
  ADD CONSTRAINT `promotions_category_id_fkey`
  FOREIGN KEY (`category_id`)
  REFERENCES `categories` (`id`)
  ON DELETE SET NULL
;

ALTER TABLE `referrals`
  ADD CONSTRAINT `referrals_order_id_fkey`
  FOREIGN KEY (`order_id`)
  REFERENCES `orders` (`id`)
  ON DELETE SET NULL
;

ALTER TABLE `reward_events`
  ADD CONSTRAINT `reward_events_order_id_fkey`
  FOREIGN KEY (`order_id`)
  REFERENCES `orders` (`id`)
  ON DELETE SET NULL
;

ALTER TABLE `wishlists`
  ADD CONSTRAINT `wishlists_product_id_fkey`
  FOREIGN KEY (`product_id`)
  REFERENCES `products` (`id`)
  ON DELETE CASCADE
;

-- Supabase auth.users relationships are intentionally omitted.
SET FOREIGN_KEY_CHECKS = 1;
