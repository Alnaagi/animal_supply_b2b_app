import { HttpError } from "./http.ts";

interface AuditWriteResult {
  data: { id?: unknown } | null;
  error: unknown;
}

interface AuditWriteContext {
  action: string;
  entityId: string;
}

export function requireAuditLogId(
  result: AuditWriteResult,
  context: AuditWriteContext,
): string {
  const id = typeof result.data?.id === "string" ? result.data.id.trim() : "";
  if (result.error || !id) {
    console.error("Required privileged audit log write failed", {
      action: context.action,
      entityId: context.entityId,
      error: result.error ?? "The insert returned no audit log id.",
    });
    throw new HttpError(
      500,
      "AUDIT_LOG_WRITE_FAILED",
      "The privileged action could not be recorded safely.",
    );
  }
  return id;
}
