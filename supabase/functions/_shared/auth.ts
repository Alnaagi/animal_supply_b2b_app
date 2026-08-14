import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";

import { HttpError } from "./http.ts";

export type AppRole = "admin" | "staff" | "customer";

export interface Caller {
  id: string;
  username: string | null;
  fullName: string | null;
  phone: string | null;
  role: AppRole;
  active: boolean;
  mustChangePassword: boolean;
  customer: {
    id: string;
    accountStatus: string;
    businessName: string;
  } | null;
}

export interface CallerAuthorizationOptions {
  allowPasswordChangeRequired?: boolean;
}

export function serviceClient(): SupabaseClient {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRole) {
    throw new HttpError(
      500,
      "SERVER_CONFIGURATION_ERROR",
      "Supabase server credentials are not configured.",
    );
  }

  return createClient(supabaseUrl, serviceRole, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

export function bearerToken(req: Request): string {
  const authorization = req.headers.get("Authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match?.[1]) {
    throw new HttpError(
      401,
      "AUTH_REQUIRED",
      "A valid bearer token is required.",
    );
  }
  return match[1].trim();
}

export async function optionalAuthenticatedUserId(
  req: Request,
  adminClient = serviceClient(),
): Promise<string | null> {
  const authorization = req.headers.get("Authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match?.[1]) return null;

  const { data, error } = await adminClient.auth.getUser(match[1].trim());
  if (error || !data.user) {
    throw new HttpError(401, "INVALID_SESSION", "The session is invalid.");
  }
  return data.user.id;
}

export async function requireCaller(
  req: Request,
  allowedRoles?: AppRole[],
  adminClient = serviceClient(),
  options: CallerAuthorizationOptions = {},
): Promise<Caller> {
  const token = bearerToken(req);
  const { data: authData, error: authError } = await adminClient.auth.getUser(
    token,
  );

  if (authError || !authData.user) {
    throw new HttpError(401, "INVALID_SESSION", "The session is invalid.");
  }

  const { data: profile, error: profileError } = await adminClient
    .from("profiles")
    .select(
      "id, username, full_name, phone, role, active, must_change_password",
    )
    .eq("id", authData.user.id)
    .maybeSingle();

  if (profileError) {
    console.error("Unable to load exact caller profile", profileError);
    throw new HttpError(
      500,
      "PROFILE_LOOKUP_FAILED",
      "The caller profile could not be verified.",
    );
  }
  if (!profile) {
    throw new HttpError(403, "PROFILE_REQUIRED", "No app profile exists.");
  }
  if (profile.active !== true) {
    throw new HttpError(403, "PROFILE_INACTIVE", "This account is inactive.");
  }

  const role = profile.role as AppRole;
  if (!["admin", "staff", "customer"].includes(role)) {
    throw new HttpError(403, "ROLE_INVALID", "The account role is invalid.");
  }
  if (allowedRoles && !allowedRoles.includes(role)) {
    throw new HttpError(
      403,
      "FORBIDDEN",
      "This account cannot perform the requested operation.",
    );
  }
  if (
    profile.must_change_password === true &&
    options.allowPasswordChangeRequired !== true
  ) {
    throw new HttpError(
      403,
      "PASSWORD_CHANGE_REQUIRED",
      "The temporary password must be changed before continuing.",
    );
  }

  let customer: Caller["customer"] = null;
  if (role === "customer") {
    const { data: customerRow, error: customerError } = await adminClient
      .from("business_customers")
      .select("id, account_status, business_name")
      .eq("profile_id", profile.id)
      .maybeSingle();
    if (customerError) {
      console.error("Unable to load exact customer account", customerError);
      throw new HttpError(
        500,
        "CUSTOMER_LOOKUP_FAILED",
        "The customer account could not be verified.",
      );
    }
    if (!customerRow) {
      throw new HttpError(
        403,
        "CUSTOMER_ACCOUNT_REQUIRED",
        "No business customer is linked to this profile.",
      );
    }
    customer = {
      id: customerRow.id,
      accountStatus: customerRow.account_status,
      businessName: customerRow.business_name,
    };
  }

  return {
    id: profile.id,
    username: profile.username,
    fullName: profile.full_name,
    phone: profile.phone,
    role,
    active: profile.active,
    mustChangePassword: profile.must_change_password,
    customer,
  };
}
