import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

import { requireCaller, serviceClient } from "../_shared/auth.ts";
import {
  firebaseAccessToken,
  firebaseServiceAccount,
  sendFirebaseMessage,
} from "../_shared/firebase.ts";
import {
  errorResponse,
  handlePreflight,
  HttpError,
  requirePost,
  successResponse,
} from "../_shared/http.ts";
import {
  deliveryRecordFailureStatus,
  notificationDeliveryData,
  notificationRecipientBlockCode,
} from "../_shared/notification_reliability.ts";
import { validateNotificationDispatchSecret } from "../_shared/security.ts";

interface ClaimedJob {
  outbox_id: string;
  notification_id: string;
  attempts: number;
}

interface NotificationRow {
  id: string;
  recipient_profile_id: string;
  type: string;
  title: string;
  body: string;
  payload: Record<string, unknown>;
  expires_at: string | null;
}

interface RecipientEligibility {
  role: string | null;
  blockCode: string | null;
}

serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);

    const adminClient = serviceClient();
    await authorizeDispatcher(req, adminClient);
    const limit = await readLimit(req);
    const account = firebaseServiceAccount();
    const workerId = `edge-${crypto.randomUUID()}`;

    const { data: claimed, error: claimError } = await adminClient.rpc(
      "claim_notification_outbox",
      { p_worker_id: workerId, p_limit: limit },
    );
    if (claimError) {
      console.error("Notification outbox claim failed", claimError);
      throw new HttpError(
        500,
        "OUTBOX_CLAIM_FAILED",
        "Notification jobs could not be claimed.",
      );
    }

    const jobs = (claimed ?? []) as ClaimedJob[];
    if (jobs.length === 0) {
      return successResponse(req, {
        processed: 0,
        sent: 0,
        failed: 0,
        dead: 0,
      });
    }

    let accessToken: string;
    try {
      accessToken = await firebaseAccessToken(account);
    } catch (error) {
      let finalizationFailures = 0;
      for (const job of jobs) {
        try {
          await finalizeJob(
            adminClient,
            workerId,
            job,
            job.attempts >= 10 ? "dead" : "failed",
            error instanceof Error ? error.message : "Firebase auth failed",
          );
        } catch (finalizationError) {
          finalizationFailures++;
          console.error(
            "Unable to release notification job after Firebase auth failure",
            {
              outboxId: job.outbox_id,
              error: finalizationError,
            },
          );
        }
      }
      if (finalizationFailures > 0) {
        throw new HttpError(
          500,
          "OUTBOX_AUTH_FAILURE_FINALIZE_FAILED",
          "Some notification jobs could not be released after provider authentication failed.",
        );
      }
      throw error;
    }
    let sentCount = 0;
    let failedCount = 0;
    let deadCount = 0;

    for (const job of jobs) {
      try {
        const result = await processJob({
          adminClient,
          account,
          accessToken,
          workerId,
          job,
        });
        if (result === "sent") sentCount++;
        if (result === "failed") failedCount++;
        if (result === "dead") deadCount++;
      } catch (error) {
        console.error("Unexpected notification job failure", {
          outboxId: job.outbox_id,
          error,
        });
        const dead = job.attempts >= 10;
        await finalizeJob(
          adminClient,
          workerId,
          job,
          dead ? "dead" : "failed",
          error instanceof Error ? error.message : "Unexpected dispatch error",
        );
        if (dead) deadCount++;
        else failedCount++;
      }
    }

    return successResponse(req, {
      processed: jobs.length,
      sent: sentCount,
      failed: failedCount,
      dead: deadCount,
    });
  } catch (error) {
    return errorResponse(req, error);
  }
});

