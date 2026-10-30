import { z } from "npm:zod@3.23.8";
import { authenticatedUser, body, hmacHex, isPhone, reply, requireRole, serviceClient } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return reply(204, {});
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  try {
    const user = await authenticatedUser(request);
    await requireRole(user.id, ["holder"]);
    const input = z.object({ phone: z.string().refine(isPhone) }).strict().parse(await body(request, 4096));
    const pepper = Deno.env.get("PHONE_HASH_PEPPER");
    const signingSecret = Deno.env.get("OTP_CHALLENGE_SECRET");
    if (!pepper || !signingSecret) throw new Error("service_not_configured");
    const phoneHash = await hmacHex(pepper, input.phone);
    const { data, error } = await serviceClient().rpc("can_send_otp", { p_phone_hash: phoneHash });
    if (error) throw new Error("otp_rate_limit_unavailable");
    const reservation = Array.isArray(data) ? data[0] : data;
    if (!reservation?.allowed) return reply(429, { error: reservation?.reason ?? "otp_locked", lockedUntil: reservation?.locked_until });

    const expiresAt = Math.floor(Date.now() / 1000) + 300;
    const tokenBody = btoa(JSON.stringify({ uid: user.id, phoneHash, exp: expiresAt }));
    const signature = await hmacHex(signingSecret, tokenBody);
    // OTP delivery is intentionally simulated. The production adapter replaces this endpoint.
    return reply(200, { demo: true, message: "Demo mode: OTP is simulated.", code: "1234", challenge: `${tokenBody}.${signature}`, expiresAt });
  } catch (error) {
    const message = error instanceof z.ZodError ? "invalid_phone" : String(error instanceof Error ? error.message : error);
    const status = message === "unauthorized" ? 401 : message === "forbidden" ? 403 : message === "otp_locked" ? 429 : 400;
    return reply(status, { error: message });
  }
});
