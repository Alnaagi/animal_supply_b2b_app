import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireAuditLogId } from "../_shared/audit.ts";
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
import {
  consumeRateLimit,
  inviteUrl,
  secureToken,
  sha256Hex,
  adminSetPassword,
  temporaryPassword,
  validatedInviteBaseUrl,
} from "../_shared/security.ts";

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
      `admin-reset-customer-password:${caller.id}`,
      30,
      60 * 60,
    );
    const body = await readJsonObject(req);
    const requestedUserId = uuidField(body, "user_id", false);
    const requestedCustomerId = uuidField(body, "customer_id", false);
    if (!requestedUserId && !requestedCustomerId) {
      throw new HttpError(
        422,
        "VALIDATION_ERROR",
        "user_id or customer_id is required.",
      );
    }

    let customerQuery = adminClient
      .from("business_customers")
      .select("id, profile_id, business_name, phone, account_status");
    customerQuery = requestedCustomerId
      ? customerQuery.eq("id", requestedCustomerId)
      : customerQuery.eq("profile_id", requestedUserId!);
    const { data: customer, error: customerError } = await customerQuery
      .maybeSingle();
    if (customerError) {
      console.error("Password reset customer lookup failed", customerError);
      throw new HttpError(
        500,
        "CUSTOMER_LOOKUP_FAILED",
        "The target customer could not be verified.",
      );
    }
    if (!customer?.profile_id || customer.account_status === "archived") {
      throw new HttpError(
        404,
        "CUSTOMER_NOT_FOUND",
        "An active or suspended customer target is required.",
      );
    }

    const { data: profile, error: profileError } = await adminClient
      .from("profiles")
      .select("id, username, role, must_change_password")
      .eq("id", customer.profile_id)
      .maybeSingle();
    if (profileError) {
      console.error("Password reset profile lookup failed", profileError);
      throw new HttpError(
        500,
        "PROFILE_LOOKUP_FAILED",
        "The target profile could not be verified.",
      );
    }
    if (!profile || profile.role !== "customer" || !profile.username) {
      throw new HttpError(
        403,
        "CUSTOMER_TARGET_REQUIRED",
        "Password reset is limited to customer accounts.",
      );
    }

    const providedPassword = Object.prototype.hasOwnProperty.call(
        body,
        "password",
      )
      ? body.password
      : Object.prototype.hasOwnProperty.call(body, "new_password")
      ? body.new_password
      : undefined;
    const setPasswordOnly = providedPassword !== undefined &&
      providedPassword !== null &&
      String(providedPassword).trim() !== "";
    const password = setPasswordOnly
      ? adminSetPassword(String(providedPassword).trim())
      : temporaryPassword();

    if (setPasswordOnly) {
      const previousMustChangePassword = profile.must_change_password === true;
      const { data: passwordPolicyRow, error: mustChangeError } =
        await adminClient
          .from("profiles")
          .update({ must_change_password: false })
          .eq("id", profile.id)
          .eq("role", "customer")
          .select("id")
          .maybeSingle();
      if (mustChangeError || !passwordPolicyRow) {
        console.error("Unable to clear password-change requirement", mustChangeError);
        throw new HttpError(
          500,
          "PASSWORD_POLICY_UPDATE_FAILED",
          "The password-reset policy could not be prepared.",
        );
      }

      let auditId: string;
      try {
        const { data: auditLog, error: auditError } = await adminClient
          .from("audit_logs")
          .insert({
            actor_id: caller.id,
            action: "customer.password_set",
            entity_table: "business_customers",
            entity_id: customer.id,
            metadata: {
              profile_id: profile.id,
            },
          })
          .select("id")
          .single();
        auditId = requireAuditLogId(
          { data: auditLog, error: auditError },
          { action: "customer.password_set", entityId: customer.id },
        );
      } catch (error) {
        await restorePasswordPolicy(
          adminClient,
          profile.id,
          previousMustChangePassword,
        );
        throw error;
      }

      const result = await adminClient.auth.admin.updateUserById(profile.id, {
        password,
      });
      if (result.error) {
        await cleanupAuditLog(adminClient, auditId);
        await restorePasswordPolicy(
          adminClient,
          profile.id,
          previousMustChangePassword,
        );
        console.error(
          "Customer Auth password set failed",
          profile.id,
          result.error,
        );
        throw new HttpError(
          400,
          "PASSWORD_RESET_FAILED",
          "The customer password could not be reset.",
        );
      }

      return successResponse(req, {
        customer_id: customer.id,
        user_id: profile.id,
        username: profile.username,
        password_updated: true,
      });
    }

    const token = secureToken();
    const tokenHash = await sha256Hex(token);
    const expiresAt = new Date(
      Date.now() + 24 * 60 * 60 * 1000,
    ).toISOString();
    const link = inviteUrl(token, profile.username, inviteBaseUrl);
    const settings = await loadSettings(adminClient);
    const whatsappMessage = buildResetMessage({
      businessName: customer.business_name,
      shopName: settings.shopName,
      username: profile.username,
      temporaryPassword: password,
      downloadLink: settings.downloadLink,
      inviteLink: link,
    });

    const { data: invite, error: inviteError } = await adminClient
      .from("invite_tokens")
      .insert({
        customer_id: customer.id,
        token_hash: tokenHash,
        client_code: profile.username,
        purpose: "password_reset",
        expires_at: expiresAt,
        created_by: caller.id,
      })
      .select("id")
      .single();
    if (inviteError || !invite) {
      console.error("Password reset invite insert failed", inviteError);
      throw new HttpError(
        500,
        "INVITE_CREATE_FAILED",
        "The secure password-reset invite could not be created.",
      );
    }

    const previousMustChangePassword = profile.must_change_password === true;
    const { data: passwordPolicyRow, error: mustChangeError } =
      await adminClient
        .from("profiles")
        .update({ must_change_password: true })
        .eq("id", profile.id)
        .eq("role", "customer")
        .select("id")
        .maybeSingle();
    if (mustChangeError || !passwordPolicyRow) {
      console.error("Unable to enforce password change", mustChangeError);
      await cleanupInvite(adminClient, invite.id);
      throw new HttpError(
        500,
        "PASSWORD_POLICY_UPDATE_FAILED",
        "The password-reset policy could not be prepared.",
      );
    }

    let auditId: string;
    try {
      const { data: auditLog, error: auditError } = await adminClient
        .from("audit_logs")
        .insert({
          actor_id: caller.id,
          action: "customer.password_reset",
          entity_table: "business_customers",
          entity_id: customer.id,
          metadata: {
            profile_id: profile.id,
            invite_expires_at: expiresAt,
          },
        })
        .select("id")
        .single();
      auditId = requireAuditLogId(
        { data: auditLog, error: auditError },
        { action: "customer.password_reset", entityId: customer.id },
      );
    } catch (error) {
      await cleanupInvite(adminClient, invite.id);
      await restorePasswordPolicy(
        adminClient,
        profile.id,
        previousMustChangePassword,
      );
      throw error;
    }

    const result = await adminClient.auth.admin.updateUserById(profile.id, {
      password,
    });
    if (result.error) {
      await cleanupInvite(adminClient, invite.id);
      await cleanupAuditLog(adminClient, auditId);
      await restorePasswordPolicy(
        adminClient,
        profile.id,
        previousMustChangePassword,
      );
      console.error(
        "Customer Auth password reset failed",
        profile.id,
        result.error,
      );
      throw new HttpError(
        400,
        "PASSWORD_RESET_FAILED",
        "The customer password could not be reset.",
      );
    }

    const { error: revokeError } = await adminClient
      .from("invite_tokens")
      .update({ revoked_at: new Date().toISOString() })
      .eq("customer_id", customer.id)
      .neq("id", invite.id)
      .is("revoked_at", null);
    if (revokeError) {
      console.error(
        "Unable to revoke older password-reset invites",
        customer.id,
        revokeError,
      );
    }

    const data = {
      customer_id: customer.id,
      user_id: profile.id,
      username: profile.username,
      temporary_password: password,
      temporaryPassword: password,
      invite_link: link,
      inviteLink: link,
      expires_at: expiresAt,
      whatsapp_message: whatsappMessage,
      whatsappMessage,
    };
    return successResponse(req, data, 200, data);
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

