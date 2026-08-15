import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireCaller, serviceClient } from "../_shared/auth.ts";
import { databaseError } from "../_shared/database.ts";
import {
  errorResponse,
  handlePreflight,
  HttpError,
  optionalStringField,
  readJsonObject,
  requirePost,
  successResponse,
  uuidField,
} from "../_shared/http.ts";
import { consumeRateLimit } from "../_shared/security.ts";

interface OrderItemInput {
  product_id: string;
  quantity: number;
}

serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);

    const adminClient = serviceClient();
    const caller = await requireCaller(req, ["customer"], adminClient);
    if (caller.customer?.accountStatus !== "active") {
      throw new HttpError(
        403,
        "CUSTOMER_ACCOUNT_INACTIVE",
        "This customer account cannot place orders.",
      );
    }
    await ensureOrderingAvailable(adminClient);
    await consumeRateLimit(
      adminClient,
      req,
      `place-order:${caller.id}`,
      120,
      15 * 60,
    );

    const body = await readJsonObject(req);
    const clientRequestId = uuidField(body, "client_request_id")!;
    const deliveryAddress = optionalStringField(
      body,
      "delivery_address",
      500,
    );
    const customerNote = optionalStringField(body, "customer_note", 1000) ??
      optionalStringField(body, "notes", 1000);
    const deliveryNote = optionalStringField(body, "delivery_note", 1000);
    const items = parseItems(body.items);

    const { data, error } = await adminClient.rpc("place_order_transaction", {
      p_actor_id: caller.id,
      p_client_request_id: clientRequestId,
      p_items: items,
      p_delivery_address: deliveryAddress,
      p_customer_note: customerNote,
      p_delivery_note: deliveryNote,
    });
    if (error) {
      throw databaseError(
        error,
        "ORDER_CREATE_FAILED",
        "The order could not be created.",
      );
    }

    const result = data as {
      order: Record<string, unknown>;
      idempotent: boolean;
    };
    const payload = {
      order: result.order,
      idempotent: result.idempotent === true,
    };
    return successResponse(
      req,
      payload,
      result.idempotent ? 200 : 201,
      payload,
    );
  } catch (error) {
    return errorResponse(req, error);
  }
});

async function ensureOrderingAvailable(
  adminClient: ReturnType<typeof serviceClient>,
): Promise<void> {
  const { data, error } = await adminClient
    .from("app_settings")
    .select("value")
    .eq("key", "maintenance_mode")
    .maybeSingle();

  if (error) {
    console.error("Unable to read maintenance mode", error);
    throw new HttpError(
      503,
      "ORDERING_CONFIGURATION_UNAVAILABLE",
      "Orders are temporarily unavailable.",
    );
  }

  const enabled = ["1", "true", "yes", "on"].includes(
    String(data?.value ?? "").trim().toLowerCase(),
  );
  if (enabled) {
    throw new HttpError(
      503,
      "MAINTENANCE_MODE",
      "Orders are temporarily unavailable while maintenance is active.",
    );
  }
}

function parseItems(value: unknown): OrderItemInput[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new HttpError(
      422,
      "ORDER_ITEMS_REQUIRED",
      "At least one order item is required.",
      { field: "items" },
    );
  }
  if (value.length > 100) {
    throw new HttpError(
      422,
      "TOO_MANY_ORDER_ITEMS",
      "The order contains too many products.",
      { field: "items", maxItems: 100 },
    );
  }

  return value.map((raw, index) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw invalidItem(index);
    }
    const item = raw as Record<string, unknown>;
    const productId = typeof item.product_id === "string"
      ? item.product_id.trim()
      : "";
    const quantity = item.quantity;
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(productId) ||
      typeof quantity !== "number" ||
      !Number.isSafeInteger(quantity) ||
      quantity <= 0 ||
      quantity > 1_000_000
    ) {
      throw invalidItem(index);
    }
    return { product_id: productId, quantity };
  });
}

function invalidItem(index: number): HttpError {
  return new HttpError(
    422,
    "INVALID_ORDER_ITEM",
    "Each item requires a product_id UUID and a positive integer quantity.",
    { field: `items[${index}]` },
  );
}
