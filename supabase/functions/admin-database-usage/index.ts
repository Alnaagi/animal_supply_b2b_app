import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { requireCaller, serviceClient } from "../_shared/auth.ts";
import { databaseError } from "../_shared/database.ts";
import {
  errorResponse,
  handlePreflight,
  requirePost,
  successResponse,
} from "../_shared/http.ts";
import { consumeRateLimit } from "../_shared/security.ts";
import {
  parseDatabaseQuotaBytes,
  parseUsedBytes,
  usagePercent,
} from "./usage.ts";

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
      `admin-database-usage:${caller.id}`,
      60,
      60,
    );

    const quotaBytes = parseDatabaseQuotaBytes(
      Deno.env.get("DATABASE_DISK_QUOTA_BYTES"),
    );
    const { data, error } = await adminClient.rpc("admin_database_usage");
    if (error) {
      throw databaseError(
        error,
        "DATABASE_USAGE_UNAVAILABLE",
        "Database usage could not be read.",
      );
    }

    const usedBytes = parseUsedBytes(data);
    return successResponse(req, {
      used_bytes: usedBytes,
      quota_bytes: quotaBytes,
      percent: usagePercent(usedBytes, quotaBytes),
      source: "postgres",
    });
  } catch (error) {
    return errorResponse(req, error);
  }
});
