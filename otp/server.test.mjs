import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { createOtpServer } from './server.mjs';

const env = {
  TWILIO_API_KEY_SID: 'SK' + 'a'.repeat(32),
  TWILIO_API_KEY_SECRET: 'test-secret-not-a-real-key',
  TWILIO_VERIFY_SERVICE_SID: 'VA' + 'b'.repeat(32),
};
let server;
let baseUrl;
let lastRequest;

before(async () => {
  server = createOtpServer({
    env,
    fetchImpl: async (url, options) => {
      lastRequest = { url, options };
      const checking = String(url).endsWith('/VerificationCheck');
      const code = options.body.get('code');
      if (checking && code === '999999') {
        return new Response(JSON.stringify({ message: 'Verification expired' }), { status: 404 });
      }
      const status = checking ? (code === '123456' ? 'approved' : 'pending') : 'pending';
      return new Response(JSON.stringify({ status }), { status: 200 });
    },
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => new Promise((resolve) => server.close(resolve)));

test('send delegates SMS to Twilio Verify over HTTPS without returning a code', async () => {
  const response = await fetch(`${baseUrl}/v1/otp/send`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phoneNumber: '+919876543210' }),
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { sent: true });
  assert.match(lastRequest.url, /^https:\/\/verify\.twilio\.com\//);
  assert.equal(lastRequest.options.body.get('channel'), 'sms');
  assert.equal(lastRequest.options.body.get('to'), '+919876543210');
  assert.equal(lastRequest.options.body.has('code'), false);
});

test('verification accepts only the provider approved status', async () => {
  const response = await fetch(`${baseUrl}/v1/otp/verify`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phoneNumber: '+919876543210', code: '123456' }),
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { verified: true });
  assert.equal(lastRequest.options.body.get('code'), '123456');
});

test('wrong and expired codes never verify', async () => {
  for (const code of ['000000', '999999']) {
    const response = await fetch(`${baseUrl}/v1/otp/verify`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ phoneNumber: '+919876543210', code }),
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).verified, false);
  }
});

test('malformed phone numbers and codes are rejected before provider access', async () => {
  const phone = await fetch(`${baseUrl}/v1/otp/send`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phoneNumber: '9876543210' }),
  });
  assert.equal(phone.status, 400);
  const code = await fetch(`${baseUrl}/v1/otp/verify`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phoneNumber: '+919876543210', code: '1234' }),
  });
  assert.equal(code.status, 400);
});

test('unconfigured service fails closed', async () => {
  const unconfigured = createOtpServer({ env: {}, fetchImpl: async () => { throw new Error('must not call provider'); } });
  await new Promise((resolve) => unconfigured.listen(0, '127.0.0.1', resolve));
  try {
    const response = await fetch(`http://127.0.0.1:${unconfigured.address().port}/v1/otp/send`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ phoneNumber: '+919876543210' }),
    });
    assert.equal(response.status, 503);
  } finally {
    await new Promise((resolve) => unconfigured.close(resolve));
  }
});
