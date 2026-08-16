import { HttpError } from "../_shared/http.ts";

export const REQUIRED_RESET_PHRASE = "RESET";

export const APPLICATION_DATA_RESET_TABLES = [
  "notification_deliveries",
  "notification_outbox",
  "notifications",
  "notification_campaigns",
  "inventory_reservations",
  "order_status_history",
  "order_items",
  "inventory_movements",
  "orders",
  "product_images",
  "product_prices",
  "customer_special_prices",
  "products",
  "categories",
  "banners",
  "invite_tokens",
  "customer_contacts",
  "business_customers",
  "device_tokens",
  "admin_device_tokens",
  "sync_outbox",
  "price_groups",
] as const;

export const PRESERVED_APPLICATION_TABLES = [
  "profiles",
  "app_settings",
  "app_versions",
  "audit_logs",
  "edge_rate_limits",
] as const;

export function requireResetConfirmPhrase(value: unknown): void {
  if (value !== REQUIRED_RESET_PHRASE) {
    throw new HttpError(
      422,
      "CONFIRM_PHRASE_INVALID",
      "The confirmation phrase must be exactly RESET.",
    );
  }
}

export function customerUserIdsFromResetPayload(
  payload: Record<string, unknown>,
  preservedAdminId: string,
): string[] {
  const raw = payload.customer_user_ids;
  if (!Array.isArray(raw)) return [];
  return raw
    .map((value) => String(value ?? "").trim())
    .filter((id) => id.length > 0 && id !== preservedAdminId);
}
