import { requireAuditLogId } from "./audit.ts";
import { HttpError } from "./http.ts";

Deno.test("required privileged audit writes return the inserted id", () => {
  const id = requireAuditLogId(
    {
      data: { id: "11111111-1111-4111-8111-111111111111" },
      error: null,
    },
    {
      action: "customer.created",
      entityId: "22222222-2222-4222-8222-222222222222",
    },
  );

  if (id !== "11111111-1111-4111-8111-111111111111") {
    throw new Error("The inserted audit log id was not preserved.");
  }
});

Deno.test("required privileged audit writes fail closed on database errors", () => {
  assertAuditFailure({
    data: null,
    error: { code: "42501", message: "permission denied" },
  });
});

Deno.test("required privileged audit writes fail closed without a returned row", () => {
  assertAuditFailure({ data: null, error: null });
});

function assertAuditFailure(result: {
  data: { id?: unknown } | null;
  error: unknown;
}): void {
  let caught: unknown;
  try {
    requireAuditLogId(result, {
      action: "invite.created",
      entityId: "33333333-3333-4333-8333-333333333333",
    });
  } catch (error) {
    caught = error;
  }

  if (
    !(caught instanceof HttpError) ||
    caught.status !== 500 ||
    caught.code !== "AUDIT_LOG_WRITE_FAILED"
  ) {
    throw new Error("Expected a stable AUDIT_LOG_WRITE_FAILED response.");
  }
}