async function restorePasswordPolicy(
  adminClient: ReturnType<typeof serviceClient>,
  profileId: string,
  previousMustChangePassword: boolean,
): Promise<void> {
  const { error } = await adminClient
    .from("profiles")
    .update({ must_change_password: previousMustChangePassword })
    .eq("id", profileId)
    .eq("role", "customer");
  if (error) {
    console.error(
      "Unable to restore password-change policy",
      profileId,
      error,
    );
  }
}

async function loadSettings(
  adminClient: ReturnType<typeof serviceClient>,
): Promise<{ shopName: string; downloadLink: string }> {
  const { data } = await adminClient
    .from("app_settings")
    .select("key,value")
    .in("key", ["shop_name", "download_link"]);
  const settings = new Map(
    (data ?? []).map((row) => [String(row.key), String(row.value)]),
  );
  return {
    shopName: settings.get("shop_name") ??
      "متجر أعلاف ومستلزمات الحيوانات",
    downloadLink: settings.get("download_link") ??
      Deno.env.get("APP_DOWNLOAD_LINK") ??
      "",
  };
}

function buildResetMessage(input: {
  businessName: string;
  shopName: string;
  username: string;
  temporaryPassword: string;
  downloadLink: string;
  inviteLink: string;
}): string {
  return `مرحباً ${input.businessName} 👋

تمت إعادة تعيين كلمة المرور لحسابكم في تطبيق ${input.shopName}.

بيانات الدخول:
اسم المستخدم: ${input.username}
كلمة المرور المؤقتة: ${input.temporaryPassword}

${
    input.downloadLink
      ? `رابط تحميل التطبيق:\n${input.downloadLink}\n\n`
      : ""
  }رابط فتح الحساب:
${input.inviteLink}

يرجى تغيير كلمة المرور فور تسجيل الدخول.`;
}
