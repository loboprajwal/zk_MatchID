import { z } from "npm:zod@3.23.8";
import { audit, authenticatedUser, body, hmacHex, reply, requireRole, secureEqual, serviceClient } from "../_shared/http.ts";

const schema = z.object({ proofId: z.string().uuid(), credentialId: z.string().uuid(), requestId: z.string().uuid(), predicate: z.string(), result: z.boolean(), nonce: z.string().uuid().or(z.string().uuid().transform((v) => v)), expiresAt: z.string().datetime(), signature: z.string().regex(/^[a-f0-9]{64}$/) }).strict();
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return reply(204, {});
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  let actor = "";
  try {
    const user = await authenticatedUser(request);
    actor = user.id;
    await requireRole(user.id, ["verifier", "admin"]);
    const input = schema.parse(await body(request));
    const secret = Deno.env.get("ATTESTATION_SIGNING_SECRET");
    if (!secret) throw new Error("service_not_configured");
    const payload = { credentialId: input.credentialId, requestId: input.requestId, predicate: input.predicate, result: input.result, nonce: input.nonce, expiresAt: input.expiresAt };
    const expected = await hmacHex(secret, JSON.stringify(payload));
    if (!secureEqual(input.signature, expected) || new Date(input.expiresAt) <= new Date()) throw new Error("invalid_or_expired_signature");
    const client = serviceClient();
    const { data: requestRow } = await client.from("verification_requests").select("id,verifier_id,expires_at").eq("id", input.requestId).maybeSingle();
    if (!requestRow || (requestRow.verifier_id !== user.id && await requireRole(user.id, ["admin"]) !== "admin") || new Date(requestRow.expires_at) <= new Date()) throw new Error("verification_request_not_owned_or_expired");
    const { data: proof, error } = await client.from("proofs").select("id,credential_id,request_id,predicate,nonce,signature,expires_at,used_at,result").eq("nonce", input.nonce).maybeSingle();
    if (error || !proof || proof.id !== input.proofId || proof.credential_id !== input.credentialId || proof.request_id !== input.requestId || proof.predicate !== input.predicate || proof.signature !== input.signature || proof.result !== (input.result ? "pass" : "fail") || new Date(proof.expires_at).getTime() !== new Date(input.expiresAt).getTime() || proof.used_at) throw new Error("replayed_or_unknown_attestation");
    const { data: credential } = await client.from("credentials").select("status,expires_at").eq("id", proof.credential_id).maybeSingle();
    if (!credential || credential.status !== "valid" || (credential.expires_at && new Date(credential.expires_at) <= new Date())) throw new Error("credential_revoked_or_expired");
    const { data: consumed, error: consumeError } = await client.rpc("consume_proof_nonce", { p_nonce: proof.nonce, p_signature: proof.signature });
    if (consumeError || !Array.isArray(consumed) || consumed[0]?.consumed !== true) throw new Error("replayed_or_expired_attestation");
    await audit(user.id, "attestation_verify", "proof", "success", { predicate: proof.predicate, result: proof.result });
    return reply(200, { verified: true, result: proof.result === "pass", protocol: "server-signed-selective-disclosure-attestation-v1", message: "Attestation signature, expiry, credential status, and one-time nonce were verified." });
  } catch (error) {
    const message = error instanceof z.ZodError ? "invalid_payload" : String(error instanceof Error ? error.message : error);
    if (actor) await audit(actor, "attestation_verify", "proof", "failure");
    return reply(message === "unauthorized" ? 401 : message === "forbidden" ? 403 : 400, { verified: false, error: message });
  }
});