async function processJob(input: {
  adminClient: SupabaseClient;
  account: ReturnType<typeof firebaseServiceAccount>;
  accessToken: string;
  workerId: string;
  job: ClaimedJob;
}): Promise<"sent" | "failed" | "dead"> {
  const { adminClient, account, accessToken, workerId, job } = input;
  const { data: notification, error: notificationError } = await adminClient
    .from("notifications")
    .select(
      "id, recipient_profile_id, type, title, body, payload, expires_at",
    )
    .eq("id", job.notification_id)
    .maybeSingle();
  if (notificationError) {
    return await finalizeJob(
      adminClient,
      workerId,
      job,
      job.attempts >= 10 ? "dead" : "failed",
      `NOTIFICATION_LOOKUP_FAILED: ${notificationError.message}`.slice(
        0,
        2000,
      ),
    );
  }
  if (!notification) {
    return await finalizeJob(
      adminClient,
      workerId,
      job,
      "dead",
      "Notification row not found",
    );
  }
  const row = notification as NotificationRow;

  if (row.expires_at && new Date(row.expires_at).getTime() <= Date.now()) {
    const { error: deliveryError } = await adminClient
      .from("notification_deliveries")
      .insert({
        outbox_id: job.outbox_id,
        status: "skipped",
        error_code: "NOTIFICATION_EXPIRED",
        error_message: "Notification expired before delivery.",
      });
    if (deliveryError) {
      throw deliveryDatabaseError(
        job,
        "Unable to record the expired notification.",
        deliveryError,
      );
    }
    return await finalizeJob(adminClient, workerId, job, "sent", null);
  }

  const recipient = await recipientEligibility(
    adminClient,
    row.recipient_profile_id,
  );
  if (recipient.blockCode) {
    const { error: deactivateError } = await adminClient
      .from("device_tokens")
      .update({
        active: false,
        updated_at: new Date().toISOString(),
      })
      .eq("profile_id", row.recipient_profile_id)
      .eq("active", true);
    if (deactivateError) {
      return await finalizeJob(
        adminClient,
        workerId,
        job,
        job.attempts >= 10 ? "dead" : "failed",
        `RECIPIENT_TOKEN_DEACTIVATION_FAILED: ${deactivateError.message}`.slice(
          0,
          2000,
        ),
      );
    }
    const { error: deliveryError } = await adminClient
      .from("notification_deliveries")
      .insert({
        outbox_id: job.outbox_id,
        status: "skipped",
        error_code: recipient.blockCode,
        error_message:
          "The recipient account is not eligible for push delivery.",
      });
    if (deliveryError) {
      throw deliveryDatabaseError(
        job,
        "Unable to record the blocked notification recipient.",
        deliveryError,
      );
    }
    return await finalizeJob(adminClient, workerId, job, "sent", null);
  }

  const { data: tokens, error: tokenError } = await adminClient
    .from("device_tokens")
    .select("id, token")
    .eq("profile_id", row.recipient_profile_id)
    .eq("active", true);
  if (tokenError) {
    return await finalizeJob(
      adminClient,
      workerId,
      job,
      job.attempts >= 10 ? "dead" : "failed",
      tokenError.message,
    );
  }

  const { data: previousDeliveries, error: previousDeliveryError } =
    await adminClient
      .from("notification_deliveries")
      .select("device_token_id")
      .eq("outbox_id", job.outbox_id)
      .eq("status", "sent");
  if (previousDeliveryError) {
    console.error("Notification delivery receipt lookup failed", {
      outboxId: job.outbox_id,
      error: previousDeliveryError,
    });
    return await finalizeJob(
      adminClient,
      workerId,
      job,
      job.attempts >= 10 ? "dead" : "failed",
      `DELIVERY_RECEIPT_LOOKUP_FAILED: ${previousDeliveryError.message}`.slice(
        0,
        2000,
      ),
    );
  }
  const alreadySent = new Set(
    (previousDeliveries ?? []).map((delivery) =>
      String(delivery.device_token_id)
    ),
  );
  const pendingTokens = (tokens ?? []).filter((token) =>
    !alreadySent.has(String(token.id))
  );

  if (pendingTokens.length === 0) {
    if ((tokens ?? []).length === 0) {
      const { error: deliveryError } = await adminClient
        .from("notification_deliveries")
        .insert({
          outbox_id: job.outbox_id,
          status: "skipped",
          error_code: "NO_ACTIVE_DEVICE_TOKEN",
          error_message: "The recipient has no active push token.",
        });
      if (deliveryError) {
        throw deliveryDatabaseError(
          job,
          "Unable to record the missing device token.",
          deliveryError,
        );
      }
    }
    return await finalizeJob(adminClient, workerId, job, "sent", null);
  }

  let retryableFailure = false;
  let terminalFailure = false;
  const failureMessages: string[] = [];
  for (const tokenRow of pendingTokens) {
    const result = await sendFirebaseMessage({
      account,
      accessToken,
      token: String(tokenRow.token),
      title: row.title,
      body: row.body,
      data: notificationDeliveryData({
        payload: row.payload,
        notificationId: row.id,
        type: row.type,
        recipientRole: recipient.role!,
      }),
    });
    const { error: deliveryError } = await adminClient
      .from("notification_deliveries")
      .insert({
        outbox_id: job.outbox_id,
        device_token_id: tokenRow.id,
        provider_message_id: result.providerMessageId ?? null,
        status: result.ok ? "sent" : "failed",
        error_code: result.errorCode ?? null,
        error_message: result.errorMessage?.slice(0, 1000) ?? null,
      });
    if (deliveryError) {
      console.error("Notification delivery receipt write failed", {
        outboxId: job.outbox_id,
        deviceTokenId: tokenRow.id,
        providerAccepted: result.ok,
        error: deliveryError,
      });
      const status = deliveryRecordFailureStatus({
        providerAccepted: result.ok,
        retryableProviderFailure: result.retryable,
        attempts: job.attempts,
      });
      const reason = result.ok
        ? "DELIVERY_RECEIPT_MISSING_AFTER_PROVIDER_ACCEPTED"
        : "DELIVERY_RECEIPT_WRITE_FAILED";
      return await finalizeJob(
        adminClient,
        workerId,
        job,
        status,
        `${reason}: ${deliveryError.message}`.slice(0, 2000),
      );
    }

    if (!result.ok) {
      retryableFailure ||= result.retryable;
      terminalFailure ||= !result.retryable && !result.deactivateToken;
      failureMessages.push(
        `${result.errorCode ?? "FCM_ERROR"}: ${
          result.errorMessage ?? "delivery failed"
        }`,
      );
      if (result.deactivateToken) {
        const { error: deactivateError } = await adminClient
          .from("device_tokens")
          .update({ active: false })
          .eq("id", tokenRow.id);
        if (deactivateError) {
          console.error("Notification token deactivation failed", {
            outboxId: job.outbox_id,
            deviceTokenId: tokenRow.id,
            error: deactivateError,
          });
          retryableFailure = true;
          failureMessages.push(
            `TOKEN_DEACTIVATION_FAILED: ${deactivateError.message}`,
          );
        }
      }
    }
  }

  if (retryableFailure) {
    const status = job.attempts >= 10 ? "dead" : "failed";
    return await finalizeJob(
      adminClient,
      workerId,
      job,
      status,
      failureMessages.join(" | ").slice(0, 2000),
    );
  }
  if (terminalFailure) {
    return await finalizeJob(
      adminClient,
      workerId,
      job,
      "dead",
      failureMessages.join(" | ").slice(0, 2000),
    );
  }
  return await finalizeJob(
    adminClient,
    workerId,
    job,
    "sent",
    failureMessages.length ? failureMessages.join(" | ").slice(0, 2000) : null,
  );
}

