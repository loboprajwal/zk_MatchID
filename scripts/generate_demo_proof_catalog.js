#!/usr/bin/env node
/**
 * Generates mobile/assets/demo_proof_catalog.json — real Groth16 proofs via
 * snarkjs + mopro/assets/generic_verifier_{wasm,final.zkey}.
 * HONEST: local-dev ceremony; not production-trusted setup.
 */
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const snarkjs = require(path.join(root, 'circuits/node_modules/snarkjs'));

const WASM = path.join(root, 'mopro/assets/generic_verifier.wasm');
const ZKEY = path.join(root, 'mopro/assets/generic_verifier_final.zkey');
const outPath = path.join(root, 'mobile/assets/demo_proof_catalog.json');
const YEAR = 2026;

const wallets = [
  { id: 'wallet_vivek', name: 'Vivek Personal', userSecret: '11111111111111111111',
    credentials: { aadhaar: { birthYear: 2000 }, degree: { institutionId: 1042 }, residency: { jurisdictionCode: 29 } } },
  { id: 'wallet_sagar', name: 'Sagar Work', userSecret: '22222222222222222222',
    credentials: { aadhaar: { birthYear: 1998 }, degree: { institutionId: 2087 }, residency: { jurisdictionCode: 7 } } },
  { id: 'wallet_prajwal', name: 'Prajwal Uni', userSecret: '33333333333333333333',
    credentials: { aadhaar: { birthYear: 2003 }, degree: { institutionId: 1042 }, residency: { jurisdictionCode: 29 } } },
];

const predicates = [
  { id: 'age_18', label: 'Age >= 18', mode: 3, thresholdA: 18, thresholdB: YEAR, allowedSet: [0,0,0,0,0],
    attrFrom: (w) => w.credentials.aadhaar.birthYear, issuer: 'did:zkmatch:gov-uidai',
    claim: 'Age >= 18 verified — DOB not disclosed' },
  { id: 'age_21', label: 'Age >= 21', mode: 3, thresholdA: 21, thresholdB: YEAR, allowedSet: [0,0,0,0,0],
    attrFrom: (w) => w.credentials.aadhaar.birthYear, issuer: 'did:zkmatch:gov-uidai',
    claim: 'Age >= 21 verified — DOB not disclosed' },
  { id: 'degree', label: 'Holds a degree (accredited)', mode: 2, thresholdA: 0, thresholdB: 0,
    allowedSet: [1042, 2087, 3311, 4509, 5120],
    attrFrom: (w) => w.credentials.degree.institutionId, issuer: 'did:zkmatch:university-pes',
    claim: 'Accredited degree possession verified — student ID not disclosed' },
  { id: 'residency', label: 'Resident of eligible state', mode: 2, thresholdA: 0, thresholdB: 0,
    allowedSet: [29, 7, 13, 22, 33],
    attrFrom: (w) => w.credentials.residency.jurisdictionCode, issuer: 'did:zkmatch:municipal-bda',
    claim: 'Eligible state residency verified — address not disclosed' },
];

(async () => {
  const catalog = {
    version: 1,
    proofKind: 'groth16_precomputed',
    note: 'Real Groth16 proofs (snarkjs + local-dev zkey). Native mopro not required for demo catalog path.',
    ceremony: 'local-dev pot12',
    generatedAt: new Date().toISOString(),
    wallets: wallets.map(({ id, name, credentials }) => ({ id, name, credentials })),
    entries: [],
  };
  for (const wallet of wallets) {
    for (const pred of predicates) {
      for (let i = 0; i < 3; i++) {
        const nonceNum = String(BigInt('0x' + Buffer.from(`${wallet.id}:${pred.id}:${i}`).toString('hex').slice(0, 30)));
        const input = {
          attributeValue: pred.attrFrom(wallet),
          userSecretKey: wallet.userSecret,
          credentialExpiry: 2035,
          predicateMode: pred.mode,
          thresholdA: pred.thresholdA,
          thresholdB: pred.thresholdB,
          allowedSet: pred.allowedSet,
          currentTimestamp: YEAR,
          sessionNonce: nonceNum,
        };
        process.stderr.write(`proving ${wallet.id} ${pred.id} #${i}...\n`);
        const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, WASM, ZKEY);
        catalog.entries.push({
          id: `${wallet.id}__${pred.id}__${i}`,
          walletId: wallet.id,
          predicateId: pred.id,
          predicateLabel: pred.label,
          predicateClaim: pred.claim,
          issuerReference: pred.issuer,
          sessionNonce: nonceNum,
          proof,
          public_inputs: publicSignals,
        });
      }
    }
  }
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(catalog));
  console.log('Wrote', outPath, 'entries=', catalog.entries.length);
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
