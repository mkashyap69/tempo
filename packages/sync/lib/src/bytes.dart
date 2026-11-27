import 'dart:convert';
import 'dart:typed_data';

/// Big-endian unsigned integer of [width] bytes.
Uint8List uintBytes(int v, int width) {
  if (v < 0) throw ArgumentError.value(v, 'v', 'must not be negative');
  final b = Uint8List(width);
  for (var i = width - 1; i >= 0; i--) {
    b[i] = v & 0xff;
    v >>= 8;
  }
  if (v != 0) throw ArgumentError('value does not fit in $width bytes');
  return b;
}

int readUint(List<int> b, int offset, int width) {
  var v = 0;
  for (var i = 0; i < width; i++) {
    v = (v << 8) | b[offset + i];
  }
  return v;
}

/// A string as a 2-byte length then its UTF-8 bytes, so fields can't run
/// into each other inside associated data.
Uint8List lengthPrefixed(String s) {
  final u = utf8.encode(s);
  return Uint8List.fromList([...uintBytes(u.length, 2), ...u]);
}

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List unhex(String s) {
  if (s.length.isOdd) throw const FormatException('odd-length hex');
  return Uint8List.fromList([
    for (var i = 0; i < s.length; i += 2)
      int.parse(s.substring(i, i + 2), radix: 16),
  ]);
}

bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
