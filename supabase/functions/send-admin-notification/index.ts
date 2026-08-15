import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireCaller, serviceClient } from "../_shared/auth.ts";
import {
  errorResponse,
  handlePreflight,
  HttpError,
  readJsonObject,
  requirePost,
  successResponse,
  uuidField,
} from "../_shared/http.ts";

// Compatibility endpoint for older clients. New-order notifications are created
// atomically by place_order_transaction; this endpoint never trusts a client to
// author notification content or create duplicate notifications.
serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);

    const adminClient = serviceClient();
    const caller = await requireCaller(
      req,
      ["admin", "staff", "customer"],
      adminClient,
    );
    const body = await readJsonObject(req);
    const orderId = uuidField(body, "order_id")!;

    const { data: order, error: orderError } = await adminClient
      .from("orders")
      .select("id, customer_id")
      .eq("id", orderId)
      .maybeSingle();
    if (orderError) {
      console.error(
        "Notification compatibility order lookup failed",
        orderError,
      );
      throw new HttpError(
        500,
        "ORDER_LOOKUP_FAILED",
        "The order could not be verified.",
      );
    }
    if (!order) {
      throw new HttpError(404, "ORDER_NOT_FOUND", "The order was not found.");
    }
    if (
      caller.role === "customer" &&
      caller.customer?.id !== order.customer_id
    ) {
      throw new HttpError(
        403,
        "FORBIDDEN",
        "The order belongs to another customer.",
      );
    }

    const { count, error: notificationError } = await adminClient
      .from("notifications")
      .select("id", { count: "exact", head: true })
      .like("dedupe_key", `order:new:${order.id}:%`);
    if (notificationError) {
      console.error(
        "Notification compatibility lookup failed",
        notificationError,
      );
      throw new HttpError(
        500,
        "NOTIFICATION_LOOKUP_FAILED",
        "The notification state could not be verified.",
      );
    }

    if (!count) {
      throw new HttpError(
        409,
        "NOTIFICATION_NOT_ENQUEUED",
        "Use place-order so the order and notification are committed together.",
      );
    }

    const data = {
      stored: true,
      notification_count: count,
      managed_by: "place-order",
    };
    return successResponse(req, data, 200, {
      stored: true,
      tokenCount: 0,
      fcmDelivery: "queued",
    });
  } catch (error) {
    return errorResponse(req, error);
  }
});
