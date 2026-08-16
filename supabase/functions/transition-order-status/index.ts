import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireCaller, serviceClient } from "../_shared/auth.ts";
import { databaseError } from "../_shared/database.ts";
import {
  errorResponse,
  handlePreflight,
  HttpError,
  optionalStringField,
  optionalTimestamptzField,
  readJsonObject,
  requirePost,
  stringField,
  successResponse,
  uuidField,
} from "../_shared/http.ts";
import { consumeRateLimit } from "../_shared/security.ts";

const validStatuses = new Set([
  "pending",
  "confirmed",
  "preparing",
  "ready",
  "delivered",
  "cancelled",
]);

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
      `transition-order-status:${caller.id}`,
      300,
      60 * 60,
    );
    const body = await readJsonObject(req);
    const orderId = uuidField(body, "order_id")!;
    const status = stringField(body, "status", {
      required: true,
      maxLength: 32,
    });
    if (!validStatuses.has(status)) {
      throw new HttpError(
        422,
        "INVALID_ORDER_STATUS",
        "The requested order status is invalid.",
        { field: "status" },
      );
    }
    const note = optionalStringField(body, "note", 1000) ??
      optionalStringField(body, "admin_note", 1000);
    const expectedUpdatedAt = optionalTimestamptzField(
      body,
      "expected_updated_at",
    );

    const { data, error } = await adminClient.rpc(
      "transition_order_status_transaction",
      {
        p_actor_id: caller.id,
        p_order_id: orderId,
        p_status: status,
        p_note: note,
        p_expected_updated_at: expectedUpdatedAt,
      },
    );
    if (error) {
      throw databaseError(
        error,
        "ORDER_STATUS_UPDATE_FAILED",
        "The order status could not be updated.",
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
    return successResponse(req, payload, 200, payload);
  } catch (error) {
    return errorResponse(req, error);
  }
});
