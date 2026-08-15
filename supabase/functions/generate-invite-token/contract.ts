import { HttpError } from "../_shared/http.ts";

export function activationInvitePurpose(
  requestedPurpose: string | null | undefined,
): "activation" {
  const purpose = requestedPurpose || "activation";
  if (purpose !== "activation") {
    throw new HttpError(
      422,
      "PASSWORD_RESET_FLOW_REQUIRED",
      "Password resets must use the atomic admin reset flow.",
      { field: "purpose" },
    );
  }
  return "activation";
}
