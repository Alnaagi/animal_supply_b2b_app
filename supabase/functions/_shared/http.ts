export class HttpError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

export function resolveAllowedOrigins(
  allowedOriginsRaw = Deno.env.get("ALLOWED_ORIGINS") ?? "",
  publicOriginRaw = Deno.env.get("APP_PUBLIC_ORIGIN") ?? "",
): string[] {
  const origins = allowedOriginsRaw
    .split(",")
    .map((origin) => origin.trim().replace(/\/+$/, ""))
    .filter(Boolean);
  const publicOrigin = publicOriginRaw.trim().replace(/\/+$/, "");
  if (publicOrigin && !origins.includes(publicOrigin)) {
    origins.push(publicOrigin);
  }
  return origins;
}

function allowedOrigins(): string[] {
  return resolveAllowedOrigins();
}

export function responseOrigin(
  req: Request,
  configuredOrigins = allowedOrigins(),
): string {
  const origin = req.headers.get("Origin");
  if (!origin) return "*";

  if (configuredOrigins.includes(origin)) {
    return origin;
  }

  throw new HttpError(
    403,
    "ORIGIN_NOT_ALLOWED",
    "This web origin is not allowed to call the function.",
  );
}

export function corsHeaders(
  req: Request,
  configuredOrigins?: string[],
): HeadersInit {
  return {
    "Access-Control-Allow-Origin": responseOrigin(req, configuredOrigins),
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-dispatch-secret",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8",
    "Vary": "Origin",
    "X-Content-Type-Options": "nosniff",
  };
}

export function handlePreflight(
  req: Request,
  configuredOrigins?: string[],
): Response | null {
  // Validate every browser origin before authentication, rate limiting,
  // database access, or service-role work can perform a side effect.
  responseOrigin(req, configuredOrigins);
  if (req.method !== "OPTIONS") return null;
  return new Response(null, {
    status: 204,
    headers: corsHeaders(req, configuredOrigins),
  });
}

export function requirePost(req: Request): void {
  if (req.method !== "POST") {
    throw new HttpError(405, "METHOD_NOT_ALLOWED", "Only POST is allowed.");
  }
}

export async function readJsonObject(
  req: Request,
): Promise<Record<string, unknown>> {
  const contentType = req.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    throw new HttpError(
      415,
      "CONTENT_TYPE_REQUIRED",
      "Content-Type must be application/json.",
    );
  }

  try {
    const body = await req.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new Error("JSON object required");
    }
    return body as Record<string, unknown>;
  } catch {
    throw new HttpError(
      400,
      "INVALID_JSON",
      "A valid JSON object is required.",
    );
  }
}

export function successResponse(
  req: Request,
  data: Record<string, unknown>,
  status = 200,
  topLevel: Record<string, unknown> = {},
): Response {
  return new Response(
    JSON.stringify({ ok: true, data, ...topLevel }),
    { status, headers: corsHeaders(req) },
  );
}

export function errorResponse(req: Request, error: unknown): Response {
  const normalized = normalizeError(error);
  let headers: HeadersInit;
  try {
    headers = corsHeaders(req);
  } catch {
    headers = {
      "Cache-Control": "no-store",
      "Content-Type": "application/json; charset=utf-8",
      "X-Content-Type-Options": "nosniff",
    };
  }
  return new Response(
    JSON.stringify({
      ok: false,
      error: {
        code: normalized.code,
        message: normalized.message,
        ...(normalized.details === undefined
          ? {}
          : { details: normalized.details }),
      },
    }),
    { status: normalized.status, headers },
  );
}

export function normalizeError(error: unknown): HttpError {
  if (error instanceof HttpError) return error;

  console.error("Unhandled Edge Function error", error);
  return new HttpError(
    500,
    "INTERNAL_ERROR",
    "The request could not be completed.",
  );
}

export function stringField(
  body: Record<string, unknown>,
  key: string,
  options: {
    required?: boolean;
    maxLength?: number;
    minLength?: number;
  } = {},
): string {
  const raw = body[key];
  const value = typeof raw === "string" ? raw.trim() : "";

  if (options.required && !value) {
    throw new HttpError(422, "VALIDATION_ERROR", `${key} is required.`, {
      field: key,
    });
  }
  if (options.minLength && value && value.length < options.minLength) {
    throw new HttpError(422, "VALIDATION_ERROR", `${key} is too short.`, {
      field: key,
      minLength: options.minLength,
    });
  }
  if (options.maxLength && value.length > options.maxLength) {
    throw new HttpError(422, "VALIDATION_ERROR", `${key} is too long.`, {
      field: key,
      maxLength: options.maxLength,
    });
  }
  return value;
}

export function optionalStringField(
  body: Record<string, unknown>,
  key: string,
  maxLength: number,
): string | null {
  const value = stringField(body, key, { maxLength });
  return value || null;
}

export function uuidField(
  body: Record<string, unknown>,
  key: string,
  required = true,
): string | null {
  const value = stringField(body, key, { required, maxLength: 36 });
  if (!value && !required) return null;
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) {
    throw new HttpError(422, "VALIDATION_ERROR", `${key} must be a UUID.`, {
      field: key,
    });
  }
  return value;
}

export function optionalTimestamptzField(
  body: Record<string, unknown>,
  key: string,
): string | null {
  if (!Object.prototype.hasOwnProperty.call(body, key) || body[key] == null) {
    return null;
  }
  const raw = body[key];
  const value = typeof raw === "string" ? raw.trim() : "";
  if (!value) return null;
  if (value.length > 40) {
    throw new HttpError(422, "VALIDATION_ERROR", `${key} is too long.`, {
      field: key,
    });
  }
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) {
    throw new HttpError(
      422,
      "VALIDATION_ERROR",
      `${key} must be an ISO-8601 timestamp.`,
      { field: key },
    );
  }
  return new Date(parsed).toISOString();
}
