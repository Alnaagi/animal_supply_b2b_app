import { HttpError } from "../_shared/http.ts";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function validatedCampaignPayload(
  raw: unknown,
): Record<string, unknown> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpError(
      422,
      "INVALID_NOTIFICATION_PAYLOAD",
      "payload must be a JSON object.",
      { field: "payload" },
    );
  }

  const payload = { ...(raw as Record<string, unknown>) };
  const productId = payload.product_id;
  if (
    productId !== undefined &&
    (typeof productId !== "string" || !uuidPattern.test(productId.trim()))
  ) {
    throw new HttpError(
      422,
      "INVALID_CAMPAIGN_PRODUCT",
      "payload.product_id must be a UUID.",
      { field: "payload.product_id" },
    );
  }
  if (typeof productId === "string") {
    payload.product_id = productId.trim();
  }

  if (JSON.stringify(payload).length > 3_000) {
    throw new HttpError(
      422,
      "INVALID_NOTIFICATION_PAYLOAD",
      "payload is too large.",
      { field: "payload", maxBytes: 3_000 },
    );
  }
  return payload;
}
