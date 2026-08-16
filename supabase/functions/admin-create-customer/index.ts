import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireAuditLogId } from "../_shared/audit.ts";
import { requireCaller, serviceClient } from "../_shared/auth.ts";
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
  inviteUrl,
  publicLoginUrl,
  secureToken,
  sha256Hex,
  adminSetPassword,
  temporaryPassword,
  validatedCustomerLoginDomain,
  validatedInviteBaseUrl,
} from "../_shared/security.ts";

serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);
    const inviteBaseUrl = validatedInviteBaseUrl();
    const customerLoginDomain = validatedCustomerLoginDomain();

    const adminClient = serviceClient();
    const caller = await requireCaller(
      req,
      ["admin", "staff"],
      adminClient,
    );
    await consumeRateLimit(
      adminClient,
      req,
      `admin-create-customer:${caller.id}`,
      30,
      60 * 60,
    );
    const body = await readJsonObject(req);

    const username = normalizeUsername(
      stringField(body, "username", {
        required: true,
        minLength: 3,
        maxLength: 64,
      }),
    );
    const businessName = stringField(body, "business_name", {
      required: true,
      maxLength: 160,
    });
    const contactPerson = optionalStringField(body, "contact_person", 160);
    const phone = optionalStringField(body, "phone", 32);
    const phoneIsWhatsapp = optionalBooleanField(body, "phone_is_whatsapp", true);
    const city = optionalStringField(body, "city", 100);
    const area = optionalStringField(body, "area", 120);
    const address = optionalStringField(body, "address", 500);
    const creditLimit = nonNegativeMoneyField(body, "credit_limit");
    const discountPercent = customerDiscountField(body, "discount_percent");

    const { data: existingProfile, error: existingProfileError } =
      await adminClient
        .from("profiles")
        .select("id")
        .eq("username", username)
        .maybeSingle();
    if (existingProfileError) {
      console.error("Username uniqueness lookup failed", existingProfileError);
      throw new HttpError(
        500,
        "CUSTOMER_LOOKUP_FAILED",
        "The customer account could not be checked.",
      );
    }
    if (existingProfile) {
      throw new HttpError(
        409,
        "USERNAME_ALREADY_EXISTS",
        "This username is already assigned.",
      );
    }

    const providedPassword = Object.prototype.hasOwnProperty.call(
        body,
        "password",
      )
      ? body.password
      : undefined;
    const setPasswordOnly = providedPassword !== undefined &&
      providedPassword !== null &&
      String(providedPassword).trim() !== "";
    const password = setPasswordOnly
      ? adminSetPassword(String(providedPassword).trim())
      : temporaryPassword();
    const token = secureToken();
    const tokenHash = await sha256Hex(token);
    const expiresAt = new Date(
      Date.now() + 7 * 24 * 60 * 60 * 1000,
    ).toISOString();
    const link = inviteUrl(token, username, inviteBaseUrl);
    const settings = await loadPublicSettings(adminClient);
    const whatsappMessage = buildInviteMessage({
      businessName,
      shopName: settings.shopName,
      username,
      temporaryPassword: password,
      loginUrl: publicLoginUrl(inviteBaseUrl),
    });
    const authEmail = `${username}@${customerLoginDomain}`;
    const authAttributes: {
      email: string;
      password: string;
      email_confirm: boolean;
      phone?: string;
      phone_confirm?: boolean;
      user_metadata: Record<string, unknown>;
    } = {
      email: authEmail,
      password,
      email_confirm: true,
      user_metadata: { username },
    };
    if (phone && /^\+[1-9][0-9]{7,14}$/.test(phone)) {
      authAttributes.phone = phone;
      authAttributes.phone_confirm = true;
    }

    const created = await adminClient.auth.admin.createUser(authAttributes);
    if (created.error || !created.data.user) {
      const message = created.error?.message ?? "";
      if (/password/i.test(message) && /at least|characters|length/i.test(message)) {
        throw new HttpError(
          422,
          "PASSWORD_TOO_SHORT",
          "The password is shorter than the Auth minimum.",
          { field: "password", minLength: 6 },
        );
      }
      throw new HttpError(
        400,
        "AUTH_USER_CREATE_FAILED",
        created.error?.message ?? "The Auth user could not be created.",
      );
    }

    const userId = created.data.user.id;
    try {
      const { error: profileError } = await adminClient.from("profiles").insert(
        {
          id: userId,
          username,
          full_name: contactPerson,
          phone,
          role: "customer",
          must_change_password: !setPasswordOnly,
          active: true,
        },
      );
      if (profileError) {
        throw new HttpError(
          400,
          "PROFILE_CREATE_FAILED",
          profileError.message,
        );
      }

      const { data: customer, error: customerError } = await adminClient
        .from("business_customers")
        .insert({
          profile_id: userId,
          business_name: businessName,
          contact_person: contactPerson,
          phone,
          phone_is_whatsapp: phoneIsWhatsapp,
          city,
          area,
          address,
          discount_percent: discountPercent,
          credit_limit: creditLimit,
          account_status: "active",
        })
        .select()
        .single();
      if (customerError || !customer) {
        throw new HttpError(
          400,
          "CUSTOMER_CREATE_FAILED",
          customerError?.message ?? "The customer could not be created.",
        );
      }
      const { error: inviteError } = await adminClient
        .from("invite_tokens")
        .insert({
          customer_id: customer.id,
          token_hash: tokenHash,
          client_code: username,
          purpose: "activation",
          expires_at: expiresAt,
          created_by: caller.id,
        });
      if (inviteError) {
        throw new HttpError(
          500,
          "INVITE_CREATE_FAILED",
          "The secure invite could not be created.",
        );
      }

      const { data: auditLog, error: auditError } = await adminClient
        .from("audit_logs")
        .insert({
          actor_id: caller.id,
          action: "customer.created",
          entity_table: "business_customers",
          entity_id: customer.id,
          metadata: {
            profile_id: userId,
            username,
            discount_percent: discountPercent,
            invite_expires_at: expiresAt,
          },
        })
        .select("id")
        .single();
      requireAuditLogId(
        { data: auditLog, error: auditError },
        { action: "customer.created", entityId: customer.id },
      );

      const data = {
        customer,
        username,
        login_identifier: username,
        temporary_password: password,
        temporaryPassword: password,
        invite_link: link,
        inviteLink: link,
        expires_at: expiresAt,
        whatsapp_message: whatsappMessage,
        whatsappMessage,
      };
      return successResponse(req, data, 201, data);
    } catch (error) {
      const { error: customerCleanupError } = await adminClient
        .from("business_customers")
        .delete()
        .eq("profile_id", userId);
      if (customerCleanupError) {
        console.error(
          "Compensating customer cleanup failed",
          userId,
          customerCleanupError,
        );
      }
      const { error: profileCleanupError } = await adminClient
        .from("profiles")
        .delete()
        .eq("id", userId);
      if (profileCleanupError) {
        console.error(
          "Compensating profile cleanup failed",
          userId,
          profileCleanupError,
        );
      }
      const cleanup = await adminClient.auth.admin.deleteUser(userId);
      if (cleanup.error) {
        console.error(
          "Compensating Auth user cleanup failed",
          userId,
          cleanup.error,
        );
      }
      throw error;
    }
  } catch (error) {
    return errorResponse(req, error);
  }
});

