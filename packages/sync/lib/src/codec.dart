import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

/// Rows to bytes and back: canonical JSON (object keys sorted at every
/// level), then gzip. JSON over CBOR keeps the package dependency-free and
/// readable in tests; gzip brings it near CBOR's size (decision 2026-11-04).
abstract final class RowCodec {
  static Uint8List encode(Map<String, List<Map<String, Object?>>> tables) =>
      Uint8List.fromList(gzip.encode(utf8.encode(canonicalJson(tables))));

  static Map<String, List<Map<String, Object?>>> decode(List<int> bytes) {
    final j = jsonDecode(utf8.decode(gzip.decode(bytes)));
    if (j is! Map<String, Object?>)
      throw const FormatException('not a table map');
    return {
      for (final e in j.entries)
        e.key: [
          for (final r in e.value! as List) (r as Map).cast<String, Object?>(),
        ],
    };
  }
}

/// JSON with object keys sorted, so equal data always gives equal bytes.
String canonicalJson(Object? v) {
  Object? sort(Object? x) => switch (x) {
    Map() => {
      for (final k in (x.keys.map((k) => k as String).toList()..sort()))
        k: sort(x[k]),
    },
    List() => [for (final e in x) sort(e)],
    double() when !x.isFinite => throw ArgumentError('non-finite number $x'),
    _ => x,
  };
  return jsonEncode(sort(v));
}
