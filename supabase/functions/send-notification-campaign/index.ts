import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireCaller, serviceClient } from "../_shared/auth.ts";
import { databaseError } from "../_shared/database.ts";
import {
  errorResponse,
  handlePreflight,
  HttpError,
  readJsonObject,
  requirePost,
  stringField,
  successResponse,
} from "../_shared/http.ts";
import { campaignIdempotencyKey } from "../_shared/notification_reliability.ts";
import { consumeRateLimit } from "../_shared/security.ts";
import { validatedCampaignPayload } from "./payload.ts";

type AudienceType =
  | "all"
  | "role"
  | "roles"
  | "profile_ids"
  | "customer_ids"
  | "city";

serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);

    const adminClient = serviceClient();
    const caller = await requireCaller(req, ["admin"], adminClient);
    const body = await readJsonObject(req);
    const title = stringField(body, "title", {
      required: true,
      maxLength: 160,
    });
    const messageBody = stringField(body, "body", {
      required: true,
      maxLength: 1000,
    });
    const notificationType = stringField(body, "type", {
      required: true,
      maxLength: 64,
    });
    if (!/^[a-z][a-z0-9_.-]{1,63}$/.test(notificationType)) {
      throw new HttpError(
        422,
        "INVALID_NOTIFICATION_TYPE",
        "type must use lowercase letters, numbers, dot, dash, or underscore.",
        { field: "type" },
      );
    }

    const payload = validatedCampaignPayload(body.payload ?? {});

    const audience = parseAudience(body);
    await consumeRateLimit(
      adminClient,
      req,
      `send-notification-campaign:${caller.id}`,
      20,
      60 * 60,
    );

    const productId = typeof payload.product_id === "string"
      ? payload.product_id
      : null;
    if (productId) {
      const { data: product, error: productError } = await adminClient
        .from("products")
        .select("id")
        .eq("id", productId)
        .eq("active", true)
        .is("archived_at", null)
        .maybeSingle();
      if (productError) {
        throw databaseError(
          productError,
          "CAMPAIGN_PRODUCT_LOOKUP_FAILED",
          "The campaign product could not be verified.",
        );
      }
      if (!product) {
        throw new HttpError(
          422,
          "CAMPAIGN_PRODUCT_UNAVAILABLE",
          "The campaign product is unavailable or archived.",
          { field: "payload.product_id" },
        );
      }
    }

    const campaignId = campaignIdempotencyKey(body.idempotency_key);
    const { data, error } = await adminClient.rpc(
      "send_notification_campaign_transaction",
      {
        p_actor_id: caller.id,
        p_campaign_id: campaignId,
        p_title: title,
        p_body: messageBody,
        p_type: notificationType,
        p_payload: payload,
        p_audience: audience,
      },
    );
    if (error) {
      throw databaseError(
        error,
        "NOTIFICATION_CAMPAIGN_FAILED",
        "The notification campaign could not be queued.",
      );
    }

    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new HttpError(
        500,
        "NOTIFICATION_CAMPAIGN_FAILED",
        "The notification campaign returned an invalid result.",
      );
    }
    const result = data as Record<string, unknown>;
    const idempotent = result.idempotent === true;
    return successResponse(req, result, idempotent ? 200 : 201, {
      sent: true,
      queued: true,
      idempotent,
      campaign_id: result.campaign_id,
      recipient_count: result.recipient_count,
    });
  } catch (error) {
    return errorResponse(req, error);
  }
});

function parseAudience(
  body: Record<string, unknown>,
): Record<string, unknown> {
  const raw = body.audience;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpError(
      422,
      "INVALID_CAMPAIGN_AUDIENCE",
      "audience must be a JSON object.",
      { field: "audience" },
    );
  }
  const audience = raw as Record<string, unknown>;
  const type = stringField(audience, "type", {
    required: true,
    maxLength: 32,
  }) as AudienceType;
  if (
    !["all", "role", "roles", "profile_ids", "customer_ids", "city"].includes(
      type,
    )
  ) {
    throw new HttpError(
      422,
      "INVALID_CAMPAIGN_AUDIENCE",
      "Unsupported audience type.",
      { field: "audience.type" },
    );
  }

  if (type === "all") return { type };
  if (type === "role") {
    const role = stringField(audience, "role", {
      required: true,
      maxLength: 16,
    });
    if (!["admin", "staff", "customer"].includes(role)) {
      throw new HttpError(
        422,
        "INVALID_CAMPAIGN_ROLE",
        "role must be admin, staff, or customer.",
        { field: "audience.role" },
      );
    }
    return { type, role };
  }
  if (type === "roles") {
    const roles = audience.roles;
    if (
      !Array.isArray(roles) ||
      roles.length === 0 ||
      roles.length > 3 ||
      roles.some(
        (role) =>
          typeof role !== "string" ||
          !["admin", "staff", "customer"].includes(role),
      )
    ) {
      throw new HttpError(
        422,
        "INVALID_CAMPAIGN_ROLE",
        "roles must contain one or more supported roles.",
        { field: "audience.roles" },
      );
    }
    return { type, roles: [...new Set(roles)] };
  }
  if (type === "city") {
    return {
      type,
      city: stringField(audience, "city", {
        required: true,
        maxLength: 100,
      }),
    };
  }

  const field = type === "profile_ids" ? "profile_ids" : "customer_ids";
  const ids = audience[field];
  if (!Array.isArray(ids) || ids.length === 0 || ids.length > 1000) {
    throw new HttpError(
      422,
      "INVALID_CAMPAIGN_AUDIENCE",
      `${field} must contain 1-1000 UUIDs.`,
      { field: `audience.${field}` },
    );
  }
  const validated = ids.map((value, index) => {
    if (
      typeof value !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(value)
    ) {
      throw new HttpError(
        422,
        "INVALID_CAMPAIGN_AUDIENCE",
        `${field} must contain UUIDs.`,
        { field: `audience.${field}[${index}]` },
      );
    }
    return value;
  });
  return { type, [field]: [...new Set(validated)] };
}
