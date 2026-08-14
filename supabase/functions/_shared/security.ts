import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

import { HttpError } from "./http.ts";

const encoder = new TextEncoder();

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function secureToken(bytes = 32): string {
  const random = crypto.getRandomValues(new Uint8Array(bytes));
  const binary = String.fromCharCode(...random);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/g, "");
}

export function temporaryPassword(): string {
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lower = "abcdefghijkmnopqrstuvwxyz";
  const digits = "23456789";
  const symbols = "!@#$%*-_";
  const all = upper + lower + digits + symbols;
  const required = [
    randomCharacter(upper),
    randomCharacter(lower),
    randomCharacter(digits),
    randomCharacter(symbols),
  ];
  while (required.length < 18) required.push(randomCharacter(all));

  for (let index = required.length - 1; index > 0; index--) {
    const randomIndex = randomInt(index + 1);
    [required[index], required[randomIndex]] = [
      required[randomIndex],
      required[index],
    ];
  }
  return required.join("");
}

export function validatedInviteBaseUrl(): string {
  return validateInviteBaseUrl(Deno.env.get("INVITE_BASE_URL"));
}

export function validatedCustomerLoginDomain(): string {
  return validateCustomerLoginDomain(Deno.env.get("CUSTOMER_LOGIN_DOMAIN"));
}

export function validateCustomerLoginDomain(
  rawDomain: string | undefined,
): string {
  const domain = rawDomain?.trim().toLowerCase() ?? "";
  const validSyntax = /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/
    .test(
      domain,
    );
  const forbidden = new Set([
    "example.com",
    "example.net",
    "example.org",
    "localhost",
  ]);
  if (
    !validSyntax ||
    forbidden.has(domain) ||
    [".invalid", ".example", ".test", ".localhost"].some((suffix) =>
      domain.endsWith(suffix)
    )
  ) {
    throw new HttpError(
      500,
      "CUSTOMER_LOGIN_DOMAIN_INVALID",
      "CUSTOMER_LOGIN_DOMAIN must be a real client-controlled DNS domain.",
    );
  }
  return domain;
}

export function validateInviteBaseUrl(baseUrl: string | undefined): string {
  if (!baseUrl) {
    throw new HttpError(
      500,
      "INVITE_BASE_URL_REQUIRED",
      "INVITE_BASE_URL must be configured for secure HTTPS invite links.",
    );
  }

  let url: URL;
  try {
    url = new URL(baseUrl);
  } catch {
    throw new HttpError(
      500,
      "INVITE_BASE_URL_INVALID",
      "INVITE_BASE_URL is not a valid URL.",
    );
  }
  if (url.protocol !== "https:") {
    throw new HttpError(
      500,
      "INVITE_BASE_URL_INSECURE",
      "INVITE_BASE_URL must use HTTPS.",
    );
  }
  const hasForbiddenParameter = [...url.searchParams.keys()].some((key) =>
    ["password", "temporary_password", "temporarypassword"].includes(
      key.toLowerCase(),
    )
  );
  if (url.username || url.password || hasForbiddenParameter) {
    throw new HttpError(
      500,
      "INVITE_BASE_URL_UNSAFE",
      "INVITE_BASE_URL must not contain credentials or password parameters.",
    );
  }

  return url.toString();
}

export function strongPassword(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpError(
      422,
      "PASSWORD_POLICY_FAILED",
      "A new password is required.",
      { field: "new_password" },
    );
  }
  if (value.length < 10 || value.length > 128) {
    throw new HttpError(
      422,
      "PASSWORD_POLICY_FAILED",
      "The password must contain 10-128 characters.",
      { field: "new_password", minLength: 10, maxLength: 128 },
    );
  }
  if (
    !/[A-Z]/.test(value) ||
    !/[a-z]/.test(value) ||
    !/[0-9]/.test(value) ||
    !/[^A-Za-z0-9]/.test(value)
  ) {
    throw new HttpError(
      422,
      "PASSWORD_POLICY_FAILED",
      "The password must contain uppercase, lowercase, number, and symbol characters.",
      { field: "new_password" },
    );
  }
  return value;
}

