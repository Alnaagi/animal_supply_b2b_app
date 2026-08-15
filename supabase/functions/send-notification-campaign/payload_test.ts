import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import { HttpError } from "../_shared/http.ts";
import { validatedCampaignPayload } from "./payload.ts";

Deno.test("campaign payload trims a valid product id", () => {
  assertEquals(
    validatedCampaignPayload({
      product_id: " 23f4f9f3-7fc8-4aaa-8aba-12e24cac0d67 ",
    }),
    { product_id: "23f4f9f3-7fc8-4aaa-8aba-12e24cac0d67" },
  );
});

Deno.test("campaign payload rejects a malformed product id", () => {
  const error = assertThrows(
    () => validatedCampaignPayload({ product_id: "not-a-product" }),
    HttpError,
  );
  assertEquals(error.status, 422);
  assertEquals(error.code, "INVALID_CAMPAIGN_PRODUCT");
});
