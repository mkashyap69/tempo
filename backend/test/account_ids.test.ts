import { describe, expect, it } from 'vitest';
import { appAccountToken, obfuscatedAccountId } from '../src/account_ids.js';

// Reference values from Python: uuid.uuid5(UUID(ns), 'uid-123') and hashlib.sha256.
describe('account ids', () => {
  it('appAccountToken is RFC 4122 UUIDv5 of the uid', () => {
    expect(appAccountToken('uid-123')).toBe('b74411ce-5581-53d0-82ad-f3dad3b4f929');
  });
  it('obfuscatedAccountId is the SHA-256 hex, 64 characters', () => {
    const v = obfuscatedAccountId('uid-123');
    expect(v).toBe('23481502b4881b15d1cc3216f86b19af5373e9a3c4ec2e91edd9dd0f00a8b414');
    expect(v).toHaveLength(64);
  });
});
