import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireCaller, serviceClient } from "../_shared/auth.ts";
import {
  errorResponse,
  handlePreflight,
  HttpError,
  readJsonObject,
  requirePost,
  stringField,
  successResponse,
} from "../_shared/http.ts";

serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);

    const adminClient = serviceClient();
    const caller = await requireCaller(req, undefined, adminClient);
    const body = await readJsonObject(req);
    const token = stringField(body, "token", { maxLength: 4096 });
    const deviceId = stringField(body, "device_id", { maxLength: 200 });
    if (!token && !deviceId) {
      throw new HttpError(
        422,
        "VALIDATION_ERROR",
        "token or device_id is required.",
      );
    }

    let query = adminClient
      .from("device_tokens")
      .update({
        active: false,
        updated_at: new Date().toISOString(),
      })
      .eq("profile_id", caller.id);
    query = token ? query.eq("token", token) : query.eq("device_id", deviceId);
    const { error } = await query;
    if (error) {
      console.error("Device token unregister failed", error);
      throw new HttpError(
        500,
        "DEVICE_TOKEN_REMOVE_FAILED",
        "The notification device could not be unregistered.",
      );
    }

    return successResponse(req, { unregistered: true }, 200, {
      unregistered: true,
    });
  } catch (error) {
    return errorResponse(req, error);
  }
});
