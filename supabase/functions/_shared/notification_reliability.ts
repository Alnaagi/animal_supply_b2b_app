import { HttpError } from "./http.ts";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function campaignIdempotencyKey(value: unknown): string {
  const key = typeof value === "string" ? value.trim() : "";
  if (!uuidPattern.test(key)) {
    throw new HttpError(
      422,
      "VALIDATION_ERROR",
      "idempotency_key must be a UUID.",
      { field: "idempotency_key" },
    );
  }
  return key;
}

export function deliveryRecordFailureStatus(input: {
  providerAccepted: boolean;
  retryableProviderFailure: boolean;
  attempts: number;
}): "failed" | "dead" {
  // If Firebase accepted the message but the database receipt failed, retrying
  // could deliver the same push twice. Quarantine the job for manual review.
  if (input.providerAccepted) return "dead";
  if (input.retryableProviderFailure && input.attempts < 10) return "failed";
  return "dead";
}

export function notificationRecipientBlockCode(input: {
  role: string | null | undefined;
  profileActive: boolean;
  mustChangePassword: boolean;
  customerStatus?: string | null;
  customerArchivedAt?: string | null;
}):
  | "RECIPIENT_ROLE_INVALID"
  | "RECIPIENT_PROFILE_INACTIVE"
  | "RECIPIENT_PASSWORD_CHANGE_REQUIRED"
  | "RECIPIENT_CUSTOMER_INACTIVE"
  | null {
  if (!["admin", "staff", "customer"].includes(input.role ?? "")) {
    return "RECIPIENT_ROLE_INVALID";
  }
  if (!input.profileActive) return "RECIPIENT_PROFILE_INACTIVE";
  if (input.mustChangePassword) {
    return "RECIPIENT_PASSWORD_CHANGE_REQUIRED";
  }
  if (
    input.role === "customer" &&
    (
      input.customerStatus !== "active" ||
      input.customerArchivedAt != null
    )
  ) {
    return "RECIPIENT_CUSTOMER_INACTIVE";
  }
  return null;
}

export function notificationDeliveryData(input: {
  payload: Record<string, unknown>;
  notificationId: string;
  type: string;
  recipientRole: string;
}): Record<string, unknown> {
  return {
    ...input.payload,
    notification_id: input.notificationId,
    type: input.type,
    recipient_role: input.recipientRole,
  };
}
