import { HttpError } from "../_shared/http.ts";
import { parseOrderPricingBody } from "./pricing.ts";

const orderId = "11111111-1111-4111-8111-111111111111";
const itemId = "22222222-2222-4222-8222-222222222222";

Deno.test("parses staff pricing updates without trusting a client total", () => {
  const input = parseOrderPricingBody({
    order_id: orderId,
    delivery_fee: 7.5,
    discount_amount: 2,
    items: [{ id: itemId, unit_price: 12.25 }],
  });

  if (
    input.orderId !== orderId ||
    input.deliveryFee !== 7.5 ||
    input.discountAmount !== 2 ||
    input.items.length !== 1 ||
    input.items[0].id !== itemId ||
    input.items[0].productId !== null ||
    input.items[0].quantity !== null ||
    input.items[0].unitPrice !== 12.25 ||
    input.adminNote !== null ||
    input.expectedUpdatedAt !== null
  ) {
    throw new Error("Pricing body was not parsed.");
  }
});

Deno.test("parses complete admin order edits and note text", () => {
  const input = parseOrderPricingBody({
    order_id: orderId,
    delivery_fee: 7.5,
    discount_amount: 2,
    admin_note: "تم تعديل الكمية",
    items: [{
      id: itemId,
      product_id: "33333333-3333-4333-8333-333333333333",
      quantity: 4,
      unit_price: 12.25,
    }],
  });

  if (
    input.items[0].productId !==
      "33333333-3333-4333-8333-333333333333" ||
    input.items[0].quantity !== 4 ||
    input.adminNote !== "تم تعديل الكمية"
  ) {
    throw new Error("Complete admin order edit was not parsed.");
  }
});

Deno.test("rejects negative money and extra decimals", () => {
  for (const body of [
    {
      order_id: orderId,
      delivery_fee: -1,
      discount_amount: 0,
      items: [{ id: itemId, unit_price: 1 }],
    },
    {
      order_id: orderId,
      delivery_fee: 1.001,
      discount_amount: 0,
      items: [{ id: itemId, unit_price: 1 }],
    },
  ]) {
    let error: unknown;
    try {
      parseOrderPricingBody(body);
    } catch (caught) {
      error = caught;
    }
    if (
      !(error instanceof HttpError) ||
      error.code !== "ORDER_PRICING_INVALID"
    ) {
      throw new Error(`Expected ORDER_PRICING_INVALID for ${JSON.stringify(body)}`);
    }
  }
});
