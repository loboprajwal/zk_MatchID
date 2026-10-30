import { createClient, type User } from "npm:@supabase/supabase-js@2.45.4";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

export async function body(request: Request, maxBytes = 16_384): Promise<Record<string, unknown>> {
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > maxBytes) throw new Error("payload_too_large");
  const value: unknown = JSON.parse(raw);
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_payload");
  return value as Record<string, unknown>;
}

export function serviceClient() {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export async function authenticatedUser(request: Request): Promise<User> {
  const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("unauthorized");
  const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) throw new Error("unauthorized");
  return data.user;
}

export async function requireRole(userId: string, roles: string[]) {
  const client = serviceClient();
  const { data, error } = await client.from("profiles").select("role").eq("id", userId).maybeSingle();
  if (error || !data || !roles.includes(data.role)) throw new Error("forbidden");
  return data.role as string;
}

export function isPhone(value: unknown): value is string {
  return typeof value === "string" && /^\+91[6-9]\d{9}$/.test(value);
}

export async function hmacHex(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const bytes = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function secureEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left.charCodeAt(i) ^ right.charCodeAt(i);
  return diff === 0;
}

export async function audit(userId: string, action: string, entity: string, outcome: "success" | "failure" | "denied", meta: Record<string, unknown> = {}) {
  const { error } = await serviceClient().from("audit_log").insert({ actor_id: userId, action, entity, outcome, meta });
  if (error) console.error("audit_write_failed", error.message);
}
