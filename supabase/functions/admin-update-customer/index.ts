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
} from "../_shared/http.ts";
import { consumeRateLimit } from "../_shared/security.ts";
import { parseCustomerUpdateBody } from "./contract.ts";

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
      `admin-update-customer:${caller.id}`,
      120,
      60 * 60,
    );
    const input = parseCustomerUpdateBody(await readJsonObject(req));

    const { data: customerTarget, error: customerTargetError } =
      await adminClient
        .from("business_customers")
        .select("id, profile_id, account_status")
        .eq("id", input.customerId)
        .maybeSingle();
    if (customerTargetError) {
      console.error(
        "Customer update target lookup failed",
        customerTargetError,
      );
      throw new HttpError(
        500,
        "CUSTOMER_LOOKUP_FAILED",
        "The customer account could not be verified.",
      );
    }
    if (!customerTarget?.profile_id) {
      throw new HttpError(
        404,
        "CUSTOMER_NOT_FOUND",
        "The customer account was not found.",
      );
    }

    const { data: targetProfile, error: targetProfileError } = await adminClient
      .from("profiles")
      .select("id, role")
      .eq("id", customerTarget.profile_id)
      .maybeSingle();
    if (targetProfileError) {
      console.error(
        "Customer update profile lookup failed",
        targetProfileError,
      );
      throw new HttpError(
        500,
        "PROFILE_LOOKUP_FAILED",
        "The customer profile could not be verified.",
      );
    }
    if (!targetProfile || targetProfile.role !== "customer") {
      throw new HttpError(
        403,
        "CUSTOMER_TARGET_REQUIRED",
        "Only a linked customer account can be updated.",
      );
    }

    const { data: customer, error: updateError } = await adminClient.rpc(
      "admin_update_business_customer_v2",
      {
        p_actor_id: caller.id,
        p_customer_id: input.customerId,
        p_business_name: input.businessName,
        p_contact_person: input.contactPerson,
        p_phone: input.phone,
        p_city: input.city,
        p_area: input.area,
        p_address: input.address,
        // A missing discount means "preserve the current value". The RPC
        // resolves that under the customer row lock so legacy clients cannot
        // overwrite a concurrent discount update with stale data.
        p_customer_discount_percent: input.discountPercent,
        p_account_status: input.accountStatus,
        p_credit_limit: input.creditLimit,
        p_outstanding_balance: input.outstandingBalance,
        p_phone_is_whatsapp: input.phoneIsWhatsapp,
        p_expected_updated_at: input.expectedUpdatedAt,
      },
    );
    if (updateError) {
      throw databaseError(
        updateError,
        "CUSTOMER_UPDATE_FAILED",
        "The customer account could not be updated.",
      );
    }
    if (!customer || typeof customer !== "object" || Array.isArray(customer)) {
      throw new HttpError(
        500,
        "CUSTOMER_UPDATE_FAILED",
        "The customer account update returned an invalid result.",
      );
    }

    const savedCustomer = customer as Record<string, unknown>;
    if (typeof savedCustomer.phone_is_whatsapp !== "boolean") {
      savedCustomer.phone_is_whatsapp = input.phoneIsWhatsapp;
    }
    if (
      typeof savedCustomer.account_status !== "string" ||
      !["active", "suspended", "archived"].includes(
        savedCustomer.account_status,
      )
    ) {
      throw new HttpError(
        500,
        "CUSTOMER_UPDATE_FAILED",
        "The customer account update did not return a valid status.",
      );
    }

    return successResponse(req, { customer: savedCustomer }, 200, {
      customer: savedCustomer,
    });
  } catch (error) {
    return errorResponse(req, error);
  }
});
