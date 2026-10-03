/// Drift schema and DAOs. Raw sample tables are append-only (enforced by
/// SQL triggers); everything else is derived and recomputable.
library;

export 'src/database.dart';
