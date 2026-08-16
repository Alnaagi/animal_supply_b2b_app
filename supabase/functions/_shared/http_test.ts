import {
  handlePreflight,
  HttpError,
  optionalTimestamptzField,
  resolveAllowedOrigins,
  responseOrigin,
} from "./http.ts";

Deno.test("browser origins must match an exact configured origin", () => {
  const configured = ["https://shop.client.ly"];
  const accepted = responseOrigin(
    new Request("https://edge.example.test", {
      headers: { Origin: configured[0] },
    }),
    configured,
  );
  if (accepted !== configured[0]) {
    throw new Error("The configured production origin was not accepted.");
  }

  for (
    const origin of [
      "https://evil.example",
      "http://localhost:8765",
      "http://127.0.0.1:8765",
    ]
  ) {
    let error: unknown;
    try {
      responseOrigin(
        new Request("https://edge.example.test", {
          headers: { Origin: origin },
        }),
        configured,
      );
    } catch (caught) {
      error = caught;
    }
    if (
      !(error instanceof HttpError) ||
      error.code !== "ORIGIN_NOT_ALLOWED"
    ) {
      throw new Error(`Expected ${origin} to be rejected.`);
    }
  }
});

Deno.test("APP_PUBLIC_ORIGIN is accepted when ALLOWED_ORIGINS is empty", () => {
  const origins = resolveAllowedOrigins(
    "",
    "https://animal-supply-b2b.alnaagi-ai.workers.dev/",
  );
  if (
    origins.length !== 1 ||
    origins[0] !== "https://animal-supply-b2b.alnaagi-ai.workers.dev"
  ) {
    throw new Error("APP_PUBLIC_ORIGIN was not added to the allowlist.");
  }
  const accepted = responseOrigin(
    new Request("https://edge.example.test", {
      headers: { Origin: origins[0] },
    }),
    origins,
  );
  if (accepted !== origins[0]) {
    throw new Error("The public app origin was not accepted for campaigns.");
  }
});

Deno.test("native requests without Origin remain supported", () => {
  const origin = responseOrigin(
    new Request("https://edge.example.test"),
    ["https://shop.client.ly"],
  );
  if (origin !== "*") {
    throw new Error("Origin-less native requests must remain supported.");
  }
});

Deno.test("actual POST origins are rejected before handler work begins", () => {
  let error: unknown;
  try {
    handlePreflight(
      new Request("https://edge.example.test", {
        method: "POST",
        headers: { Origin: "https://evil.example" },
      }),
      ["https://shop.client.ly"],
    );
  } catch (caught) {
    error = caught;
  }

  if (
    !(error instanceof HttpError) ||
    error.code !== "ORIGIN_NOT_ALLOWED"
  ) {
    throw new Error("The POST origin was not rejected at request entry.");
  }
});

Deno.test("optional timestamps accept ISO-8601 or omit the field", () => {
  const parsed = optionalTimestamptzField(
    { expected_updated_at: "2026-08-16T09:15:00.000Z" },
    "expected_updated_at",
  );
  if (parsed !== "2026-08-16T09:15:00.000Z") {
    throw new Error(`Unexpected timestamp ${parsed}`);
  }
  if (optionalTimestamptzField({}, "expected_updated_at") !== null) {
    throw new Error("Missing timestamp should be null.");
  }
});
