import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'auth_key.dart';

/// AES-128-ECB over exactly one 16-byte block, as the auth handshake needs.
Uint8List encryptChallenge(AuthKey key, Uint8List challenge) {
  if (challenge.length != 16) {
    throw ArgumentError.value(challenge.length, 'challenge', 'need 16 bytes');
  }
  final cipher = AESEngine()..init(true, KeyParameter(key.bytes));
  final out = Uint8List(16);
  cipher.processBlock(challenge, 0, out, 0);
  return out;
}

/// One-block AES-CBC with a zero IV. For a single block that is AES-ECB.
Uint8List _aesBlock(Uint8List key, Uint8List block) {
  final cipher = AESEngine()..init(true, KeyParameter(key));
  final out = Uint8List(16);
  cipher.processBlock(block, 0, out, 0);
  return out;
}

BigInt _fromLe(List<int> bytes) {
  var n = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    n = (n << 8) | BigInt.from(bytes[i]);
  }
  return n;
}

/// sect163r2 (NIST B-163) over GF(2^163). Firmware V1.0.6.20 rejected a
/// secp192r1 point with chunked status 0x28. Wire format is 24-byte
/// little-endian limbs: X then Y.
///
/// The band drops the handshake if the second chunk arrives late. An affine
/// double-and-add inverted the field on every add and took ~13s on the phone
/// (`android-2026-10-04T12-20-26`), so this uses 32-bit carryless limbs and
/// Lopez-Dahab coordinates (one inverse per scalar multiply).
final class HuamiEcdh {
  HuamiEcdh._(this._private, this.publicBytes);

  final BigInt _private;

  /// 48 bytes: X then Y.
  final Uint8List publicBytes;

  static HuamiEcdh generate() {
    final random = Random.secure();
    BigInt scalar;
    do {
      scalar = BigInt.zero;
      for (var i = 0; i < 21; i++) {
        scalar |= BigInt.from(random.nextInt(256)) << (8 * i);
      }
      // Order is 162 bits; keep bits 0..160.
      scalar &= (BigInt.one << 161) - BigInt.one;
    } while (scalar.bitLength < 82);
    return HuamiEcdh._(scalar, _mulPoint(_gx, _gy, scalar));
  }

  /// `05 || AES(auth, random) || AES(session, random)`.
  /// Session is shared X bytes 8..24 XORed with the auth key.
  Uint8List secondCommand(
    AuthKey auth,
    Uint8List remoteRandom,
    Uint8List remotePublic,
  ) {
    final shared = _mulPoint(
      _feFromBytes(remotePublic.sublist(0, 24)),
      _feFromBytes(remotePublic.sublist(24, 48)),
      _private,
    );
    final session = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      session[i] = shared[i + 8] ^ auth.bytes[i];
    }
    final random = Uint8List.fromList(remoteRandom);
    return Uint8List.fromList([
      0x05,
      ..._aesBlock(auth.bytes, random),
      ..._aesBlock(session, random),
    ]);
  }
}

const _limbs = 6;
const _deg = 163;

Uint32List _fe() => Uint32List(_limbs);

Uint32List _feCopy(Uint32List a) {
  final o = _fe();
  o.setAll(0, a);
  return o;
}

Uint32List _feFromBytes(List<int> bytes) {
  final o = _fe();
  for (var i = 0; i < _limbs; i++) {
    o[i] =
        bytes[i * 4] |
        (bytes[i * 4 + 1] << 8) |
        (bytes[i * 4 + 2] << 16) |
        (bytes[i * 4 + 3] << 24);
  }
  o[5] &= 7;
  return o;
}

Uint8List _feBytes(Uint32List a) {
  final o = Uint8List(24);
  for (var i = 0; i < _limbs; i++) {
    final v = a[i];
    o[i * 4] = v & 0xff;
    o[i * 4 + 1] = (v >> 8) & 0xff;
    o[i * 4 + 2] = (v >> 16) & 0xff;
    o[i * 4 + 3] = (v >> 24) & 0xff;
  }
  return o;
}

bool _feZero(Uint32List a) {
  for (var i = 0; i < _limbs; i++) {
    if (a[i] != 0) return false;
  }
  return true;
}