function optionalBooleanField(
  body: Record<string, unknown>,
  key: string,
  defaultValue: boolean,
): boolean {
  if (!Object.prototype.hasOwnProperty.call(body, key)) return defaultValue;
  const value = body[key];
  if (typeof value !== "boolean") {
    throw new HttpError(
      422,
      "VALIDATION_ERROR",
      `${key} must be a boolean.`,
      { field: key },
    );
  }
  return value;
}

function normalizeUsername(value: string): string {
  const username = value.toLowerCase();
  if (
    !/^[a-z0-9](?:[a-z0-9._-]{1,62}[a-z0-9])$/.test(username) ||
    username.includes("..")
  ) {
    throw new HttpError(
      422,
      "USERNAME_INVALID",
      "Username must use 3-64 Latin letters, numbers, dot, dash, or underscore.",
      { field: "username" },
    );
  }
  return username;
}

function nonNegativeMoneyField(
  body: Record<string, unknown>,
  key: string,
): number {
  const raw = body[key] ?? 0;
  if (
    typeof raw !== "number" ||
    !Number.isFinite(raw) ||
    raw < 0 ||
    raw > 9_999_999_999.99 ||
    Math.abs(Math.round(raw * 100) / 100 - raw) > 1e-9
  ) {
    throw new HttpError(
      422,
      "VALIDATION_ERROR",
      `${key} must be a non-negative amount with at most two decimals.`,
      { field: key },
    );
  }
  return raw;
}

function customerDiscountField(
  body: Record<string, unknown>,
  key: string,
): number {
  const raw = body[key] ?? 0;
  if (
    typeof raw !== "number" ||
    !Number.isFinite(raw) ||
    raw < 0 ||
    raw >= 100 ||
    Math.abs(Math.round(raw * 100) / 100 - raw) > 1e-9
  ) {
    throw new HttpError(
      422,
      "VALIDATION_ERROR",
      `${key} must be between 0 and 99.99 with at most two decimals.`,
      { field: key },
    );
  }
  return raw;
}

async function loadPublicSettings(
  adminClient: ReturnType<typeof serviceClient>,
): Promise<{ shopName: string; downloadLink: string }> {
  const { data, error } = await adminClient
    .from("app_settings")
    .select("key,value")
    .in("key", ["shop_name", "download_link"]);
  if (error) console.error("Unable to load invite settings", error);

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

function buildInviteMessage(input: {
  businessName: string;
  shopName: string;
  username: string;
  temporaryPassword: string;
  loginUrl: string;
}): string {
  const loginBlock = input.loginUrl
    ? `\n\nرابط تسجيل الدخول:\n${input.loginUrl}`
    : "";
  return `مرحباً ${input.businessName} 👋

أهلاً بكم في ${input.shopName}. يسعدنا انضمام نشاطكم إلى متجر طلبات الجملة للأعلاف ومستلزمات الحيوانات.

بيانات الدخول:
اسم المستخدم: ${input.username}
كلمة المرور المؤقتة: ${input.temporaryPassword}${loginBlock}

يمكنكم تسجيل الدخول باستخدام اسم المستخدم وكلمة المرور الظاهرة هنا.`;
}
