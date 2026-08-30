import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireCaller, serviceClient } from "../_shared/auth.ts";
import { databaseError } from "../_shared/database.ts";
import {
  errorResponse,
  handlePreflight,
  HttpError,
  readJsonObject,
  requirePost,
  successResponse,
  uuidField,
} from "../_shared/http.ts";
import { consumeRateLimit } from "../_shared/security.ts";

serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);

    const adminClient = serviceClient();
    const caller = await requireCaller(req, ["admin", "staff"], adminClient);
    await consumeRateLimit(
      adminClient,
      req,
      `admin-reset-customer-device-binding:${caller.id}`,
      60,
      60 * 60,
      caller.id,
    );

    const body = await readJsonObject(req);
    const customerId = uuidField(body, "customer_id");
    if (!customerId) {
      throw new HttpError(
        422,
        "VALIDATION_ERROR",
        "customer_id is required.",
        { field: "customer_id" },
      );
    }

    const { data, error } = await adminClient.rpc(
      "admin_reset_customer_device_binding",
      {
        p_actor_id: caller.id,
        p_customer_id: customerId,
      },
    );
    if (error) {
      throw databaseError(
        error,
        "DEVICE_BINDING_RESET_FAILED",
        "The customer device binding could not be reset.",
      );
    }
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new HttpError(
        500,
        "DEVICE_BINDING_RESET_FAILED",
        "The device reset returned an invalid result.",
      );
    }

    return successResponse(
      req,
      data as Record<string, unknown>,
      200,
      { reset: true },
    );
  } catch (error) {
    return errorResponse(req, error);
  }
});