async function recipientEligibility(
  adminClient: SupabaseClient,
  profileId: string,
): Promise<RecipientEligibility> {
  const { data: profile, error: profileError } = await adminClient
    .from("profiles")
    .select("role, active, must_change_password")
    .eq("id", profileId)
    .maybeSingle();
  if (profileError) {
    throw new HttpError(
      500,
      "RECIPIENT_PROFILE_LOOKUP_FAILED",
      "The notification recipient could not be verified.",
    );
  }
  if (!profile) {
    return {
      role: null,
      blockCode: "RECIPIENT_PROFILE_MISSING",
    };
  }

  let customerStatus: string | null = null;
  let customerArchivedAt: string | null = null;
  if (profile.role === "customer") {
    const { data: customer, error: customerError } = await adminClient
      .from("business_customers")
      .select("account_status, archived_at")
      .eq("profile_id", profileId)
      .maybeSingle();
    if (customerError) {
      throw new HttpError(
        500,
        "RECIPIENT_CUSTOMER_LOOKUP_FAILED",
        "The notification recipient could not be verified.",
      );
    }
    if (!customer) {
      return {
        role: profile.role,
        blockCode: "RECIPIENT_CUSTOMER_MISSING",
      };
    }
    customerStatus = customer.account_status;
    customerArchivedAt = customer.archived_at;
  }

  return {
    role: profile.role,
    blockCode: notificationRecipientBlockCode({
      role: profile.role,
      profileActive: profile.active === true,
      mustChangePassword: profile.must_change_password === true,
      customerStatus,
      customerArchivedAt,
    }),
  };
}

