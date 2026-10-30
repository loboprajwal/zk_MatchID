const assert = require("node:assert/strict");
const { after, before, test } = require("node:test");
const { SimulatedDigiLockerProvider, ISSUER_ID } = require("./document_provider");
const { createIssuerServer } = require("./server");

const now = Date.UTC(2030, 0, 1);
const phone = "+919999990001";
let provider;
let server;
let baseUrl;

before(async () => {
  provider = new SimulatedDigiLockerProvider({ now: () => now });
  server = createIssuerServer({ provider });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => new Promise((resolve) => server.close(resolve)));

test("issues a signed demo credential only for the verified sample phone", async () => {
  const response = await fetch(`${baseUrl}/v1/demo/issue`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ type: "aadhaar", verifiedPhone: phone }),
  });
  assert.equal(response.status, 200);
  const envelope = await response.json();
  assert.equal(envelope.issuerStatus, "SIMULATED");
  assert.equal(envelope.credential.issuer.id, ISSUER_ID);
  assert.equal(envelope.credential.credentialSubject.maskedAadhaar, "XXXX-XXXX-1201");
  assert.equal(provider.verifySignature(envelope).status, "VALID");
  assert.equal(provider.verifySignature(envelope, { phoneNumber: phone }).valid, true);
});

test("rejects unverified, mismatched, unsupported, and duplicate requests", async () => {
  const noPhone = await fetch(`${baseUrl}/v1/demo/issue`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ type: "aadhaar" }),
  });
  assert.equal(noPhone.status, 401);
  const mismatch = await fetch(`${baseUrl}/v1/demo/issue`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ type: "aadhaar", verifiedPhone: "+919876543210" }),
  });
  assert.equal(mismatch.status, 404);
  const unsupported = await fetch(`${baseUrl}/v1/demo/issue`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ type: "bank", verifiedPhone: phone }),
  });
  assert.equal(unsupported.status, 400);
  const duplicate = await fetch(`${baseUrl}/v1/demo/issue`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ type: "aadhaar", verifiedPhone: phone }),
  });
  assert.equal(duplicate.status, 422);
});

test("rejects tampered envelopes, expired credentials, and revocation", async () => {
  const envelope = await provider.fetchDocument("college", { verifiedPhone: "+919999990002" });
  const tampered = { ...envelope, credential: { ...envelope.credential, credentialSubject: { ...envelope.credential.credentialSubject, name: "Changed" } } };
  assert.equal(provider.verifySignature(tampered).status, "INVALID_SIGNATURE");
  const expired = { ...envelope, token: provider._sign(envelope.credential, { validitySeconds: -1 }) };
  assert.equal(provider.verifySignature(expired).status, "EXPIRED");
  provider.revoke(envelope.credential.id);
  assert.equal(provider.verifySignature(envelope).status, "REVOKED");
});

test("public key endpoint exposes only the demo trust key", async () => {
  const response = await fetch(`${baseUrl}/v1/public-key`);
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.issuer, ISSUER_ID);
  assert.equal(body.algorithm, "EdDSA");
  assert.equal(body.publicKey.length > 0, true);
  assert.equal("privateKey" in body, false);
});
