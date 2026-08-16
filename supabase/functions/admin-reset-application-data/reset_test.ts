import { HttpError } from "../_shared/http.ts";
import {
  APPLICATION_DATA_RESET_TABLES,
  customerUserIdsFromResetPayload,
  PRESERVED_APPLICATION_TABLES,
  REQUIRED_RESET_PHRASE,
  requireResetConfirmPhrase,
} from "./reset.ts";

Deno.test("confirm phrase accepts only exact RESET", () => {
  requireResetConfirmPhrase("RESET");
  if (REQUIRED_RESET_PHRASE !== "RESET") {
    throw new Error("The required phrase drifted from RESET.");
  }
  for (const value of ["reset", "Reset", "RESET ", "", null, undefined]) {
    let error: unknown;
    try {
      requireResetConfirmPhrase(value);
    } catch (caught) {
      error = caught;
    }
    if (
      !(error instanceof HttpError) ||
      error.code !== "CONFIRM_PHRASE_INVALID"
    ) {
      throw new Error(`Expected CONFIRM_PHRASE_INVALID for ${value}`);
    }
  }
});

Deno.test("documented wipe list includes catalog orders customers banners", () => {
  const tables = new Set<string>(APPLICATION_DATA_RESET_TABLES);
  for (const required of [
    "products",
    "categories",
    "orders",
    "order_items",
    "business_customers",
    "banners",
    "invite_tokens",
  ]) {
    if (!tables.has(required)) {
      throw new Error(`${required} must be wiped`);
    }
  }
  const preserved = new Set<string>(PRESERVED_APPLICATION_TABLES);
  for (const required of [
    "profiles",
    "app_settings",
    "app_versions",
    "audit_logs",
  ]) {
    if (!preserved.has(required)) {
      throw new Error(`${required} must be preserved`);
    }
  }
});

Deno.test("caller admin id is never queued for Auth deletion", () => {
  const adminId = "11111111-1111-4111-8111-111111111111";
  const customerId = "22222222-2222-4222-8222-222222222222";
  const ids = customerUserIdsFromResetPayload(
    { customer_user_ids: [customerId, adminId, ""] },
    adminId,
  );
  if (ids.length !== 1 || ids[0] !== customerId) {
    throw new Error("The calling admin must be excluded from Auth deletion.");
  }
});
