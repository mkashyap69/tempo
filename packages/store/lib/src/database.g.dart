// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $MinuteSamplesTable extends MinuteSamples
    with TableInfo<$MinuteSamplesTable, MinuteSample> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MinuteSamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<int> ts = GeneratedColumn<int>(
    'ts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stepsMeta = const VerificationMeta('steps');
  @override
  late final GeneratedColumn<int> steps = GeneratedColumn<int>(
    'steps',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intensityMeta = const VerificationMeta(
    'intensity',
  );
  @override
  late final GeneratedColumn<int> intensity = GeneratedColumn<int>(
    'intensity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<int> kind = GeneratedColumn<int>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _auxMeta = const VerificationMeta('aux');
  @override
  late final GeneratedColumn<int> aux = GeneratedColumn<int>(
    'aux',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hrMeta = const VerificationMeta('hr');
  @override
  late final GeneratedColumn<int> hr = GeneratedColumn<int>(
    'hr',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [ts, steps, intensity, kind, aux, hr];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'minute_samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<MinuteSample> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    }
    if (data.containsKey('steps')) {
      context.handle(
        _stepsMeta,
        steps.isAcceptableOrUnknown(data['steps']!, _stepsMeta),
      );
    } else if (isInserting) {
      context.missing(_stepsMeta);
    }
    if (data.containsKey('intensity')) {
      context.handle(
        _intensityMeta,
        intensity.isAcceptableOrUnknown(data['intensity']!, _intensityMeta),
      );
    } else if (isInserting) {
      context.missing(_intensityMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('aux')) {
      context.handle(
        _auxMeta,
        aux.isAcceptableOrUnknown(data['aux']!, _auxMeta),
      );
    }
    if (data.containsKey('hr')) {
      context.handle(_hrMeta, hr.isAcceptableOrUnknown(data['hr']!, _hrMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ts};
  @override
  MinuteSample map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MinuteSample(
      ts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ts'],
      )!,
      steps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}steps'],
      )!,
      intensity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}intensity'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kind'],
      )!,
      aux: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}aux'],
      ),
      hr: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hr'],
      ),
    );
  }

  @override
  $MinuteSamplesTable createAlias(String alias) {
    return $MinuteSamplesTable(attachedDatabase, alias);
  }
}

