import { z } from "npm:zod@3.23.8";
import { audit, authenticatedUser, body, hmacHex, isPhone, reply, requireRole, secureEqual, serviceClient } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return reply(204, {});
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  let actor = "";
  try {
    const user = await authenticatedUser(request);
    actor = user.id;
    await requireRole(user.id, ["holder"]);
    const input = z.object({ phone: z.string().refine(isPhone), code: z.string().regex(/^\d{4}$/), challenge: z.string().max(2048) }).strict().parse(await body(request, 4096));
    const secret = Deno.env.get("OTP_CHALLENGE_SECRET");
    const pepper = Deno.env.get("PHONE_HASH_PEPPER");
    if (!secret || !pepper) throw new Error("service_not_configured");
    const [tokenBody, signature, extra] = input.challenge.split(".");
    if (!tokenBody || !signature || extra) throw new Error("invalid_challenge");
    if (!secureEqual(signature, await hmacHex(secret, tokenBody))) throw new Error("invalid_challenge");
    const claims = JSON.parse(atob(tokenBody));
    const phoneHash = await hmacHex(pepper, input.phone);
    if (claims.uid !== user.id || claims.phoneHash !== phoneHash || !Number.isInteger(claims.exp) || claims.exp < Math.floor(Date.now() / 1000)) throw new Error("invalid_challenge");
    if (input.code !== "1234") {
      const { data, error } = await serviceClient().rpc("reserve_otp_attempt", { p_phone_hash: phoneHash });
      if (error) throw new Error("otp_rate_limit_unavailable");
      const reservation = Array.isArray(data) ? data[0] : data;
      await audit(user.id, "otp_verify", "identity", "failure");
      return reply(401, { error: reservation?.allowed ? "invalid_code" : "otp_locked", lockedUntil: reservation?.locked_until });
    }
    const client = serviceClient();
    const { data: attempts, error: attemptsError } = await client.from("otp_attempts").select("locked_until").eq("phone_hash", phoneHash).maybeSingle();
    if (attemptsError || (attempts?.locked_until && new Date(attempts.locked_until) > new Date())) throw new Error("otp_locked");
    const { error: resetError } = await client.rpc("reset_otp_attempts", { p_phone_hash: phoneHash });
    if (resetError) throw new Error("otp_rate_limit_unavailable");
    const { error: identityError } = await client.from("identities").upsert({ user_id: user.id, phone_hash: phoneHash, verified_at: new Date().toISOString() }, { onConflict: "user_id" });
    if (identityError) throw new Error(identityError.code === "23505" ? "phone_already_linked" : "identity_store_failed");
    await audit(user.id, "otp_verify", "identity", "success");
    return reply(200, { verified: true, phone: input.phone, phoneHash });
  } catch (error) {
    const message = error instanceof z.ZodError ? "invalid_payload" : String(error instanceof Error ? error.message : error);
    return reply(message === "unauthorized" ? 401 : message === "forbidden" ? 403 : 400, { error: message });
  }
});
