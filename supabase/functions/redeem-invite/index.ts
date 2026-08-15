import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireCaller, serviceClient } from "../_shared/auth.ts";
import { databaseError } from "../_shared/database.ts";
import {
  errorResponse,
  handlePreflight,
  readJsonObject,
  requirePost,
  stringField,
  successResponse,
} from "../_shared/http.ts";
import { consumeRateLimit, sha256Hex } from "../_shared/security.ts";

serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);

    const adminClient = serviceClient();
    const caller = await requireCaller(
      req,
      ["customer"],
      adminClient,
      { allowPasswordChangeRequired: true },
    );
    const body = await readJsonObject(req);
    const token = stringField(body, "token", {
      required: true,
      minLength: 32,
      maxLength: 256,
    });
    const clientCode = stringField(body, "client_code", { maxLength: 64 }) ||
      null;

    await consumeRateLimit(
      adminClient,
      req,
      `redeem-invite:${caller.id}`,
      10,
      15 * 60,
    );

    const tokenHash = await sha256Hex(token);
    const { data, error } = await adminClient.rpc("redeem_invite_token", {
      p_token_hash: tokenHash,
      p_client_code: clientCode,
      p_redeemed_by: caller.id,
    });
    if (error) {
      throw databaseError(
        error,
        "INVITE_REDEEM_FAILED",
        "The invite could not be redeemed.",
      );
    }

    const result = data as Record<string, unknown>;
    return successResponse(
      req,
      {
        ...result,
        success: true,
        redeemed: true,
      },
      200,
      {
        success: true,
        redeemed: true,
        ...result,
      },
    );
  } catch (error) {
    return errorResponse(req, error);
  }
});