bool _feEq(Uint32List a, Uint32List b) {
  for (var i = 0; i < _limbs; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint32List _feXor(Uint32List a, Uint32List b) {
  final o = _fe();
  for (var i = 0; i < _limbs; i++) {
    o[i] = a[i] ^ b[i];
  }
  return o;
}

/// Carryless product of two reduced field elements, then reduce mod
/// x^163 + x^7 + x^6 + x^3 + 1.
Uint32List _feMul(Uint32List a, Uint32List b) {
  final prod = Uint32List(12);
  for (var i = 0; i < _limbs; i++) {
    final ai = a[i];
    if (ai == 0) continue;
    for (var j = 0; j < _limbs; j++) {
      final bj = b[j];
      if (bj == 0) continue;
      var lo = 0;
      var hi = 0;
      for (var s = 0; s < 32; s++) {
        if ((bj & (1 << s)) == 0) continue;
        lo ^= (ai << s) & 0xffffffff;
        if (s != 0) hi ^= ai >> (32 - s);
      }
      prod[i + j] ^= lo;
      prod[i + j + 1] ^= hi;
    }
  }
  for (var bit = 324; bit >= _deg; bit--) {
    final limb = bit >> 5;
    final sh = bit & 31;
    if (((prod[limb] >> sh) & 1) == 0) continue;
    final d = bit - _deg;
    _xorBit(prod, bit);
    _xorBit(prod, d + 7);
    _xorBit(prod, d + 6);
    _xorBit(prod, d + 3);
    _xorBit(prod, d);
  }
  final out = _fe();
  for (var i = 0; i < _limbs; i++) {
    out[i] = prod[i];
  }
  out[5] &= 7;
  return out;
}

void _xorBit(Uint32List p, int bit) {
  final limb = bit >> 5;
  p[limb] = (p[limb] ^ (1 << (bit & 31))) & 0xffffffff;
}

Uint32List _feSqr(Uint32List a) => _feMul(a, a);

Uint32List _feInv(Uint32List a) {
  var r = _fe();
  r[0] = 1;
  var p = _feCopy(a);
  for (var i = 1; i < _deg; i++) {
    p = _feSqr(p);
    r = _feMul(r, p);
  }
  return r;
}

// Base point of sect163r2, little-endian limbs from NIST.
final _gx = _feFromBytes([
  0x36,
  0x3e,
  0x34,
  0xe8,
  0x37,
  0x46,
  0x99,
  0xd4,
  0x68,
  0x11,
  0x99,
  0xa0,
  0x7e,
  0xd5,
  0xa2,
  0x86,
  0x62,
  0xa1,
  0xeb,
  0xf0,
  0x03,
  0x00,
  0x00,
  0x00,
]);
final _gy = _feFromBytes([
  0xf1,
  0x24,
  0x73,
  0x79,
  0x0c,
  0x5c,
  0x1c,
  0xb1,
  0x45,
  0xd5,
  0xcd,
  0xa2,
  0x4f,
  0x09,
  0xa0,
  0x71,
  0x6c,
  0xbc,
  0x1f,
  0xd5,
  0x00,
  0x00,
  0x00,
  0x00,
]);

/// b from the base point: y^2 + xy + x^3 + x^2, since a = 1.
final _b = _curveB();

Uint32List _curveB() {
  final y2 = _feSqr(_gy);
  final xy = _feMul(_gx, _gy);
  final x2 = _feSqr(_gx);
  final x3 = _feMul(x2, _gx);
  return _feXor(_feXor(y2, xy), _feXor(x3, x2));
}

final class _P3 {
  _P3(this.x, this.y, this.z, {this.inf = false});
  final Uint32List x, y, z;
  final bool inf;
}

/// Lopez-Dahab doubling, a2 = 1 (dbl-2005-dl).
_P3 _dbl(_P3 p) {
  final a = _feSqr(p.z);
  final bTerm = _feMul(_b, _feSqr(a));
  final c = _feSqr(p.x);
  final z3 = _feMul(a, c);
  final x3 = _feXor(_feSqr(c), bTerm);
  final y3 = _feXor(
    _feMul(_feXor(_feXor(_feSqr(p.y), z3), bTerm), x3),
    _feMul(z3, bTerm),
  );
  return _P3(x3, y3, z3);
}

/// Lopez-Dahab addition (add-2005-dl). Same-x cases match the affine rules.
_P3 _add(_P3 p, _P3 q) {
  if (p.inf) return q;
  if (q.inf) return p;
  final a = _feMul(p.x, q.z);
  final b = _feMul(q.x, p.z);
  final g = _feMul(p.y, _feSqr(q.z));
  final h = _feMul(q.y, _feSqr(p.z));
  if (_feEq(a, b)) {
    if (!_feEq(g, h) || _feZero(p.x)) {
      return _P3(_fe(), _fe(), _fe(), inf: true);
    }
    return _dbl(p);
  }
  final c = _feSqr(a);
  final d = _feSqr(b);
  final e = _feXor(a, b);
  final f = _feXor(c, d);
  final i = _feXor(g, h);
  final j = _feMul(i, e);
  final z3 = _feMul(_feMul(f, p.z), q.z);
  final x3 = _feXor(_feMul(a, _feXor(h, d)), _feMul(b, _feXor(c, g)));
  // Y3 = (A*J + F*G)*F + (J+Z3)*X3
  final y3 = _feXor(
    _feMul(_feXor(_feMul(a, j), _feMul(f, g)), f),
    _feMul(_feXor(j, z3), x3),
  );
  return _P3(x3, y3, z3);
}

Uint32List _feOne() {
  final o = _fe();
  o[0] = 1;
  return o;
}

/// k*P in Lopez-Dahab coordinates, then one inverse back to affine bytes.
Uint8List _mulPoint(Uint32List px, Uint32List py, BigInt k) {
  var r = _P3(_fe(), _fe(), _fe(), inf: true);
  var q = _P3(_feCopy(px), _feCopy(py), _feOne());
  var n = k;
  while (n > BigInt.zero) {
    if (n.isOdd) r = _add(r, q);
    q = _dbl(q);
    n >>= 1;
  }
  if (r.inf) return Uint8List(48);
  final zi = _feInv(r.z);
  final x = _feMul(r.x, zi);
  final y = _feMul(r.y, _feSqr(zi));
  return Uint8List.fromList([..._feBytes(x), ..._feBytes(y)]);
}

/// Public key for a raw 24-byte scalar. Bits above 160 are cleared,
/// matching the band's key generation.
Uint8List huamiPublicForTest(Uint8List private24) {
  final scalar = _fromLe(private24) & ((BigInt.one << 161) - BigInt.one);
  return _mulPoint(_gx, _gy, scalar);
}

/// Shared point X||Y. [private24] is masked the same way as key generation.
Uint8List huamiSharedForTest(Uint8List private24, Uint8List remotePublic) {
  final scalar = _fromLe(private24) & ((BigInt.one << 161) - BigInt.one);
  return _mulPoint(
    _feFromBytes(remotePublic.sublist(0, 24)),
    _feFromBytes(remotePublic.sublist(24, 48)),
    scalar,
  );
}
