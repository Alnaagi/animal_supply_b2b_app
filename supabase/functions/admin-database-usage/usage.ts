import { HttpError } from "../_shared/http.ts";

export const DEFAULT_DATABASE_DISK_QUOTA_BYTES = 500 * 1024 * 1024;

export function parseDatabaseQuotaBytes(raw: string | undefined): number {
  if (raw == null || raw.trim() === "") {
    return DEFAULT_DATABASE_DISK_QUOTA_BYTES;
  }

  const parsed = Number(raw.trim());
  if (
    !Number.isFinite(parsed) ||
    parsed < 1 ||
    parsed > Number.MAX_SAFE_INTEGER
  ) {
    throw new HttpError(
      500,
      "DATABASE_QUOTA_INVALID",
      "DATABASE_DISK_QUOTA_BYTES must be a positive byte count.",
    );
  }
  return Math.floor(parsed);
}

export function parseUsedBytes(data: unknown): number {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpError(
      500,
      "DATABASE_USAGE_UNAVAILABLE",
      "Database usage could not be read.",
    );
  }

  const raw = (data as Record<string, unknown>).used_bytes;
  const used = typeof raw === "number"
    ? raw
    : typeof raw === "string"
    ? Number(raw)
    : NaN;
  if (!Number.isFinite(used) || used < 0) {
    throw new HttpError(
      500,
      "DATABASE_USAGE_UNAVAILABLE",
      "Database usage could not be read.",
    );
  }
  return Math.floor(used);
}

export function usagePercent(usedBytes: number, quotaBytes: number): number {
  const used = Number.isFinite(usedBytes) && usedBytes > 0 ? usedBytes : 0;
  if (!Number.isFinite(quotaBytes) || quotaBytes < 1) {
    throw new HttpError(
      500,
      "DATABASE_QUOTA_INVALID",
      "DATABASE_DISK_QUOTA_BYTES must be a positive byte count.",
    );
  }
  return Math.min(100, Math.max(0, Math.round((used / quotaBytes) * 100)));
}
