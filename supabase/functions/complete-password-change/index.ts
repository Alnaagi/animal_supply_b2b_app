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
import { consumeRateLimit, strongPassword } from "../_shared/security.ts";

serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);

    const adminClient = serviceClient();
    const caller = await requireCaller(
      req,
      undefined,
      adminClient,
      { allowPasswordChangeRequired: true },
    );
    await consumeRateLimit(
      adminClient,
      req,
      `complete-password-change:${caller.id}`,
      20,
      60 * 60,
    );
    const body = await readJsonObject(req);
    const newPassword = strongPassword(body.new_password);

    if (caller.mustChangePassword) {
      if (caller.role === "customer") {
        if (!caller.customer) {
          throw new HttpError(
            403,
            "CUSTOMER_ACCOUNT_REQUIRED",
            "A linked customer account is required.",
          );
        }
        const { data: inviteProof, error: inviteProofError } = await adminClient
          .from("invite_tokens")
          .select("id")
          .eq("customer_id", caller.customer.id)
          .eq("used_by", caller.id)
          .in("purpose", ["activation", "password_reset"])
          .not("used_at", "is", null)
          .is("revoked_at", null)
          .gt("expires_at", new Date().toISOString())
          .order("used_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        if (inviteProofError) {
          console.error(
            "Password-change invite proof lookup failed",
            caller.id,
            inviteProofError,
          );
          throw new HttpError(
            500,
            "INVITE_PROOF_LOOKUP_FAILED",
            "The invite proof could not be verified.",
          );
        }
        if (!inviteProof) {
          throw new HttpError(
            403,
            "INVITE_REDEMPTION_REQUIRED",
            "Open and redeem the current invite link before changing the temporary password.",
          );
        }
      }

      const passwordResult = await adminClient.auth.admin.updateUserById(
        caller.id,
        { password: newPassword },
      );
      if (passwordResult.error) {
        console.error(
          "Required password update failed",
          caller.id,
          passwordResult.error,
        );
        throw new HttpError(
          400,
          "PASSWORD_UPDATE_FAILED",
          "The new password could not be saved.",
        );
      }

      const { data: completion, error: completionError } = await adminClient
        .rpc(
          "complete_required_password_change_transaction",
          { p_profile_id: caller.id },
        );
      if (completionError) {
        throw databaseError(
          completionError,
          "PASSWORD_COMPLETION_FAILED",
          "The password-change requirement could not be completed.",
        );
      }
      if (
        !completion ||
        typeof completion !== "object" ||
        Array.isArray(completion) ||
        (completion as Record<string, unknown>).completed !== true
      ) {
        throw new HttpError(
          500,
          "PASSWORD_COMPLETION_FAILED",
          "The password-change requirement returned an invalid result.",
        );
      }
    }

    const data = {
      success: true,
      completed: true,
      already_completed: !caller.mustChangePassword,
    };
    return successResponse(req, data, 200, data);
  } catch (error) {
    return errorResponse(req, error);
  }
});
