import { HttpError } from "./http.ts";

interface PostgrestErrorLike {
  code?: string;
  message?: string;
  details?: string | null;
  hint?: string | null;
}

const statusByCode: Record<string, number> = {
  AUTH_REQUIRED: 401,
  PROFILE_REQUIRED: 403,
  ROLE_INVALID: 403,
  ADMIN_AUTH_REQUIRED: 403,
  STAFF_AUTH_REQUIRED: 403,
  CUSTOMER_ACCOUNT_NOT_FOUND: 403,
  CUSTOMER_ACCOUNT_REQUIRED: 403,
  CUSTOMER_ACCOUNT_INACTIVE: 403,
  PROFILE_INACTIVE: 403,
  CUSTOMER_NOT_FOUND: 404,
  CUSTOMER_TARGET_REQUIRED: 403,
  CUSTOMER_UPDATE_INVALID: 422,
  CUSTOMER_UPDATE_CONFLICT: 409,
  ORDER_NOT_FOUND: 404,
  INVITE_CUSTOMER_NOT_FOUND: 404,
  INVALID_INVITE_TOKEN: 404,
  INVITE_REVOKED: 410,
  INVITE_ALREADY_USED: 410,
  INVITE_EXPIRED: 410,
  INVITE_CLIENT_CODE_MISMATCH: 422,
  INVITE_USER_MISMATCH: 403,
  INVITE_REDEMPTION_REQUIRED: 403,
  CLIENT_REQUEST_ID_REQUIRED: 422,
  IDEMPOTENCY_CONFLICT: 409,
  ORDER_ITEMS_REQUIRED: 422,
  TOO_MANY_ORDER_ITEMS: 422,
  INVALID_ORDER_ITEM: 422,
  PRODUCT_UNAVAILABLE: 422,
  MINIMUM_QUANTITY_NOT_MET: 422,
  INSUFFICIENT_STOCK: 409,
  INSUFFICIENT_STOCK_AT_DELIVERY: 409,
  ORDER_RESERVATION_INCOMPLETE: 409,
  STOCK_BELOW_ACTIVE_RESERVATIONS: 409,
  PRODUCT_PRICE_UNAVAILABLE: 422,
  MINIMUM_ORDER_AMOUNT_NOT_MET: 422,
  ORDER_TEXT_TOO_LONG: 422,
  ORDER_NOTE_TOO_LONG: 422,
  INVALID_ORDER_STATUS: 422,
  INVALID_STATUS_TRANSITION: 409,
  CAMPAIGN_ID_REQUIRED: 422,
  CAMPAIGN_ID_CONFLICT: 409,
  INVALID_CAMPAIGN_CONTENT: 422,
  INVALID_NOTIFICATION_TYPE: 422,
  INVALID_NOTIFICATION_PAYLOAD: 422,
  INVALID_CAMPAIGN_AUDIENCE: 422,
  INVALID_CAMPAIGN_ROLE: 422,
  NO_CAMPAIGN_RECIPIENTS: 422,
  INVALID_DEVICE_TOKEN: 422,
};

export function databaseError(
  error: PostgrestErrorLike,
  fallbackCode: string,
  fallbackMessage: string,
): HttpError {
  const code = error.message && statusByCode[error.message]
    ? error.message
    : fallbackCode;
  const status = statusByCode[code] ??
    (error.code === "23505" ? 409 : 500);

  if (status >= 500) {
    console.error("Database operation failed", error);
  }

  return new HttpError(
    status,
    code,
    status >= 500 ? fallbackMessage : humanMessage(code),
    error.details ? parseDetails(error.details) : undefined,
  );
}

function parseDetails(details: string): unknown {
  try {
    return JSON.parse(details);
  } catch {
    return details;
  }
}

