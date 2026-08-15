import { HttpError } from "../_shared/http.ts";
import { activationInvitePurpose } from "./contract.ts";

Deno.test("activation invite purpose defaults safely", () => {
  if (
    activationInvitePurpose(undefined) !== "activation" ||
    activationInvitePurpose(null) !== "activation" ||
    activationInvitePurpose("activation") !== "activation"
  ) {
    throw new Error("Activation invite purpose was not normalized safely.");
  }
});

Deno.test("password reset purpose requires the atomic reset endpoint", () => {
  let caught: unknown;
  try {
    activationInvitePurpose("password_reset");
  } catch (error) {
    caught = error;
  }

  if (
    !(caught instanceof HttpError) ||
    caught.status !== 422 ||
    caught.code !== "PASSWORD_RESET_FLOW_REQUIRED"
  ) {
    throw new Error("Expected PASSWORD_RESET_FLOW_REQUIRED.");
  }
});
