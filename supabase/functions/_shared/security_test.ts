import { HttpError } from "./http.ts";
import {
  inviteUrl,
  rateLimitIdentity,
  strongPassword,
  validateCustomerLoginDomain,
  validateInviteBaseUrl,
  validateNotificationDispatchSecret,
  validateRateLimitSalt,
} from "./security.ts";

Deno.test("strongPassword accepts the shared Flutter policy", () => {
  const value = "Secure-Password-42!";
  if (strongPassword(value) !== value) {
    throw new Error("The validated password was not returned unchanged.");
  }
});

Deno.test("strongPassword rejects weak or oversized values", () => {
  for (
    const value of [
      null,
      "short",
      "alllowercase42!",
      "ALLUPPERCASE42!",
      "NoNumberHere!",
      "NoSymbolHere42",
      `A1!${"a".repeat(126)}`,
    ]
  ) {
    let error: unknown;
    try {
      strongPassword(value);
    } catch (caught) {
      error = caught;
    }
    if (
      !(error instanceof HttpError) ||
      error.code !== "PASSWORD_POLICY_FAILED"
    ) {
      throw new Error(`Expected PASSWORD_POLICY_FAILED for ${String(value)}`);
    }
  }
});

Deno.test("inviteUrl keeps credentials out of the HTTPS one-time link", () => {
  const link = inviteUrl(
    "server-generated-token",
    "shop-1",
    "https://app.example.ly/invite",
  );
  const url = new URL(link);
  if (
    url.protocol !== "https:" ||
    url.searchParams.get("token") !== "server-generated-token" ||
    url.searchParams.get("client") !== "shop-1" ||
    url.searchParams.has("password")
  ) {
    throw new Error("The secure invite URL was not constructed as expected.");
  }
});

Deno.test("validateInviteBaseUrl rejects unsafe configuration", () => {
  for (
    const value of [
      undefined,
      "http://app.example.ly/invite",
      "https://user:secret@app.example.ly/invite",
      "https://app.example.ly/invite?temporary_password=secret",
    ]
  ) {
    let error: unknown;
    try {
      validateInviteBaseUrl(value);
    } catch (caught) {
      error = caught;
    }
    if (!(error instanceof HttpError)) {
      throw new Error(`Expected unsafe invite base URL rejection: ${value}`);
    }
  }

  const safe = validateInviteBaseUrl("https://app.example.ly/invite");
  if (safe !== "https://app.example.ly/invite") {
    throw new Error("The safe invite base URL was unexpectedly changed.");
  }
});

Deno.test("customer login domain must be real and client-controlled", () => {
  for (
    const value of [
      undefined,
      "",
      "localhost",
      "example.com",
      "accounts.example.invalid",
      "https://accounts.client.ly",
    ]
  ) {
    let error: unknown;
    try {
      validateCustomerLoginDomain(value);
    } catch (caught) {
      error = caught;
    }
    if (
      !(error instanceof HttpError) ||
      error.code !== "CUSTOMER_LOGIN_DOMAIN_INVALID"
    ) {
      throw new Error(`Expected invalid customer login domain: ${value}`);
    }
  }

  const safe = validateCustomerLoginDomain("Accounts.Client.ly");
  if (safe !== "accounts.client.ly") {
    throw new Error("The customer login domain was not normalized.");
  }
});

Deno.test("authenticated rate limits can remain account-scoped across IPs", () => {
  const first = rateLimitIdentity(
    new Request("https://example.test", {
      headers: { "x-forwarded-for": "192.0.2.1" },
    }),
    "profile-1",
  );
  const second = rateLimitIdentity(
    new Request("https://example.test", {
      headers: { "x-forwarded-for": "198.51.100.2" },
    }),
    "profile-1",
  );

  if (first !== "profile-1" || second !== first) {
    throw new Error("The authenticated account rate-limit key was not stable.");
  }
});

Deno.test("hosted rate limiting requires a dedicated strong salt", () => {
  const configured = "0123456789abcdef0123456789abcdef";
  if (
    validateRateLimitSalt(
      configured,
      "https://project.supabase.co",
    ) !== configured
  ) {
    throw new Error("The configured rate-limit salt was not preserved.");
  }

  for (const salt of [undefined, "", "too-short"]) {
    let error: unknown;
    try {
      validateRateLimitSalt(salt, "https://project.supabase.co");
    } catch (caught) {
      error = caught;
    }
    if (
      !(error instanceof HttpError) ||
      error.code !== "RATE_LIMIT_SALT_REQUIRED"
    ) {
      throw new Error("Hosted deployment accepted an unsafe rate-limit salt.");
    }
  }
});

Deno.test("local Supabase keeps a development-only salt fallback", () => {
  for (
    const url of [
      "http://localhost:54321",
      "http://127.0.0.1:54321",
      "http://[::1]:54321",
    ]
  ) {
    if (!validateRateLimitSalt(undefined, url).startsWith("local-")) {
      throw new Error(`Local fallback was not enabled for ${url}.`);
    }
  }
});

Deno.test("notification dispatcher accepts only a strong configured secret", () => {
  const configured = "0123456789abcdef0123456789abcdef";
  if (validateNotificationDispatchSecret(configured) !== configured) {
    throw new Error("The dispatcher secret was unexpectedly changed.");
  }
  for (const absent of [undefined, "", "   "]) {
    if (validateNotificationDispatchSecret(absent) !== null) {
      throw new Error(
        "An absent dispatcher secret did not preserve JWT fallback.",
      );
    }
  }
  for (
    const value of [
      "short",
      "change-me-please-change-me-please-change-me",
      "example-dispatch-secret-example-dispatch-secret",
      "x".repeat(513),
    ]
  ) {
    let error: unknown;
    try {
      validateNotificationDispatchSecret(value);
    } catch (caught) {
      error = caught;
    }
    if (
      !(error instanceof HttpError) ||
      error.code !== "NOTIFICATION_DISPATCH_SECRET_INVALID"
    ) {
      throw new Error(`Unsafe dispatcher secret was accepted: ${value}`);
    }
  }
});
