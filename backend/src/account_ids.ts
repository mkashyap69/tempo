import { createHash } from 'node:crypto';

// Every purchase carries the account it was bought under, so a receipt sent
// from another account is caught (Backend plan → Purchase flow).
//
// iOS: appAccountToken, a UUID. We use a name-based UUID (version 5, SHA-1)
// of the uid under a fixed namespace, so the app and server derive the same
// value without storing it. Android: obfuscatedAccountId, at most 64
// characters: the SHA-256 hex of the uid.

/** Namespace for appAccountToken (a random UUID fixed for Tempo). */
export const appAccountNamespace = '6f1d3c52-8f0e-4b8e-9a43-2a7d6c1b5e90';

function uuidBytes(u: string): Buffer {
  return Buffer.from(u.replace(/-/g, ''), 'hex');
}

export function appAccountToken(uid: string): string {
  const h = createHash('sha1').update(uuidBytes(appAccountNamespace)).update(uid, 'utf8').digest();
  const b = Buffer.from(h.subarray(0, 16));
  b[6] = (b[6]! & 0x0f) | 0x50; // version 5
  b[8] = (b[8]! & 0x3f) | 0x80; // RFC 4122 variant
  const x = b.toString('hex');
  return `${x.slice(0, 8)}-${x.slice(8, 12)}-${x.slice(12, 16)}-${x.slice(16, 20)}-${x.slice(20)}`;
}

export function obfuscatedAccountId(uid: string): string {
  return createHash('sha256').update(uid, 'utf8').digest('hex');
}
