// Resolve the exact installed signing identity embedded in a Developer ID profile (AITD-447).
import { execFileSync } from 'node:child_process';
import { findProfileSigningIdentity } from './lib/developer-id.mjs';

const profilePath = process.argv[2];
if (!profilePath) {
  console.error('Usage: node scripts/mac-devid-identity.mjs <provisioning-profile>');
  process.exit(1);
}

const profile = execFileSync('security', ['cms', '-D', '-i', profilePath]);
const extract = key => execFileSync('plutil', ['-extract', key, 'raw', '-o', '-', '-'], {
  input: profile, encoding: 'utf8',
}).trim();
const certificate = Buffer.from(extract('DeveloperCertificates.0'), 'base64');
const teamId = extract('TeamIdentifier.0');
const identities = execFileSync('security', ['find-identity', '-v', '-p', 'codesigning'], { encoding: 'utf8' });
console.log(`${findProfileSigningIdentity(certificate, teamId, identities)} ${teamId}`);
