import { supabase } from '@/lib/supabaseClient';
import { logger } from '@/services/logger';

/**
 * Admin audit trail (Workstream 9).
 * Fire-and-forget safe — never breaks primary admin actions.
 */

export const AUDIT_ACTIONS = {
  PRODUCT_CREATED: 'product.created',
  PRODUCT_UPDATED: 'product.updated',
  PRODUCT_DELETED: 'product.deleted',
  INVENTORY_UPDATED: 'inventory.updated',
  PROMOTION_CHANGED: 'promotion.changed',
  COUPON_CREATED: 'coupon.created',
  COUPON_UPDATED: 'coupon.updated',
  ORDER_UPDATED: 'order.updated',
  USER_ROLE_CHANGED: 'user.role_changed',
  GIFT_CARD_ISSUED: 'gift_card.issued',
  LOYALTY_RULES_UPDATED: 'loyalty.rules_updated',
  EXPORT_GENERATED: 'export.generated',
};

/**
 * @param {{ action: string, entityType: string, entityId?: string, summary?: string, metadata?: object }} input
 */
export async function writeAudit(input) {
  try {
    const { data, error } = await supabase.rpc('write_admin_audit', {
      p_action: input.action,
      p_entity_type: input.entityType,
      p_entity_id: input.entityId != null ? String(input.entityId) : null,
      p_summary: input.summary || null,
      p_metadata: input.metadata || {},
    });
    if (error) {
      // Fallback direct insert if RPC missing (migration not applied)
      const { data: { user } } = await supabase.auth.getUser();
      const { error: insertError } = await supabase.from('admin_audit_logs').insert({
        actor_id: user?.id || null,
        action: input.action,
        entity_type: input.entityType,
        entity_id: input.entityId != null ? String(input.entityId) : null,
        summary: input.summary || null,
        metadata: input.metadata || {},
      });
      if (insertError) {
        logger.warn('audit', 'Audit write failed', { message: insertError.message });
        return null;
      }
    }
    logger.audit(input.action, {
      entityType: input.entityType,
      entityId: input.entityId,
    });
    return data || true;
  } catch (err) {
    logger.warn('audit', 'Audit write exception', { message: err?.message });
    return null;
  }
}

export function writeAuditSafe(input) {
  return writeAudit(input).catch(() => null);
}

export async function listAuditLogs({ limit = 50 } = {}) {
  const { data, error } = await supabase
    .from('admin_audit_logs')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data || []).map((row) => ({
    id: row.id,
    actorId: row.actor_id,
    action: row.action,
    entityType: row.entity_type,
    entityId: row.entity_id,
    summary: row.summary,
    metadata: row.metadata || {},
    createdAt: row.created_at,
  }));
}

export const auditService = {
  writeAudit,
  writeAuditSafe,
  listAuditLogs,
  AUDIT_ACTIONS,
};
