import { HttpError } from "./http.ts";

interface FirebaseServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

interface FirebaseSendResult {
  ok: boolean;
  providerMessageId?: string;
  errorCode?: string;
  errorMessage?: string;
  retryable: boolean;
  deactivateToken: boolean;
}

export const androidNotificationChannelId = "animal_supply_orders";

export function firebaseServiceAccount(): FirebaseServiceAccount {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) {
    throw new HttpError(
      500,
      "FIREBASE_CONFIGURATION_REQUIRED",
      "Firebase service-account credentials are not configured.",
    );
  }

  try {
    const parsed = JSON.parse(raw) as Partial<FirebaseServiceAccount>;
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      throw new Error("Required service-account fields are missing");
    }
    return parsed as FirebaseServiceAccount;
  } catch {
    throw new HttpError(
      500,
      "FIREBASE_CONFIGURATION_INVALID",
      "Firebase service-account credentials are invalid.",
    );
  }
}

export async function firebaseAccessToken(
  account: FirebaseServiceAccount,
): Promise<string> {
  const tokenUri = account.token_uri ??
    "https://oauth2.googleapis.com/token";
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlJson({ alg: "RS256", typ: "JWT" });
  const claims = base64UrlJson({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  });
  const unsigned = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${base64UrlBytes(new Uint8Array(signature))}`;

  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const body = await response.json().catch(() => ({})) as {
    access_token?: string;
    error?: string;
    error_description?: string;
  };
  if (!response.ok || !body.access_token) {
    console.error("Firebase OAuth token request failed", {
      status: response.status,
      error: body.error,
      description: body.error_description,
    });
    throw new HttpError(
      502,
      "FIREBASE_AUTH_FAILED",
      "Firebase authentication failed.",
    );
  }
  return body.access_token;
}

export async function sendFirebaseMessage(input: {
  account: FirebaseServiceAccount;
  accessToken: string;
  token: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
}): Promise<FirebaseSendResult> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${
      encodeURIComponent(input.account.project_id)
    }/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${input.accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(firebaseMessagePayload(input)),
    },
  );
  const body = await response.json().catch(() => ({})) as {
    name?: string;
    error?: {
      status?: string;
      message?: string;
      details?: Array<{ errorCode?: string }>;
    };
  };
  if (response.ok && body.name) {
    return {
      ok: true,
      providerMessageId: body.name,
      retryable: false,
      deactivateToken: false,
    };
  }

  const errorCode = body.error?.details
    ?.map((detail) => detail.errorCode)
    .find(Boolean) ?? body.error?.status ?? `HTTP_${response.status}`;
  const retryable = response.status === 429 ||
    response.status >= 500 ||
    ["QUOTA_EXCEEDED", "UNAVAILABLE", "INTERNAL"].includes(errorCode);
  const deactivateToken = response.status === 404 ||
    ["UNREGISTERED", "SENDER_ID_MISMATCH"].includes(errorCode);
  return {
    ok: false,
    errorCode,
    errorMessage: body.error?.message ?? "Firebase rejected the message.",
    retryable,
    deactivateToken,
  };
}

export function firebaseMessagePayload(input: {
  token: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
}): Record<string, unknown> {
  return {
    message: {
      token: input.token,
      notification: {
        title: input.title,
        body: input.body,
      },
      data: stringifyData(input.data),
      android: {
        priority: "high",
        notification: {
          channel_id: androidNotificationChannelId,
          sound: "default",
        },
      },
      apns: {
        headers: { "apns-priority": "10" },
        payload: { aps: { sound: "default" } },
      },
      webpush: {
        headers: { Urgency: "high" },
        notification: {
          dir: "rtl",
          lang: "ar",
          icon: "/icons/Icon-192.png",
          badge: "/icons/Icon-192.png",
        },
      },
    },
  };
}

function stringifyData(
  data: Record<string, unknown>,
): Record<string, string> {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [
      key,
      typeof value === "string" ? value : JSON.stringify(value),
    ]),
  );
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0)).buffer;
}

function base64UrlJson(value: unknown): string {
  return base64UrlBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function base64UrlBytes(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/g, "");
}
