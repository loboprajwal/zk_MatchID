import { z } from "npm:zod@3.23.8";
import { audit, authenticatedUser, body, hmacHex, reply, requireRole, serviceClient } from "../_shared/http.ts";

const schema = z.object({ credentialId: z.string().uuid(), requestId: z.string().uuid(), result: z.boolean() }).strict();
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return reply(204, {});
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  try {
    const user = await authenticatedUser(request);
    await requireRole(user.id, ["holder"]);
    const input = schema.parse(await body(request));
    const client = serviceClient();
    const { data: requestRow, error: requestError } = await client.from("verification_requests").select("id,predicate,expires_at").eq("id", input.requestId).maybeSingle();
    if (requestError || !requestRow || new Date(requestRow.expires_at) <= new Date()) throw new Error("verification_request_expired_or_missing");
    const { data: credential, error: credentialError } = await client.from("credentials").select("id,wallet_id,status,expires_at,claims").eq("id", input.credentialId).maybeSingle();
    if (credentialError || !credential || credential.status !== "valid" || (credential.expires_at && new Date(credential.expires_at) <= new Date())) throw new Error("credential_not_valid");
    const { data: wallet } = await client.from("wallets").select("identity_id,identities!inner(user_id)").eq("id", credential.wallet_id).maybeSingle();
    const identity = Array.isArray(wallet?.identities) ? wallet.identities[0] : wallet?.identities;
    if (identity?.user_id !== user.id) throw new Error("forbidden");

    // The boolean is an attestation from the demo backend, not a ZK proof.
    const claims = credential.claims as Record<string, unknown>;
    const computed = evaluate(requestRow.predicate, claims);
    if (computed !== input.result) throw new Error("predicate_result_mismatch");
    const nonce = crypto.randomUUID() + crypto.randomUUID();
    const expiresAt = new Date(Date.now() + 5 * 60_000).toISOString();
    const payload = { credentialId: credential.id, requestId: requestRow.id, predicate: requestRow.predicate, result: computed, nonce, expiresAt };
    const secret = Deno.env.get("ATTESTATION_SIGNING_SECRET");
    if (!secret) throw new Error("service_not_configured");
    const signature = await hmacHex(secret, JSON.stringify(payload));
    const { data: storedProof, error: insertError } = await client.from("proofs").insert({ credential_id: credential.id, request_id: requestRow.id, predicate: requestRow.predicate, nonce, signature, expires_at: expiresAt, result: computed ? "pass" : "fail" }).select("id").single();
    if (insertError) throw new Error("attestation_store_failed");
    await audit(user.id, "attestation_issue", "proof", "success", { predicate: requestRow.predicate });
    return reply(200, { protocol: "server-signed-selective-disclosure-attestation-v1", proofId: storedProof.id, ...payload, signature });
  } catch (error) {
    const message = error instanceof z.ZodError ? "invalid_payload" : String(error instanceof Error ? error.message : error);
    return reply(message === "unauthorized" ? 401 : message === "forbidden" ? 403 : 400, { error: message });
  }
});

function evaluate(predicate: string, claims: Record<string, unknown>): boolean {
  switch (predicate) {
    case "age_18": return typeof claims.birthYear === "number" && new Date().getFullYear() - claims.birthYear >= 18;
    case "age_21": return typeof claims.birthYear === "number" && new Date().getFullYear() - claims.birthYear >= 21;
    case "address_verified": return claims.addressVerified === true;
    case "region_membership": return typeof claims.region === "string" && claims.region.length > 0;
    case "degree": return claims.degreeAwarded === true;
    case "name_match": return claims.nameMatch === true;
    case "income_threshold": return typeof claims.monthlyIncome === "number" && claims.monthlyIncome >= 4000;
    case "student_status": return claims.enrollmentStatus === "Active";
    default: throw new Error("unsupported_predicate");
  }
}