function humanMessage(code: string): string {
  const messages: Record<string, string> = {
    AUTH_REQUIRED: "Authentication is required.",
    PROFILE_REQUIRED: "No app profile exists for this account.",
    ROLE_INVALID: "The account role is invalid.",
    ADMIN_AUTH_REQUIRED: "An active admin account is required.",
    STAFF_AUTH_REQUIRED: "An active staff or admin account is required.",
    CUSTOMER_ACCOUNT_NOT_FOUND: "The customer account could not be verified.",
    CUSTOMER_ACCOUNT_REQUIRED: "The customer account could not be verified.",
    CUSTOMER_ACCOUNT_INACTIVE: "The customer account cannot place orders.",
    PROFILE_INACTIVE: "This account is inactive.",
    CUSTOMER_NOT_FOUND: "The customer account was not found.",
    CUSTOMER_TARGET_REQUIRED: "Only a linked customer account can be updated.",
    CUSTOMER_UPDATE_INVALID: "The customer update data is invalid.",
    CUSTOMER_UPDATE_CONFLICT: "The customer account changed during the update.",
    ORDER_NOT_FOUND: "The order was not found.",
    INVALID_INVITE_TOKEN: "The invite link is invalid.",
    INVITE_CUSTOMER_NOT_FOUND: "The invited customer account was not found.",
    INVITE_REVOKED: "This invite link was revoked.",
    INVITE_ALREADY_USED: "This invite link was already used.",
    INVITE_EXPIRED: "This invite link has expired.",
    INVITE_CLIENT_CODE_MISMATCH: "The invite does not match the client code.",
    INVITE_USER_MISMATCH: "The invite belongs to another account.",
    INVITE_REDEMPTION_REQUIRED:
      "The current invite link must be opened before changing the temporary password.",
    CLIENT_REQUEST_ID_REQUIRED: "A request identifier is required.",
    IDEMPOTENCY_CONFLICT:
      "This request identifier was already used for different order data.",
    ORDER_ITEMS_REQUIRED: "At least one order item is required.",
    TOO_MANY_ORDER_ITEMS: "The order contains too many different products.",
    INVALID_ORDER_ITEM: "One or more order items are invalid.",
    PRODUCT_UNAVAILABLE: "One or more products are unavailable.",
    MINIMUM_QUANTITY_NOT_MET: "A product minimum quantity was not met.",
    INSUFFICIENT_STOCK: "There is not enough stock for one or more products.",
    INSUFFICIENT_STOCK_AT_DELIVERY:
      "Stock changed and the order cannot be marked delivered.",
    ORDER_RESERVATION_INCOMPLETE:
      "The order inventory reservation is incomplete and must be repaired before fulfillment.",
    STOCK_BELOW_ACTIVE_RESERVATIONS:
      "Physical stock cannot be reduced below quantities reserved by active orders.",
    PRODUCT_PRICE_UNAVAILABLE: "A valid product price is unavailable.",
    MINIMUM_ORDER_AMOUNT_NOT_MET: "The minimum order amount was not met.",
    ORDER_TEXT_TOO_LONG: "An order text field is too long.",
    ORDER_NOTE_TOO_LONG: "The order note is too long.",
    INVALID_ORDER_STATUS: "The requested order status is invalid.",
    INVALID_STATUS_TRANSITION: "This order status change is not allowed.",
    CAMPAIGN_ID_REQUIRED: "A campaign identifier is required.",
    CAMPAIGN_ID_CONFLICT:
      "This campaign identifier was already used for different content.",
    INVALID_CAMPAIGN_CONTENT: "The campaign title or body is invalid.",
    INVALID_NOTIFICATION_TYPE: "The notification type is invalid.",
    INVALID_NOTIFICATION_PAYLOAD: "The notification payload must be an object.",
    INVALID_CAMPAIGN_AUDIENCE: "The campaign audience is invalid.",
    INVALID_CAMPAIGN_ROLE: "The campaign role is invalid.",
    NO_CAMPAIGN_RECIPIENTS: "No active recipients match this audience.",
    INVALID_DEVICE_TOKEN: "The device token registration is invalid.",
  };
  return messages[code] ?? "The request could not be completed.";
}
