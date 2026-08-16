import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireCaller, serviceClient } from "../_shared/auth.ts";
import { databaseError } from "../_shared/database.ts";
import {
  errorResponse,
  handlePreflight,
  HttpError,
  readJsonObject,
  requirePost,
  successResponse,
} from "../_shared/http.ts";
import { consumeRateLimit } from "../_shared/security.ts";
import {
  customerUserIdsFromResetPayload,
  requireResetConfirmPhrase,
} from "./reset.ts";

serve(async (req) => {
  try {
    const preflight = handlePreflight(req);
    if (preflight) return preflight;
    requirePost(req);

    const adminClient = serviceClient();
    const caller = await requireCaller(req, ["admin"], adminClient);
    await consumeRateLimit(
      adminClient,
      req,
      `admin-reset-application-data:${caller.id}`,
      3,
      60 * 60 * 24,
    );

    const body = await readJsonObject(req);
    requireResetConfirmPhrase(body.confirm_phrase);

    const { data, error } = await adminClient.rpc(
      "admin_reset_application_data",
      { p_actor_id: caller.id },
    );
    if (error) {
      throw databaseError(
        error,
        "APPLICATION_RESET_FAILED",
        "Application data could not be reset.",
      );
    }

    const payload = (data ?? {}) as Record<string, unknown>;
    if (payload.reset !== true) {
      throw new HttpError(
        500,
        "APPLICATION_RESET_FAILED",
        "Application data could not be reset.",
      );
    }

    const customerIds = customerUserIdsFromResetPayload(payload, caller.id);
    const authDeletionFailures: string[] = [];
    let customerAuthUsersDeleted = 0;
    for (const userId of customerIds) {
      const result = await adminClient.auth.admin.deleteUser(userId);
      if (result.error) {
        console.error("Customer Auth delete after reset failed", userId, result.error);
        authDeletionFailures.push(userId);
        continue;
      }
      customerAuthUsersDeleted += 1;
    }

    let storageEmptied = false;
    const storageResult = await adminClient.storage.emptyBucket("product-images");
    if (storageResult.error) {
      console.error("Product-image bucket empty after reset failed", storageResult.error);
    } else {
      storageEmptied = true;
    }

    return successResponse(req, {
      reset: true,
      preserved_admin_id: caller.id,
      truncated_tables: payload.truncated_tables ?? [],
      preserved_tables: payload.preserved_tables ?? [],
      customer_profiles_deleted: payload.customer_profiles_deleted ?? 0,
      customer_auth_users_deleted: customerAuthUsersDeleted,
      customer_auth_deletion_failures: authDeletionFailures,
      storage_emptied: storageEmptied,
      storage_objects_deleted: payload.storage_objects_deleted ?? 0,
    });
  } catch (error) {
    return errorResponse(req, error);
  }
});