function randomCharacter(alphabet: string): string {
  return alphabet[randomInt(alphabet.length)];
}

function randomInt(maxExclusive: number): number {
  if (maxExclusive < 1) throw new Error("maxExclusive must be positive");
  const uint32Range = 0x100000000;
  const rejectionLimit = uint32Range - (uint32Range % maxExclusive);
  const buffer = new Uint32Array(1);
  do crypto.getRandomValues(buffer); while (buffer[0] >= rejectionLimit);
  return buffer[0] % maxExclusive;
}

export function inviteUrl(
  token: string,
  clientCode?: string | null,
  validatedBaseUrl = validatedInviteBaseUrl(),
): string {
  const url = new URL(validatedBaseUrl);
  url.searchParams.set("token", token);
  if (clientCode) url.searchParams.set("client", clientCode);
  return url.toString();
}

export async function consumeRateLimit(
  adminClient: SupabaseClient,
  req: Request,
  endpoint: string,
  limit: number,
  windowSeconds: number,
  keyMaterial?: string,
): Promise<{ remaining: number; resetAt: string }> {
  const source = rateLimitIdentity(req, keyMaterial);
  const salt = validateRateLimitSalt(
    Deno.env.get("RATE_LIMIT_SALT"),
    Deno.env.get("SUPABASE_URL"),
  );
  const keyHash = await sha256Hex(`${salt}|${source}`);

  const { data, error } = await adminClient.rpc("consume_edge_rate_limit", {
    p_endpoint: endpoint,
    p_key_hash: keyHash,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });
  if (error) {
    console.error("Rate limit RPC failed", error);
    throw new HttpError(
      503,
      "RATE_LIMIT_UNAVAILABLE",
      "The security check is temporarily unavailable.",
    );
  }

  const result = data as {
    allowed?: boolean;
    remaining?: number;
    reset_at?: string;
  };
  if (result.allowed !== true) {
    throw new HttpError(
      429,
      "RATE_LIMITED",
      "Too many attempts. Please try again later.",
      { resetAt: result.reset_at },
    );
  }

  return {
    remaining: Number(result.remaining ?? 0),
    resetAt: String(result.reset_at ?? ""),
  };
}

export function validateRateLimitSalt(
  rawSalt: string | undefined,
  rawSupabaseUrl: string | undefined,
): string {
  const salt = rawSalt?.trim() ?? "";
  if (salt.length >= 32) return salt;

  // A predictable fallback is acceptable only for the local Supabase stack.
  if (isLocalSupabaseUrl(rawSupabaseUrl)) {
    return "local-development-rate-limit-salt";
  }

  throw new HttpError(
    500,
    "RATE_LIMIT_SALT_REQUIRED",
    "RATE_LIMIT_SALT must be configured with at least 32 characters.",
  );
}

export function validateNotificationDispatchSecret(
  rawSecret: string | undefined,
): string | null {
  if (rawSecret == null || rawSecret.trim().length === 0) return null;
  const secret = rawSecret.trim();
  const normalized = secret.toLowerCase();
  const knownPlaceholder = normalized.includes("replace-me") ||
    normalized.includes("change-me") ||
    normalized.includes("example") ||
    normalized === "secret";
  if (secret.length < 32 || secret.length > 512 || knownPlaceholder) {
    throw new HttpError(
      500,
      "NOTIFICATION_DISPATCH_SECRET_INVALID",
      "NOTIFICATION_DISPATCH_SECRET must be a non-placeholder secret containing 32-512 characters.",
    );
  }
  return secret;
}

export function rateLimitIdentity(
  req: Request,
  keyMaterial?: string,
): string {
  return keyMaterial?.trim() ||
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    req.headers.get("cf-connecting-ip") ||
    req.headers.get("user-agent") ||
    "unknown";
}

function isLocalSupabaseUrl(rawUrl: string | undefined): boolean {
  if (!rawUrl) return false;
  try {
    const host = new URL(rawUrl).hostname;
    return host === "localhost" ||
      host === "127.0.0.1" ||
      host === "::1" ||
      host === "[::1]";
  } catch {
    return false;
  }
}
