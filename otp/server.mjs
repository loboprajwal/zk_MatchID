import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';

const phonePattern = /^\+[1-9]\d{7,14}$/;
const codePattern = /^\d{6}$/;
const windowMs = 60 * 60 * 1000;
const maxSendsPerWindow = 5;
const sendHistory = new Map();

function json(response, status, payload) {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  });
  response.end(JSON.stringify(payload));
}

async function readBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 4096) throw Object.assign(new Error('Request too large'), { status: 413 });
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw Object.assign(new Error('Invalid request'), { status: 400 });
  }
}

function configured(env) {
  return Boolean(
    env.TWILIO_API_KEY_SID &&
      env.TWILIO_API_KEY_SECRET &&
      /^VA[0-9a-fA-F]{32}$/.test(env.TWILIO_VERIFY_SERVICE_SID ?? ''),
  );
}

function createRateLimiter(now = () => Date.now()) {
  return (phone) => {
    const timestamps = (sendHistory.get(phone) ?? []).filter((time) => now() - time < windowMs);
    if (timestamps.length >= maxSendsPerWindow) return false;
    timestamps.push(now());
    sendHistory.set(phone, timestamps);
    if (sendHistory.size > 10000) {
      for (const [number, history] of sendHistory) {
        if (history.every((time) => now() - time >= windowMs)) sendHistory.delete(number);
      }
    }
    return true;
  };
}

export function createOtpServer({ env = process.env, fetchImpl = fetch } = {}) {
  const allowSend = createRateLimiter();
  return createServer(async (request, response) => {
    const url = new URL(request.url ?? '/', 'http://localhost');
    if (request.method === 'GET' && url.pathname === '/health') {
      return json(response, 200, { status: 'ok', otpConfigured: configured(env) });
    }
    if (request.method !== 'POST' || !['/v1/otp/send', '/v1/otp/verify'].includes(url.pathname)) {
      return json(response, 404, { error: 'Not found' });
    }
    if (!configured(env)) return json(response, 503, { error: 'Phone verification is not configured.' });

    try {
      const body = await readBody(request);
      const phone = body?.phoneNumber;
      if (typeof phone !== 'string' || !phonePattern.test(phone)) {
        return json(response, 400, { error: 'Enter a valid phone number in international E.164 format.' });
      }

      const isSend = url.pathname.endsWith('/send');
      if (!isSend && (typeof body?.code !== 'string' || !codePattern.test(body.code))) {
        return json(response, 400, { error: 'Enter the six-digit code.' });
      }
      if (isSend && !allowSend(phone)) {
        return json(response, 429, { error: 'Too many code requests. Try again later.' });
      }

      const endpoint = isSend ? 'Verifications' : 'VerificationCheck';
      const form = new URLSearchParams({ to: phone });
      form.set(isSend ? 'channel' : 'code', isSend ? 'sms' : body.code);
      const basic = Buffer.from(`${env.TWILIO_API_KEY_SID}:${env.TWILIO_API_KEY_SECRET}`).toString('base64');
      const result = await fetchImpl(
        `https://verify.twilio.com/v2/Services/${env.TWILIO_VERIFY_SERVICE_SID}/${endpoint}`,
        {
          method: 'POST',
          headers: {
            authorization: `Basic ${basic}`,
            'content-type': 'application/x-www-form-urlencoded',
          },
          body: form,
          signal: AbortSignal.timeout(10000),
        },
      );
      const providerData = await result.json().catch(() => ({}));
      if (!result.ok) {
        if (!isSend && [400, 404].includes(result.status)) {
          return json(response, 200, { verified: false, error: 'That code is invalid or expired. Request a new code and try again.' });
        }
        if (result.status === 429) return json(response, 429, { error: 'Too many attempts. Try again later.' });
        return json(response, 502, { error: isSend ? 'Could not send a verification code. Check the number and retry.' : 'Could not verify the code. Please retry.' });
      }
      if (isSend) return json(response, 200, { sent: providerData.status === 'pending' });
      return json(response, 200, { verified: providerData.status === 'approved' });
    } catch (error) {
      const status = Number.isInteger(error?.status) ? error.status : 502;
      return json(response, status, {
        error: status === 413 ? 'Request is too large.' : status === 400 ? 'Invalid request.' : 'Phone verification service is unavailable. Please retry.',
      });
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const server = createOtpServer();
  const port = Number(process.env.PORT ?? 8080);
  server.listen(port, '0.0.0.0', () => {
    process.stdout.write(`OTP service listening on port ${port}\n`);
  });
}
