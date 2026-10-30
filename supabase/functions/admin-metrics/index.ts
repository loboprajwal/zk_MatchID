import { audit, authenticatedUser, reply, requireRole, serviceClient } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return reply(204, {});
  if (request.method !== "GET") return reply(405, { error: "method_not_allowed" });
  try {
    const user = await authenticatedUser(request);
    await requireRole(user.id, ["admin"]);
    const client = serviceClient();
    const [users, credentials, pass, fail, audits] = await Promise.all([
      client.from("profiles").select("id", { count: "exact", head: true }),
      client.from("credentials").select("id", { count: "exact", head: true }),
      client.from("proofs").select("id", { count: "exact", head: true }).eq("result", "pass"),
      client.from("proofs").select("id", { count: "exact", head: true }).eq("result", "fail"),
      client.from("audit_log").select("id,actor_id,action,entity,outcome,meta,created_at").order("created_at", { ascending: false }).limit(100),
    ]);
    const error = [users, credentials, pass, fail, audits].find((value) => value.error)?.error;
    if (error) throw new Error("metrics_query_failed");
    await audit(user.id, "admin_metrics_read", "dashboard", "success");
    return reply(200, { users: users.count ?? 0, credentials: credentials.count ?? 0, verificationPass: pass.count ?? 0, verificationFail: fail.count ?? 0, recentAudit: audits.data ?? [] });
  } catch (error) {
    const message = String(error instanceof Error ? error.message : error);
    return reply(message === "unauthorized" ? 401 : message === "forbidden" ? 403 : 400, { error: message });
  }
});
