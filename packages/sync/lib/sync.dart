/// End-to-end encrypted sync for Tempo (Backend plan → Encrypted sync, S1).
///
/// Pure Dart: no Flutter, no network. The app moves the bytes this package
/// makes; the server only ever stores [Segment] ciphertext and a
/// [WrappedKey], neither of which it can open.
library;

export 'src/classification.dart';
export 'src/codec.dart';
export 'src/keys.dart';
export 'src/merge.dart';
export 'src/recovery_key.dart';
export 'src/segment.dart';
