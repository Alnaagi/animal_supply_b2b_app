import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireAuditLogId } from "../_shared/audit.ts";
import { requireCaller, serviceClient } from "../_shared/auth.ts";
import {
  errorResponse,
  handlePreflight,
  HttpError,
  readJsonObject,
  requirePost,
  stringField,
  successResponse,
  uuidField,
} from "../_shared/http.ts";
import {
  consumeRateLimit,
  inviteUrl,
  secureToken,
  sha256Hex,
  validatedInviteBaseUrl,
} from "../_shared/security.ts";
import { activationInvitePurpose } from "./contract.ts";

serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);
    const inviteBaseUrl = validatedInviteBaseUrl();

    const adminClient = serviceClient();
    const caller = await requireCaller(
      req,
      ["admin", "staff"],
      adminClient,
    );
    await consumeRateLimit(
      adminClient,
      req,
      `generate-invite-token:${caller.id}`,
      100,
      60 * 60,
    );
    const body = await readJsonObject(req);
    const customerId = uuidField(body, "customer_id")!;
    const purpose = activationInvitePurpose(
      stringField(body, "purpose", { maxLength: 32 }),
    );

    const expiresInDaysRaw = body.expires_in_days;
    const expiresInDays = typeof expiresInDaysRaw === "number"
      ? Math.trunc(expiresInDaysRaw)
      : 7;
    if (expiresInDays < 1 || expiresInDays > 30) {
      throw new HttpError(
        422,
        "VALIDATION_ERROR",
        "expires_in_days must be between 1 and 30.",
        { field: "expires_in_days" },
      );
    }

    const { data: customer, error: customerError } = await adminClient
      .from("business_customers")
      .select("id, profile_id, business_name, account_status")
      .eq("id", customerId)
      .maybeSingle();
    if (customerError) {
      console.error("Invite customer lookup failed", customerError);
      throw new HttpError(
        500,
        "CUSTOMER_LOOKUP_FAILED",
        "The customer could not be verified.",
      );
    }
    if (
      !customer?.profile_id ||
      customer.account_status === "archived"
    ) {
      throw new HttpError(
        404,
        "CUSTOMER_NOT_FOUND",
        "The customer was not found.",
      );
    }

    const { data: profile, error: profileError } = await adminClient
      .from("profiles")
      .select("id, username, role")
      .eq("id", customer.profile_id)
      .maybeSingle();
    if (profileError) {
      console.error("Invite profile lookup failed", profileError);
      throw new HttpError(
        500,
        "PROFILE_LOOKUP_FAILED",
        "The customer profile could not be verified.",
      );
    }
    if (!profile || profile.role !== "customer" || !profile.username) {
      throw new HttpError(
        403,
        "CUSTOMER_TARGET_REQUIRED",
        "Invites can only target customer profiles.",
      );
    }

    const requestedClientCode = stringField(body, "client_code", {
      maxLength: 64,
    });
    if (
      requestedClientCode &&
      requestedClientCode.toLowerCase() !== profile.username.toLowerCase()
    ) {
      throw new HttpError(
        422,
        "CLIENT_CODE_MISMATCH",
        "client_code must match the customer username.",
        { field: "client_code" },
      );
    }

    const token = secureToken();
    const tokenHash = await sha256Hex(token);
    const expiresAt = new Date(
      Date.now() + expiresInDays * 24 * 60 * 60 * 1000,
    ).toISOString();
    const link = inviteUrl(token, profile.username, inviteBaseUrl);
    const { data: invite, error: inviteError } = await adminClient
      .from("invite_tokens")
      .insert({
        customer_id: customer.id,
        token_hash: tokenHash,
        client_code: profile.username,
        purpose,
        expires_at: expiresAt,
        created_by: caller.id,
      })
      .select("id, customer_id, purpose, expires_at, created_at")
      .single();
    if (inviteError || !invite) {
      console.error("Invite insert failed", inviteError);
      throw new HttpError(
        500,
        "INVITE_CREATE_FAILED",
        "The secure invite could not be created.",
      );
    }

    let auditId: string;
    try {
      const { data: auditLog, error: auditError } = await adminClient
        .from("audit_logs")
        .insert({
          actor_id: caller.id,
          action: "invite.created",
          entity_table: "business_customers",
          entity_id: customer.id,
          metadata: {
            invite_id: invite.id,
            purpose,
            expires_at: expiresAt,
          },
        })
        .select("id")
        .single();
      auditId = requireAuditLogId(
        { data: auditLog, error: auditError },
        { action: "invite.created", entityId: customer.id },
      );
    } catch (error) {
      await cleanupInvite(adminClient, invite.id);
      throw error;
    }

    const { error: revokeError } = await adminClient
      .from("invite_tokens")
      .update({ revoked_at: new Date().toISOString() })
      .eq("customer_id", customer.id)
      .neq("id", invite.id)
      .is("revoked_at", null);
    if (revokeError) {
      await cleanupInvite(adminClient, invite.id);
      await cleanupAuditLog(adminClient, auditId);
      console.error("Older invite revocation failed", customer.id, revokeError);
      throw new HttpError(
        500,
        "INVITE_REPLACEMENT_FAILED",
        "The existing invite could not be replaced safely.",
      );
    }

    const data = {
      invite_id: invite.id,
      customer_id: customer.id,
      business_name: customer.business_name,
      client_code: profile.username,
      purpose,
      token,
      invite_link: link,
      inviteLink: link,
      expires_at: expiresAt,
      expiresAt,
    };
    return successResponse(req, data, 201, data);
  } catch (error) {
    return errorResponse(req, error);
  }
});

async function cleanupInvite(
  adminClient: ReturnType<typeof serviceClient>,
  inviteId: string,
): Promise<void> {
  const { error } = await adminClient
    .from("invite_tokens")
    .delete()
    .eq("id", inviteId);
  if (error) {
    console.error("Compensating invite cleanup failed", inviteId, error);
  }
}

async function cleanupAuditLog(
  adminClient: ReturnType<typeof serviceClient>,
  auditId: string,
): Promise<void> {
  const { error } = await adminClient
    .from("audit_logs")
    .delete()
    .eq("id", auditId);
  if (error) {
    console.error("Compensating audit log cleanup failed", auditId, error);
  }
}
