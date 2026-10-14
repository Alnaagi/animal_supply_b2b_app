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
  stringField,
  successResponse,
} from "../_shared/http.ts";
import {
  consumeRateLimit,
  sha256Hex,
  validatedInstallationId,
} from "../_shared/security.ts";

serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);

    const adminClient = serviceClient();
    const caller = await requireCaller(req, undefined, adminClient);
    const body = await readJsonObject(req);
    const token = stringField(body, "token", {
      required: true,
      minLength: 20,
      maxLength: 4096,
    });
    const platform = stringField(body, "platform", {
      required: true,
      maxLength: 16,
    });
    if (!["android", "ios", "web"].includes(platform)) {
      throw new HttpError(
        422,
        "VALIDATION_ERROR",
        "platform must be android, ios, or web.",
        { field: "platform" },
      );
    }
    const deviceId = optionalStringField(body, "device_id", 200);
    const installationIdRaw = Object.prototype.hasOwnProperty.call(
        body,
        "installation_id",
      )
      ? validatedInstallationId(body.installation_id)
      : null;
    if (caller.role === "customer" && !installationIdRaw) {
      throw new HttpError(
        422,
        "VALIDATION_ERROR",
        "installation_id is required for customer device binding.",
        { field: "installation_id" },
      );
    }
    const installationIdHash = installationIdRaw
      ? await sha256Hex(installationIdRaw)
      : null;
    const deviceLabel = optionalStringField(body, "device_label", 200);
    const appVersion = optionalStringField(body, "app_version", 50);
    const locale = optionalStringField(body, "locale", 20) ?? "ar_LY";

    await consumeRateLimit(
      adminClient,
      req,
      "register-device-token",
      60,
      60 * 60,
      caller.id,
    );

    const { data, error } = await adminClient.rpc(
      "register_device_token_transaction",
      {
        p_profile_id: caller.id,
        p_token: token,
        p_platform: platform,
        p_device_id: deviceId,
        p_installation_id_hash: installationIdHash,
        p_device_label: deviceLabel,
        p_app_version: appVersion,
        p_locale: locale,
        p_max_active: caller.role === "customer" ? 1 : 8,
      },
    );
    if (error) {
      throw databaseError(
        error,
        "DEVICE_TOKEN_SAVE_FAILED",
        "The notification device could not be registered.",
      );
    }
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new HttpError(
        500,
        "DEVICE_TOKEN_SAVE_FAILED",
        "The notification device returned an invalid result.",
      );
    }

    const result = data as Record<string, unknown>;
    return successResponse(req, result, 200, {
      registered: true,
      active_device_count: result.active_device_count,
      deactivated_device_count: result.deactivated_device_count,
    });
  } catch (error) {
    return errorResponse(req, error);
  }
});
