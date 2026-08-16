import { HttpError, optionalTimestamptzField, uuidField } from "../_shared/http.ts";

export type OrderPricingItemInput = {
  id: string;
  unitPrice: number;
};

export type OrderPricingInput = {
  orderId: string;
  items: OrderPricingItemInput[];
  deliveryFee: number;
  discountAmount: number;
  expectedUpdatedAt: string | null;
};

const moneyKeys = ["unit_price", "unitPrice"] as const;

export function parseOrderPricingBody(
  body: Record<string, unknown>,
): OrderPricingInput {
  const orderId = uuidField(body, "order_id");
  if (!orderId) {
    throw new HttpError(422, "VALIDATION_ERROR", "order_id is required.", {
      field: "order_id",
    });
  }

  const rawItems = body.items;
  if (!Array.isArray(rawItems) || rawItems.length === 0) {
    throw new HttpError(
      422,
      "ORDER_ITEMS_REQUIRED",
      "Every current order line must be included.",
      { field: "items" },
    );
  }
  if (rawItems.length > 200) {
    throw new HttpError(
      422,
      "TOO_MANY_ORDER_ITEMS",
      "The order contains too many different products.",
    );
  }

  const items = rawItems.map((raw, index) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw new HttpError(
        422,
        "INVALID_ORDER_ITEM",
        "One or more order items are invalid.",
        { index },
      );
    }
    const row = raw as Record<string, unknown>;
    const id = uuidField(row, "id", false) ?? uuidField(row, "item_id", false);
    if (!id) {
      throw new HttpError(
        422,
        "INVALID_ORDER_ITEM",
        "One or more order items are invalid.",
        { index, field: "id" },
      );
    }
    return {
      id,
      unitPrice: moneyField(row, moneyKeys, { index }),
    };
  });

  const ids = new Set(items.map((item) => item.id));
  if (ids.size !== items.length) {
    throw new HttpError(
      422,
      "ORDER_ITEM_MISMATCH",
      "Order line identifiers must be unique.",
    );
  }

  return {
    orderId,
    items,
    deliveryFee: moneyField(body, ["delivery_fee", "deliveryFee"]),
    discountAmount: moneyField(body, ["discount_amount", "discountAmount"]),
    expectedUpdatedAt: optionalTimestamptzField(body, "expected_updated_at"),
  };
}

function moneyField(
  body: Record<string, unknown>,
  keys: readonly string[],
  details: Record<string, unknown> = {},
): number {
  let raw: unknown;
  for (const key of keys) {
    if (body[key] !== undefined) {
      raw = body[key];
      break;
    }
  }
  const value = typeof raw === "number"
    ? raw
    : typeof raw === "string" && raw.trim() !== ""
    ? Number(raw)
    : NaN;
  if (!Number.isFinite(value) || value < 0 || value > 1_000_000) {
    throw new HttpError(
      422,
      "ORDER_PRICING_INVALID",
      "Order money values must be between 0 and 1,000,000.",
      details,
    );
  }
  const rounded = Math.round(value * 100) / 100;
  if (Math.abs(rounded - value) > 0.0000001) {
    throw new HttpError(
      422,
      "ORDER_PRICING_INVALID",
      "Order money values may have at most two decimals.",
      details,
    );
  }
  return rounded;
}
