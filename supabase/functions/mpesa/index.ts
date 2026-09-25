/**
 * Babees Place — M-Pesa Edge Function (OAuth smoke test first)
 *
 * Routes:
 *   GET|POST /oauth   — Daraja Sandbox (or production) OAuth token request
 *   POST /stk-push    — Not Implemented yet (placeholder)
 *   POST /stk-query   — Not Implemented yet (placeholder)
 *   POST /callback    — Not Implemented yet (placeholder)
 *
 * Secrets (Supabase Edge secrets / local functions env — NEVER VITE_*):
 *   MPESA_CONSUMER_KEY
 *   MPESA_CONSUMER_SECRET
 *   MPESA_ENV=sandbox|production  (default: sandbox)
 *
 * Does NOT expose the access token to the caller. Returns only proof of success.
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

type MpesaEnv = "sandbox" | "production";

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function getMpesaEnv(): MpesaEnv {
  const raw = (Deno.env.get("MPESA_ENV") || "sandbox").toLowerCase();
  return raw === "production" ? "production" : "sandbox";
}

function oauthBaseUrl(env: MpesaEnv): string {
  return env === "production"
    ? "https://api.safaricom.co.ke"
    : "https://sandbox.safaricom.co.ke";
}

/**
 * Request an OAuth access token from Daraja.
 * Token stays server-side; callers only receive success metadata.
 */
async function requestDarajaAccessToken(): Promise<{
  ok: boolean;
  expiresIn?: number;
  tokenType?: string;
  error?: string;
  darajaStatus?: number;
  darajaBody?: unknown;
}> {
  const consumerKey = Deno.env.get("MPESA_CONSUMER_KEY")?.trim();
  const consumerSecret = Deno.env.get("MPESA_CONSUMER_SECRET")?.trim();
  const env = getMpesaEnv();

  if (!consumerKey || !consumerSecret) {
    return {
      ok: false,
      error:
        "Missing MPESA_CONSUMER_KEY or MPESA_CONSUMER_SECRET. Local: put non-empty values in supabase/functions/.env and restart `supabase functions serve mpesa --env-file supabase/functions/.env`. Remote: `supabase secrets set`. Never use VITE_* / frontend/.env for these.",
    };
  }

  const credentials = btoa(`${consumerKey}:${consumerSecret}`);
  const url =
    `${oauthBaseUrl(env)}/oauth/v1/generate?grant_type=client_credentials`;

  let res: Response;
  try {
    res = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Basic ${credentials}`,
      },
    });
  } catch (err) {
    return {
      ok: false,
      error: `Network error calling Daraja OAuth: ${
        err instanceof Error ? err.message : String(err)
      }`,
    };
  }

  const text = await res.text();
  let data: Record<string, unknown> = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { raw: text };
  }

  if (!res.ok) {
    // Never echo credentials; only Daraja error shape / status.
    return {
      ok: false,
      error: "Daraja OAuth request failed",
      darajaStatus: res.status,
      darajaBody: {
        error: data.error,
        error_description: data.error_description,
        requestId: data.requestId,
        // Keep payload small and free of secrets
      },
    };
  }

  const accessToken = typeof data.access_token === "string"
    ? data.access_token
    : null;
  if (!accessToken) {
    return {
      ok: false,
      error: "Daraja OAuth succeeded but access_token missing in response",
      darajaStatus: res.status,
    };
  }

  const expiresIn = data.expires_in != null
    ? Number(data.expires_in)
    : undefined;

  return {
    ok: true,
    expiresIn: Number.isFinite(expiresIn) ? expiresIn : undefined,
    tokenType: typeof data.token_type === "string"
      ? data.token_type
      : "Bearer",
  };
}

function routePath(req: Request): string {
  const url = new URL(req.url);
  // Paths look like /mpesa/oauth when served under functions/v1/mpesa/...
  // or /oauth when the function root handles subpaths.
  const pathname = url.pathname.replace(/\/+$/, "") || "/";
  const parts = pathname.split("/").filter(Boolean);
  // Drop leading function name if present
  const withoutFn = parts[0] === "mpesa" ? parts.slice(1) : parts;
  return "/" + (withoutFn.join("/") || "");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const path = routePath(req);

  // --- OAuth smoke test (Consumer Key + Secret only) ---
  if (
    (path === "/" || path === "/oauth" || path === "/token") &&
    (req.method === "GET" || req.method === "POST")
  ) {
    const result = await requestDarajaAccessToken();
    if (!result.ok) {
      return jsonResponse(
        {
          ok: false,
          authenticated: false,
          env: getMpesaEnv(),
          error: result.error,
          darajaStatus: result.darajaStatus ?? null,
          darajaBody: result.darajaBody ?? null,
        },
        result.darajaStatus && result.darajaStatus >= 400
          ? 502
          : 500,
      );
    }

    // Do NOT return access_token to the client.
    return jsonResponse({
      ok: true,
      authenticated: true,
      env: getMpesaEnv(),
      tokenType: result.tokenType,
      expiresIn: result.expiresIn ?? null,
      message: "Daraja OAuth succeeded; access token retained server-side",
    });
  }

  // Placeholders — STK / callback not implemented yet
  if (path === "/stk-push" || path === "/stk-query" || path === "/callback") {
    return jsonResponse(
      {
        ok: false,
        error: "Not Implemented",
        path,
        hint:
          "OAuth is available at GET|POST /oauth. STK Push comes after sandbox Passkey + Shortcode are configured.",
      },
      501,
    );
  }

  return jsonResponse(
    {
      ok: false,
      error: "Unknown route",
      path,
      available: ["/oauth", "/token"],
      notImplemented: ["/stk-push", "/stk-query", "/callback"],
    },
    404,
  );
});
