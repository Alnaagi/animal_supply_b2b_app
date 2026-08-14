import { HttpError } from "../_shared/http.ts";
import { parseCustomerUpdateBody } from "./contract.ts";

const validBody = {
  customer_id: "11111111-1111-4111-8111-111111111111",
  business_name: "شركة طرابلس للحيوانات",
  contact_person: "محمد",
  phone: "+218 91 000 0001",
  city: "طرابلس",
  area: "حي الأندلس",
  address: "شارع السوق",
  discount_percent: 12.5,
  account_status: "active",
  credit_limit: 2500.5,
  outstanding_balance: 420,
};

Deno.test("customer update contract normalizes a complete valid request", () => {
  const parsed = parseCustomerUpdateBody(validBody);
  if (
    parsed.customerId !== validBody.customer_id ||
    parsed.businessName !== validBody.business_name ||
    parsed.discountPercent !== validBody.discount_percent ||
    parsed.accountStatus !== "active" ||
    parsed.creditLimit !== 2500.5
  ) {
    throw new Error("The customer update request was not parsed correctly.");
  }
});

Deno.test("customer update contract rejects privilege or linkage fields", () => {
  assertValidationError({
    ...validBody,
    profile_id: "22222222-2222-4222-8222-222222222222",
  });
  assertValidationError({ ...validBody, role: "admin" });
  assertValidationError({ ...validBody, username: "renamed-client" });
});

Deno.test("customer update contract rejects incomplete or invalid account data", () => {
  const incomplete = { ...validBody } as Record<string, unknown>;
  delete incomplete.outstanding_balance;
  assertValidationError(incomplete);
  assertValidationError({ ...validBody, account_status: "super-admin" });
  assertValidationError({ ...validBody, credit_limit: -1 });
  assertValidationError({ ...validBody, outstanding_balance: 10.123 });
  assertValidationError({ ...validBody, discount_percent: -0.01 });
  assertValidationError({ ...validBody, discount_percent: 100 });
  assertValidationError({ ...validBody, discount_percent: 10.123 });
  assertValidationError({ ...validBody, phone: "not-a-phone" });
});

Deno.test("customer update accepts a legacy price group payload safely", () => {
  const legacyBody = { ...validBody } as Record<string, unknown>;
  delete legacyBody.discount_percent;
  legacyBody.price_group_id = "33333333-3333-4333-8333-333333333333";

  const parsed = parseCustomerUpdateBody(legacyBody);
  if (parsed.discountPercent !== null) {
    throw new Error(
      "Legacy customer updates must preserve the saved discount.",
    );
  }
});

function assertValidationError(body: Record<string, unknown>): void {
  let caught: unknown;
  try {
    parseCustomerUpdateBody(body);
  } catch (error) {
    caught = error;
  }
  if (!(caught instanceof HttpError) || caught.status !== 422) {
    throw new Error("Expected a 422 customer update validation error.");
  }
}