class MinuteSample extends DataClass implements Insertable<MinuteSample> {
  final int ts;
  final int steps;
  final int intensity;
  final int kind;
  final int? aux;
  final int? hr;
  const MinuteSample({
    required this.ts,
    required this.steps,
    required this.intensity,
    required this.kind,
    this.aux,
    this.hr,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ts'] = Variable<int>(ts);
    map['steps'] = Variable<int>(steps);
    map['intensity'] = Variable<int>(intensity);
    map['kind'] = Variable<int>(kind);
    if (!nullToAbsent || aux != null) {
      map['aux'] = Variable<int>(aux);
    }
    if (!nullToAbsent || hr != null) {
      map['hr'] = Variable<int>(hr);
    }
    return map;
  }

  MinuteSamplesCompanion toCompanion(bool nullToAbsent) {
    return MinuteSamplesCompanion(
      ts: Value(ts),
      steps: Value(steps),
      intensity: Value(intensity),
      kind: Value(kind),
      aux: aux == null && nullToAbsent ? const Value.absent() : Value(aux),
      hr: hr == null && nullToAbsent ? const Value.absent() : Value(hr),
    );
  }

  factory MinuteSample.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MinuteSample(
      ts: serializer.fromJson<int>(json['ts']),
      steps: serializer.fromJson<int>(json['steps']),
      intensity: serializer.fromJson<int>(json['intensity']),
      kind: serializer.fromJson<int>(json['kind']),
      aux: serializer.fromJson<int?>(json['aux']),
      hr: serializer.fromJson<int?>(json['hr']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ts': serializer.toJson<int>(ts),
      'steps': serializer.toJson<int>(steps),
      'intensity': serializer.toJson<int>(intensity),
      'kind': serializer.toJson<int>(kind),
      'aux': serializer.toJson<int?>(aux),
      'hr': serializer.toJson<int?>(hr),
    };
  }

  MinuteSample copyWith({
    int? ts,
    int? steps,
    int? intensity,
    int? kind,
    Value<int?> aux = const Value.absent(),
    Value<int?> hr = const Value.absent(),
  }) => MinuteSample(
    ts: ts ?? this.ts,
    steps: steps ?? this.steps,
    intensity: intensity ?? this.intensity,
    kind: kind ?? this.kind,
    aux: aux.present ? aux.value : this.aux,
    hr: hr.present ? hr.value : this.hr,
  );
  MinuteSample copyWithCompanion(MinuteSamplesCompanion data) {
    return MinuteSample(
      ts: data.ts.present ? data.ts.value : this.ts,
      steps: data.steps.present ? data.steps.value : this.steps,
      intensity: data.intensity.present ? data.intensity.value : this.intensity,
      kind: data.kind.present ? data.kind.value : this.kind,
      aux: data.aux.present ? data.aux.value : this.aux,
      hr: data.hr.present ? data.hr.value : this.hr,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MinuteSample(')
          ..write('ts: $ts, ')
          ..write('steps: $steps, ')
          ..write('intensity: $intensity, ')
          ..write('kind: $kind, ')
          ..write('aux: $aux, ')
          ..write('hr: $hr')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ts, steps, intensity, kind, aux, hr);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MinuteSample &&
          other.ts == this.ts &&
          other.steps == this.steps &&
          other.intensity == this.intensity &&
          other.kind == this.kind &&
          other.aux == this.aux &&
          other.hr == this.hr);
}

class MinuteSamplesCompanion extends UpdateCompanion<MinuteSample> {
  final Value<int> ts;
  final Value<int> steps;
  final Value<int> intensity;
  final Value<int> kind;
  final Value<int?> aux;
  final Value<int?> hr;
  const MinuteSamplesCompanion({
    this.ts = const Value.absent(),
    this.steps = const Value.absent(),
    this.intensity = const Value.absent(),
    this.kind = const Value.absent(),
    this.aux = const Value.absent(),
    this.hr = const Value.absent(),
  });
  MinuteSamplesCompanion.insert({
    this.ts = const Value.absent(),
    required int steps,
    required int intensity,
    required int kind,
    this.aux = const Value.absent(),
    this.hr = const Value.absent(),
  }) : steps = Value(steps),
       intensity = Value(intensity),
       kind = Value(kind);
  static Insertable<MinuteSample> custom({
    Expression<int>? ts,
    Expression<int>? steps,
    Expression<int>? intensity,
    Expression<int>? kind,
    Expression<int>? aux,
    Expression<int>? hr,
  }) {
    return RawValuesInsertable({
      if (ts != null) 'ts': ts,
      if (steps != null) 'steps': steps,
      if (intensity != null) 'intensity': intensity,
      if (kind != null) 'kind': kind,
      if (aux != null) 'aux': aux,
      if (hr != null) 'hr': hr,
    });
  }

  MinuteSamplesCompanion copyWith({
    Value<int>? ts,
    Value<int>? steps,
    Value<int>? intensity,
    Value<int>? kind,
    Value<int?>? aux,
    Value<int?>? hr,
  }) {
    return MinuteSamplesCompanion(
      ts: ts ?? this.ts,
      steps: steps ?? this.steps,
      intensity: intensity ?? this.intensity,
      kind: kind ?? this.kind,
      aux: aux ?? this.aux,
      hr: hr ?? this.hr,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ts.present) {
      map['ts'] = Variable<int>(ts.value);
    }
    if (steps.present) {
      map['steps'] = Variable<int>(steps.value);
    }
    if (intensity.present) {
      map['intensity'] = Variable<int>(intensity.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(kind.value);
    }
    if (aux.present) {
      map['aux'] = Variable<int>(aux.value);
    }
    if (hr.present) {
      map['hr'] = Variable<int>(hr.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MinuteSamplesCompanion(')
          ..write('ts: $ts, ')
          ..write('steps: $steps, ')
          ..write('intensity: $intensity, ')
          ..write('kind: $kind, ')
          ..write('aux: $aux, ')
          ..write('hr: $hr')
          ..write(')'))
        .toString();
  }
}

class $HrLiveTable extends HrLive with TableInfo<$HrLiveTable, HrLiveData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HrLiveTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<int> ts = GeneratedColumn<int>(
    'ts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bpmMeta = const VerificationMeta('bpm');
  @override
  late final GeneratedColumn<int> bpm = GeneratedColumn<int>(
    'bpm',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('band'),
  );
  @override
  List<GeneratedColumn> get $columns => [ts, bpm, source];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hr_live';
  @override
  VerificationContext validateIntegrity(
    Insertable<HrLiveData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    }
    if (data.containsKey('bpm')) {
      context.handle(
        _bpmMeta,
        bpm.isAcceptableOrUnknown(data['bpm']!, _bpmMeta),
      );
    } else if (isInserting) {
      context.missing(_bpmMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ts};
  @override
  HrLiveData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HrLiveData(
      ts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ts'],
      )!,
      bpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bpm'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
    );
  }

  @override
  $HrLiveTable createAlias(String alias) {
    return $HrLiveTable(attachedDatabase, alias);
  }
}

class HrLiveData extends DataClass implements Insertable<HrLiveData> {
  final int ts;
  final int bpm;
  final String source;
  const HrLiveData({required this.ts, required this.bpm, required this.source});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ts'] = Variable<int>(ts);
    map['bpm'] = Variable<int>(bpm);
    map['source'] = Variable<String>(source);
    return map;
  }

  HrLiveCompanion toCompanion(bool nullToAbsent) {
    return HrLiveCompanion(
      ts: Value(ts),
      bpm: Value(bpm),
      source: Value(source),
    );
  }

  factory HrLiveData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HrLiveData(
      ts: serializer.fromJson<int>(json['ts']),
      bpm: serializer.fromJson<int>(json['bpm']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ts': serializer.toJson<int>(ts),
      'bpm': serializer.toJson<int>(bpm),
      'source': serializer.toJson<String>(source),
    };
  }

  HrLiveData copyWith({int? ts, int? bpm, String? source}) => HrLiveData(
    ts: ts ?? this.ts,
    bpm: bpm ?? this.bpm,
    source: source ?? this.source,
  );
  HrLiveData copyWithCompanion(HrLiveCompanion data) {
    return HrLiveData(
      ts: data.ts.present ? data.ts.value : this.ts,
      bpm: data.bpm.present ? data.bpm.value : this.bpm,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HrLiveData(')
          ..write('ts: $ts, ')
          ..write('bpm: $bpm, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ts, bpm, source);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HrLiveData &&
          other.ts == this.ts &&
          other.bpm == this.bpm &&
          other.source == this.source);
}

class HrLiveCompanion extends UpdateCompanion<HrLiveData> {
  final Value<int> ts;
  final Value<int> bpm;
  final Value<String> source;
  const HrLiveCompanion({
    this.ts = const Value.absent(),
    this.bpm = const Value.absent(),
    this.source = const Value.absent(),
  });
  HrLiveCompanion.insert({
    this.ts = const Value.absent(),
    required int bpm,
    this.source = const Value.absent(),
  }) : bpm = Value(bpm);
  static Insertable<HrLiveData> custom({
    Expression<int>? ts,
    Expression<int>? bpm,
    Expression<String>? source,
  }) {
    return RawValuesInsertable({
      if (ts != null) 'ts': ts,
      if (bpm != null) 'bpm': bpm,
      if (source != null) 'source': source,
    });
  }

  HrLiveCompanion copyWith({
    Value<int>? ts,
    Value<int>? bpm,
    Value<String>? source,
  }) {
    return HrLiveCompanion(
      ts: ts ?? this.ts,
      bpm: bpm ?? this.bpm,
      source: source ?? this.source,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ts.present) {
      map['ts'] = Variable<int>(ts.value);
    }
    if (bpm.present) {
      map['bpm'] = Variable<int>(bpm.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HrLiveCompanion(')
          ..write('ts: $ts, ')
          ..write('bpm: $bpm, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }
}

class $StressSamplesTable extends StressSamples
    with TableInfo<$StressSamplesTable, StressSample> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StressSamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<int> ts = GeneratedColumn<int>(
    'ts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<int> value = GeneratedColumn<int>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [ts, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stress_samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<StressSample> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ts};
  @override
  StressSample map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StressSample(
      ts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ts'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $StressSamplesTable createAlias(String alias) {
    return $StressSamplesTable(attachedDatabase, alias);
  }
}

class StressSample extends DataClass implements Insertable<StressSample> {
  final int ts;
  final int value;
  const StressSample({required this.ts, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ts'] = Variable<int>(ts);
    map['value'] = Variable<int>(value);
    return map;
  }

  StressSamplesCompanion toCompanion(bool nullToAbsent) {
    return StressSamplesCompanion(ts: Value(ts), value: Value(value));
  }

  factory StressSample.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StressSample(
      ts: serializer.fromJson<int>(json['ts']),
      value: serializer.fromJson<int>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ts': serializer.toJson<int>(ts),
      'value': serializer.toJson<int>(value),
    };
  }

  StressSample copyWith({int? ts, int? value}) =>
      StressSample(ts: ts ?? this.ts, value: value ?? this.value);
  StressSample copyWithCompanion(StressSamplesCompanion data) {
    return StressSample(
      ts: data.ts.present ? data.ts.value : this.ts,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StressSample(')
          ..write('ts: $ts, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ts, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StressSample &&
          other.ts == this.ts &&
          other.value == this.value);
}

class StressSamplesCompanion extends UpdateCompanion<StressSample> {
  final Value<int> ts;
  final Value<int> value;
  const StressSamplesCompanion({
    this.ts = const Value.absent(),
    this.value = const Value.absent(),
  });
  StressSamplesCompanion.insert({
    this.ts = const Value.absent(),
    required int value,
  }) : value = Value(value);
  static Insertable<StressSample> custom({
    Expression<int>? ts,
    Expression<int>? value,
  }) {
    return RawValuesInsertable({
      if (ts != null) 'ts': ts,
      if (value != null) 'value': value,
    });
  }

  StressSamplesCompanion copyWith({Value<int>? ts, Value<int>? value}) {
    return StressSamplesCompanion(
      ts: ts ?? this.ts,
      value: value ?? this.value,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ts.present) {
      map['ts'] = Variable<int>(ts.value);
    }
    if (value.present) {
      map['value'] = Variable<int>(value.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StressSamplesCompanion(')
          ..write('ts: $ts, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }
}

class $Spo2SamplesTable extends Spo2Samples
    with TableInfo<$Spo2SamplesTable, Spo2Sample> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Spo2SamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<int> ts = GeneratedColumn<int>(
    'ts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<int> value = GeneratedColumn<int>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _qualityMeta = const VerificationMeta(
    'quality',
  );
  @override
  late final GeneratedColumn<int> quality = GeneratedColumn<int>(
    'quality',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [ts, value, quality];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'spo2_samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<Spo2Sample> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('quality')) {
      context.handle(
        _qualityMeta,
        quality.isAcceptableOrUnknown(data['quality']!, _qualityMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ts};
  @override
  Spo2Sample map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Spo2Sample(
      ts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ts'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value'],
      )!,
      quality: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quality'],
      ),
    );
  }

  @override
  $Spo2SamplesTable createAlias(String alias) {
    return $Spo2SamplesTable(attachedDatabase, alias);
  }
}

class Spo2Sample extends DataClass implements Insertable<Spo2Sample> {
  final int ts;
  final int value;
  final int? quality;
  const Spo2Sample({required this.ts, required this.value, this.quality});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ts'] = Variable<int>(ts);
    map['value'] = Variable<int>(value);
    if (!nullToAbsent || quality != null) {
      map['quality'] = Variable<int>(quality);
    }
    return map;
  }

  Spo2SamplesCompanion toCompanion(bool nullToAbsent) {
    return Spo2SamplesCompanion(
      ts: Value(ts),
      value: Value(value),
      quality: quality == null && nullToAbsent
          ? const Value.absent()
          : Value(quality),
    );
  }

  factory Spo2Sample.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Spo2Sample(
      ts: serializer.fromJson<int>(json['ts']),
      value: serializer.fromJson<int>(json['value']),
      quality: serializer.fromJson<int?>(json['quality']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ts': serializer.toJson<int>(ts),
      'value': serializer.toJson<int>(value),
      'quality': serializer.toJson<int?>(quality),
    };
  }

  Spo2Sample copyWith({
    int? ts,
    int? value,
    Value<int?> quality = const Value.absent(),
  }) => Spo2Sample(
    ts: ts ?? this.ts,
    value: value ?? this.value,
    quality: quality.present ? quality.value : this.quality,
  );
  Spo2Sample copyWithCompanion(Spo2SamplesCompanion data) {
    return Spo2Sample(
      ts: data.ts.present ? data.ts.value : this.ts,
      value: data.value.present ? data.value.value : this.value,
      quality: data.quality.present ? data.quality.value : this.quality,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Spo2Sample(')
          ..write('ts: $ts, ')
          ..write('value: $value, ')
          ..write('quality: $quality')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ts, value, quality);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Spo2Sample &&
          other.ts == this.ts &&
          other.value == this.value &&
          other.quality == this.quality);
}

class Spo2SamplesCompanion extends UpdateCompanion<Spo2Sample> {
  final Value<int> ts;
  final Value<int> value;
  final Value<int?> quality;
  const Spo2SamplesCompanion({
    this.ts = const Value.absent(),
    this.value = const Value.absent(),
    this.quality = const Value.absent(),
  });
  Spo2SamplesCompanion.insert({
    this.ts = const Value.absent(),
    required int value,
    this.quality = const Value.absent(),
  }) : value = Value(value);
  static Insertable<Spo2Sample> custom({
    Expression<int>? ts,
    Expression<int>? value,
    Expression<int>? quality,
  }) {
    return RawValuesInsertable({
      if (ts != null) 'ts': ts,
      if (value != null) 'value': value,
      if (quality != null) 'quality': quality,
    });
  }

  Spo2SamplesCompanion copyWith({
    Value<int>? ts,
    Value<int>? value,
    Value<int?>? quality,
  }) {
    return Spo2SamplesCompanion(
      ts: ts ?? this.ts,
      value: value ?? this.value,
      quality: quality ?? this.quality,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ts.present) {
      map['ts'] = Variable<int>(ts.value);
    }
    if (value.present) {
      map['value'] = Variable<int>(value.value);
    }
    if (quality.present) {
      map['quality'] = Variable<int>(quality.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Spo2SamplesCompanion(')
          ..write('ts: $ts, ')
          ..write('value: $value, ')
          ..write('quality: $quality')
          ..write(')'))
        .toString();
  }
}

class $BandWorkoutsTable extends BandWorkouts
    with TableInfo<$BandWorkoutsTable, BandWorkoutRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BandWorkoutsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _startMeta = const VerificationMeta('start');
  @override
  late final GeneratedColumn<int> start = GeneratedColumn<int>(
    'start',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endMeta = const VerificationMeta('end');
  @override
  late final GeneratedColumn<int> end = GeneratedColumn<int>(
    'end',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<int> kind = GeneratedColumn<int>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawMeta = const VerificationMeta('raw');
  @override
  late final GeneratedColumn<String> raw = GeneratedColumn<String>(
    'raw',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [start, end, kind, raw, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'band_workouts';
  @override
  VerificationContext validateIntegrity(
    Insertable<BandWorkoutRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('start')) {
      context.handle(
        _startMeta,
        start.isAcceptableOrUnknown(data['start']!, _startMeta),
      );
    }
    if (data.containsKey('end')) {
      context.handle(
        _endMeta,
        end.isAcceptableOrUnknown(data['end']!, _endMeta),
      );
    } else if (isInserting) {
      context.missing(_endMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('raw')) {
      context.handle(
        _rawMeta,
        raw.isAcceptableOrUnknown(data['raw']!, _rawMeta),
      );
    } else if (isInserting) {
      context.missing(_rawMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {start};
  @override
  BandWorkoutRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BandWorkoutRow(
      start: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start'],
      )!,
      end: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kind'],
      )!,
      raw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $BandWorkoutsTable createAlias(String alias) {
    return $BandWorkoutsTable(attachedDatabase, alias);
  }
}

class BandWorkoutRow extends DataClass implements Insertable<BandWorkoutRow> {
  final int start;
  final int end;
  final int kind;
  final String raw;
  final int fetchedAt;
  const BandWorkoutRow({
    required this.start,
    required this.end,
    required this.kind,
    required this.raw,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['start'] = Variable<int>(start);
    map['end'] = Variable<int>(end);
    map['kind'] = Variable<int>(kind);
    map['raw'] = Variable<String>(raw);
    map['fetched_at'] = Variable<int>(fetchedAt);
    return map;
  }

  BandWorkoutsCompanion toCompanion(bool nullToAbsent) {
    return BandWorkoutsCompanion(
      start: Value(start),
      end: Value(end),
      kind: Value(kind),
      raw: Value(raw),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory BandWorkoutRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BandWorkoutRow(
      start: serializer.fromJson<int>(json['start']),
      end: serializer.fromJson<int>(json['end']),
      kind: serializer.fromJson<int>(json['kind']),
      raw: serializer.fromJson<String>(json['raw']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'start': serializer.toJson<int>(start),
      'end': serializer.toJson<int>(end),
      'kind': serializer.toJson<int>(kind),
      'raw': serializer.toJson<String>(raw),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
    };
  }

  BandWorkoutRow copyWith({
    int? start,
    int? end,
    int? kind,
    String? raw,
    int? fetchedAt,
  }) => BandWorkoutRow(
    start: start ?? this.start,
    end: end ?? this.end,
    kind: kind ?? this.kind,
    raw: raw ?? this.raw,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  BandWorkoutRow copyWithCompanion(BandWorkoutsCompanion data) {
    return BandWorkoutRow(
      start: data.start.present ? data.start.value : this.start,
      end: data.end.present ? data.end.value : this.end,
      kind: data.kind.present ? data.kind.value : this.kind,
      raw: data.raw.present ? data.raw.value : this.raw,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BandWorkoutRow(')
          ..write('start: $start, ')
          ..write('end: $end, ')
          ..write('kind: $kind, ')
          ..write('raw: $raw, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(start, end, kind, raw, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BandWorkoutRow &&
          other.start == this.start &&
          other.end == this.end &&
          other.kind == this.kind &&
          other.raw == this.raw &&
          other.fetchedAt == this.fetchedAt);
}

class BandWorkoutsCompanion extends UpdateCompanion<BandWorkoutRow> {
  final Value<int> start;
  final Value<int> end;
  final Value<int> kind;
  final Value<String> raw;
  final Value<int> fetchedAt;
  const BandWorkoutsCompanion({
    this.start = const Value.absent(),
    this.end = const Value.absent(),
    this.kind = const Value.absent(),
    this.raw = const Value.absent(),
    this.fetchedAt = const Value.absent(),
  });
  BandWorkoutsCompanion.insert({
    this.start = const Value.absent(),
    required int end,
    required int kind,
    required String raw,
    required int fetchedAt,
  }) : end = Value(end),
       kind = Value(kind),
       raw = Value(raw),
       fetchedAt = Value(fetchedAt);
  static Insertable<BandWorkoutRow> custom({
    Expression<int>? start,
    Expression<int>? end,
    Expression<int>? kind,
    Expression<String>? raw,
    Expression<int>? fetchedAt,
  }) {
    return RawValuesInsertable({
      if (start != null) 'start': start,
      if (end != null) 'end': end,
      if (kind != null) 'kind': kind,
      if (raw != null) 'raw': raw,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
    });
  }

  BandWorkoutsCompanion copyWith({
    Value<int>? start,
    Value<int>? end,
    Value<int>? kind,
    Value<String>? raw,
    Value<int>? fetchedAt,
  }) {
    return BandWorkoutsCompanion(
      start: start ?? this.start,
      end: end ?? this.end,
      kind: kind ?? this.kind,
      raw: raw ?? this.raw,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (start.present) {
      map['start'] = Variable<int>(start.value);
    }
    if (end.present) {
      map['end'] = Variable<int>(end.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(kind.value);
    }
    if (raw.present) {
      map['raw'] = Variable<String>(raw.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BandWorkoutsCompanion(')
          ..write('start: $start, ')
          ..write('end: $end, ')
          ..write('kind: $kind, ')
          ..write('raw: $raw, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }
}

class $OdEventsTable extends OdEvents
    with TableInfo<$OdEventsTable, OdEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OdEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<int> ts = GeneratedColumn<int>(
    'ts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dropMeta = const VerificationMeta('drop');
  @override
  late final GeneratedColumn<int> drop = GeneratedColumn<int>(
    'drop',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _spo2Meta = const VerificationMeta('spo2');
  @override
  late final GeneratedColumn<String> spo2 = GeneratedColumn<String>(
    'spo2',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hrMeta = const VerificationMeta('hr');
  @override
  late final GeneratedColumn<String> hr = GeneratedColumn<String>(
    'hr',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [ts, drop, spo2, hr];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'od_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<OdEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    }
    if (data.containsKey('drop')) {
      context.handle(
        _dropMeta,
        drop.isAcceptableOrUnknown(data['drop']!, _dropMeta),
      );
    } else if (isInserting) {
      context.missing(_dropMeta);
    }
    if (data.containsKey('spo2')) {
      context.handle(
        _spo2Meta,
        spo2.isAcceptableOrUnknown(data['spo2']!, _spo2Meta),
      );
    } else if (isInserting) {
      context.missing(_spo2Meta);
    }
    if (data.containsKey('hr')) {
      context.handle(_hrMeta, hr.isAcceptableOrUnknown(data['hr']!, _hrMeta));
    } else if (isInserting) {
      context.missing(_hrMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ts};
  @override
  OdEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OdEventRow(
      ts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ts'],
      )!,
      drop: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}drop'],
      )!,
      spo2: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}spo2'],
      )!,
      hr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hr'],
      )!,
    );
  }

  @override
  $OdEventsTable createAlias(String alias) {
    return $OdEventsTable(attachedDatabase, alias);
  }
}

class OdEventRow extends DataClass implements Insertable<OdEventRow> {
  final int ts;
  final int drop;
  final String spo2;
  final String hr;
  const OdEventRow({
    required this.ts,
    required this.drop,
    required this.spo2,
    required this.hr,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ts'] = Variable<int>(ts);
    map['drop'] = Variable<int>(drop);
    map['spo2'] = Variable<String>(spo2);
    map['hr'] = Variable<String>(hr);
    return map;
  }

  OdEventsCompanion toCompanion(bool nullToAbsent) {
    return OdEventsCompanion(
      ts: Value(ts),
      drop: Value(drop),
      spo2: Value(spo2),
      hr: Value(hr),
    );
  }

  factory OdEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OdEventRow(
      ts: serializer.fromJson<int>(json['ts']),
      drop: serializer.fromJson<int>(json['drop']),
      spo2: serializer.fromJson<String>(json['spo2']),
      hr: serializer.fromJson<String>(json['hr']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ts': serializer.toJson<int>(ts),
      'drop': serializer.toJson<int>(drop),
      'spo2': serializer.toJson<String>(spo2),
      'hr': serializer.toJson<String>(hr),
    };
  }

  OdEventRow copyWith({int? ts, int? drop, String? spo2, String? hr}) =>
      OdEventRow(
        ts: ts ?? this.ts,
        drop: drop ?? this.drop,
        spo2: spo2 ?? this.spo2,
        hr: hr ?? this.hr,
      );
  OdEventRow copyWithCompanion(OdEventsCompanion data) {
    return OdEventRow(
      ts: data.ts.present ? data.ts.value : this.ts,
      drop: data.drop.present ? data.drop.value : this.drop,
      spo2: data.spo2.present ? data.spo2.value : this.spo2,
      hr: data.hr.present ? data.hr.value : this.hr,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OdEventRow(')
          ..write('ts: $ts, ')
          ..write('drop: $drop, ')
          ..write('spo2: $spo2, ')
          ..write('hr: $hr')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ts, drop, spo2, hr);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OdEventRow &&
          other.ts == this.ts &&
          other.drop == this.drop &&
          other.spo2 == this.spo2 &&
          other.hr == this.hr);
}

class OdEventsCompanion extends UpdateCompanion<OdEventRow> {
  final Value<int> ts;
  final Value<int> drop;
  final Value<String> spo2;
  final Value<String> hr;
  const OdEventsCompanion({
    this.ts = const Value.absent(),
    this.drop = const Value.absent(),
    this.spo2 = const Value.absent(),
    this.hr = const Value.absent(),
  });
  OdEventsCompanion.insert({
    this.ts = const Value.absent(),
    required int drop,
    required String spo2,
    required String hr,
  }) : drop = Value(drop),
       spo2 = Value(spo2),
       hr = Value(hr);
  static Insertable<OdEventRow> custom({
    Expression<int>? ts,
    Expression<int>? drop,
    Expression<String>? spo2,
    Expression<String>? hr,
  }) {
    return RawValuesInsertable({
      if (ts != null) 'ts': ts,
      if (drop != null) 'drop': drop,
      if (spo2 != null) 'spo2': spo2,
      if (hr != null) 'hr': hr,
    });
  }

  OdEventsCompanion copyWith({
    Value<int>? ts,
    Value<int>? drop,
    Value<String>? spo2,
    Value<String>? hr,
  }) {
    return OdEventsCompanion(
      ts: ts ?? this.ts,
      drop: drop ?? this.drop,
      spo2: spo2 ?? this.spo2,
      hr: hr ?? this.hr,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ts.present) {
      map['ts'] = Variable<int>(ts.value);
    }
    if (drop.present) {
      map['drop'] = Variable<int>(drop.value);
    }
    if (spo2.present) {
      map['spo2'] = Variable<String>(spo2.value);
    }
    if (hr.present) {
      map['hr'] = Variable<String>(hr.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OdEventsCompanion(')
          ..write('ts: $ts, ')
          ..write('drop: $drop, ')
          ..write('spo2: $spo2, ')
          ..write('hr: $hr')
          ..write(')'))
        .toString();
  }
}

class $SleepSessionsTable extends SleepSessions
    with TableInfo<$SleepSessionsTable, SleepSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SleepSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _startMeta = const VerificationMeta('start');
  @override
  late final GeneratedColumn<int> start = GeneratedColumn<int>(
    'start',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endMeta = const VerificationMeta('end');
  @override
  late final GeneratedColumn<int> end = GeneratedColumn<int>(
    'end',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stagesMeta = const VerificationMeta('stages');
  @override
  late final GeneratedColumn<String> stages = GeneratedColumn<String>(
    'stages',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _algoVersionMeta = const VerificationMeta(
    'algoVersion',
  );
  @override
  late final GeneratedColumn<int> algoVersion = GeneratedColumn<int>(
    'algo_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, start, end, stages, algoVersion];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sleep_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SleepSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('start')) {
      context.handle(
        _startMeta,
        start.isAcceptableOrUnknown(data['start']!, _startMeta),
      );
    } else if (isInserting) {
      context.missing(_startMeta);
    }
    if (data.containsKey('end')) {
      context.handle(
        _endMeta,
        end.isAcceptableOrUnknown(data['end']!, _endMeta),
      );
    } else if (isInserting) {
      context.missing(_endMeta);
    }
    if (data.containsKey('stages')) {
      context.handle(
        _stagesMeta,
        stages.isAcceptableOrUnknown(data['stages']!, _stagesMeta),
      );
    } else if (isInserting) {
      context.missing(_stagesMeta);
    }
    if (data.containsKey('algo_version')) {
      context.handle(
        _algoVersionMeta,
        algoVersion.isAcceptableOrUnknown(
          data['algo_version']!,
          _algoVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_algoVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SleepSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SleepSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      start: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start'],
      )!,
      end: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end'],
      )!,
      stages: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stages'],
      )!,
      algoVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}algo_version'],
      )!,
    );
  }

  @override
  $SleepSessionsTable createAlias(String alias) {
    return $SleepSessionsTable(attachedDatabase, alias);
  }
}

class SleepSession extends DataClass implements Insertable<SleepSession> {
  final int id;
  final int start;
  final int end;
  final String stages;
  final int algoVersion;
  const SleepSession({
    required this.id,
    required this.start,
    required this.end,
    required this.stages,
    required this.algoVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['start'] = Variable<int>(start);
    map['end'] = Variable<int>(end);
    map['stages'] = Variable<String>(stages);
    map['algo_version'] = Variable<int>(algoVersion);
    return map;
  }

  SleepSessionsCompanion toCompanion(bool nullToAbsent) {
    return SleepSessionsCompanion(
      id: Value(id),
      start: Value(start),
      end: Value(end),
      stages: Value(stages),
      algoVersion: Value(algoVersion),
    );
  }

  factory SleepSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SleepSession(
      id: serializer.fromJson<int>(json['id']),
      start: serializer.fromJson<int>(json['start']),
      end: serializer.fromJson<int>(json['end']),
      stages: serializer.fromJson<String>(json['stages']),
      algoVersion: serializer.fromJson<int>(json['algoVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'start': serializer.toJson<int>(start),
      'end': serializer.toJson<int>(end),
      'stages': serializer.toJson<String>(stages),
      'algoVersion': serializer.toJson<int>(algoVersion),
    };
  }

  SleepSession copyWith({
    int? id,
    int? start,
    int? end,
    String? stages,
    int? algoVersion,
  }) => SleepSession(
    id: id ?? this.id,
    start: start ?? this.start,
    end: end ?? this.end,
    stages: stages ?? this.stages,
    algoVersion: algoVersion ?? this.algoVersion,
  );
  SleepSession copyWithCompanion(SleepSessionsCompanion data) {
    return SleepSession(
      id: data.id.present ? data.id.value : this.id,
      start: data.start.present ? data.start.value : this.start,
      end: data.end.present ? data.end.value : this.end,
      stages: data.stages.present ? data.stages.value : this.stages,
      algoVersion: data.algoVersion.present
          ? data.algoVersion.value
          : this.algoVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SleepSession(')
          ..write('id: $id, ')
          ..write('start: $start, ')
          ..write('end: $end, ')
          ..write('stages: $stages, ')
          ..write('algoVersion: $algoVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, start, end, stages, algoVersion);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SleepSession &&
          other.id == this.id &&
          other.start == this.start &&
          other.end == this.end &&
          other.stages == this.stages &&
          other.algoVersion == this.algoVersion);
}

class SleepSessionsCompanion extends UpdateCompanion<SleepSession> {
  final Value<int> id;
  final Value<int> start;
  final Value<int> end;
  final Value<String> stages;
  final Value<int> algoVersion;
  const SleepSessionsCompanion({
    this.id = const Value.absent(),
    this.start = const Value.absent(),
    this.end = const Value.absent(),
    this.stages = const Value.absent(),
    this.algoVersion = const Value.absent(),
  });
  SleepSessionsCompanion.insert({
    this.id = const Value.absent(),
    required int start,
    required int end,
    required String stages,
    required int algoVersion,
  }) : start = Value(start),
       end = Value(end),
       stages = Value(stages),
       algoVersion = Value(algoVersion);
  static Insertable<SleepSession> custom({
    Expression<int>? id,
    Expression<int>? start,
    Expression<int>? end,
    Expression<String>? stages,
    Expression<int>? algoVersion,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (start != null) 'start': start,
      if (end != null) 'end': end,
      if (stages != null) 'stages': stages,
      if (algoVersion != null) 'algo_version': algoVersion,
    });
  }

  SleepSessionsCompanion copyWith({
    Value<int>? id,
    Value<int>? start,
    Value<int>? end,
    Value<String>? stages,
    Value<int>? algoVersion,
  }) {
    return SleepSessionsCompanion(
      id: id ?? this.id,
      start: start ?? this.start,
      end: end ?? this.end,
      stages: stages ?? this.stages,
      algoVersion: algoVersion ?? this.algoVersion,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (start.present) {
      map['start'] = Variable<int>(start.value);
    }
    if (end.present) {
      map['end'] = Variable<int>(end.value);
    }
    if (stages.present) {
      map['stages'] = Variable<String>(stages.value);
    }
    if (algoVersion.present) {
      map['algo_version'] = Variable<int>(algoVersion.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SleepSessionsCompanion(')
          ..write('id: $id, ')
          ..write('start: $start, ')
          ..write('end: $end, ')
          ..write('stages: $stages, ')
          ..write('algoVersion: $algoVersion')
          ..write(')'))
        .toString();
  }
}

class $DailyScoresTable extends DailyScores
    with TableInfo<$DailyScoresTable, DailyScore> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyScoresTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _strainMeta = const VerificationMeta('strain');
  @override
  late final GeneratedColumn<double> strain = GeneratedColumn<double>(
    'strain',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trimpMeta = const VerificationMeta('trimp');
  @override
  late final GeneratedColumn<double> trimp = GeneratedColumn<double>(
    'trimp',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hrMaxMeta = const VerificationMeta('hrMax');
  @override
  late final GeneratedColumn<int> hrMax = GeneratedColumn<int>(
    'hr_max',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sleepPerfMeta = const VerificationMeta(
    'sleepPerf',
  );
  @override
  late final GeneratedColumn<double> sleepPerf = GeneratedColumn<double>(
    'sleep_perf',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sleptHoursMeta = const VerificationMeta(
    'sleptHours',
  );
  @override
  late final GeneratedColumn<double> sleptHours = GeneratedColumn<double>(
    'slept_hours',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _needHoursMeta = const VerificationMeta(
    'needHours',
  );
  @override
  late final GeneratedColumn<double> needHours = GeneratedColumn<double>(
    'need_hours',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _napHoursMeta = const VerificationMeta(
    'napHours',
  );
  @override
  late final GeneratedColumn<double> napHours = GeneratedColumn<double>(
    'nap_hours',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _baseNeedMeta = const VerificationMeta(
    'baseNeed',
  );
  @override
  late final GeneratedColumn<double> baseNeed = GeneratedColumn<double>(
    'base_need',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sleepStartMeta = const VerificationMeta(
    'sleepStart',
  );
  @override
  late final GeneratedColumn<int> sleepStart = GeneratedColumn<int>(
    'sleep_start',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sleepEndMeta = const VerificationMeta(
    'sleepEnd',
  );
  @override
  late final GeneratedColumn<int> sleepEnd = GeneratedColumn<int>(
    'sleep_end',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recoveryMeta = const VerificationMeta(
    'recovery',
  );
  @override
  late final GeneratedColumn<double> recovery = GeneratedColumn<double>(
    'recovery',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rhrMeta = const VerificationMeta('rhr');
  @override
  late final GeneratedColumn<double> rhr = GeneratedColumn<double>(
    'rhr',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hrvProxyMeta = const VerificationMeta(
    'hrvProxy',
  );
  @override
  late final GeneratedColumn<double> hrvProxy = GeneratedColumn<double>(
    'hrv_proxy',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _calibratingMeta = const VerificationMeta(
    'calibrating',
  );
  @override
  late final GeneratedColumn<bool> calibrating = GeneratedColumn<bool>(
    'calibrating',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("calibrating" IN (0, 1))',
    ),
  );
  static const VerificationMeta _algoVersionMeta = const VerificationMeta(
    'algoVersion',
  );
  @override
  late final GeneratedColumn<int> algoVersion = GeneratedColumn<int>(
    'algo_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    date,
    strain,
    trimp,
    hrMax,
    sleepPerf,
    sleptHours,
    needHours,
    napHours,
    baseNeed,
    sleepStart,
    sleepEnd,
    recovery,
    rhr,
    hrvProxy,
    calibrating,
    algoVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_scores';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyScore> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('strain')) {
      context.handle(
        _strainMeta,
        strain.isAcceptableOrUnknown(data['strain']!, _strainMeta),
      );
    } else if (isInserting) {
      context.missing(_strainMeta);
    }
    if (data.containsKey('trimp')) {
      context.handle(
        _trimpMeta,
        trimp.isAcceptableOrUnknown(data['trimp']!, _trimpMeta),
      );
    } else if (isInserting) {
      context.missing(_trimpMeta);
    }
    if (data.containsKey('hr_max')) {
      context.handle(
        _hrMaxMeta,
        hrMax.isAcceptableOrUnknown(data['hr_max']!, _hrMaxMeta),
      );
    } else if (isInserting) {
      context.missing(_hrMaxMeta);
    }
    if (data.containsKey('sleep_perf')) {
      context.handle(
        _sleepPerfMeta,
        sleepPerf.isAcceptableOrUnknown(data['sleep_perf']!, _sleepPerfMeta),
      );
    }
    if (data.containsKey('slept_hours')) {
      context.handle(
        _sleptHoursMeta,
        sleptHours.isAcceptableOrUnknown(data['slept_hours']!, _sleptHoursMeta),
      );
    }
    if (data.containsKey('need_hours')) {
      context.handle(
        _needHoursMeta,
        needHours.isAcceptableOrUnknown(data['need_hours']!, _needHoursMeta),
      );
    }
    if (data.containsKey('nap_hours')) {
      context.handle(
        _napHoursMeta,
        napHours.isAcceptableOrUnknown(data['nap_hours']!, _napHoursMeta),
      );
    }
    if (data.containsKey('base_need')) {
      context.handle(
        _baseNeedMeta,
        baseNeed.isAcceptableOrUnknown(data['base_need']!, _baseNeedMeta),
      );
    }
    if (data.containsKey('sleep_start')) {
      context.handle(
        _sleepStartMeta,
        sleepStart.isAcceptableOrUnknown(data['sleep_start']!, _sleepStartMeta),
      );
    }
    if (data.containsKey('sleep_end')) {
      context.handle(
        _sleepEndMeta,
        sleepEnd.isAcceptableOrUnknown(data['sleep_end']!, _sleepEndMeta),
      );
    }
    if (data.containsKey('recovery')) {
      context.handle(
        _recoveryMeta,
        recovery.isAcceptableOrUnknown(data['recovery']!, _recoveryMeta),
      );
    }
    if (data.containsKey('rhr')) {
      context.handle(
        _rhrMeta,
        rhr.isAcceptableOrUnknown(data['rhr']!, _rhrMeta),
      );
    }
    if (data.containsKey('hrv_proxy')) {
      context.handle(
        _hrvProxyMeta,
        hrvProxy.isAcceptableOrUnknown(data['hrv_proxy']!, _hrvProxyMeta),
      );
    }
    if (data.containsKey('calibrating')) {
      context.handle(
        _calibratingMeta,
        calibrating.isAcceptableOrUnknown(
          data['calibrating']!,
          _calibratingMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_calibratingMeta);
    }
    if (data.containsKey('algo_version')) {
      context.handle(
        _algoVersionMeta,
        algoVersion.isAcceptableOrUnknown(
          data['algo_version']!,
          _algoVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_algoVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date};
  @override
  DailyScore map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyScore(
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      strain: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}strain'],
      )!,
      trimp: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}trimp'],
      )!,
      hrMax: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hr_max'],
      )!,
      sleepPerf: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sleep_perf'],
      ),
      sleptHours: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}slept_hours'],
      ),
      needHours: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}need_hours'],
      ),
      napHours: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}nap_hours'],
      )!,
      baseNeed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}base_need'],
      ),
      sleepStart: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sleep_start'],
      ),
      sleepEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sleep_end'],
      ),
      recovery: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}recovery'],
      ),
      rhr: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rhr'],
      ),
      hrvProxy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}hrv_proxy'],
      ),
      calibrating: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}calibrating'],
      )!,
      algoVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}algo_version'],
      )!,
    );
  }

  @override
  $DailyScoresTable createAlias(String alias) {
    return $DailyScoresTable(attachedDatabase, alias);
  }
}

class DailyScore extends DataClass implements Insertable<DailyScore> {
  final String date;
  final double strain;
  final double trimp;
  final int hrMax;
  final double? sleepPerf;
  final double? sleptHours;
  final double? needHours;
  final double napHours;
  final double? baseNeed;
  final int? sleepStart;
  final int? sleepEnd;
  final double? recovery;
  final double? rhr;
  final double? hrvProxy;
  final bool calibrating;
  final int algoVersion;
  const DailyScore({
    required this.date,
    required this.strain,
    required this.trimp,
    required this.hrMax,
    this.sleepPerf,
    this.sleptHours,
    this.needHours,
    required this.napHours,
    this.baseNeed,
    this.sleepStart,
    this.sleepEnd,
    this.recovery,
    this.rhr,
    this.hrvProxy,
    required this.calibrating,
    required this.algoVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['strain'] = Variable<double>(strain);
    map['trimp'] = Variable<double>(trimp);
    map['hr_max'] = Variable<int>(hrMax);
    if (!nullToAbsent || sleepPerf != null) {
      map['sleep_perf'] = Variable<double>(sleepPerf);
    }
    if (!nullToAbsent || sleptHours != null) {
      map['slept_hours'] = Variable<double>(sleptHours);
    }
    if (!nullToAbsent || needHours != null) {
      map['need_hours'] = Variable<double>(needHours);
    }
    map['nap_hours'] = Variable<double>(napHours);
    if (!nullToAbsent || baseNeed != null) {
      map['base_need'] = Variable<double>(baseNeed);
    }
    if (!nullToAbsent || sleepStart != null) {
      map['sleep_start'] = Variable<int>(sleepStart);
    }
    if (!nullToAbsent || sleepEnd != null) {
      map['sleep_end'] = Variable<int>(sleepEnd);
    }
    if (!nullToAbsent || recovery != null) {
      map['recovery'] = Variable<double>(recovery);
    }
    if (!nullToAbsent || rhr != null) {
      map['rhr'] = Variable<double>(rhr);
    }
    if (!nullToAbsent || hrvProxy != null) {
      map['hrv_proxy'] = Variable<double>(hrvProxy);
    }
    map['calibrating'] = Variable<bool>(calibrating);
    map['algo_version'] = Variable<int>(algoVersion);
    return map;
  }

  DailyScoresCompanion toCompanion(bool nullToAbsent) {
    return DailyScoresCompanion(
      date: Value(date),
      strain: Value(strain),
      trimp: Value(trimp),
      hrMax: Value(hrMax),
      sleepPerf: sleepPerf == null && nullToAbsent
          ? const Value.absent()
          : Value(sleepPerf),
      sleptHours: sleptHours == null && nullToAbsent
          ? const Value.absent()
          : Value(sleptHours),
      needHours: needHours == null && nullToAbsent
          ? const Value.absent()
          : Value(needHours),
      napHours: Value(napHours),
      baseNeed: baseNeed == null && nullToAbsent
          ? const Value.absent()
          : Value(baseNeed),
      sleepStart: sleepStart == null && nullToAbsent
          ? const Value.absent()
          : Value(sleepStart),
      sleepEnd: sleepEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(sleepEnd),
      recovery: recovery == null && nullToAbsent
          ? const Value.absent()
          : Value(recovery),
      rhr: rhr == null && nullToAbsent ? const Value.absent() : Value(rhr),
      hrvProxy: hrvProxy == null && nullToAbsent
          ? const Value.absent()
          : Value(hrvProxy),
      calibrating: Value(calibrating),
      algoVersion: Value(algoVersion),
    );
  }

  factory DailyScore.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyScore(
      date: serializer.fromJson<String>(json['date']),
      strain: serializer.fromJson<double>(json['strain']),
      trimp: serializer.fromJson<double>(json['trimp']),
      hrMax: serializer.fromJson<int>(json['hrMax']),
      sleepPerf: serializer.fromJson<double?>(json['sleepPerf']),
      sleptHours: serializer.fromJson<double?>(json['sleptHours']),
      needHours: serializer.fromJson<double?>(json['needHours']),
      napHours: serializer.fromJson<double>(json['napHours']),
      baseNeed: serializer.fromJson<double?>(json['baseNeed']),
      sleepStart: serializer.fromJson<int?>(json['sleepStart']),
      sleepEnd: serializer.fromJson<int?>(json['sleepEnd']),
      recovery: serializer.fromJson<double?>(json['recovery']),
      rhr: serializer.fromJson<double?>(json['rhr']),
      hrvProxy: serializer.fromJson<double?>(json['hrvProxy']),
      calibrating: serializer.fromJson<bool>(json['calibrating']),
      algoVersion: serializer.fromJson<int>(json['algoVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'strain': serializer.toJson<double>(strain),
      'trimp': serializer.toJson<double>(trimp),
      'hrMax': serializer.toJson<int>(hrMax),
      'sleepPerf': serializer.toJson<double?>(sleepPerf),
      'sleptHours': serializer.toJson<double?>(sleptHours),
      'needHours': serializer.toJson<double?>(needHours),
      'napHours': serializer.toJson<double>(napHours),
      'baseNeed': serializer.toJson<double?>(baseNeed),
      'sleepStart': serializer.toJson<int?>(sleepStart),
      'sleepEnd': serializer.toJson<int?>(sleepEnd),
      'recovery': serializer.toJson<double?>(recovery),
      'rhr': serializer.toJson<double?>(rhr),
      'hrvProxy': serializer.toJson<double?>(hrvProxy),
      'calibrating': serializer.toJson<bool>(calibrating),
      'algoVersion': serializer.toJson<int>(algoVersion),
    };
  }

  DailyScore copyWith({
    String? date,
    double? strain,
    double? trimp,
    int? hrMax,
    Value<double?> sleepPerf = const Value.absent(),
    Value<double?> sleptHours = const Value.absent(),
    Value<double?> needHours = const Value.absent(),
    double? napHours,
    Value<double?> baseNeed = const Value.absent(),
    Value<int?> sleepStart = const Value.absent(),
    Value<int?> sleepEnd = const Value.absent(),
    Value<double?> recovery = const Value.absent(),
    Value<double?> rhr = const Value.absent(),
    Value<double?> hrvProxy = const Value.absent(),
    bool? calibrating,
    int? algoVersion,
  }) => DailyScore(
    date: date ?? this.date,
    strain: strain ?? this.strain,
    trimp: trimp ?? this.trimp,
    hrMax: hrMax ?? this.hrMax,
    sleepPerf: sleepPerf.present ? sleepPerf.value : this.sleepPerf,
    sleptHours: sleptHours.present ? sleptHours.value : this.sleptHours,
    needHours: needHours.present ? needHours.value : this.needHours,
    napHours: napHours ?? this.napHours,
    baseNeed: baseNeed.present ? baseNeed.value : this.baseNeed,
    sleepStart: sleepStart.present ? sleepStart.value : this.sleepStart,
    sleepEnd: sleepEnd.present ? sleepEnd.value : this.sleepEnd,
    recovery: recovery.present ? recovery.value : this.recovery,
    rhr: rhr.present ? rhr.value : this.rhr,
    hrvProxy: hrvProxy.present ? hrvProxy.value : this.hrvProxy,
    calibrating: calibrating ?? this.calibrating,
    algoVersion: algoVersion ?? this.algoVersion,
  );
  DailyScore copyWithCompanion(DailyScoresCompanion data) {
    return DailyScore(
      date: data.date.present ? data.date.value : this.date,
      strain: data.strain.present ? data.strain.value : this.strain,
      trimp: data.trimp.present ? data.trimp.value : this.trimp,
      hrMax: data.hrMax.present ? data.hrMax.value : this.hrMax,
      sleepPerf: data.sleepPerf.present ? data.sleepPerf.value : this.sleepPerf,
      sleptHours: data.sleptHours.present
          ? data.sleptHours.value
          : this.sleptHours,
      needHours: data.needHours.present ? data.needHours.value : this.needHours,
      napHours: data.napHours.present ? data.napHours.value : this.napHours,
      baseNeed: data.baseNeed.present ? data.baseNeed.value : this.baseNeed,
      sleepStart: data.sleepStart.present
          ? data.sleepStart.value
          : this.sleepStart,
      sleepEnd: data.sleepEnd.present ? data.sleepEnd.value : this.sleepEnd,
      recovery: data.recovery.present ? data.recovery.value : this.recovery,
      rhr: data.rhr.present ? data.rhr.value : this.rhr,
      hrvProxy: data.hrvProxy.present ? data.hrvProxy.value : this.hrvProxy,
      calibrating: data.calibrating.present
          ? data.calibrating.value
          : this.calibrating,
      algoVersion: data.algoVersion.present
          ? data.algoVersion.value
          : this.algoVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyScore(')
          ..write('date: $date, ')
          ..write('strain: $strain, ')
          ..write('trimp: $trimp, ')
          ..write('hrMax: $hrMax, ')
          ..write('sleepPerf: $sleepPerf, ')
          ..write('sleptHours: $sleptHours, ')
          ..write('needHours: $needHours, ')
          ..write('napHours: $napHours, ')
          ..write('baseNeed: $baseNeed, ')
          ..write('sleepStart: $sleepStart, ')
          ..write('sleepEnd: $sleepEnd, ')
          ..write('recovery: $recovery, ')
          ..write('rhr: $rhr, ')
          ..write('hrvProxy: $hrvProxy, ')
          ..write('calibrating: $calibrating, ')
          ..write('algoVersion: $algoVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    date,
    strain,
    trimp,
    hrMax,
    sleepPerf,
    sleptHours,
    needHours,
    napHours,
    baseNeed,
    sleepStart,
    sleepEnd,
    recovery,
    rhr,
    hrvProxy,
    calibrating,
    algoVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyScore &&
          other.date == this.date &&
          other.strain == this.strain &&
          other.trimp == this.trimp &&
          other.hrMax == this.hrMax &&
          other.sleepPerf == this.sleepPerf &&
          other.sleptHours == this.sleptHours &&
          other.needHours == this.needHours &&
          other.napHours == this.napHours &&
          other.baseNeed == this.baseNeed &&
          other.sleepStart == this.sleepStart &&
          other.sleepEnd == this.sleepEnd &&
          other.recovery == this.recovery &&
          other.rhr == this.rhr &&
          other.hrvProxy == this.hrvProxy &&
          other.calibrating == this.calibrating &&
          other.algoVersion == this.algoVersion);
}

class DailyScoresCompanion extends UpdateCompanion<DailyScore> {
  final Value<String> date;
  final Value<double> strain;
  final Value<double> trimp;
  final Value<int> hrMax;
  final Value<double?> sleepPerf;
  final Value<double?> sleptHours;
  final Value<double?> needHours;
  final Value<double> napHours;
  final Value<double?> baseNeed;
  final Value<int?> sleepStart;
  final Value<int?> sleepEnd;
  final Value<double?> recovery;
  final Value<double?> rhr;
  final Value<double?> hrvProxy;
  final Value<bool> calibrating;
  final Value<int> algoVersion;
  final Value<int> rowid;
  const DailyScoresCompanion({
    this.date = const Value.absent(),
    this.strain = const Value.absent(),
    this.trimp = const Value.absent(),
    this.hrMax = const Value.absent(),
    this.sleepPerf = const Value.absent(),
    this.sleptHours = const Value.absent(),
    this.needHours = const Value.absent(),
    this.napHours = const Value.absent(),
    this.baseNeed = const Value.absent(),
    this.sleepStart = const Value.absent(),
    this.sleepEnd = const Value.absent(),
    this.recovery = const Value.absent(),
    this.rhr = const Value.absent(),
    this.hrvProxy = const Value.absent(),
    this.calibrating = const Value.absent(),
    this.algoVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyScoresCompanion.insert({
    required String date,
    required double strain,
    required double trimp,
    required int hrMax,
    this.sleepPerf = const Value.absent(),
    this.sleptHours = const Value.absent(),
    this.needHours = const Value.absent(),
    this.napHours = const Value.absent(),
    this.baseNeed = const Value.absent(),
    this.sleepStart = const Value.absent(),
    this.sleepEnd = const Value.absent(),
    this.recovery = const Value.absent(),
    this.rhr = const Value.absent(),
    this.hrvProxy = const Value.absent(),
    required bool calibrating,
    required int algoVersion,
    this.rowid = const Value.absent(),
  }) : date = Value(date),
       strain = Value(strain),
       trimp = Value(trimp),
       hrMax = Value(hrMax),
       calibrating = Value(calibrating),
       algoVersion = Value(algoVersion);
  static Insertable<DailyScore> custom({
    Expression<String>? date,
    Expression<double>? strain,
    Expression<double>? trimp,
    Expression<int>? hrMax,
    Expression<double>? sleepPerf,
    Expression<double>? sleptHours,
    Expression<double>? needHours,
    Expression<double>? napHours,
    Expression<double>? baseNeed,
    Expression<int>? sleepStart,
    Expression<int>? sleepEnd,
    Expression<double>? recovery,
    Expression<double>? rhr,
    Expression<double>? hrvProxy,
    Expression<bool>? calibrating,
    Expression<int>? algoVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (strain != null) 'strain': strain,
      if (trimp != null) 'trimp': trimp,
      if (hrMax != null) 'hr_max': hrMax,
      if (sleepPerf != null) 'sleep_perf': sleepPerf,
      if (sleptHours != null) 'slept_hours': sleptHours,
      if (needHours != null) 'need_hours': needHours,
      if (napHours != null) 'nap_hours': napHours,
      if (baseNeed != null) 'base_need': baseNeed,
      if (sleepStart != null) 'sleep_start': sleepStart,
      if (sleepEnd != null) 'sleep_end': sleepEnd,
      if (recovery != null) 'recovery': recovery,
      if (rhr != null) 'rhr': rhr,
      if (hrvProxy != null) 'hrv_proxy': hrvProxy,
      if (calibrating != null) 'calibrating': calibrating,
      if (algoVersion != null) 'algo_version': algoVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyScoresCompanion copyWith({
    Value<String>? date,
    Value<double>? strain,
    Value<double>? trimp,
    Value<int>? hrMax,
    Value<double?>? sleepPerf,
    Value<double?>? sleptHours,
    Value<double?>? needHours,
    Value<double>? napHours,
    Value<double?>? baseNeed,
    Value<int?>? sleepStart,
    Value<int?>? sleepEnd,
    Value<double?>? recovery,
    Value<double?>? rhr,
    Value<double?>? hrvProxy,
    Value<bool>? calibrating,
    Value<int>? algoVersion,
    Value<int>? rowid,
  }) {
    return DailyScoresCompanion(
      date: date ?? this.date,
      strain: strain ?? this.strain,
      trimp: trimp ?? this.trimp,
      hrMax: hrMax ?? this.hrMax,
      sleepPerf: sleepPerf ?? this.sleepPerf,
      sleptHours: sleptHours ?? this.sleptHours,
      needHours: needHours ?? this.needHours,
      napHours: napHours ?? this.napHours,
      baseNeed: baseNeed ?? this.baseNeed,
      sleepStart: sleepStart ?? this.sleepStart,
      sleepEnd: sleepEnd ?? this.sleepEnd,
      recovery: recovery ?? this.recovery,
      rhr: rhr ?? this.rhr,
      hrvProxy: hrvProxy ?? this.hrvProxy,
      calibrating: calibrating ?? this.calibrating,
      algoVersion: algoVersion ?? this.algoVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (strain.present) {
      map['strain'] = Variable<double>(strain.value);
    }
    if (trimp.present) {
      map['trimp'] = Variable<double>(trimp.value);
    }
    if (hrMax.present) {
      map['hr_max'] = Variable<int>(hrMax.value);
    }
    if (sleepPerf.present) {
      map['sleep_perf'] = Variable<double>(sleepPerf.value);
    }
    if (sleptHours.present) {
      map['slept_hours'] = Variable<double>(sleptHours.value);
    }
    if (needHours.present) {
      map['need_hours'] = Variable<double>(needHours.value);
    }
    if (napHours.present) {
      map['nap_hours'] = Variable<double>(napHours.value);
    }
    if (baseNeed.present) {
      map['base_need'] = Variable<double>(baseNeed.value);
    }
    if (sleepStart.present) {
      map['sleep_start'] = Variable<int>(sleepStart.value);
    }
    if (sleepEnd.present) {
      map['sleep_end'] = Variable<int>(sleepEnd.value);
    }
    if (recovery.present) {
      map['recovery'] = Variable<double>(recovery.value);
    }
    if (rhr.present) {
      map['rhr'] = Variable<double>(rhr.value);
    }
    if (hrvProxy.present) {
      map['hrv_proxy'] = Variable<double>(hrvProxy.value);
    }
    if (calibrating.present) {
      map['calibrating'] = Variable<bool>(calibrating.value);
    }
    if (algoVersion.present) {
      map['algo_version'] = Variable<int>(algoVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyScoresCompanion(')
          ..write('date: $date, ')
          ..write('strain: $strain, ')
          ..write('trimp: $trimp, ')
          ..write('hrMax: $hrMax, ')
          ..write('sleepPerf: $sleepPerf, ')
          ..write('sleptHours: $sleptHours, ')
          ..write('needHours: $needHours, ')
          ..write('napHours: $napHours, ')
          ..write('baseNeed: $baseNeed, ')
          ..write('sleepStart: $sleepStart, ')
          ..write('sleepEnd: $sleepEnd, ')
          ..write('recovery: $recovery, ')
          ..write('rhr: $rhr, ')
          ..write('hrvProxy: $hrvProxy, ')
          ..write('calibrating: $calibrating, ')
          ..write('algoVersion: $algoVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BaselinesTable extends Baselines
    with TableInfo<$BaselinesTable, Baseline> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BaselinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _metricMeta = const VerificationMeta('metric');
  @override
  late final GeneratedColumn<String> metric = GeneratedColumn<String>(
    'metric',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _windowMeta = const VerificationMeta('window');
  @override
  late final GeneratedColumn<int> window = GeneratedColumn<int>(
    'window',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _meanMeta = const VerificationMeta('mean');
  @override
  late final GeneratedColumn<double> mean = GeneratedColumn<double>(
    'mean',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sdMeta = const VerificationMeta('sd');
  @override
  late final GeneratedColumn<double> sd = GeneratedColumn<double>(
    'sd',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [metric, window, mean, sd, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'baselines';
  @override
  VerificationContext validateIntegrity(
    Insertable<Baseline> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('metric')) {
      context.handle(
        _metricMeta,
        metric.isAcceptableOrUnknown(data['metric']!, _metricMeta),
      );
    } else if (isInserting) {
      context.missing(_metricMeta);
    }
    if (data.containsKey('window')) {
      context.handle(
        _windowMeta,
        window.isAcceptableOrUnknown(data['window']!, _windowMeta),
      );
    } else if (isInserting) {
      context.missing(_windowMeta);
    }
    if (data.containsKey('mean')) {
      context.handle(
        _meanMeta,
        mean.isAcceptableOrUnknown(data['mean']!, _meanMeta),
      );
    } else if (isInserting) {
      context.missing(_meanMeta);
    }
    if (data.containsKey('sd')) {
      context.handle(_sdMeta, sd.isAcceptableOrUnknown(data['sd']!, _sdMeta));
    } else if (isInserting) {
      context.missing(_sdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {metric, window};
  @override
  Baseline map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Baseline(
      metric: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric'],
      )!,
      window: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}window'],
      )!,
      mean: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}mean'],
      )!,
      sd: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sd'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BaselinesTable createAlias(String alias) {
    return $BaselinesTable(attachedDatabase, alias);
  }
}

class Baseline extends DataClass implements Insertable<Baseline> {
  final String metric;
  final int window;
  final double mean;
  final double sd;
  final int updatedAt;
  const Baseline({
    required this.metric,
    required this.window,
    required this.mean,
    required this.sd,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['metric'] = Variable<String>(metric);
    map['window'] = Variable<int>(window);
    map['mean'] = Variable<double>(mean);
    map['sd'] = Variable<double>(sd);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  BaselinesCompanion toCompanion(bool nullToAbsent) {
    return BaselinesCompanion(
      metric: Value(metric),
      window: Value(window),
      mean: Value(mean),
      sd: Value(sd),
      updatedAt: Value(updatedAt),
    );
  }

  factory Baseline.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Baseline(
      metric: serializer.fromJson<String>(json['metric']),
      window: serializer.fromJson<int>(json['window']),
      mean: serializer.fromJson<double>(json['mean']),
      sd: serializer.fromJson<double>(json['sd']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'metric': serializer.toJson<String>(metric),
      'window': serializer.toJson<int>(window),
      'mean': serializer.toJson<double>(mean),
      'sd': serializer.toJson<double>(sd),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Baseline copyWith({
    String? metric,
    int? window,
    double? mean,
    double? sd,
    int? updatedAt,
  }) => Baseline(
    metric: metric ?? this.metric,
    window: window ?? this.window,
    mean: mean ?? this.mean,
    sd: sd ?? this.sd,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Baseline copyWithCompanion(BaselinesCompanion data) {
    return Baseline(
      metric: data.metric.present ? data.metric.value : this.metric,
      window: data.window.present ? data.window.value : this.window,
      mean: data.mean.present ? data.mean.value : this.mean,
      sd: data.sd.present ? data.sd.value : this.sd,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Baseline(')
          ..write('metric: $metric, ')
          ..write('window: $window, ')
          ..write('mean: $mean, ')
          ..write('sd: $sd, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(metric, window, mean, sd, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Baseline &&
          other.metric == this.metric &&
          other.window == this.window &&
          other.mean == this.mean &&
          other.sd == this.sd &&
          other.updatedAt == this.updatedAt);
}

class BaselinesCompanion extends UpdateCompanion<Baseline> {
  final Value<String> metric;
  final Value<int> window;
  final Value<double> mean;
  final Value<double> sd;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const BaselinesCompanion({
    this.metric = const Value.absent(),
    this.window = const Value.absent(),
    this.mean = const Value.absent(),
    this.sd = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BaselinesCompanion.insert({
    required String metric,
    required int window,
    required double mean,
    required double sd,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : metric = Value(metric),
       window = Value(window),
       mean = Value(mean),
       sd = Value(sd),
       updatedAt = Value(updatedAt);
  static Insertable<Baseline> custom({
    Expression<String>? metric,
    Expression<int>? window,
    Expression<double>? mean,
    Expression<double>? sd,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (metric != null) 'metric': metric,
      if (window != null) 'window': window,
      if (mean != null) 'mean': mean,
      if (sd != null) 'sd': sd,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BaselinesCompanion copyWith({
    Value<String>? metric,
    Value<int>? window,
    Value<double>? mean,
    Value<double>? sd,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return BaselinesCompanion(
      metric: metric ?? this.metric,
      window: window ?? this.window,
      mean: mean ?? this.mean,
      sd: sd ?? this.sd,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (metric.present) {
      map['metric'] = Variable<String>(metric.value);
    }
    if (window.present) {
      map['window'] = Variable<int>(window.value);
    }
    if (mean.present) {
      map['mean'] = Variable<double>(mean.value);
    }
    if (sd.present) {
      map['sd'] = Variable<double>(sd.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BaselinesCompanion(')
          ..write('metric: $metric, ')
          ..write('window: $window, ')
          ..write('mean: $mean, ')
          ..write('sd: $sd, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $JournalTable extends Journal with TableInfo<$JournalTable, JournalData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JournalTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
    'tag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<bool> value = GeneratedColumn<bool>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("value" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [date, tag, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'journal';
  @override
  VerificationContext validateIntegrity(
    Insertable<JournalData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('tag')) {
      context.handle(
        _tagMeta,
        tag.isAcceptableOrUnknown(data['tag']!, _tagMeta),
      );
    } else if (isInserting) {
      context.missing(_tagMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date, tag};
  @override
  JournalData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JournalData(
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      tag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $JournalTable createAlias(String alias) {
    return $JournalTable(attachedDatabase, alias);
  }
}

class JournalData extends DataClass implements Insertable<JournalData> {
  final String date;
  final String tag;
  final bool value;
  const JournalData({
    required this.date,
    required this.tag,
    required this.value,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['tag'] = Variable<String>(tag);
    map['value'] = Variable<bool>(value);
    return map;
  }

  JournalCompanion toCompanion(bool nullToAbsent) {
    return JournalCompanion(
      date: Value(date),
      tag: Value(tag),
      value: Value(value),
    );
  }

  factory JournalData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JournalData(
      date: serializer.fromJson<String>(json['date']),
      tag: serializer.fromJson<String>(json['tag']),
      value: serializer.fromJson<bool>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'tag': serializer.toJson<String>(tag),
      'value': serializer.toJson<bool>(value),
    };
  }

  JournalData copyWith({String? date, String? tag, bool? value}) => JournalData(
    date: date ?? this.date,
    tag: tag ?? this.tag,
    value: value ?? this.value,
  );
  JournalData copyWithCompanion(JournalCompanion data) {
    return JournalData(
      date: data.date.present ? data.date.value : this.date,
      tag: data.tag.present ? data.tag.value : this.tag,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JournalData(')
          ..write('date: $date, ')
          ..write('tag: $tag, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(date, tag, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JournalData &&
          other.date == this.date &&
          other.tag == this.tag &&
          other.value == this.value);
}

class JournalCompanion extends UpdateCompanion<JournalData> {
  final Value<String> date;
  final Value<String> tag;
  final Value<bool> value;
  final Value<int> rowid;
  const JournalCompanion({
    this.date = const Value.absent(),
    this.tag = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JournalCompanion.insert({
    required String date,
    required String tag,
    required bool value,
    this.rowid = const Value.absent(),
  }) : date = Value(date),
       tag = Value(tag),
       value = Value(value);
  static Insertable<JournalData> custom({
    Expression<String>? date,
    Expression<String>? tag,
    Expression<bool>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (tag != null) 'tag': tag,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JournalCompanion copyWith({
    Value<String>? date,
    Value<String>? tag,
    Value<bool>? value,
    Value<int>? rowid,
  }) {
    return JournalCompanion(
      date: date ?? this.date,
      tag: tag ?? this.tag,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (value.present) {
      map['value'] = Variable<bool>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JournalCompanion(')
          ..write('date: $date, ')
          ..write('tag: $tag, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceMeta = const VerificationMeta('device');
  @override
  late final GeneratedColumn<String> device = GeneratedColumn<String>(
    'device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataTypeMeta = const VerificationMeta(
    'dataType',
  );
  @override
  late final GeneratedColumn<String> dataType = GeneratedColumn<String>(
    'data_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastTsMeta = const VerificationMeta('lastTs');
  @override
  late final GeneratedColumn<int> lastTs = GeneratedColumn<int>(
    'last_ts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [device, dataType, lastTs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device')) {
      context.handle(
        _deviceMeta,
        device.isAcceptableOrUnknown(data['device']!, _deviceMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceMeta);
    }
    if (data.containsKey('data_type')) {
      context.handle(
        _dataTypeMeta,
        dataType.isAcceptableOrUnknown(data['data_type']!, _dataTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_dataTypeMeta);
    }
    if (data.containsKey('last_ts')) {
      context.handle(
        _lastTsMeta,
        lastTs.isAcceptableOrUnknown(data['last_ts']!, _lastTsMeta),
      );
    } else if (isInserting) {
      context.missing(_lastTsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {device, dataType};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      device: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device'],
      )!,
      dataType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_type'],
      )!,
      lastTs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_ts'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final String device;
  final String dataType;
  final int lastTs;
  const SyncStateData({
    required this.device,
    required this.dataType,
    required this.lastTs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device'] = Variable<String>(device);
    map['data_type'] = Variable<String>(dataType);
    map['last_ts'] = Variable<int>(lastTs);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      device: Value(device),
      dataType: Value(dataType),
      lastTs: Value(lastTs),
    );
  }

  factory SyncStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      device: serializer.fromJson<String>(json['device']),
      dataType: serializer.fromJson<String>(json['dataType']),
      lastTs: serializer.fromJson<int>(json['lastTs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'device': serializer.toJson<String>(device),
      'dataType': serializer.toJson<String>(dataType),
      'lastTs': serializer.toJson<int>(lastTs),
    };
  }

  SyncStateData copyWith({String? device, String? dataType, int? lastTs}) =>
      SyncStateData(
        device: device ?? this.device,
        dataType: dataType ?? this.dataType,
        lastTs: lastTs ?? this.lastTs,
      );
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      device: data.device.present ? data.device.value : this.device,
      dataType: data.dataType.present ? data.dataType.value : this.dataType,
      lastTs: data.lastTs.present ? data.lastTs.value : this.lastTs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('device: $device, ')
          ..write('dataType: $dataType, ')
          ..write('lastTs: $lastTs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(device, dataType, lastTs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.device == this.device &&
          other.dataType == this.dataType &&
          other.lastTs == this.lastTs);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<String> device;
  final Value<String> dataType;
  final Value<int> lastTs;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.device = const Value.absent(),
    this.dataType = const Value.absent(),
    this.lastTs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String device,
    required String dataType,
    required int lastTs,
    this.rowid = const Value.absent(),
  }) : device = Value(device),
       dataType = Value(dataType),
       lastTs = Value(lastTs);
  static Insertable<SyncStateData> custom({
    Expression<String>? device,
    Expression<String>? dataType,
    Expression<int>? lastTs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (device != null) 'device': device,
      if (dataType != null) 'data_type': dataType,
      if (lastTs != null) 'last_ts': lastTs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? device,
    Value<String>? dataType,
    Value<int>? lastTs,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      device: device ?? this.device,
      dataType: dataType ?? this.dataType,
      lastTs: lastTs ?? this.lastTs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (device.present) {
      map['device'] = Variable<String>(device.value);
    }
    if (dataType.present) {
      map['data_type'] = Variable<String>(dataType.value);
    }
    if (lastTs.present) {
      map['last_ts'] = Variable<int>(lastTs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('device: $device, ')
          ..write('dataType: $dataType, ')
          ..write('lastTs: $lastTs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkoutsTable extends Workouts with TableInfo<$WorkoutsTable, Workout> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkoutsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _startMeta = const VerificationMeta('start');
  @override
  late final GeneratedColumn<int> start = GeneratedColumn<int>(
    'start',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endMeta = const VerificationMeta('end');
  @override
  late final GeneratedColumn<int> end = GeneratedColumn<int>(
    'end',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sportMeta = const VerificationMeta('sport');
  @override
  late final GeneratedColumn<String> sport = GeneratedColumn<String>(
    'sport',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confirmedMeta = const VerificationMeta(
    'confirmed',
  );
  @override
  late final GeneratedColumn<bool> confirmed = GeneratedColumn<bool>(
    'confirmed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("confirmed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _strainMeta = const VerificationMeta('strain');
  @override
  late final GeneratedColumn<double> strain = GeneratedColumn<double>(
    'strain',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trimpMeta = const VerificationMeta('trimp');
  @override
  late final GeneratedColumn<double> trimp = GeneratedColumn<double>(
    'trimp',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avgHrMeta = const VerificationMeta('avgHr');
  @override
  late final GeneratedColumn<int> avgHr = GeneratedColumn<int>(
    'avg_hr',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxHrMeta = const VerificationMeta('maxHr');
  @override
  late final GeneratedColumn<int> maxHr = GeneratedColumn<int>(
    'max_hr',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _zonesMeta = const VerificationMeta('zones');
  @override
  late final GeneratedColumn<String> zones = GeneratedColumn<String>(
    'zones',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rpeMeta = const VerificationMeta('rpe');
  @override
  late final GeneratedColumn<int> rpe = GeneratedColumn<int>(
    'rpe',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _planMeta = const VerificationMeta('plan');
  @override
  late final GeneratedColumn<String> plan = GeneratedColumn<String>(
    'plan',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    start,
    end,
    sport,
    title,
    source,
    confirmed,
    strain,
    trimp,
    avgHr,
    maxHr,
    zones,
    rpe,
    plan,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workouts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Workout> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('start')) {
      context.handle(
        _startMeta,
        start.isAcceptableOrUnknown(data['start']!, _startMeta),
      );
    } else if (isInserting) {
      context.missing(_startMeta);
    }
    if (data.containsKey('end')) {
      context.handle(
        _endMeta,
        end.isAcceptableOrUnknown(data['end']!, _endMeta),
      );
    } else if (isInserting) {
      context.missing(_endMeta);
    }
    if (data.containsKey('sport')) {
      context.handle(
        _sportMeta,
        sport.isAcceptableOrUnknown(data['sport']!, _sportMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('confirmed')) {
      context.handle(
        _confirmedMeta,
        confirmed.isAcceptableOrUnknown(data['confirmed']!, _confirmedMeta),
      );
    }
    if (data.containsKey('strain')) {
      context.handle(
        _strainMeta,
        strain.isAcceptableOrUnknown(data['strain']!, _strainMeta),
      );
    } else if (isInserting) {
      context.missing(_strainMeta);
    }
    if (data.containsKey('trimp')) {
      context.handle(
        _trimpMeta,
        trimp.isAcceptableOrUnknown(data['trimp']!, _trimpMeta),
      );
    } else if (isInserting) {
      context.missing(_trimpMeta);
    }
    if (data.containsKey('avg_hr')) {
      context.handle(
        _avgHrMeta,
        avgHr.isAcceptableOrUnknown(data['avg_hr']!, _avgHrMeta),
      );
    }
    if (data.containsKey('max_hr')) {
      context.handle(
        _maxHrMeta,
        maxHr.isAcceptableOrUnknown(data['max_hr']!, _maxHrMeta),
      );
    }
    if (data.containsKey('zones')) {
      context.handle(
        _zonesMeta,
        zones.isAcceptableOrUnknown(data['zones']!, _zonesMeta),
      );
    } else if (isInserting) {
      context.missing(_zonesMeta);
    }
    if (data.containsKey('rpe')) {
      context.handle(
        _rpeMeta,
        rpe.isAcceptableOrUnknown(data['rpe']!, _rpeMeta),
      );
    }
    if (data.containsKey('plan')) {
      context.handle(
        _planMeta,
        plan.isAcceptableOrUnknown(data['plan']!, _planMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Workout map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Workout(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      start: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start'],
      )!,
      end: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end'],
      )!,
      sport: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sport'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      confirmed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}confirmed'],
      )!,
      strain: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}strain'],
      )!,
      trimp: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}trimp'],
      )!,
      avgHr: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}avg_hr'],
      ),
      maxHr: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_hr'],
      ),
      zones: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}zones'],
      )!,
      rpe: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rpe'],
      ),
      plan: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan'],
      ),
    );
  }

  @override
  $WorkoutsTable createAlias(String alias) {
    return $WorkoutsTable(attachedDatabase, alias);
  }
}

class Workout extends DataClass implements Insertable<Workout> {
  final int id;
  final int start;
  final int end;
  final String? sport;
  final String title;
  final String source;
  final bool confirmed;
  final double strain;
  final double trimp;
  final int? avgHr;
  final int? maxHr;
  final String zones;
  final int? rpe;
  final String? plan;
  const Workout({
    required this.id,
    required this.start,
    required this.end,
    this.sport,
    required this.title,
    required this.source,
    required this.confirmed,
    required this.strain,
    required this.trimp,
    this.avgHr,
    this.maxHr,
    required this.zones,
    this.rpe,
    this.plan,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['start'] = Variable<int>(start);
    map['end'] = Variable<int>(end);
    if (!nullToAbsent || sport != null) {
      map['sport'] = Variable<String>(sport);
    }
    map['title'] = Variable<String>(title);
    map['source'] = Variable<String>(source);
    map['confirmed'] = Variable<bool>(confirmed);
    map['strain'] = Variable<double>(strain);
    map['trimp'] = Variable<double>(trimp);
    if (!nullToAbsent || avgHr != null) {
      map['avg_hr'] = Variable<int>(avgHr);
    }
    if (!nullToAbsent || maxHr != null) {
      map['max_hr'] = Variable<int>(maxHr);
    }
    map['zones'] = Variable<String>(zones);
    if (!nullToAbsent || rpe != null) {
      map['rpe'] = Variable<int>(rpe);
    }
    if (!nullToAbsent || plan != null) {
      map['plan'] = Variable<String>(plan);
    }
    return map;
  }

  WorkoutsCompanion toCompanion(bool nullToAbsent) {
    return WorkoutsCompanion(
      id: Value(id),
      start: Value(start),
      end: Value(end),
      sport: sport == null && nullToAbsent
          ? const Value.absent()
          : Value(sport),
      title: Value(title),
      source: Value(source),
      confirmed: Value(confirmed),
      strain: Value(strain),
      trimp: Value(trimp),
      avgHr: avgHr == null && nullToAbsent
          ? const Value.absent()
          : Value(avgHr),
      maxHr: maxHr == null && nullToAbsent
          ? const Value.absent()
          : Value(maxHr),
      zones: Value(zones),
      rpe: rpe == null && nullToAbsent ? const Value.absent() : Value(rpe),
      plan: plan == null && nullToAbsent ? const Value.absent() : Value(plan),
    );
  }

  factory Workout.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Workout(
      id: serializer.fromJson<int>(json['id']),
      start: serializer.fromJson<int>(json['start']),
      end: serializer.fromJson<int>(json['end']),
      sport: serializer.fromJson<String?>(json['sport']),
      title: serializer.fromJson<String>(json['title']),
      source: serializer.fromJson<String>(json['source']),
      confirmed: serializer.fromJson<bool>(json['confirmed']),
      strain: serializer.fromJson<double>(json['strain']),
      trimp: serializer.fromJson<double>(json['trimp']),
      avgHr: serializer.fromJson<int?>(json['avgHr']),
      maxHr: serializer.fromJson<int?>(json['maxHr']),
      zones: serializer.fromJson<String>(json['zones']),
      rpe: serializer.fromJson<int?>(json['rpe']),
      plan: serializer.fromJson<String?>(json['plan']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'start': serializer.toJson<int>(start),
      'end': serializer.toJson<int>(end),
      'sport': serializer.toJson<String?>(sport),
      'title': serializer.toJson<String>(title),
      'source': serializer.toJson<String>(source),
      'confirmed': serializer.toJson<bool>(confirmed),
      'strain': serializer.toJson<double>(strain),
      'trimp': serializer.toJson<double>(trimp),
      'avgHr': serializer.toJson<int?>(avgHr),
      'maxHr': serializer.toJson<int?>(maxHr),
      'zones': serializer.toJson<String>(zones),
      'rpe': serializer.toJson<int?>(rpe),
      'plan': serializer.toJson<String?>(plan),
    };
  }

  Workout copyWith({
    int? id,
    int? start,
    int? end,
    Value<String?> sport = const Value.absent(),
    String? title,
    String? source,
    bool? confirmed,
    double? strain,
    double? trimp,
    Value<int?> avgHr = const Value.absent(),
    Value<int?> maxHr = const Value.absent(),
    String? zones,
    Value<int?> rpe = const Value.absent(),
    Value<String?> plan = const Value.absent(),
  }) => Workout(
    id: id ?? this.id,
    start: start ?? this.start,
    end: end ?? this.end,
    sport: sport.present ? sport.value : this.sport,
    title: title ?? this.title,
    source: source ?? this.source,
    confirmed: confirmed ?? this.confirmed,
    strain: strain ?? this.strain,
    trimp: trimp ?? this.trimp,
    avgHr: avgHr.present ? avgHr.value : this.avgHr,
    maxHr: maxHr.present ? maxHr.value : this.maxHr,
    zones: zones ?? this.zones,
    rpe: rpe.present ? rpe.value : this.rpe,
    plan: plan.present ? plan.value : this.plan,
  );
  Workout copyWithCompanion(WorkoutsCompanion data) {
    return Workout(
      id: data.id.present ? data.id.value : this.id,
      start: data.start.present ? data.start.value : this.start,
      end: data.end.present ? data.end.value : this.end,
      sport: data.sport.present ? data.sport.value : this.sport,
      title: data.title.present ? data.title.value : this.title,
      source: data.source.present ? data.source.value : this.source,
      confirmed: data.confirmed.present ? data.confirmed.value : this.confirmed,
      strain: data.strain.present ? data.strain.value : this.strain,
      trimp: data.trimp.present ? data.trimp.value : this.trimp,
      avgHr: data.avgHr.present ? data.avgHr.value : this.avgHr,
      maxHr: data.maxHr.present ? data.maxHr.value : this.maxHr,
      zones: data.zones.present ? data.zones.value : this.zones,
      rpe: data.rpe.present ? data.rpe.value : this.rpe,
      plan: data.plan.present ? data.plan.value : this.plan,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Workout(')
          ..write('id: $id, ')
          ..write('start: $start, ')
          ..write('end: $end, ')
          ..write('sport: $sport, ')
          ..write('title: $title, ')
          ..write('source: $source, ')
          ..write('confirmed: $confirmed, ')
          ..write('strain: $strain, ')
          ..write('trimp: $trimp, ')
          ..write('avgHr: $avgHr, ')
          ..write('maxHr: $maxHr, ')
          ..write('zones: $zones, ')
          ..write('rpe: $rpe, ')
          ..write('plan: $plan')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    start,
    end,
    sport,
    title,
    source,
    confirmed,
    strain,
    trimp,
    avgHr,
    maxHr,
    zones,
    rpe,
    plan,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Workout &&
          other.id == this.id &&
          other.start == this.start &&
          other.end == this.end &&
          other.sport == this.sport &&
          other.title == this.title &&
          other.source == this.source &&
          other.confirmed == this.confirmed &&
          other.strain == this.strain &&
          other.trimp == this.trimp &&
          other.avgHr == this.avgHr &&
          other.maxHr == this.maxHr &&
          other.zones == this.zones &&
          other.rpe == this.rpe &&
          other.plan == this.plan);
}

class WorkoutsCompanion extends UpdateCompanion<Workout> {
  final Value<int> id;
  final Value<int> start;
  final Value<int> end;
  final Value<String?> sport;
  final Value<String> title;
  final Value<String> source;
  final Value<bool> confirmed;
  final Value<double> strain;
  final Value<double> trimp;
  final Value<int?> avgHr;
  final Value<int?> maxHr;
  final Value<String> zones;
  final Value<int?> rpe;
  final Value<String?> plan;
  const WorkoutsCompanion({
    this.id = const Value.absent(),
    this.start = const Value.absent(),
    this.end = const Value.absent(),
    this.sport = const Value.absent(),
    this.title = const Value.absent(),
    this.source = const Value.absent(),
    this.confirmed = const Value.absent(),
    this.strain = const Value.absent(),
    this.trimp = const Value.absent(),
    this.avgHr = const Value.absent(),
    this.maxHr = const Value.absent(),
    this.zones = const Value.absent(),
    this.rpe = const Value.absent(),
    this.plan = const Value.absent(),
  });
  WorkoutsCompanion.insert({
    this.id = const Value.absent(),
    required int start,
    required int end,
    this.sport = const Value.absent(),
    required String title,
    required String source,
    this.confirmed = const Value.absent(),
    required double strain,
    required double trimp,
    this.avgHr = const Value.absent(),
    this.maxHr = const Value.absent(),
    required String zones,
    this.rpe = const Value.absent(),
    this.plan = const Value.absent(),
  }) : start = Value(start),
       end = Value(end),
       title = Value(title),
       source = Value(source),
       strain = Value(strain),
       trimp = Value(trimp),
       zones = Value(zones);
  static Insertable<Workout> custom({
    Expression<int>? id,
    Expression<int>? start,
    Expression<int>? end,
    Expression<String>? sport,
    Expression<String>? title,
    Expression<String>? source,
    Expression<bool>? confirmed,
    Expression<double>? strain,
    Expression<double>? trimp,
    Expression<int>? avgHr,
    Expression<int>? maxHr,
    Expression<String>? zones,
    Expression<int>? rpe,
    Expression<String>? plan,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (start != null) 'start': start,
      if (end != null) 'end': end,
      if (sport != null) 'sport': sport,
      if (title != null) 'title': title,
      if (source != null) 'source': source,
      if (confirmed != null) 'confirmed': confirmed,
      if (strain != null) 'strain': strain,
      if (trimp != null) 'trimp': trimp,
      if (avgHr != null) 'avg_hr': avgHr,
      if (maxHr != null) 'max_hr': maxHr,
      if (zones != null) 'zones': zones,
      if (rpe != null) 'rpe': rpe,
      if (plan != null) 'plan': plan,
    });
  }

  WorkoutsCompanion copyWith({
    Value<int>? id,
    Value<int>? start,
    Value<int>? end,
    Value<String?>? sport,
    Value<String>? title,
    Value<String>? source,
    Value<bool>? confirmed,
    Value<double>? strain,
    Value<double>? trimp,
    Value<int?>? avgHr,
    Value<int?>? maxHr,
    Value<String>? zones,
    Value<int?>? rpe,
    Value<String?>? plan,
  }) {
    return WorkoutsCompanion(
      id: id ?? this.id,
      start: start ?? this.start,
      end: end ?? this.end,
      sport: sport ?? this.sport,
      title: title ?? this.title,
      source: source ?? this.source,
      confirmed: confirmed ?? this.confirmed,
      strain: strain ?? this.strain,
      trimp: trimp ?? this.trimp,
      avgHr: avgHr ?? this.avgHr,
      maxHr: maxHr ?? this.maxHr,
      zones: zones ?? this.zones,
      rpe: rpe ?? this.rpe,
      plan: plan ?? this.plan,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (start.present) {
      map['start'] = Variable<int>(start.value);
    }
    if (end.present) {
      map['end'] = Variable<int>(end.value);
    }
    if (sport.present) {
      map['sport'] = Variable<String>(sport.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (confirmed.present) {
      map['confirmed'] = Variable<bool>(confirmed.value);
    }
    if (strain.present) {
      map['strain'] = Variable<double>(strain.value);
    }
    if (trimp.present) {
      map['trimp'] = Variable<double>(trimp.value);
    }
    if (avgHr.present) {
      map['avg_hr'] = Variable<int>(avgHr.value);
    }
    if (maxHr.present) {
      map['max_hr'] = Variable<int>(maxHr.value);
    }
    if (zones.present) {
      map['zones'] = Variable<String>(zones.value);
    }
    if (rpe.present) {
      map['rpe'] = Variable<int>(rpe.value);
    }
    if (plan.present) {
      map['plan'] = Variable<String>(plan.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutsCompanion(')
          ..write('id: $id, ')
          ..write('start: $start, ')
          ..write('end: $end, ')
          ..write('sport: $sport, ')
          ..write('title: $title, ')
          ..write('source: $source, ')
          ..write('confirmed: $confirmed, ')
          ..write('strain: $strain, ')
          ..write('trimp: $trimp, ')
          ..write('avgHr: $avgHr, ')
          ..write('maxHr: $maxHr, ')
          ..write('zones: $zones, ')
          ..write('rpe: $rpe, ')
          ..write('plan: $plan')
          ..write(')'))
        .toString();
  }
}

class $PlanDaysTable extends PlanDays with TableInfo<$PlanDaysTable, PlanDay> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanDaysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionMeta = const VerificationMeta(
    'session',
  );
  @override
  late final GeneratedColumn<String> session = GeneratedColumn<String>(
    'session',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalMeta = const VerificationMeta(
    'original',
  );
  @override
  late final GeneratedColumn<String> original = GeneratedColumn<String>(
    'original',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _adaptedAtMeta = const VerificationMeta(
    'adaptedAt',
  );
  @override
  late final GeneratedColumn<int> adaptedAt = GeneratedColumn<int>(
    'adapted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _generalMeta = const VerificationMeta(
    'general',
  );
  @override
  late final GeneratedColumn<bool> general = GeneratedColumn<bool>(
    'general',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("general" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    date,
    session,
    original,
    reason,
    adaptedAt,
    general,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plan_days';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlanDay> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('session')) {
      context.handle(
        _sessionMeta,
        session.isAcceptableOrUnknown(data['session']!, _sessionMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionMeta);
    }
    if (data.containsKey('original')) {
      context.handle(
        _originalMeta,
        original.isAcceptableOrUnknown(data['original']!, _originalMeta),
      );
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('adapted_at')) {
      context.handle(
        _adaptedAtMeta,
        adaptedAt.isAcceptableOrUnknown(data['adapted_at']!, _adaptedAtMeta),
      );
    }
    if (data.containsKey('general')) {
      context.handle(
        _generalMeta,
        general.isAcceptableOrUnknown(data['general']!, _generalMeta),
      );
    } else if (isInserting) {
      context.missing(_generalMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date};
  @override
  PlanDay map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanDay(
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      session: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session'],
      )!,
      original: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original'],
      ),
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      adaptedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}adapted_at'],
      ),
      general: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}general'],
      )!,
    );
  }

  @override
  $PlanDaysTable createAlias(String alias) {
    return $PlanDaysTable(attachedDatabase, alias);
  }
}

class PlanDay extends DataClass implements Insertable<PlanDay> {
  final String date;
  final String session;
  final String? original;
  final String? reason;
  final int? adaptedAt;
  final bool general;
  const PlanDay({
    required this.date,
    required this.session,
    this.original,
    this.reason,
    this.adaptedAt,
    required this.general,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['session'] = Variable<String>(session);
    if (!nullToAbsent || original != null) {
      map['original'] = Variable<String>(original);
    }
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    if (!nullToAbsent || adaptedAt != null) {
      map['adapted_at'] = Variable<int>(adaptedAt);
    }
    map['general'] = Variable<bool>(general);
    return map;
  }

  PlanDaysCompanion toCompanion(bool nullToAbsent) {
    return PlanDaysCompanion(
      date: Value(date),
      session: Value(session),
      original: original == null && nullToAbsent
          ? const Value.absent()
          : Value(original),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      adaptedAt: adaptedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(adaptedAt),
      general: Value(general),
    );
  }

  factory PlanDay.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanDay(
      date: serializer.fromJson<String>(json['date']),
      session: serializer.fromJson<String>(json['session']),
      original: serializer.fromJson<String?>(json['original']),
      reason: serializer.fromJson<String?>(json['reason']),
      adaptedAt: serializer.fromJson<int?>(json['adaptedAt']),
      general: serializer.fromJson<bool>(json['general']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'session': serializer.toJson<String>(session),
      'original': serializer.toJson<String?>(original),
      'reason': serializer.toJson<String?>(reason),
      'adaptedAt': serializer.toJson<int?>(adaptedAt),
      'general': serializer.toJson<bool>(general),
    };
  }

  PlanDay copyWith({
    String? date,
    String? session,
    Value<String?> original = const Value.absent(),
    Value<String?> reason = const Value.absent(),
    Value<int?> adaptedAt = const Value.absent(),
    bool? general,
  }) => PlanDay(
    date: date ?? this.date,
    session: session ?? this.session,
    original: original.present ? original.value : this.original,
    reason: reason.present ? reason.value : this.reason,
    adaptedAt: adaptedAt.present ? adaptedAt.value : this.adaptedAt,
    general: general ?? this.general,
  );
  PlanDay copyWithCompanion(PlanDaysCompanion data) {
    return PlanDay(
      date: data.date.present ? data.date.value : this.date,
      session: data.session.present ? data.session.value : this.session,
      original: data.original.present ? data.original.value : this.original,
      reason: data.reason.present ? data.reason.value : this.reason,
      adaptedAt: data.adaptedAt.present ? data.adaptedAt.value : this.adaptedAt,
      general: data.general.present ? data.general.value : this.general,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanDay(')
          ..write('date: $date, ')
          ..write('session: $session, ')
          ..write('original: $original, ')
          ..write('reason: $reason, ')
          ..write('adaptedAt: $adaptedAt, ')
          ..write('general: $general')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(date, session, original, reason, adaptedAt, general);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanDay &&
          other.date == this.date &&
          other.session == this.session &&
          other.original == this.original &&
          other.reason == this.reason &&
          other.adaptedAt == this.adaptedAt &&
          other.general == this.general);
}

class PlanDaysCompanion extends UpdateCompanion<PlanDay> {
  final Value<String> date;
  final Value<String> session;
  final Value<String?> original;
  final Value<String?> reason;
  final Value<int?> adaptedAt;
  final Value<bool> general;
  final Value<int> rowid;
  const PlanDaysCompanion({
    this.date = const Value.absent(),
    this.session = const Value.absent(),
    this.original = const Value.absent(),
    this.reason = const Value.absent(),
    this.adaptedAt = const Value.absent(),
    this.general = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlanDaysCompanion.insert({
    required String date,
    required String session,
    this.original = const Value.absent(),
    this.reason = const Value.absent(),
    this.adaptedAt = const Value.absent(),
    required bool general,
    this.rowid = const Value.absent(),
  }) : date = Value(date),
       session = Value(session),
       general = Value(general);
  static Insertable<PlanDay> custom({
    Expression<String>? date,
    Expression<String>? session,
    Expression<String>? original,
    Expression<String>? reason,
    Expression<int>? adaptedAt,
    Expression<bool>? general,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (session != null) 'session': session,
      if (original != null) 'original': original,
      if (reason != null) 'reason': reason,
      if (adaptedAt != null) 'adapted_at': adaptedAt,
      if (general != null) 'general': general,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlanDaysCompanion copyWith({
    Value<String>? date,
    Value<String>? session,
    Value<String?>? original,
    Value<String?>? reason,
    Value<int?>? adaptedAt,
    Value<bool>? general,
    Value<int>? rowid,
  }) {
    return PlanDaysCompanion(
      date: date ?? this.date,
      session: session ?? this.session,
      original: original ?? this.original,
      reason: reason ?? this.reason,
      adaptedAt: adaptedAt ?? this.adaptedAt,
      general: general ?? this.general,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (session.present) {
      map['session'] = Variable<String>(session.value);
    }
    if (original.present) {
      map['original'] = Variable<String>(original.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (adaptedAt.present) {
      map['adapted_at'] = Variable<int>(adaptedAt.value);
    }
    if (general.present) {
      map['general'] = Variable<bool>(general.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanDaysCompanion(')
          ..write('date: $date, ')
          ..write('session: $session, ')
          ..write('original: $original, ')
          ..write('reason: $reason, ')
          ..write('adaptedAt: $adaptedAt, ')
          ..write('general: $general, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncLogTable extends SyncLog with TableInfo<$SyncLogTable, SyncLogData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncLogTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<int> ts = GeneratedColumn<int>(
    'ts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resultMeta = const VerificationMeta('result');
  @override
  late final GeneratedColumn<String> result = GeneratedColumn<String>(
    'result',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, ts, summary, result, durationMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncLogData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    } else if (isInserting) {
      context.missing(_tsMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    } else if (isInserting) {
      context.missing(_summaryMeta);
    }
    if (data.containsKey('result')) {
      context.handle(
        _resultMeta,
        result.isAcceptableOrUnknown(data['result']!, _resultMeta),
      );
    } else if (isInserting) {
      context.missing(_resultMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncLogData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncLogData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      ts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ts'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      )!,
      result: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
    );
  }

  @override
  $SyncLogTable createAlias(String alias) {
    return $SyncLogTable(attachedDatabase, alias);
  }
}

class SyncLogData extends DataClass implements Insertable<SyncLogData> {
  final int id;
  final int ts;
  final String summary;
  final String result;
  final int? durationMs;
  const SyncLogData({
    required this.id,
    required this.ts,
    required this.summary,
    required this.result,
    this.durationMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['ts'] = Variable<int>(ts);
    map['summary'] = Variable<String>(summary);
    map['result'] = Variable<String>(result);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    return map;
  }

  SyncLogCompanion toCompanion(bool nullToAbsent) {
    return SyncLogCompanion(
      id: Value(id),
      ts: Value(ts),
      summary: Value(summary),
      result: Value(result),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
    );
  }

  factory SyncLogData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncLogData(
      id: serializer.fromJson<int>(json['id']),
      ts: serializer.fromJson<int>(json['ts']),
      summary: serializer.fromJson<String>(json['summary']),
      result: serializer.fromJson<String>(json['result']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'ts': serializer.toJson<int>(ts),
      'summary': serializer.toJson<String>(summary),
      'result': serializer.toJson<String>(result),
      'durationMs': serializer.toJson<int?>(durationMs),
    };
  }

  SyncLogData copyWith({
    int? id,
    int? ts,
    String? summary,
    String? result,
    Value<int?> durationMs = const Value.absent(),
  }) => SyncLogData(
    id: id ?? this.id,
    ts: ts ?? this.ts,
    summary: summary ?? this.summary,
    result: result ?? this.result,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
  );
  SyncLogData copyWithCompanion(SyncLogCompanion data) {
    return SyncLogData(
      id: data.id.present ? data.id.value : this.id,
      ts: data.ts.present ? data.ts.value : this.ts,
      summary: data.summary.present ? data.summary.value : this.summary,
      result: data.result.present ? data.result.value : this.result,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncLogData(')
          ..write('id: $id, ')
          ..write('ts: $ts, ')
          ..write('summary: $summary, ')
          ..write('result: $result, ')
          ..write('durationMs: $durationMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, ts, summary, result, durationMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncLogData &&
          other.id == this.id &&
          other.ts == this.ts &&
          other.summary == this.summary &&
          other.result == this.result &&
          other.durationMs == this.durationMs);
}

class SyncLogCompanion extends UpdateCompanion<SyncLogData> {
  final Value<int> id;
  final Value<int> ts;
  final Value<String> summary;
  final Value<String> result;
  final Value<int?> durationMs;
  const SyncLogCompanion({
    this.id = const Value.absent(),
    this.ts = const Value.absent(),
    this.summary = const Value.absent(),
    this.result = const Value.absent(),
    this.durationMs = const Value.absent(),
  });
  SyncLogCompanion.insert({
    this.id = const Value.absent(),
    required int ts,
    required String summary,
    required String result,
    this.durationMs = const Value.absent(),
  }) : ts = Value(ts),
       summary = Value(summary),
       result = Value(result);
  static Insertable<SyncLogData> custom({
    Expression<int>? id,
    Expression<int>? ts,
    Expression<String>? summary,
    Expression<String>? result,
    Expression<int>? durationMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ts != null) 'ts': ts,
      if (summary != null) 'summary': summary,
      if (result != null) 'result': result,
      if (durationMs != null) 'duration_ms': durationMs,
    });
  }

  SyncLogCompanion copyWith({
    Value<int>? id,
    Value<int>? ts,
    Value<String>? summary,
    Value<String>? result,
    Value<int?>? durationMs,
  }) {
    return SyncLogCompanion(
      id: id ?? this.id,
      ts: ts ?? this.ts,
      summary: summary ?? this.summary,
      result: result ?? this.result,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (ts.present) {
      map['ts'] = Variable<int>(ts.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (result.present) {
      map['result'] = Variable<String>(result.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncLogCompanion(')
          ..write('id: $id, ')
          ..write('ts: $ts, ')
          ..write('summary: $summary, ')
          ..write('result: $result, ')
          ..write('durationMs: $durationMs')
          ..write(')'))
        .toString();
  }
}

abstract class _$TempoDb extends GeneratedDatabase {
  _$TempoDb(QueryExecutor e) : super(e);
  $TempoDbManager get managers => $TempoDbManager(this);
  late final $MinuteSamplesTable minuteSamples = $MinuteSamplesTable(this);
  late final $HrLiveTable hrLive = $HrLiveTable(this);
  late final $StressSamplesTable stressSamples = $StressSamplesTable(this);
  late final $Spo2SamplesTable spo2Samples = $Spo2SamplesTable(this);
  late final $BandWorkoutsTable bandWorkouts = $BandWorkoutsTable(this);
  late final $OdEventsTable odEvents = $OdEventsTable(this);
  late final $SleepSessionsTable sleepSessions = $SleepSessionsTable(this);
  late final $DailyScoresTable dailyScores = $DailyScoresTable(this);
  late final $BaselinesTable baselines = $BaselinesTable(this);
  late final $JournalTable journal = $JournalTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $WorkoutsTable workouts = $WorkoutsTable(this);
  late final $PlanDaysTable planDays = $PlanDaysTable(this);
  late final $SyncLogTable syncLog = $SyncLogTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    minuteSamples,
    hrLive,
    stressSamples,
    spo2Samples,
    bandWorkouts,
    odEvents,
    sleepSessions,
    dailyScores,
    baselines,
    journal,
    syncState,
    settings,
    workouts,
    planDays,
    syncLog,
  ];
}

typedef $$MinuteSamplesTableCreateCompanionBuilder =
    MinuteSamplesCompanion Function({
      Value<int> ts,
      required int steps,
      required int intensity,
      required int kind,
      Value<int?> aux,
      Value<int?> hr,
    });
typedef $$MinuteSamplesTableUpdateCompanionBuilder =
    MinuteSamplesCompanion Function({
      Value<int> ts,
      Value<int> steps,
      Value<int> intensity,
      Value<int> kind,
      Value<int?> aux,
      Value<int?> hr,
    });

class $$MinuteSamplesTableFilterComposer
    extends Composer<_$TempoDb, $MinuteSamplesTable> {
  $$MinuteSamplesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intensity => $composableBuilder(
    column: $table.intensity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get aux => $composableBuilder(
    column: $table.aux,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hr => $composableBuilder(
    column: $table.hr,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MinuteSamplesTableOrderingComposer
    extends Composer<_$TempoDb, $MinuteSamplesTable> {
  $$MinuteSamplesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intensity => $composableBuilder(
    column: $table.intensity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get aux => $composableBuilder(
    column: $table.aux,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hr => $composableBuilder(
    column: $table.hr,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MinuteSamplesTableAnnotationComposer
    extends Composer<_$TempoDb, $MinuteSamplesTable> {
  $$MinuteSamplesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<int> get steps =>
      $composableBuilder(column: $table.steps, builder: (column) => column);

  GeneratedColumn<int> get intensity =>
      $composableBuilder(column: $table.intensity, builder: (column) => column);

  GeneratedColumn<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get aux =>
      $composableBuilder(column: $table.aux, builder: (column) => column);

  GeneratedColumn<int> get hr =>
      $composableBuilder(column: $table.hr, builder: (column) => column);
}

class $$MinuteSamplesTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $MinuteSamplesTable,
          MinuteSample,
          $$MinuteSamplesTableFilterComposer,
          $$MinuteSamplesTableOrderingComposer,
          $$MinuteSamplesTableAnnotationComposer,
          $$MinuteSamplesTableCreateCompanionBuilder,
          $$MinuteSamplesTableUpdateCompanionBuilder,
          (
            MinuteSample,
            BaseReferences<_$TempoDb, $MinuteSamplesTable, MinuteSample>,
          ),
          MinuteSample,
          PrefetchHooks Function()
        > {
  $$MinuteSamplesTableTableManager(_$TempoDb db, $MinuteSamplesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MinuteSamplesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MinuteSamplesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MinuteSamplesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> ts = const Value.absent(),
                Value<int> steps = const Value.absent(),
                Value<int> intensity = const Value.absent(),
                Value<int> kind = const Value.absent(),
                Value<int?> aux = const Value.absent(),
                Value<int?> hr = const Value.absent(),
              }) => MinuteSamplesCompanion(
                ts: ts,
                steps: steps,
                intensity: intensity,
                kind: kind,
                aux: aux,
                hr: hr,
              ),
          createCompanionCallback:
              ({
                Value<int> ts = const Value.absent(),
                required int steps,
                required int intensity,
                required int kind,
                Value<int?> aux = const Value.absent(),
                Value<int?> hr = const Value.absent(),
              }) => MinuteSamplesCompanion.insert(
                ts: ts,
                steps: steps,
                intensity: intensity,
                kind: kind,
                aux: aux,
                hr: hr,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MinuteSamplesTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $MinuteSamplesTable,
      MinuteSample,
      $$MinuteSamplesTableFilterComposer,
      $$MinuteSamplesTableOrderingComposer,
      $$MinuteSamplesTableAnnotationComposer,
      $$MinuteSamplesTableCreateCompanionBuilder,
      $$MinuteSamplesTableUpdateCompanionBuilder,
      (
        MinuteSample,
        BaseReferences<_$TempoDb, $MinuteSamplesTable, MinuteSample>,
      ),
      MinuteSample,
      PrefetchHooks Function()
    >;
typedef $$HrLiveTableCreateCompanionBuilder = HrLiveCompanion Function({
  Value<int> ts,
  required int bpm,
  Value<String> source,
});
typedef $$HrLiveTableUpdateCompanionBuilder = HrLiveCompanion Function({
  Value<int> ts,
  Value<int> bpm,
  Value<String> source,
});

class $$HrLiveTableFilterComposer extends Composer<_$TempoDb, $HrLiveTable> {
  $$HrLiveTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bpm => $composableBuilder(
    column: $table.bpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HrLiveTableOrderingComposer extends Composer<_$TempoDb, $HrLiveTable> {
  $$HrLiveTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bpm => $composableBuilder(
    column: $table.bpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HrLiveTableAnnotationComposer
    extends Composer<_$TempoDb, $HrLiveTable> {
  $$HrLiveTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<int> get bpm =>
      $composableBuilder(column: $table.bpm, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$HrLiveTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $HrLiveTable,
          HrLiveData,
          $$HrLiveTableFilterComposer,
          $$HrLiveTableOrderingComposer,
          $$HrLiveTableAnnotationComposer,
          $$HrLiveTableCreateCompanionBuilder,
          $$HrLiveTableUpdateCompanionBuilder,
          (HrLiveData, BaseReferences<_$TempoDb, $HrLiveTable, HrLiveData>),
          HrLiveData,
          PrefetchHooks Function()
        > {
  $$HrLiveTableTableManager(_$TempoDb db, $HrLiveTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HrLiveTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HrLiveTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HrLiveTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> ts = const Value.absent(),
            Value<int> bpm = const Value.absent(),
            Value<String> source = const Value.absent(),
          }) => HrLiveCompanion(ts: ts, bpm: bpm, source: source),
          createCompanionCallback: ({
            Value<int> ts = const Value.absent(),
            required int bpm,
            Value<String> source = const Value.absent(),
          }) => HrLiveCompanion.insert(ts: ts, bpm: bpm, source: source),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HrLiveTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $HrLiveTable,
      HrLiveData,
      $$HrLiveTableFilterComposer,
      $$HrLiveTableOrderingComposer,
      $$HrLiveTableAnnotationComposer,
      $$HrLiveTableCreateCompanionBuilder,
      $$HrLiveTableUpdateCompanionBuilder,
      (HrLiveData, BaseReferences<_$TempoDb, $HrLiveTable, HrLiveData>),
      HrLiveData,
      PrefetchHooks Function()
    >;
typedef $$StressSamplesTableCreateCompanionBuilder =
    StressSamplesCompanion Function({Value<int> ts, required int value});
typedef $$StressSamplesTableUpdateCompanionBuilder =
    StressSamplesCompanion Function({Value<int> ts, Value<int> value});

class $$StressSamplesTableFilterComposer
    extends Composer<_$TempoDb, $StressSamplesTable> {
  $$StressSamplesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StressSamplesTableOrderingComposer
    extends Composer<_$TempoDb, $StressSamplesTable> {
  $$StressSamplesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StressSamplesTableAnnotationComposer
    extends Composer<_$TempoDb, $StressSamplesTable> {
  $$StressSamplesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<int> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$StressSamplesTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $StressSamplesTable,
          StressSample,
          $$StressSamplesTableFilterComposer,
          $$StressSamplesTableOrderingComposer,
          $$StressSamplesTableAnnotationComposer,
          $$StressSamplesTableCreateCompanionBuilder,
          $$StressSamplesTableUpdateCompanionBuilder,
          (
            StressSample,
            BaseReferences<_$TempoDb, $StressSamplesTable, StressSample>,
          ),
          StressSample,
          PrefetchHooks Function()
        > {
  $$StressSamplesTableTableManager(_$TempoDb db, $StressSamplesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StressSamplesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StressSamplesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StressSamplesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> ts = const Value.absent(),
            Value<int> value = const Value.absent(),
          }) => StressSamplesCompanion(ts: ts, value: value),
          createCompanionCallback: ({
            Value<int> ts = const Value.absent(),
            required int value,
          }) => StressSamplesCompanion.insert(ts: ts, value: value),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StressSamplesTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $StressSamplesTable,
      StressSample,
      $$StressSamplesTableFilterComposer,
      $$StressSamplesTableOrderingComposer,
      $$StressSamplesTableAnnotationComposer,
      $$StressSamplesTableCreateCompanionBuilder,
      $$StressSamplesTableUpdateCompanionBuilder,
      (
        StressSample,
        BaseReferences<_$TempoDb, $StressSamplesTable, StressSample>,
      ),
      StressSample,
      PrefetchHooks Function()
    >;
typedef $$Spo2SamplesTableCreateCompanionBuilder =
    Spo2SamplesCompanion Function({
      Value<int> ts,
      required int value,
      Value<int?> quality,
    });
typedef $$Spo2SamplesTableUpdateCompanionBuilder =
    Spo2SamplesCompanion Function({
      Value<int> ts,
      Value<int> value,
      Value<int?> quality,
    });

class $$Spo2SamplesTableFilterComposer
    extends Composer<_$TempoDb, $Spo2SamplesTable> {
  $$Spo2SamplesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Spo2SamplesTableOrderingComposer
    extends Composer<_$TempoDb, $Spo2SamplesTable> {
  $$Spo2SamplesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Spo2SamplesTableAnnotationComposer
    extends Composer<_$TempoDb, $Spo2SamplesTable> {
  $$Spo2SamplesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<int> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get quality =>
      $composableBuilder(column: $table.quality, builder: (column) => column);
}

class $$Spo2SamplesTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $Spo2SamplesTable,
          Spo2Sample,
          $$Spo2SamplesTableFilterComposer,
          $$Spo2SamplesTableOrderingComposer,
          $$Spo2SamplesTableAnnotationComposer,
          $$Spo2SamplesTableCreateCompanionBuilder,
          $$Spo2SamplesTableUpdateCompanionBuilder,
          (
            Spo2Sample,
            BaseReferences<_$TempoDb, $Spo2SamplesTable, Spo2Sample>,
          ),
          Spo2Sample,
          PrefetchHooks Function()
        > {
  $$Spo2SamplesTableTableManager(_$TempoDb db, $Spo2SamplesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Spo2SamplesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Spo2SamplesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Spo2SamplesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> ts = const Value.absent(),
            Value<int> value = const Value.absent(),
            Value<int?> quality = const Value.absent(),
          }) => Spo2SamplesCompanion(ts: ts, value: value, quality: quality),
          createCompanionCallback:
              ({
                Value<int> ts = const Value.absent(),
                required int value,
                Value<int?> quality = const Value.absent(),
              }) => Spo2SamplesCompanion.insert(
                ts: ts,
                value: value,
                quality: quality,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$Spo2SamplesTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $Spo2SamplesTable,
      Spo2Sample,
      $$Spo2SamplesTableFilterComposer,
      $$Spo2SamplesTableOrderingComposer,
      $$Spo2SamplesTableAnnotationComposer,
      $$Spo2SamplesTableCreateCompanionBuilder,
      $$Spo2SamplesTableUpdateCompanionBuilder,
      (Spo2Sample, BaseReferences<_$TempoDb, $Spo2SamplesTable, Spo2Sample>),
      Spo2Sample,
      PrefetchHooks Function()
    >;
typedef $$BandWorkoutsTableCreateCompanionBuilder =
    BandWorkoutsCompanion Function({
      Value<int> start,
      required int end,
      required int kind,
      required String raw,
      required int fetchedAt,
    });
typedef $$BandWorkoutsTableUpdateCompanionBuilder =
    BandWorkoutsCompanion Function({
      Value<int> start,
      Value<int> end,
      Value<int> kind,
      Value<String> raw,
      Value<int> fetchedAt,
    });

class $$BandWorkoutsTableFilterComposer
    extends Composer<_$TempoDb, $BandWorkoutsTable> {
  $$BandWorkoutsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get start => $composableBuilder(
    column: $table.start,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get end => $composableBuilder(
    column: $table.end,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get raw => $composableBuilder(
    column: $table.raw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BandWorkoutsTableOrderingComposer
    extends Composer<_$TempoDb, $BandWorkoutsTable> {
  $$BandWorkoutsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get start => $composableBuilder(
    column: $table.start,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get end => $composableBuilder(
    column: $table.end,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get raw => $composableBuilder(
    column: $table.raw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BandWorkoutsTableAnnotationComposer
    extends Composer<_$TempoDb, $BandWorkoutsTable> {
  $$BandWorkoutsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get start =>
      $composableBuilder(column: $table.start, builder: (column) => column);

  GeneratedColumn<int> get end =>
      $composableBuilder(column: $table.end, builder: (column) => column);

  GeneratedColumn<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get raw =>
      $composableBuilder(column: $table.raw, builder: (column) => column);

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$BandWorkoutsTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $BandWorkoutsTable,
          BandWorkoutRow,
          $$BandWorkoutsTableFilterComposer,
          $$BandWorkoutsTableOrderingComposer,
          $$BandWorkoutsTableAnnotationComposer,
          $$BandWorkoutsTableCreateCompanionBuilder,
          $$BandWorkoutsTableUpdateCompanionBuilder,
          (
            BandWorkoutRow,
            BaseReferences<_$TempoDb, $BandWorkoutsTable, BandWorkoutRow>,
          ),
          BandWorkoutRow,
          PrefetchHooks Function()
        > {
  $$BandWorkoutsTableTableManager(_$TempoDb db, $BandWorkoutsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BandWorkoutsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BandWorkoutsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BandWorkoutsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> start = const Value.absent(),
                Value<int> end = const Value.absent(),
                Value<int> kind = const Value.absent(),
                Value<String> raw = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
              }) => BandWorkoutsCompanion(
                start: start,
                end: end,
                kind: kind,
                raw: raw,
                fetchedAt: fetchedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> start = const Value.absent(),
                required int end,
                required int kind,
                required String raw,
                required int fetchedAt,
              }) => BandWorkoutsCompanion.insert(
                start: start,
                end: end,
                kind: kind,
                raw: raw,
                fetchedAt: fetchedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BandWorkoutsTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $BandWorkoutsTable,
      BandWorkoutRow,
      $$BandWorkoutsTableFilterComposer,
      $$BandWorkoutsTableOrderingComposer,
      $$BandWorkoutsTableAnnotationComposer,
      $$BandWorkoutsTableCreateCompanionBuilder,
      $$BandWorkoutsTableUpdateCompanionBuilder,
      (
        BandWorkoutRow,
        BaseReferences<_$TempoDb, $BandWorkoutsTable, BandWorkoutRow>,
      ),
      BandWorkoutRow,
      PrefetchHooks Function()
    >;
typedef $$OdEventsTableCreateCompanionBuilder = OdEventsCompanion Function({
  Value<int> ts,
  required int drop,
  required String spo2,
  required String hr,
});
typedef $$OdEventsTableUpdateCompanionBuilder = OdEventsCompanion Function({
  Value<int> ts,
  Value<int> drop,
  Value<String> spo2,
  Value<String> hr,
});

class $$OdEventsTableFilterComposer
    extends Composer<_$TempoDb, $OdEventsTable> {
  $$OdEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get drop => $composableBuilder(
    column: $table.drop,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get spo2 => $composableBuilder(
    column: $table.spo2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hr => $composableBuilder(
    column: $table.hr,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OdEventsTableOrderingComposer
    extends Composer<_$TempoDb, $OdEventsTable> {
  $$OdEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get drop => $composableBuilder(
    column: $table.drop,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get spo2 => $composableBuilder(
    column: $table.spo2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hr => $composableBuilder(
    column: $table.hr,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OdEventsTableAnnotationComposer
    extends Composer<_$TempoDb, $OdEventsTable> {
  $$OdEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<int> get drop =>
      $composableBuilder(column: $table.drop, builder: (column) => column);

  GeneratedColumn<String> get spo2 =>
      $composableBuilder(column: $table.spo2, builder: (column) => column);

  GeneratedColumn<String> get hr =>
      $composableBuilder(column: $table.hr, builder: (column) => column);
}

class $$OdEventsTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $OdEventsTable,
          OdEventRow,
          $$OdEventsTableFilterComposer,
          $$OdEventsTableOrderingComposer,
          $$OdEventsTableAnnotationComposer,
          $$OdEventsTableCreateCompanionBuilder,
          $$OdEventsTableUpdateCompanionBuilder,
          (OdEventRow, BaseReferences<_$TempoDb, $OdEventsTable, OdEventRow>),
          OdEventRow,
          PrefetchHooks Function()
        > {
  $$OdEventsTableTableManager(_$TempoDb db, $OdEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OdEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OdEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OdEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> ts = const Value.absent(),
            Value<int> drop = const Value.absent(),
            Value<String> spo2 = const Value.absent(),
            Value<String> hr = const Value.absent(),
          }) => OdEventsCompanion(ts: ts, drop: drop, spo2: spo2, hr: hr),
          createCompanionCallback:
              ({
                Value<int> ts = const Value.absent(),
                required int drop,
                required String spo2,
                required String hr,
              }) => OdEventsCompanion.insert(
                ts: ts,
                drop: drop,
                spo2: spo2,
                hr: hr,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OdEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $OdEventsTable,
      OdEventRow,
      $$OdEventsTableFilterComposer,
      $$OdEventsTableOrderingComposer,
      $$OdEventsTableAnnotationComposer,
      $$OdEventsTableCreateCompanionBuilder,
      $$OdEventsTableUpdateCompanionBuilder,
      (OdEventRow, BaseReferences<_$TempoDb, $OdEventsTable, OdEventRow>),
      OdEventRow,
      PrefetchHooks Function()
    >;
typedef $$SleepSessionsTableCreateCompanionBuilder =
    SleepSessionsCompanion Function({
      Value<int> id,
      required int start,
      required int end,
      required String stages,
      required int algoVersion,
    });
typedef $$SleepSessionsTableUpdateCompanionBuilder =
    SleepSessionsCompanion Function({
      Value<int> id,
      Value<int> start,
      Value<int> end,
      Value<String> stages,
      Value<int> algoVersion,
    });

class $$SleepSessionsTableFilterComposer
    extends Composer<_$TempoDb, $SleepSessionsTable> {
  $$SleepSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get start => $composableBuilder(
    column: $table.start,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get end => $composableBuilder(
    column: $table.end,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stages => $composableBuilder(
    column: $table.stages,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get algoVersion => $composableBuilder(
    column: $table.algoVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SleepSessionsTableOrderingComposer
    extends Composer<_$TempoDb, $SleepSessionsTable> {
  $$SleepSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get start => $composableBuilder(
    column: $table.start,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get end => $composableBuilder(
    column: $table.end,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stages => $composableBuilder(
    column: $table.stages,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get algoVersion => $composableBuilder(
    column: $table.algoVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SleepSessionsTableAnnotationComposer
    extends Composer<_$TempoDb, $SleepSessionsTable> {
  $$SleepSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get start =>
      $composableBuilder(column: $table.start, builder: (column) => column);

  GeneratedColumn<int> get end =>
      $composableBuilder(column: $table.end, builder: (column) => column);

  GeneratedColumn<String> get stages =>
      $composableBuilder(column: $table.stages, builder: (column) => column);

  GeneratedColumn<int> get algoVersion => $composableBuilder(
    column: $table.algoVersion,
    builder: (column) => column,
  );
}

class $$SleepSessionsTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $SleepSessionsTable,
          SleepSession,
          $$SleepSessionsTableFilterComposer,
          $$SleepSessionsTableOrderingComposer,
          $$SleepSessionsTableAnnotationComposer,
          $$SleepSessionsTableCreateCompanionBuilder,
          $$SleepSessionsTableUpdateCompanionBuilder,
          (
            SleepSession,
            BaseReferences<_$TempoDb, $SleepSessionsTable, SleepSession>,
          ),
          SleepSession,
          PrefetchHooks Function()
        > {
  $$SleepSessionsTableTableManager(_$TempoDb db, $SleepSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SleepSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SleepSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SleepSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> start = const Value.absent(),
                Value<int> end = const Value.absent(),
                Value<String> stages = const Value.absent(),
                Value<int> algoVersion = const Value.absent(),
              }) => SleepSessionsCompanion(
                id: id,
                start: start,
                end: end,
                stages: stages,
                algoVersion: algoVersion,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int start,
                required int end,
                required String stages,
                required int algoVersion,
              }) => SleepSessionsCompanion.insert(
                id: id,
                start: start,
                end: end,
                stages: stages,
                algoVersion: algoVersion,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SleepSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $SleepSessionsTable,
      SleepSession,
      $$SleepSessionsTableFilterComposer,
      $$SleepSessionsTableOrderingComposer,
      $$SleepSessionsTableAnnotationComposer,
      $$SleepSessionsTableCreateCompanionBuilder,
      $$SleepSessionsTableUpdateCompanionBuilder,
      (
        SleepSession,
        BaseReferences<_$TempoDb, $SleepSessionsTable, SleepSession>,
      ),
      SleepSession,
      PrefetchHooks Function()
    >;
typedef $$DailyScoresTableCreateCompanionBuilder =
    DailyScoresCompanion Function({
      required String date,
      required double strain,
      required double trimp,
      required int hrMax,
      Value<double?> sleepPerf,
      Value<double?> sleptHours,
      Value<double?> needHours,
      Value<double> napHours,
      Value<double?> baseNeed,
      Value<int?> sleepStart,
      Value<int?> sleepEnd,
      Value<double?> recovery,
      Value<double?> rhr,
      Value<double?> hrvProxy,
      required bool calibrating,
      required int algoVersion,
      Value<int> rowid,
    });
typedef $$DailyScoresTableUpdateCompanionBuilder =
    DailyScoresCompanion Function({
      Value<String> date,
      Value<double> strain,
      Value<double> trimp,
      Value<int> hrMax,
      Value<double?> sleepPerf,
      Value<double?> sleptHours,
      Value<double?> needHours,
      Value<double> napHours,
      Value<double?> baseNeed,
      Value<int?> sleepStart,
      Value<int?> sleepEnd,
      Value<double?> recovery,
      Value<double?> rhr,
      Value<double?> hrvProxy,
      Value<bool> calibrating,
      Value<int> algoVersion,
      Value<int> rowid,
    });

class $$DailyScoresTableFilterComposer
    extends Composer<_$TempoDb, $DailyScoresTable> {
  $$DailyScoresTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get strain => $composableBuilder(
    column: $table.strain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get trimp => $composableBuilder(
    column: $table.trimp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hrMax => $composableBuilder(
    column: $table.hrMax,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sleepPerf => $composableBuilder(
    column: $table.sleepPerf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sleptHours => $composableBuilder(
    column: $table.sleptHours,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get needHours => $composableBuilder(
    column: $table.needHours,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get napHours => $composableBuilder(
    column: $table.napHours,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get baseNeed => $composableBuilder(
    column: $table.baseNeed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sleepStart => $composableBuilder(
    column: $table.sleepStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sleepEnd => $composableBuilder(
    column: $table.sleepEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get recovery => $composableBuilder(
    column: $table.recovery,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rhr => $composableBuilder(
    column: $table.rhr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get hrvProxy => $composableBuilder(
    column: $table.hrvProxy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get calibrating => $composableBuilder(
    column: $table.calibrating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get algoVersion => $composableBuilder(
    column: $table.algoVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyScoresTableOrderingComposer
    extends Composer<_$TempoDb, $DailyScoresTable> {
  $$DailyScoresTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get strain => $composableBuilder(
    column: $table.strain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get trimp => $composableBuilder(
    column: $table.trimp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hrMax => $composableBuilder(
    column: $table.hrMax,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sleepPerf => $composableBuilder(
    column: $table.sleepPerf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sleptHours => $composableBuilder(
    column: $table.sleptHours,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get needHours => $composableBuilder(
    column: $table.needHours,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get napHours => $composableBuilder(
    column: $table.napHours,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get baseNeed => $composableBuilder(
    column: $table.baseNeed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sleepStart => $composableBuilder(
    column: $table.sleepStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sleepEnd => $composableBuilder(
    column: $table.sleepEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get recovery => $composableBuilder(
    column: $table.recovery,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rhr => $composableBuilder(
    column: $table.rhr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get hrvProxy => $composableBuilder(
    column: $table.hrvProxy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get calibrating => $composableBuilder(
    column: $table.calibrating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get algoVersion => $composableBuilder(
    column: $table.algoVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyScoresTableAnnotationComposer
    extends Composer<_$TempoDb, $DailyScoresTable> {
  $$DailyScoresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<double> get strain =>
      $composableBuilder(column: $table.strain, builder: (column) => column);

  GeneratedColumn<double> get trimp =>
      $composableBuilder(column: $table.trimp, builder: (column) => column);

  GeneratedColumn<int> get hrMax =>
      $composableBuilder(column: $table.hrMax, builder: (column) => column);

  GeneratedColumn<double> get sleepPerf =>
      $composableBuilder(column: $table.sleepPerf, builder: (column) => column);

  GeneratedColumn<double> get sleptHours => $composableBuilder(
    column: $table.sleptHours,
    builder: (column) => column,
  );

  GeneratedColumn<double> get needHours =>
      $composableBuilder(column: $table.needHours, builder: (column) => column);

  GeneratedColumn<double> get napHours =>
      $composableBuilder(column: $table.napHours, builder: (column) => column);

  GeneratedColumn<double> get baseNeed =>
      $composableBuilder(column: $table.baseNeed, builder: (column) => column);

  GeneratedColumn<int> get sleepStart => $composableBuilder(
    column: $table.sleepStart,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sleepEnd =>
      $composableBuilder(column: $table.sleepEnd, builder: (column) => column);

  GeneratedColumn<double> get recovery =>
      $composableBuilder(column: $table.recovery, builder: (column) => column);

  GeneratedColumn<double> get rhr =>
      $composableBuilder(column: $table.rhr, builder: (column) => column);

  GeneratedColumn<double> get hrvProxy =>
      $composableBuilder(column: $table.hrvProxy, builder: (column) => column);

  GeneratedColumn<bool> get calibrating => $composableBuilder(
    column: $table.calibrating,
    builder: (column) => column,
  );

  GeneratedColumn<int> get algoVersion => $composableBuilder(
    column: $table.algoVersion,
    builder: (column) => column,
  );
}

class $$DailyScoresTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $DailyScoresTable,
          DailyScore,
          $$DailyScoresTableFilterComposer,
          $$DailyScoresTableOrderingComposer,
          $$DailyScoresTableAnnotationComposer,
          $$DailyScoresTableCreateCompanionBuilder,
          $$DailyScoresTableUpdateCompanionBuilder,
          (
            DailyScore,
            BaseReferences<_$TempoDb, $DailyScoresTable, DailyScore>,
          ),
          DailyScore,
          PrefetchHooks Function()
        > {
  $$DailyScoresTableTableManager(_$TempoDb db, $DailyScoresTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyScoresTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyScoresTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyScoresTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> date = const Value.absent(),
                Value<double> strain = const Value.absent(),
                Value<double> trimp = const Value.absent(),
                Value<int> hrMax = const Value.absent(),
                Value<double?> sleepPerf = const Value.absent(),
                Value<double?> sleptHours = const Value.absent(),
                Value<double?> needHours = const Value.absent(),
                Value<double> napHours = const Value.absent(),
                Value<double?> baseNeed = const Value.absent(),
                Value<int?> sleepStart = const Value.absent(),
                Value<int?> sleepEnd = const Value.absent(),
                Value<double?> recovery = const Value.absent(),
                Value<double?> rhr = const Value.absent(),
                Value<double?> hrvProxy = const Value.absent(),
                Value<bool> calibrating = const Value.absent(),
                Value<int> algoVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyScoresCompanion(
                date: date,
                strain: strain,
                trimp: trimp,
                hrMax: hrMax,
                sleepPerf: sleepPerf,
                sleptHours: sleptHours,
                needHours: needHours,
                napHours: napHours,
                baseNeed: baseNeed,
                sleepStart: sleepStart,
                sleepEnd: sleepEnd,
                recovery: recovery,
                rhr: rhr,
                hrvProxy: hrvProxy,
                calibrating: calibrating,
                algoVersion: algoVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String date,
                required double strain,
                required double trimp,
                required int hrMax,
                Value<double?> sleepPerf = const Value.absent(),
                Value<double?> sleptHours = const Value.absent(),
                Value<double?> needHours = const Value.absent(),
                Value<double> napHours = const Value.absent(),
                Value<double?> baseNeed = const Value.absent(),
                Value<int?> sleepStart = const Value.absent(),
                Value<int?> sleepEnd = const Value.absent(),
                Value<double?> recovery = const Value.absent(),
                Value<double?> rhr = const Value.absent(),
                Value<double?> hrvProxy = const Value.absent(),
                required bool calibrating,
                required int algoVersion,
                Value<int> rowid = const Value.absent(),
              }) => DailyScoresCompanion.insert(
                date: date,
                strain: strain,
                trimp: trimp,
                hrMax: hrMax,
                sleepPerf: sleepPerf,
                sleptHours: sleptHours,
                needHours: needHours,
                napHours: napHours,
                baseNeed: baseNeed,
                sleepStart: sleepStart,
                sleepEnd: sleepEnd,
                recovery: recovery,
                rhr: rhr,
                hrvProxy: hrvProxy,
                calibrating: calibrating,
                algoVersion: algoVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyScoresTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $DailyScoresTable,
      DailyScore,
      $$DailyScoresTableFilterComposer,
      $$DailyScoresTableOrderingComposer,
      $$DailyScoresTableAnnotationComposer,
      $$DailyScoresTableCreateCompanionBuilder,
      $$DailyScoresTableUpdateCompanionBuilder,
      (DailyScore, BaseReferences<_$TempoDb, $DailyScoresTable, DailyScore>),
      DailyScore,
      PrefetchHooks Function()
    >;
typedef $$BaselinesTableCreateCompanionBuilder = BaselinesCompanion Function({
  required String metric,
  required int window,
  required double mean,
  required double sd,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$BaselinesTableUpdateCompanionBuilder = BaselinesCompanion Function({
  Value<String> metric,
  Value<int> window,
  Value<double> mean,
  Value<double> sd,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$BaselinesTableFilterComposer
    extends Composer<_$TempoDb, $BaselinesTable> {
  $$BaselinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get metric => $composableBuilder(
    column: $table.metric,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get window => $composableBuilder(
    column: $table.window,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get mean => $composableBuilder(
    column: $table.mean,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sd => $composableBuilder(
    column: $table.sd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BaselinesTableOrderingComposer
    extends Composer<_$TempoDb, $BaselinesTable> {
  $$BaselinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get metric => $composableBuilder(
    column: $table.metric,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get window => $composableBuilder(
    column: $table.window,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get mean => $composableBuilder(
    column: $table.mean,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sd => $composableBuilder(
    column: $table.sd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BaselinesTableAnnotationComposer
    extends Composer<_$TempoDb, $BaselinesTable> {
  $$BaselinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get metric =>
      $composableBuilder(column: $table.metric, builder: (column) => column);

  GeneratedColumn<int> get window =>
      $composableBuilder(column: $table.window, builder: (column) => column);

  GeneratedColumn<double> get mean =>
      $composableBuilder(column: $table.mean, builder: (column) => column);

  GeneratedColumn<double> get sd =>
      $composableBuilder(column: $table.sd, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$BaselinesTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $BaselinesTable,
          Baseline,
          $$BaselinesTableFilterComposer,
          $$BaselinesTableOrderingComposer,
          $$BaselinesTableAnnotationComposer,
          $$BaselinesTableCreateCompanionBuilder,
          $$BaselinesTableUpdateCompanionBuilder,
          (Baseline, BaseReferences<_$TempoDb, $BaselinesTable, Baseline>),
          Baseline,
          PrefetchHooks Function()
        > {
  $$BaselinesTableTableManager(_$TempoDb db, $BaselinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BaselinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BaselinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BaselinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> metric = const Value.absent(),
                Value<int> window = const Value.absent(),
                Value<double> mean = const Value.absent(),
                Value<double> sd = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BaselinesCompanion(
                metric: metric,
                window: window,
                mean: mean,
                sd: sd,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String metric,
                required int window,
                required double mean,
                required double sd,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BaselinesCompanion.insert(
                metric: metric,
                window: window,
                mean: mean,
                sd: sd,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BaselinesTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $BaselinesTable,
      Baseline,
      $$BaselinesTableFilterComposer,
      $$BaselinesTableOrderingComposer,
      $$BaselinesTableAnnotationComposer,
      $$BaselinesTableCreateCompanionBuilder,
      $$BaselinesTableUpdateCompanionBuilder,
      (Baseline, BaseReferences<_$TempoDb, $BaselinesTable, Baseline>),
      Baseline,
      PrefetchHooks Function()
    >;
typedef $$JournalTableCreateCompanionBuilder = JournalCompanion Function({
  required String date,
  required String tag,
  required bool value,
  Value<int> rowid,
});
typedef $$JournalTableUpdateCompanionBuilder = JournalCompanion Function({
  Value<String> date,
  Value<String> tag,
  Value<bool> value,
  Value<int> rowid,
});

class $$JournalTableFilterComposer extends Composer<_$TempoDb, $JournalTable> {
  $$JournalTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$JournalTableOrderingComposer
    extends Composer<_$TempoDb, $JournalTable> {
  $$JournalTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$JournalTableAnnotationComposer
    extends Composer<_$TempoDb, $JournalTable> {
  $$JournalTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);

  GeneratedColumn<bool> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$JournalTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $JournalTable,
          JournalData,
          $$JournalTableFilterComposer,
          $$JournalTableOrderingComposer,
          $$JournalTableAnnotationComposer,
          $$JournalTableCreateCompanionBuilder,
          $$JournalTableUpdateCompanionBuilder,
          (JournalData, BaseReferences<_$TempoDb, $JournalTable, JournalData>),
          JournalData,
          PrefetchHooks Function()
        > {
  $$JournalTableTableManager(_$TempoDb db, $JournalTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JournalTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JournalTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JournalTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> date = const Value.absent(),
                Value<String> tag = const Value.absent(),
                Value<bool> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JournalCompanion(
                date: date,
                tag: tag,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String date,
                required String tag,
                required bool value,
                Value<int> rowid = const Value.absent(),
              }) => JournalCompanion.insert(
                date: date,
                tag: tag,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$JournalTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $JournalTable,
      JournalData,
      $$JournalTableFilterComposer,
      $$JournalTableOrderingComposer,
      $$JournalTableAnnotationComposer,
      $$JournalTableCreateCompanionBuilder,
      $$JournalTableUpdateCompanionBuilder,
      (JournalData, BaseReferences<_$TempoDb, $JournalTable, JournalData>),
      JournalData,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  required String device,
  required String dataType,
  required int lastTs,
  Value<int> rowid,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<String> device,
  Value<String> dataType,
  Value<int> lastTs,
  Value<int> rowid,
});

class $$SyncStateTableFilterComposer
    extends Composer<_$TempoDb, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get device => $composableBuilder(
    column: $table.device,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataType => $composableBuilder(
    column: $table.dataType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastTs => $composableBuilder(
    column: $table.lastTs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$TempoDb, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get device => $composableBuilder(
    column: $table.device,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataType => $composableBuilder(
    column: $table.dataType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastTs => $composableBuilder(
    column: $table.lastTs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$TempoDb, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get device =>
      $composableBuilder(column: $table.device, builder: (column) => column);

  GeneratedColumn<String> get dataType =>
      $composableBuilder(column: $table.dataType, builder: (column) => column);

  GeneratedColumn<int> get lastTs =>
      $composableBuilder(column: $table.lastTs, builder: (column) => column);
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateData,
            BaseReferences<_$TempoDb, $SyncStateTable, SyncStateData>,
          ),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$TempoDb db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> device = const Value.absent(),
                Value<String> dataType = const Value.absent(),
                Value<int> lastTs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion(
                device: device,
                dataType: dataType,
                lastTs: lastTs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String device,
                required String dataType,
                required int lastTs,
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion.insert(
                device: device,
                dataType: dataType,
                lastTs: lastTs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateData,
        BaseReferences<_$TempoDb, $SyncStateTable, SyncStateData>,
      ),
      SyncStateData,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$TempoDb, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$TempoDb, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$TempoDb, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$TempoDb, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$TempoDb db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$TempoDb, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$WorkoutsTableCreateCompanionBuilder = WorkoutsCompanion Function({
  Value<int> id,
  required int start,
  required int end,
  Value<String?> sport,
  required String title,
  required String source,
  Value<bool> confirmed,
  required double strain,
  required double trimp,
  Value<int?> avgHr,
  Value<int?> maxHr,
  required String zones,
  Value<int?> rpe,
  Value<String?> plan,
});
typedef $$WorkoutsTableUpdateCompanionBuilder = WorkoutsCompanion Function({
  Value<int> id,
  Value<int> start,
  Value<int> end,
  Value<String?> sport,
  Value<String> title,
  Value<String> source,
  Value<bool> confirmed,
  Value<double> strain,
  Value<double> trimp,
  Value<int?> avgHr,
  Value<int?> maxHr,
  Value<String> zones,
  Value<int?> rpe,
  Value<String?> plan,
});

class $$WorkoutsTableFilterComposer
    extends Composer<_$TempoDb, $WorkoutsTable> {
  $$WorkoutsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get start => $composableBuilder(
    column: $table.start,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get end => $composableBuilder(
    column: $table.end,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sport => $composableBuilder(
    column: $table.sport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get confirmed => $composableBuilder(
    column: $table.confirmed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get strain => $composableBuilder(
    column: $table.strain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get trimp => $composableBuilder(
    column: $table.trimp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get avgHr => $composableBuilder(
    column: $table.avgHr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxHr => $composableBuilder(
    column: $table.maxHr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get zones => $composableBuilder(
    column: $table.zones,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rpe => $composableBuilder(
    column: $table.rpe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plan => $composableBuilder(
    column: $table.plan,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkoutsTableOrderingComposer
    extends Composer<_$TempoDb, $WorkoutsTable> {
  $$WorkoutsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get start => $composableBuilder(
    column: $table.start,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get end => $composableBuilder(
    column: $table.end,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sport => $composableBuilder(
    column: $table.sport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get confirmed => $composableBuilder(
    column: $table.confirmed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get strain => $composableBuilder(
    column: $table.strain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get trimp => $composableBuilder(
    column: $table.trimp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get avgHr => $composableBuilder(
    column: $table.avgHr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxHr => $composableBuilder(
    column: $table.maxHr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get zones => $composableBuilder(
    column: $table.zones,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rpe => $composableBuilder(
    column: $table.rpe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plan => $composableBuilder(
    column: $table.plan,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkoutsTableAnnotationComposer
    extends Composer<_$TempoDb, $WorkoutsTable> {
  $$WorkoutsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get start =>
      $composableBuilder(column: $table.start, builder: (column) => column);

  GeneratedColumn<int> get end =>
      $composableBuilder(column: $table.end, builder: (column) => column);

  GeneratedColumn<String> get sport =>
      $composableBuilder(column: $table.sport, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get confirmed =>
      $composableBuilder(column: $table.confirmed, builder: (column) => column);

  GeneratedColumn<double> get strain =>
      $composableBuilder(column: $table.strain, builder: (column) => column);

  GeneratedColumn<double> get trimp =>
      $composableBuilder(column: $table.trimp, builder: (column) => column);

  GeneratedColumn<int> get avgHr =>
      $composableBuilder(column: $table.avgHr, builder: (column) => column);

  GeneratedColumn<int> get maxHr =>
      $composableBuilder(column: $table.maxHr, builder: (column) => column);

  GeneratedColumn<String> get zones =>
      $composableBuilder(column: $table.zones, builder: (column) => column);

  GeneratedColumn<int> get rpe =>
      $composableBuilder(column: $table.rpe, builder: (column) => column);

  GeneratedColumn<String> get plan =>
      $composableBuilder(column: $table.plan, builder: (column) => column);
}

class $$WorkoutsTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $WorkoutsTable,
          Workout,
          $$WorkoutsTableFilterComposer,
          $$WorkoutsTableOrderingComposer,
          $$WorkoutsTableAnnotationComposer,
          $$WorkoutsTableCreateCompanionBuilder,
          $$WorkoutsTableUpdateCompanionBuilder,
          (Workout, BaseReferences<_$TempoDb, $WorkoutsTable, Workout>),
          Workout,
          PrefetchHooks Function()
        > {
  $$WorkoutsTableTableManager(_$TempoDb db, $WorkoutsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkoutsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkoutsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkoutsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> start = const Value.absent(),
                Value<int> end = const Value.absent(),
                Value<String?> sport = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> confirmed = const Value.absent(),
                Value<double> strain = const Value.absent(),
                Value<double> trimp = const Value.absent(),
                Value<int?> avgHr = const Value.absent(),
                Value<int?> maxHr = const Value.absent(),
                Value<String> zones = const Value.absent(),
                Value<int?> rpe = const Value.absent(),
                Value<String?> plan = const Value.absent(),
              }) => WorkoutsCompanion(
                id: id,
                start: start,
                end: end,
                sport: sport,
                title: title,
                source: source,
                confirmed: confirmed,
                strain: strain,
                trimp: trimp,
                avgHr: avgHr,
                maxHr: maxHr,
                zones: zones,
                rpe: rpe,
                plan: plan,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int start,
                required int end,
                Value<String?> sport = const Value.absent(),
                required String title,
                required String source,
                Value<bool> confirmed = const Value.absent(),
                required double strain,
                required double trimp,
                Value<int?> avgHr = const Value.absent(),
                Value<int?> maxHr = const Value.absent(),
                required String zones,
                Value<int?> rpe = const Value.absent(),
                Value<String?> plan = const Value.absent(),
              }) => WorkoutsCompanion.insert(
                id: id,
                start: start,
                end: end,
                sport: sport,
                title: title,
                source: source,
                confirmed: confirmed,
                strain: strain,
                trimp: trimp,
                avgHr: avgHr,
                maxHr: maxHr,
                zones: zones,
                rpe: rpe,
                plan: plan,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkoutsTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $WorkoutsTable,
      Workout,
      $$WorkoutsTableFilterComposer,
      $$WorkoutsTableOrderingComposer,
      $$WorkoutsTableAnnotationComposer,
      $$WorkoutsTableCreateCompanionBuilder,
      $$WorkoutsTableUpdateCompanionBuilder,
      (Workout, BaseReferences<_$TempoDb, $WorkoutsTable, Workout>),
      Workout,
      PrefetchHooks Function()
    >;
typedef $$PlanDaysTableCreateCompanionBuilder = PlanDaysCompanion Function({
  required String date,
  required String session,
  Value<String?> original,
  Value<String?> reason,
  Value<int?> adaptedAt,
  required bool general,
  Value<int> rowid,
});
typedef $$PlanDaysTableUpdateCompanionBuilder = PlanDaysCompanion Function({
  Value<String> date,
  Value<String> session,
  Value<String?> original,
  Value<String?> reason,
  Value<int?> adaptedAt,
  Value<bool> general,
  Value<int> rowid,
});

class $$PlanDaysTableFilterComposer
    extends Composer<_$TempoDb, $PlanDaysTable> {
  $$PlanDaysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get session => $composableBuilder(
    column: $table.session,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get original => $composableBuilder(
    column: $table.original,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get adaptedAt => $composableBuilder(
    column: $table.adaptedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get general => $composableBuilder(
    column: $table.general,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlanDaysTableOrderingComposer
    extends Composer<_$TempoDb, $PlanDaysTable> {
  $$PlanDaysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get session => $composableBuilder(
    column: $table.session,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get original => $composableBuilder(
    column: $table.original,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get adaptedAt => $composableBuilder(
    column: $table.adaptedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get general => $composableBuilder(
    column: $table.general,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlanDaysTableAnnotationComposer
    extends Composer<_$TempoDb, $PlanDaysTable> {
  $$PlanDaysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get session =>
      $composableBuilder(column: $table.session, builder: (column) => column);

  GeneratedColumn<String> get original =>
      $composableBuilder(column: $table.original, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<int> get adaptedAt =>
      $composableBuilder(column: $table.adaptedAt, builder: (column) => column);

  GeneratedColumn<bool> get general =>
      $composableBuilder(column: $table.general, builder: (column) => column);
}

class $$PlanDaysTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $PlanDaysTable,
          PlanDay,
          $$PlanDaysTableFilterComposer,
          $$PlanDaysTableOrderingComposer,
          $$PlanDaysTableAnnotationComposer,
          $$PlanDaysTableCreateCompanionBuilder,
          $$PlanDaysTableUpdateCompanionBuilder,
          (PlanDay, BaseReferences<_$TempoDb, $PlanDaysTable, PlanDay>),
          PlanDay,
          PrefetchHooks Function()
        > {
  $$PlanDaysTableTableManager(_$TempoDb db, $PlanDaysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanDaysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlanDaysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlanDaysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> date = const Value.absent(),
                Value<String> session = const Value.absent(),
                Value<String?> original = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<int?> adaptedAt = const Value.absent(),
                Value<bool> general = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanDaysCompanion(
                date: date,
                session: session,
                original: original,
                reason: reason,
                adaptedAt: adaptedAt,
                general: general,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String date,
                required String session,
                Value<String?> original = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<int?> adaptedAt = const Value.absent(),
                required bool general,
                Value<int> rowid = const Value.absent(),
              }) => PlanDaysCompanion.insert(
                date: date,
                session: session,
                original: original,
                reason: reason,
                adaptedAt: adaptedAt,
                general: general,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlanDaysTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $PlanDaysTable,
      PlanDay,
      $$PlanDaysTableFilterComposer,
      $$PlanDaysTableOrderingComposer,
      $$PlanDaysTableAnnotationComposer,
      $$PlanDaysTableCreateCompanionBuilder,
      $$PlanDaysTableUpdateCompanionBuilder,
      (PlanDay, BaseReferences<_$TempoDb, $PlanDaysTable, PlanDay>),
      PlanDay,
      PrefetchHooks Function()
    >;
typedef $$SyncLogTableCreateCompanionBuilder = SyncLogCompanion Function({
  Value<int> id,
  required int ts,
  required String summary,
  required String result,
  Value<int?> durationMs,
});
typedef $$SyncLogTableUpdateCompanionBuilder = SyncLogCompanion Function({
  Value<int> id,
  Value<int> ts,
  Value<String> summary,
  Value<String> result,
  Value<int?> durationMs,
});

class $$SyncLogTableFilterComposer extends Composer<_$TempoDb, $SyncLogTable> {
  $$SyncLogTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncLogTableOrderingComposer
    extends Composer<_$TempoDb, $SyncLogTable> {
  $$SyncLogTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncLogTableAnnotationComposer
    extends Composer<_$TempoDb, $SyncLogTable> {
  $$SyncLogTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get result =>
      $composableBuilder(column: $table.result, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );
}

class $$SyncLogTableTableManager
    extends
        RootTableManager<
          _$TempoDb,
          $SyncLogTable,
          SyncLogData,
          $$SyncLogTableFilterComposer,
          $$SyncLogTableOrderingComposer,
          $$SyncLogTableAnnotationComposer,
          $$SyncLogTableCreateCompanionBuilder,
          $$SyncLogTableUpdateCompanionBuilder,
          (SyncLogData, BaseReferences<_$TempoDb, $SyncLogTable, SyncLogData>),
          SyncLogData,
          PrefetchHooks Function()
        > {
  $$SyncLogTableTableManager(_$TempoDb db, $SyncLogTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncLogTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncLogTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncLogTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> ts = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<String> result = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
              }) => SyncLogCompanion(
                id: id,
                ts: ts,
                summary: summary,
                result: result,
                durationMs: durationMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int ts,
                required String summary,
                required String result,
                Value<int?> durationMs = const Value.absent(),
              }) => SyncLogCompanion.insert(
                id: id,
                ts: ts,
                summary: summary,
                result: result,
                durationMs: durationMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncLogTableProcessedTableManager =
    ProcessedTableManager<
      _$TempoDb,
      $SyncLogTable,
      SyncLogData,
      $$SyncLogTableFilterComposer,
      $$SyncLogTableOrderingComposer,
      $$SyncLogTableAnnotationComposer,
      $$SyncLogTableCreateCompanionBuilder,
      $$SyncLogTableUpdateCompanionBuilder,
      (SyncLogData, BaseReferences<_$TempoDb, $SyncLogTable, SyncLogData>),
      SyncLogData,
      PrefetchHooks Function()
    >;

class $TempoDbManager {
  final _$TempoDb _db;
  $TempoDbManager(this._db);
  $$MinuteSamplesTableTableManager get minuteSamples =>
      $$MinuteSamplesTableTableManager(_db, _db.minuteSamples);
  $$HrLiveTableTableManager get hrLive =>
      $$HrLiveTableTableManager(_db, _db.hrLive);
  $$StressSamplesTableTableManager get stressSamples =>
      $$StressSamplesTableTableManager(_db, _db.stressSamples);
  $$Spo2SamplesTableTableManager get spo2Samples =>
      $$Spo2SamplesTableTableManager(_db, _db.spo2Samples);
  $$BandWorkoutsTableTableManager get bandWorkouts =>
      $$BandWorkoutsTableTableManager(_db, _db.bandWorkouts);
  $$OdEventsTableTableManager get odEvents =>
      $$OdEventsTableTableManager(_db, _db.odEvents);
  $$SleepSessionsTableTableManager get sleepSessions =>
      $$SleepSessionsTableTableManager(_db, _db.sleepSessions);
  $$DailyScoresTableTableManager get dailyScores =>
      $$DailyScoresTableTableManager(_db, _db.dailyScores);
  $$BaselinesTableTableManager get baselines =>
      $$BaselinesTableTableManager(_db, _db.baselines);
  $$JournalTableTableManager get journal =>
      $$JournalTableTableManager(_db, _db.journal);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$WorkoutsTableTableManager get workouts =>
      $$WorkoutsTableTableManager(_db, _db.workouts);
  $$PlanDaysTableTableManager get planDays =>
      $$PlanDaysTableTableManager(_db, _db.planDays);
  $$SyncLogTableTableManager get syncLog =>
      $$SyncLogTableTableManager(_db, _db.syncLog);
}
