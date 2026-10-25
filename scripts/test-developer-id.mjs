// node --test scripts/test-developer-id.mjs — the certificate choice behind mac-devid-profile.mjs (AITD-447).
import test from 'node:test';
import assert from 'node:assert/strict';
import { pickDeveloperIdCert } from './lib/developer-id.mjs';

const cert = (id, certificateType, expirationDate) => ({ id, attributes: { certificateType, expirationDate } });
const now = new Date('2026-10-25T00:00:00Z');

test('a G2 replacement is found — the API types it DEVELOPER_ID_APPLICATION_G2', () => {
  const picked = pickDeveloperIdCert([cert('g2', 'DEVELOPER_ID_APPLICATION_G2', '2027-10-25T00:00:00Z')], now);
  assert.equal(picked?.id, 'g2');
});

test('with both, the one that expires last wins over the old Sub-CA certificate', () => {
  const picked = pickDeveloperIdCert([
    cert('old', 'DEVELOPER_ID_APPLICATION', '2027-02-01T22:12:00Z'),
    cert('g2', 'DEVELOPER_ID_APPLICATION_G2', '2027-10-25T00:00:00Z'),
  ], now);
  assert.equal(picked?.id, 'g2');
});

test('other certificate types and expired certificates are never picked', () => {
  assert.equal(pickDeveloperIdCert([
    cert('dist', 'DISTRIBUTION', '2027-10-25T00:00:00Z'),
    cert('gone', 'DEVELOPER_ID_APPLICATION', '2026-01-01T00:00:00Z'),
  ], now), null);
  assert.equal(pickDeveloperIdCert(undefined, now), null);
});
