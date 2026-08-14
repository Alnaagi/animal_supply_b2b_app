import { databaseError } from "./database.ts";

Deno.test("order idempotency conflicts remain a stable HTTP 409", () => {
  const error = databaseError(
    {
      code: "P0001",
      message: "IDEMPOTENCY_CONFLICT",
      details: "11111111-1111-4111-8111-111111111111",
    },
    "ORDER_CREATE_FAILED",
    "The order could not be created.",
  );

  if (
    error.status !== 409 ||
    error.code !== "IDEMPOTENCY_CONFLICT" ||
    error.details !== "11111111-1111-4111-8111-111111111111"
  ) {
    throw new Error("IDEMPOTENCY_CONFLICT was not preserved as HTTP 409.");
  }
});
