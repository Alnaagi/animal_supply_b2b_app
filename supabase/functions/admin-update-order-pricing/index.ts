import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireCaller, serviceClient } from "../_shared/auth.ts";
import { databaseError } from "../_shared/database.ts";
import {
  errorResponse,
  handlePreflight,
  readJsonObject,
  requirePost,
  successResponse,
} from "../_shared/http.ts";
import { consumeRateLimit } from "../_shared/security.ts";
import { parseOrderPricingBody } from "./pricing.ts";

serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);

    const adminClient = serviceClient();
    const caller = await requireCaller(
      req,
      ["admin", "staff"],
      adminClient,
    );
    await consumeRateLimit(
      adminClient,
      req,
      `admin-update-order-pricing:${caller.id}`,
      180,
      60 * 60,
    );
    const input = parseOrderPricingBody(await readJsonObject(req));

    const { data, error } = await adminClient.rpc(
      "admin_update_order_pricing_transaction",
      {
        p_actor_id: caller.id,
        p_order_id: input.orderId,
        p_items: input.items.map((item) => ({
          id: item.id,
          unit_price: item.unitPrice,
        })),
        p_delivery_fee: input.deliveryFee,
        p_discount_amount: input.discountAmount,
        p_expected_updated_at: input.expectedUpdatedAt,
      },
    );
    if (error) {
      throw databaseError(
        error,
        "ORDER_PRICING_UPDATE_FAILED",
        "The order pricing could not be updated.",
      );
    }

    const result = (data ?? {}) as { order?: Record<string, unknown> };
    const payload = { order: result.order ?? {} };
    return successResponse(req, payload, 200, payload);
  } catch (error) {
    return errorResponse(req, error);
  }
});
