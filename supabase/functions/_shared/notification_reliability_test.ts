import { HttpError } from "./http.ts";
import {
  campaignIdempotencyKey,
  deliveryRecordFailureStatus,
  notificationDeliveryData,
  notificationRecipientBlockCode,
} from "./notification_reliability.ts";

Deno.test("campaign idempotency key accepts a client UUID unchanged", () => {
  const key = "11111111-1111-4111-8111-111111111111";
  if (campaignIdempotencyKey(key) !== key) {
    throw new Error("The campaign idempotency key was unexpectedly changed.");
  }
});

Deno.test("campaign idempotency key rejects missing or unsafe values", () => {
  for (const value of [null, "", "campaign-1", crypto.randomUUID() + "x"]) {
    let error: unknown;
    try {
      campaignIdempotencyKey(value);
    } catch (caught) {
      error = caught;
    }
    if (
      !(error instanceof HttpError) ||
      error.code !== "VALIDATION_ERROR"
    ) {
      throw new Error(`Expected idempotency validation failure: ${value}`);
    }
  }
});

Deno.test("accepted provider sends are never retried after receipt failure", () => {
  const status = deliveryRecordFailureStatus({
    providerAccepted: true,
    retryableProviderFailure: false,
    attempts: 1,
  });
  if (status !== "dead") {
    throw new Error("An accepted provider send could have been duplicated.");
  }
});

Deno.test("unsent retryable failures retain bounded retry behavior", () => {
  const retry = deliveryRecordFailureStatus({
    providerAccepted: false,
    retryableProviderFailure: true,
    attempts: 3,
  });
  const exhausted = deliveryRecordFailureStatus({
    providerAccepted: false,
    retryableProviderFailure: true,
    attempts: 10,
  });
  if (retry !== "failed" || exhausted !== "dead") {
    throw new Error("Delivery failure disposition is not bounded.");
  }
});

Deno.test("notification recipients fail closed when account access is locked", () => {
  const blocked = [
    notificationRecipientBlockCode({
      role: "customer",
      profileActive: false,
      mustChangePassword: false,
      customerStatus: "active",
    }),
    notificationRecipientBlockCode({
      role: "customer",
      profileActive: true,
      mustChangePassword: true,
      customerStatus: "active",
    }),
    notificationRecipientBlockCode({
      role: "customer",
      profileActive: true,
      mustChangePassword: false,
      customerStatus: "suspended",
    }),
    notificationRecipientBlockCode({
      role: "customer",
      profileActive: true,
      mustChangePassword: false,
      customerStatus: "active",
      customerArchivedAt: "2026-07-22T00:00:00Z",
    }),
  ];
  if (blocked.some((code) => code == null)) {
    throw new Error("A locked notification recipient remained eligible.");
  }

  const eligible = notificationRecipientBlockCode({
    role: "customer",
    profileActive: true,
    mustChangePassword: false,
    customerStatus: "active",
  });
  if (eligible !== null) {
    throw new Error(`An active recipient was blocked: ${eligible}`);
  }
});

Deno.test("notification delivery data uses authoritative reserved fields", () => {
  const data = notificationDeliveryData({
    payload: {
      order_id: "order-1",
      notification_id: "untrusted-notification",
      type: "untrusted-type",
      recipient_role: "admin",
    },
    notificationId: "notification-1",
    type: "order_status",
    recipientRole: "customer",
  });
  if (
    data.order_id !== "order-1" ||
    data.notification_id !== "notification-1" ||
    data.type !== "order_status" ||
    data.recipient_role !== "customer"
  ) {
    throw new Error(
      "Reserved notification routing data was not authoritative.",
    );
  }
});
