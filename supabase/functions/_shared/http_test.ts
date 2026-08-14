import { handlePreflight, HttpError, responseOrigin } from "./http.ts";

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
