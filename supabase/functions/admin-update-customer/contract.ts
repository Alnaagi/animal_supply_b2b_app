import {
  HttpError,
  optionalStringField,
  optionalTimestamptzField,
  stringField,
  uuidField,
} from "../_shared/http.ts";

const allowedFields = new Set([
  "customer_id",
  "business_name",
  "contact_person",
  "phone",
  "city",
  "area",
  "address",
  "discount_percent",
  // Transitional compatibility for installed clients that still send the
  // retired pricing-group field. It is validated and ignored.
  "price_group_id",
  "account_status",
  "credit_limit",
  "outstanding_balance",
  "phone_is_whatsapp",
  "expected_updated_at",
]);

const requiredFields = [
  "customer_id",
  "business_name",
  "contact_person",
  "phone",
  "city",
  "area",
  "address",
  "account_status",
  "credit_limit",
  "outstanding_balance",
];
const maximumAccountAmount = 9_999_999_999.99;

export interface CustomerUpdateInput {
  customerId: string;
  businessName: string;
  contactPerson: string | null;
  phone: string | null;
  city: string | null;
  area: string | null;
  address: string | null;
  discountPercent: number | null;
  accountStatus: "active" | "suspended" | "archived";
  creditLimit: number;
  outstandingBalance: number;
  phoneIsWhatsapp: boolean;
  expectedUpdatedAt: string | null;
}

export function parseCustomerUpdateBody(
  body: Record<string, unknown>,
): CustomerUpdateInput {
  for (const key of Object.keys(body)) {
    if (!allowedFields.has(key)) {
      throw new HttpError(
        422,
        "VALIDATION_ERROR",
        `${key} is not accepted by this endpoint.`,
        { field: key },
      );
    }
  }
  for (const key of requiredFields) {
    if (!Object.prototype.hasOwnProperty.call(body, key)) {
      throw new HttpError(
        422,
        "VALIDATION_ERROR",
        `${key} is required.`,
        { field: key },
      );
    }
  }

  const accountStatus = stringField(body, "account_status", {
    required: true,
    maxLength: 16,
  });
  if (!["active", "suspended", "archived"].includes(accountStatus)) {
    throw new HttpError(
      422,
      "VALIDATION_ERROR",
      "account_status must be active, suspended, or archived.",
      { field: "account_status" },
    );
  }

  const phone = optionalStringField(body, "phone", 32);
  if (phone) {
    const digits = phone.replace(/\D/g, "");
    if (
      !/^\+?[0-9 ()-]+$/.test(phone) ||
      digits.length < 7 ||
      digits.length > 15
    ) {
      throw new HttpError(
        422,
        "VALIDATION_ERROR",
        "phone must contain a valid international or local phone number.",
        { field: "phone" },
      );
    }
  }
  if (Object.prototype.hasOwnProperty.call(body, "price_group_id")) {
    uuidField(body, "price_group_id", false);
  }

  return {
    customerId: uuidField(body, "customer_id")!,
    businessName: stringField(body, "business_name", {
      required: true,
      maxLength: 160,
    }),
    contactPerson: optionalStringField(body, "contact_person", 160),
    phone,
    city: optionalStringField(body, "city", 100),
    area: optionalStringField(body, "area", 120),
    address: optionalStringField(body, "address", 500),
    discountPercent: optionalDiscountPercentField(body, "discount_percent"),
    accountStatus: accountStatus as CustomerUpdateInput["accountStatus"],
    creditLimit: accountAmountField(body, "credit_limit"),
    outstandingBalance: accountAmountField(body, "outstanding_balance"),
    phoneIsWhatsapp: optionalBooleanField(body, "phone_is_whatsapp", true),
    expectedUpdatedAt: optionalTimestamptzField(body, "expected_updated_at"),
  };
}

function optionalBooleanField(
  body: Record<string, unknown>,
  key: string,
  defaultValue: boolean,
): boolean {
  if (!Object.prototype.hasOwnProperty.call(body, key)) return defaultValue;
  const value = body[key];
  if (typeof value !== "boolean") {
    throw new HttpError(
      422,
      "VALIDATION_ERROR",
      `${key} must be a boolean.`,
      { field: key },
    );
  }
  return value;
}

function optionalDiscountPercentField(
  body: Record<string, unknown>,
  key: string,
): number | null {
  if (!Object.prototype.hasOwnProperty.call(body, key)) return null;
  const raw = body[key];
  if (typeof raw !== "number" || !Number.isFinite(raw)) {
    throw new HttpError(
      422,
      "VALIDATION_ERROR",
      `${key} must be a finite number.`,
      { field: key },
    );
  }
  const normalized = Math.round(raw * 100) / 100;
  if (
    Math.abs(normalized - raw) > 1e-9 ||
    normalized < 0 ||
    normalized >= 100
  ) {
    throw new HttpError(
      422,
      "VALIDATION_ERROR",
      `${key} must be between 0 and 99.99 with at most two decimals.`,
      { field: key },
    );
  }
  return normalized;
}

function accountAmountField(
  body: Record<string, unknown>,
  key: string,
): number {
  const raw = body[key];
  if (typeof raw !== "number" || !Number.isFinite(raw)) {
    throw new HttpError(
      422,
      "VALIDATION_ERROR",
      `${key} must be a finite number.`,
      { field: key },
    );
  }
  const normalized = Math.round(raw * 100) / 100;
  if (
    Math.abs(normalized - raw) > 1e-9 ||
    normalized < 0 ||
    normalized > maximumAccountAmount
  ) {
    throw new HttpError(
      422,
      "VALIDATION_ERROR",
      `${key} must be a non-negative amount with at most two decimals.`,
      { field: key },
    );
  }
  return normalized;
}