async function finalizeJob(
  adminClient: SupabaseClient,
  workerId: string,
  job: ClaimedJob,
  status: "sent" | "failed" | "dead",
  lastError: string | null,
): Promise<"sent" | "failed" | "dead"> {
  const delayMinutes = Math.min(2 ** Math.max(job.attempts - 1, 0), 60);
  const update = {
    status,
    sent_at: status === "sent" ? new Date().toISOString() : null,
    next_attempt_at: status === "failed"
      ? new Date(Date.now() + delayMinutes * 60 * 1000).toISOString()
      : new Date().toISOString(),
    locked_at: null,
    locked_by: null,
    last_error: lastError?.slice(0, 2000) ?? null,
  };
  const { data: finalized, error } = await adminClient
    .from("notification_outbox")
    .update(update)
    .eq("id", job.outbox_id)
    .eq("locked_by", workerId)
    .select("id")
    .maybeSingle();
  if (error || !finalized) {
    console.error("Notification outbox finalization failed", {
      outboxId: job.outbox_id,
      error,
      lockLost: !finalized,
    });
    throw new HttpError(
      500,
      "OUTBOX_FINALIZE_FAILED",
      "A notification job could not be finalized.",
    );
  }
  return status;
}

function deliveryDatabaseError(
  job: ClaimedJob,
  message: string,
  error: { message: string },
): HttpError {
  console.error("Notification delivery audit write failed", {
    outboxId: job.outbox_id,
    error,
  });
  return new HttpError(
    500,
    "DELIVERY_AUDIT_WRITE_FAILED",
    message,
  );
}

async function authorizeDispatcher(
  req: Request,
  adminClient: SupabaseClient,
): Promise<void> {
  const configuredSecret = validateNotificationDispatchSecret(
    Deno.env.get("NOTIFICATION_DISPATCH_SECRET"),
  );
  const suppliedSecret = req.headers.get("x-dispatch-secret");
  if (
    configuredSecret &&
    suppliedSecret &&
    constantTimeEqual(configuredSecret, suppliedSecret)
  ) {
    return;
  }
  await requireCaller(req, ["admin"], adminClient);
}

async function readLimit(req: Request): Promise<number> {
  const raw = await req.text();
  if (!raw.trim()) return 25;
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    throw new HttpError(400, "INVALID_JSON", "A valid JSON body is required.");
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new HttpError(400, "INVALID_JSON", "A JSON object is required.");
  }
  const value = (body as Record<string, unknown>).limit;
  if (value === undefined) return 25;
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 1 ||
    value > 100
  ) {
    throw new HttpError(
      422,
      "VALIDATION_ERROR",
      "limit must be an integer from 1 to 100.",
      { field: "limit" },
    );
  }
  return value;
}

function constantTimeEqual(expected: string, actual: string): boolean {
  const expectedBytes = new TextEncoder().encode(expected);
  const actualBytes = new TextEncoder().encode(actual);
  if (expectedBytes.length !== actualBytes.length) return false;
  let difference = 0;
  for (let index = 0; index < expectedBytes.length; index++) {
    difference |= expectedBytes[index] ^ actualBytes[index];
  }
  return difference === 0;
}
