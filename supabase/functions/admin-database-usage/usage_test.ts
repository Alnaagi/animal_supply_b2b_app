import { HttpError } from "../_shared/http.ts";
import {
  DEFAULT_DATABASE_DISK_QUOTA_BYTES,
  parseDatabaseQuotaBytes,
  parseUsedBytes,
  usagePercent,
} from "./usage.ts";

Deno.test("default quota is the documented 500 MB database plan", () => {
  if (
    parseDatabaseQuotaBytes(undefined) !== DEFAULT_DATABASE_DISK_QUOTA_BYTES ||
    parseDatabaseQuotaBytes("  ") !== DEFAULT_DATABASE_DISK_QUOTA_BYTES ||
    DEFAULT_DATABASE_DISK_QUOTA_BYTES !== 500 * 1024 * 1024
  ) {
    throw new Error("The default database quota was not 500 MiB.");
  }
});

Deno.test("configured quota must be a positive byte count", () => {
  if (parseDatabaseQuotaBytes("8589934592") !== 8589934592) {
    throw new Error("A valid configured quota was rejected.");
  }

  for (const value of ["0", "-1", "abc", "Infinity"]) {
    let error: unknown;
    try {
      parseDatabaseQuotaBytes(value);
    } catch (caught) {
      error = caught;
    }
    if (
      !(error instanceof HttpError) ||
      error.code !== "DATABASE_QUOTA_INVALID"
    ) {
      throw new Error(`Expected DATABASE_QUOTA_INVALID for ${value}`);
    }
  }
});

Deno.test("used bytes and percent come from live size versus quota", () => {
  if (parseUsedBytes({ used_bytes: 134217728 }) !== 134217728) {
    throw new Error("Numeric used_bytes was not accepted.");
  }
  if (parseUsedBytes({ used_bytes: "1024" }) !== 1024) {
    throw new Error("String used_bytes was not accepted.");
  }
  if (usagePercent(250 * 1024 * 1024, 500 * 1024 * 1024) !== 50) {
    throw new Error("Half-full usage was not 50 percent.");
  }
  if (usagePercent(0, 500 * 1024 * 1024) !== 0) {
    throw new Error("Empty usage was not 0 percent.");
  }
  if (usagePercent(900 * 1024 * 1024, 500 * 1024 * 1024) !== 100) {
    throw new Error("Over-quota usage was not clamped to 100 percent.");
  }
});
