const { createServer } = require("node:http");
const { SimulatedDigiLockerProvider, SUPPORTED_TYPES } = require("./document_provider");

const maxBodyBytes = 16 * 1024;

function json(response, status, value) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
  });
  response.end(JSON.stringify(value));
}

async function readBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maxBodyBytes) throw coded("TOO_LARGE", "Request exceeds the 16 KB demo limit.");
    chunks.push(chunk);
  }
  try {
    const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error();
    return body;
  } catch {
    throw coded("BAD_REQUEST", "Request must contain a JSON object.");
  }
}

function createIssuerServer({ provider = new SimulatedDigiLockerProvider() } = {}) {
  return createServer(async (request, response) => {
    const url = new URL(request.url ?? "/", "http://127.0.0.1");
    if (request.method === "GET" && url.pathname === "/health") {
      return json(response, 200, { status: "ok", issuer: "SIMULATED DIGILOCKER (DEMO)", demoOnly: true });
    }
    if (request.method === "GET" && url.pathname === "/v1/public-key") {
      return json(response, 200, provider.getPublicKey());
    }
    if (request.method !== "POST" || url.pathname !== "/v1/demo/issue") {
      return json(response, 404, { error: "Not found" });
    }
    try {
      const body = await readBody(request);
      if (typeof body.type !== "string" || !SUPPORTED_TYPES.has(body.type)) {
        return json(response, 400, { code: "UNSUPPORTED_TYPE", error: "Choose Aadhaar, Voter ID, Passport, or College (all demo-only)." });
      }
      const envelope = await provider.fetchDocument(body.type, { verifiedPhone: body.verifiedPhone });
      return json(response, 200, envelope);
    } catch (error) {
      const status = error.code === "TOO_LARGE" ? 413 : error.code === "BAD_REQUEST" ? 400 : error.code === "PHONE_NOT_VERIFIED" ? 401 : error.code === "PHONE_MISMATCH" ? 404 : 422;
      return json(response, status, { code: error.code ?? "ISSUANCE_FAILED", error: error.message });
    }
  });
}

function coded(code, message) { const error = new Error(message); error.code = code; return error; }

if (require.main === module) {
  const provider = new SimulatedDigiLockerProvider();
  const server = createIssuerServer({ provider });
  const port = Number(process.env.PORT ?? 8090);
  server.listen(port, "127.0.0.1", () => {
    process.stdout.write(`SIMULATED DIGILOCKER demo service listening on 127.0.0.1:${port}\n`);
    process.stdout.write(`Demo issuer key ID: ${provider.getPublicKey().id}\n`);
    process.stdout.write("No production DigiLocker or UIDAI connection is configured.\n");
  });
}

module.exports = { createIssuerServer, readBody, maxBodyBytes };
