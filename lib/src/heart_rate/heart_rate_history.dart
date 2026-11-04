import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

typedef HistoryDirectoryProvider = Future<Directory> Function();

enum HeartRateZone { low, medium, high }

const int lowHeartRateThreshold = 60;
const int highHeartRateThreshold = 100;

HeartRateZone heartRateZoneFor(int beatsPerMinute) {
  if (beatsPerMinute < lowHeartRateThreshold) {
    return HeartRateZone.low;
  }
  if (beatsPerMinute > highHeartRateThreshold) {
    return HeartRateZone.high;
  }
  return HeartRateZone.medium;
}

extension HeartRateZoneLabel on HeartRateZone {
  String get label {
    return switch (this) {
      HeartRateZone.low => '低',
      HeartRateZone.medium => '中',
      HeartRateZone.high => '高',
    };
  }
}

class HeartRateHistoryPoint {
  const HeartRateHistoryPoint({
    required this.id,
    required this.beatsPerMinute,
    required this.recordedAt,
    required this.source,
    this.sessionId = 'legacy',
  });

  final String id;
  final int beatsPerMinute;
  final DateTime recordedAt;
  final String source;
  final String sessionId;

  HeartRateZone get zone => heartRateZoneFor(beatsPerMinute);

  Map<String, Object> toJson() {
    return <String, Object>{
      'id': id,
      'bpm': beatsPerMinute,
      'recordedAt': recordedAt.toUtc().toIso8601String(),
      'source': source,
      'sessionId': sessionId,
    };
  }

  static HeartRateHistoryPoint? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final bpm = json['bpm'];
    final recordedAt = json['recordedAt'];
    final source = json['source'];
    final sessionId = json['sessionId'];
    if (id is! String ||
        id.isEmpty ||
        bpm is! int ||
        bpm <= 0 ||
        bpm > 300 ||
        recordedAt is! String) {
      return null;
    }
    final parsedAt = DateTime.tryParse(recordedAt);
    if (parsedAt == null) {
      return null;
    }
    return HeartRateHistoryPoint(
      id: id,
      beatsPerMinute: bpm,
      recordedAt: parsedAt.toLocal(),
      source: source is String ? source : '',
      sessionId: sessionId is String && sessionId.isNotEmpty
          ? sessionId
          : 'legacy',
    );
  }
}

class HeartRateHistorySession {
  const HeartRateHistorySession({
    required this.id,
    required this.source,
    required this.deviceId,
    required this.startedAt,
    this.endedAt,
  });

  final String id;
  final String source;
  final String? deviceId;
  final DateTime startedAt;
  final DateTime? endedAt;

  bool get isActive => endedAt == null;

  HeartRateHistorySession copyWith({DateTime? endedAt}) {
    return HeartRateHistorySession(
      id: id,
      source: source,
      deviceId: deviceId,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'source': source,
      'deviceId': deviceId,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt?.toUtc().toIso8601String(),
    };
  }

  static HeartRateHistorySession? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final source = json['source'];
    final deviceId = json['deviceId'];
    final startedAt = json['startedAt'];
    final endedAt = json['endedAt'];
    if (id is! String || id.isEmpty || startedAt is! String) {
      return null;
    }
    final start = DateTime.tryParse(startedAt);
    if (start == null) {
      return null;
    }
    final end = endedAt is String ? DateTime.tryParse(endedAt) : null;
    return HeartRateHistorySession(
      id: id,
      source: source is String ? source : '',
      deviceId: deviceId is String ? deviceId : null,
      startedAt: start.toLocal(),
      endedAt: end?.toLocal(),
    );
  }
}

class HeartRateHistoryNote {
  const HeartRateHistoryNote({
    required this.pointId,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
  });

  final String pointId;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object> toJson() {
    return <String, Object>{
      'pointId': pointId,
      'text': text,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  static HeartRateHistoryNote? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final pointId = json['pointId'];
    final text = json['text'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    if (pointId is! String ||
        pointId.isEmpty ||
        text is! String ||
        text.trim().isEmpty ||
        createdAt is! String ||
        updatedAt is! String) {
      return null;
    }
    final created = DateTime.tryParse(createdAt);
    final updated = DateTime.tryParse(updatedAt);
    if (created == null || updated == null) {
      return null;
    }
    return HeartRateHistoryNote(
      pointId: pointId,
      text: text.trim(),
      createdAt: created.toLocal(),
      updatedAt: updated.toLocal(),
    );
  }
}

/// Points encoded per isolate hop.
///
/// A compaction at the 100k cap used to hand the whole list to a single
/// isolate and build one NDJSON string in one go: the isolate received a copy
/// of every point and then allocated a multi-megabyte string before the write.
/// Encoding and appending fixed-size chunks bounds both peaks, while keeping
/// the on-disk bytes identical (`<json>\n` per point).
const int _pointWriteChunkSize = 4000;

Future<void> _writePointChunkInIsolate({
  required String path,
  required List<HeartRateHistoryPoint> points,
  required FileMode mode,
}) {
  return Isolate.run(() async {
    final buffer = StringBuffer();
    for (final point in points) {
      buffer
        ..write(jsonEncode(point.toJson()))
        ..writeln();
    }
    await File(path).writeAsString(buffer.toString(), mode: mode, flush: true);
  });
}

Future<void> _appendPointChunksInIsolates({
  required String path,
  required List<HeartRateHistoryPoint> points,
}) async {
  for (var start = 0; start < points.length; start += _pointWriteChunkSize) {
    final end = math.min(start + _pointWriteChunkSize, points.length);
    await _writePointChunkInIsolate(
      path: path,
      points: points.sublist(start, end),
      mode: FileMode.append,
    );
  }
}

Future<void> _writePointFileInIsolate({
  required String path,
  required List<HeartRateHistoryPoint> points,
  required bool append,
}) async {
  if (append) {
    await _appendPointChunksInIsolates(path: path, points: points);
    return;
  }
  final temporaryFile = File('$path.tmp');
  // Start from an empty file so a leftover temporary file can never leak
  // points that were already evicted from the in-memory list.
  await temporaryFile.writeAsString('');
  await _appendPointChunksInIsolates(path: temporaryFile.path, points: points);
  try {
    await temporaryFile.rename(path);
  } on FileSystemException {
    final destination = File(path);
    if (await destination.exists()) {
      await destination.delete();
    }
    await temporaryFile.rename(path);
  }
}

class _LoadedHistoryPoints {
  const _LoadedHistoryPoints({required this.points, required this.compacted});

  final List<HeartRateHistoryPoint> points;
  final bool compacted;
}

List<HeartRateHistoryPoint> _mergeLoadedAndLivePoints(
  List<HeartRateHistoryPoint> loaded,
  List<HeartRateHistoryPoint> live,
  int maxPoints,
) {
  final merged = <HeartRateHistoryPoint>[...loaded, ...live]
    ..sort((left, right) => left.recordedAt.compareTo(right.recordedAt));
  final result = <HeartRateHistoryPoint>[];
  String? lastId;
  for (final point in merged) {
    if (point.id == lastId) {
      continue;
    }
    result.add(point);
    lastId = point.id;
  }
  if (result.length <= maxPoints) {
    return result;
  }
  return result.sublist(result.length - maxPoints);
}

/// Persists every real heart-rate reading and its point-level notes.
///
/// Immutable readings are appended to an NDJSON file while the comparatively
/// small notes file is replaced atomically. Writes are coalesced for
/// [saveDelay] so a fast BLE stream does not force a disk flush for every
/// notification. [flush] is still available for shutdown and tests.
class HeartRateHistoryStore {
  HeartRateHistoryStore({
    HistoryDirectoryProvider? directoryProvider,
    this.saveDelay = const Duration(seconds: 8),
    this.retentionPeriod = const Duration(days: 30),
    this.sampleInterval = const Duration(seconds: 1),
    this.maxPoints = 100000,
    this.maxPendingPoints = 1000,
  }) : assert(sampleInterval > Duration.zero),
       assert(maxPoints > 0),
       assert(maxPendingPoints > 0),
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const _pointsFileName = 'pulse_heart_rate_points.ndjson';
  static const _notesFileName = 'pulse_heart_rate_notes.json';
  static const _formatVersion = 2;

  final HistoryDirectoryProvider _directoryProvider;
  final Duration saveDelay;
  final Duration retentionPeriod;
  final Duration sampleInterval;
  final int maxPoints;
  final int maxPendingPoints;
  final List<HeartRateHistoryPoint> _points = <HeartRateHistoryPoint>[];
  final List<HeartRateHistoryPoint> _pendingPoints = <HeartRateHistoryPoint>[];
  final Map<String, HeartRateHistoryNote> _notes =
      <String, HeartRateHistoryNote>{};
  final Map<String, HeartRateHistorySession> _sessions =
      <String, HeartRateHistorySession>{};
  late final UnmodifiableListView<HeartRateHistoryPoint> _pointsView =
      UnmodifiableListView<HeartRateHistoryPoint>(_points);
  late final UnmodifiableListView<HeartRateHistoryNote> _notesView =
      UnmodifiableListView<HeartRateHistoryNote>(_notes.values);
  List<HeartRateHistorySession>? _sortedSessions;

  Timer? _saveTimer;
  Future<void> _writeChain = Future<void>.value();
  Future<void>? _loadFuture;
  Directory? _cachedDirectory;
  bool _isLoaded = false;
  bool _saveRequestedDuringLoad = false;
  bool _disposed = false;
  bool _replacePointsFile = false;
  bool _compactionPending = false;
  int _appendedSinceCompaction = 0;
  String? _activeSessionId;
  int _notesRevision = 0;
  int _writtenNotesRevision = -1;
  DateTime _nextRetentionCheckAt = DateTime.now();
  Object? _loadError;
  Object? _saveError;

  bool get isLoaded => _isLoaded;
  Object? get loadError => _loadError;
  Object? get saveError => _saveError;
  UnmodifiableListView<HeartRateHistoryPoint> get points => _pointsView;
  UnmodifiableListView<HeartRateHistoryNote> get notes => _notesView;
  List<HeartRateHistorySession> get sessions {
    final cached = _sortedSessions;
    if (cached != null) {
      return cached;
    }
    final sorted = _sessions.values.toList()
      ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return _sortedSessions = List<HeartRateHistorySession>.unmodifiable(sorted);
  }

  Future<void> load() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final directory = await _historyDirectory();
      await _loadPoints(directory);
      // The isolate already orders points by their ISO-8601 timestamp, so
      // this is usually a cheap linear verification; only mixed-format
      // timestamps from old files need the O(n log n) resort.
      var sorted = true;
      for (var index = 1; index < _points.length; index++) {
        if (_points[index].recordedAt.isBefore(
          _points[index - 1].recordedAt,
        )) {
          sorted = false;
          break;
        }
      }
      if (!sorted) {
        _points.sort(
          (left, right) => left.recordedAt.compareTo(right.recordedAt),
        );
      }
      await _loadNotes(directory);
      if (_trimExpired(DateTime.now()) || _replacePointsFile) {
        _scheduleSave();
      }
    } on Object catch (error) {
      _loadError = error;
    } finally {
      _isLoaded = true;
      // Mutations that arrived while the on-disk history was still being read
      // must not be lost: replay the deferred save now that the merged state
      // (loaded + live points, disk notes) is authoritative.
      if (_saveRequestedDuringLoad) {
        _saveRequestedDuringLoad = false;
        _scheduleSave();
      }
    }
  }

  Future<void> _loadPoints(Directory directory) async {
    final file = _pointsFileIn(directory);
    if (!await file.exists()) {
      return;
    }
    final path = file.path;
    final cutoffMicros = DateTime.now()
        .subtract(retentionPeriod)
        .microsecondsSinceEpoch;
    final maxPointsForLoad = maxPoints;
    final result = await Isolate.run(() async {
      final parsed = <Map<String, Object?>>[];
      final source = File(path);
      await for (final line
          in source
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim().isEmpty) {
          continue;
        }
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map) {
            parsed.add(Map<String, Object?>.from(decoded));
          }
        } on Object {
          // A damaged final line should not make earlier readings unreadable.
        }
      }
      parsed.sort((left, right) {
        final leftTime = left['recordedAt'];
        final rightTime = right['recordedAt'];
        if (leftTime is String && rightTime is String) {
          return leftTime.compareTo(rightTime);
        }
        return 0;
      });
      final retained = parsed.where((point) {
        final recordedAt = point['recordedAt'];
        if (recordedAt is! String) {
          return false;
        }
        final parsedAt = DateTime.tryParse(recordedAt);
        return parsedAt != null &&
            parsedAt.microsecondsSinceEpoch >= cutoffMicros;
      }).toList();
      final limited = retained.length <= maxPointsForLoad
          ? retained
          : retained.sublist(retained.length - maxPointsForLoad);
      final points = <HeartRateHistoryPoint>[];
      String? lastPointId;
      for (final rawPoint in limited) {
        final point = HeartRateHistoryPoint.fromJson(rawPoint);
        if (point != null && point.id != lastPointId) {
          points.add(point);
          lastPointId = point.id;
        }
      }
      return _LoadedHistoryPoints(
        points: points,
        compacted:
            limited.length != parsed.length ||
            limited.length != retained.length,
      );
    });
    final livePoints = List<HeartRateHistoryPoint>.of(_points);
    final merged = livePoints.isEmpty
        ? result.points
        : await Isolate.run(
            () => _mergeLoadedAndLivePoints(
              result.points,
              livePoints,
              maxPointsForLoad,
            ),
          );
    if (result.compacted || merged.length != result.points.length) {
      _replacePointsFile = true;
    }
    _points
      ..clear()
      ..addAll(merged);
  }

  Future<void> _loadNotes(Directory directory) async {
    final file = _notesFileIn(directory);
    if (!await file.exists()) {
      _ensureSessionsForPoints();
      return;
    }
    // Decode in an isolate: the notes file grows with every session, and the
    // main isolate should not block on JSON parsing during startup.
    final path = file.path;
    final Object? decoded;
    try {
      decoded = await Isolate.run(
        () => jsonDecode(File(path).readAsStringSync()),
      );
    } on Object {
      // A damaged notes file must not make the loaded points unusable.
      _ensureSessionsForPoints();
      return;
    }
    if (decoded is! Map) {
      _ensureSessionsForPoints();
      return;
    }
    final rawNotes = decoded['notes'];
    if (rawNotes is List) {
      for (final rawNote in rawNotes) {
        final note = HeartRateHistoryNote.fromJson(rawNote);
        if (note == null || _findPointById(note.pointId) == null) {
          continue;
        }
        // A note edited while the load was in flight refers to a live point;
        // keep the newer in-memory version over the older disk snapshot.
        if (_notes.containsKey(note.pointId)) {
          continue;
        }
        _notes[note.pointId] = note;
      }
    }
    final rawSessions = decoded['sessions'];
    if (rawSessions is List) {
      for (final rawSession in rawSessions) {
        final session = HeartRateHistorySession.fromJson(rawSession);
        if (session != null) {
          _sessions[session.id] = session;
        }
      }
    }
    _ensureSessionsForPoints();
  }

  HeartRateHistorySession startSession({
    required String source,
    String? deviceId,
    DateTime? startedAt,
  }) {
    final start = startedAt ?? DateTime.now();
    final baseId = start.microsecondsSinceEpoch.toString();
    var id = baseId;
    var suffix = 1;
    while (_sessions.containsKey(id)) {
      id = '$baseId-${suffix++}';
    }
    final session = HeartRateHistorySession(
      id: id,
      source: source,
      deviceId: deviceId,
      startedAt: start,
    );
    _sessions[id] = session;
    _activeSessionId = id;
    _sortedSessions = null;
    _notesRevision++;
    _scheduleSave();
    return session;
  }

  void endSession(String sessionId, {DateTime? endedAt}) {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    _sessions[sessionId] = session.copyWith(endedAt: endedAt ?? DateTime.now());
    if (_activeSessionId == sessionId) {
      _activeSessionId = null;
    }
    _sortedSessions = null;
    _notesRevision++;
    _scheduleSave();
  }

  Future<bool> deleteSession(String sessionId) async {
    return (await deleteSessions({sessionId})) > 0;
  }

  /// 批量删除多个会话及其心率点，返回实际删除的会话数。
  ///
  /// 多个会话只做一次点过滤和一次文件重写，比逐个 [deleteSession] 便宜。
  Future<int> deleteSessions(Set<String> sessionIds) async {
    if (sessionIds.isEmpty) {
      return 0;
    }
    var deleted = 0;
    for (final id in sessionIds) {
      if (_sessions.remove(id) == null) {
        continue;
      }
      if (_activeSessionId == id) {
        _activeSessionId = null;
      }
      deleted++;
    }
    if (deleted == 0) {
      return 0;
    }
    _sortedSessions = null;
    _points.removeWhere((point) => sessionIds.contains(point.sessionId));
    _pendingPoints.removeWhere((point) => sessionIds.contains(point.sessionId));
    _notes.removeWhere((key, _) => !_hasPointWithId(key));
    _replacePointsFile = true;
    _compactionPending = false;
    _notesRevision++;
    await flush();
    return deleted;
  }

  bool _hasPointWithId(String pointId) => _findPointById(pointId) != null;

  void _ensureSessionsForPoints() {
    final missing = <String, List<HeartRateHistoryPoint>>{};
    for (final point in _points) {
      if (_sessions.containsKey(point.sessionId)) {
        continue;
      }
      missing
          .putIfAbsent(point.sessionId, () => <HeartRateHistoryPoint>[])
          .add(point);
    }
    for (final entry in missing.entries) {
      final first = entry.value.first;
      final last = entry.value.last;
      _sessions[entry.key] = HeartRateHistorySession(
        id: entry.key,
        source: first.source,
        deviceId: null,
        startedAt: first.recordedAt,
        endedAt: last.recordedAt,
      );
    }
    if (missing.isNotEmpty) {
      _sortedSessions = null;
      _replacePointsFile = true;
    }
    _normalizeLoadedSessions();
  }

  void _normalizeLoadedSessions() {
    for (final entry in _sessions.entries.toList()) {
      final session = entry.value;
      if (session.endedAt != null || session.id == _activeSessionId) {
        continue;
      }
      DateTime? lastPointAt;
      for (final point in _points.reversed) {
        if (point.sessionId == session.id) {
          lastPointAt = point.recordedAt;
          break;
        }
      }
      _sessions[entry.key] = session.copyWith(
        endedAt: lastPointAt ?? session.startedAt,
      );
      _sortedSessions = null;
      _notesRevision++;
    }
  }

  HeartRateHistoryPoint? addMeasurement({
    required int beatsPerMinute,
    required DateTime recordedAt,
    required String source,
    String sessionId = 'legacy',
  }) {
    final now = DateTime.now();
    if (!now.isBefore(_nextRetentionCheckAt)) {
      _trimExpired(now);
      _nextRetentionCheckAt = now.add(const Duration(minutes: 10));
    }
    if (recordedAt.isBefore(now.subtract(retentionPeriod))) {
      return null;
    }
    final intervalMicros = sampleInterval.inMicroseconds;
    final bucketMicros =
        recordedAt.microsecondsSinceEpoch ~/ intervalMicros * intervalMicros;
    final insertionIndex = _insertionIndexFor(recordedAt);
    if (insertionIndex > 0 &&
        _bucketFor(_points[insertionIndex - 1].recordedAt) == bucketMicros) {
      return null;
    }
    if (insertionIndex < _points.length &&
        _bucketFor(_points[insertionIndex].recordedAt) == bucketMicros) {
      return null;
    }
    if (!_sessions.containsKey(sessionId)) {
      _sessions[sessionId] = HeartRateHistorySession(
        id: sessionId,
        source: source,
        deviceId: null,
        startedAt: recordedAt,
      );
      _sortedSessions = null;
      _notesRevision++;
    }
    final point = HeartRateHistoryPoint(
      id: bucketMicros.toString(),
      beatsPerMinute: beatsPerMinute,
      recordedAt: recordedAt,
      source: source,
      sessionId: sessionId,
    );
    if (insertionIndex == _points.length) {
      _points.add(point);
    } else {
      _points.insert(insertionIndex, point);
    }
    _enforceMaxPoints();
    _pendingPoints.add(point);
    _scheduleSave();
    return point;
  }

  HeartRateHistoryNote? noteForPoint(String pointId) => _notes[pointId];

  Future<void> saveNote({
    required String pointId,
    required String text,
    DateTime? now,
  }) async {
    if (_findPointById(pointId) == null) {
      return;
    }
    final trimmed = text.trim();
    final existing = _notes[pointId];
    if (trimmed.isEmpty) {
      if (existing == null) {
        return;
      }
      _notes.remove(pointId);
      _notesRevision++;
      _scheduleSave();
      return;
    }
    final timestamp = now ?? DateTime.now();
    _notes[pointId] = HeartRateHistoryNote(
      pointId: pointId,
      text: trimmed,
      createdAt: existing?.createdAt ?? timestamp,
      updatedAt: timestamp,
    );
    _notesRevision++;
    _scheduleSave();
  }

  Future<void> removeNote(String pointId) async {
    if (_notes.remove(pointId) != null) {
      _notesRevision++;
      _scheduleSave();
    }
  }

  Future<void> clearAll() async {
    _points.clear();
    _pendingPoints.clear();
    _notes.clear();
    _sessions.clear();
    _sortedSessions = null;
    _activeSessionId = null;
    _replacePointsFile = true;
    _compactionPending = false;
    _appendedSinceCompaction = 0;
    _notesRevision++;
    await flush();
  }

  Future<void> flush() async {
    if (!_isLoaded) {
      // Never write a partial snapshot: finish reading the on-disk history
      // first so notes/sessions loaded here cannot be overwritten by empty
      // in-memory maps (explicit flushes from deleteSessions/clearAll and
      // shutdown both go through this path).
      await load();
    }
    _saveTimer?.cancel();
    _saveTimer = null;
    _writeChain = _writeChain
        .catchError((Object _) {
          // A later save should still be attempted after an earlier failure.
        })
        .then((_) => _flushPendingWrites());
    try {
      await _writeChain;
      _saveError = null;
    } on Object catch (error) {
      _saveError = error;
      rethrow;
    }
  }

  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  void _scheduleSave() {
    if (_disposed) {
      return;
    }
    if (!_isLoaded) {
      // Writing before the load completes would replace the on-disk history
      // with the (still empty) in-memory snapshot. Defer until load finishes;
      // [flush] awaits the load future, so nothing is lost.
      _saveRequestedDuringLoad = true;
      return;
    }
    if (_pendingPoints.length >= maxPendingPoints) {
      unawaited(flush().catchError((Object _) {}));
      return;
    }
    _saveTimer ??= Timer(saveDelay, () {
      _saveTimer = null;
      unawaited(flush().catchError((Object _) {}));
    });
  }

  Future<void> _flushPendingWrites() async {
    final directory = await _historyDirectory();
    final points = List<HeartRateHistoryPoint>.of(_pendingPoints);
    _pendingPoints.clear();
    final compactionThreshold = math.max(1, maxPoints ~/ 2);
    final replacePoints =
        _replacePointsFile ||
        (_compactionPending && _appendedSinceCompaction >= compactionThreshold);
    _replacePointsFile = false;
    final notesRevision = _notesRevision;
    var pointsCommitted = !replacePoints && points.isEmpty;

    try {
      if (replacePoints) {
        await _replacePoints(directory);
        pointsCommitted = true;
        _appendedSinceCompaction = 0;
        _compactionPending = false;
      } else if (points.isNotEmpty) {
        await _appendPoints(directory, points);
        pointsCommitted = true;
        _appendedSinceCompaction += points.length;
        if (_compactionPending &&
            _appendedSinceCompaction >= compactionThreshold) {
          _replacePointsFile = true;
        }
      }
      if (replacePoints || notesRevision != _writtenNotesRevision) {
        await _writeNotes(directory);
        _writtenNotesRevision = notesRevision;
      }
    } on Object {
      if (!pointsCommitted && points.isNotEmpty) {
        _pendingPoints.insertAll(0, points);
      }
      if (!pointsCommitted) {
        _replacePointsFile = _replacePointsFile || replacePoints;
        _compactionPending = _compactionPending || replacePoints;
      }
      rethrow;
    }
  }

  Future<void> _appendPoints(
    Directory directory,
    List<HeartRateHistoryPoint> points,
  ) async {
    if (points.length <= 128) {
      // Small appends are cheaper to encode inline than to spawn an isolate.
      final buffer = StringBuffer();
      for (final point in points) {
        buffer
          ..write(jsonEncode(point.toJson()))
          ..writeln();
      }
      await _pointsFileIn(directory)
          .writeAsString(buffer.toString(), mode: FileMode.append, flush: true);
      return;
    }
    await _writePointFileInIsolate(
      path: _pointsFileIn(directory).path,
      points: points,
      append: true,
    );
  }

  Future<void> _replacePoints(Directory directory) async {
    // Snapshot the references once: readings keep arriving while the chunks
    // are written, and a partially updated list would produce a corrupt file.
    final snapshot = List<HeartRateHistoryPoint>.of(_points);
    await _writePointFileInIsolate(
      path: _pointsFileIn(directory).path,
      points: snapshot,
      append: false,
    );
  }

  Future<void> _writeNotes(Directory directory) async {
    final payload = jsonEncode(<String, Object>{
      'version': _formatVersion,
      'notes': _notes.values.map((note) => note.toJson()).toList(),
      'sessions': _sessions.values.map((session) => session.toJson()).toList(),
    });
    await _writeAtomically(_notesFileIn(directory), payload);
  }

  Future<void> _writeAtomically(File file, String payload) async {
    final temporaryFile = File('${file.path}.tmp');
    await temporaryFile.writeAsString(payload, flush: true);
    try {
      await temporaryFile.rename(file.path);
    } on FileSystemException {
      // Some Windows filesystems do not replace an existing destination.
      if (await file.exists()) {
        await file.delete();
      }
      await temporaryFile.rename(file.path);
    }
  }

  Future<Directory> _historyDirectory() async {
    final cached = _cachedDirectory;
    if (cached != null) {
      return cached;
    }
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    _cachedDirectory = directory;
    return directory;
  }

  File _pointsFileIn(Directory directory) {
    return File('${directory.path}${Platform.pathSeparator}$_pointsFileName');
  }

  File _notesFileIn(Directory directory) {
    return File('${directory.path}${Platform.pathSeparator}$_notesFileName');
  }

  bool _trimExpired(DateTime now) {
    final cutoff = now.subtract(retentionPeriod);
    final byTime = _lowerBound(cutoff);
    final overflow = math.max(0, _points.length - byTime - maxPoints);
    final firstRetained = byTime + overflow;
    if (firstRetained <= 0) {
      return false;
    }
    _dropOldestPoints(firstRetained);
    if (_isLoaded) {
      _compactionPending = true;
    } else {
      _replacePointsFile = true;
    }
    _notesRevision++;
    return true;
  }

  /// Removes the oldest [count] points from the in-memory list.
  ///
  /// `removeRange` is one contiguous memmove of the surviving references, which
  /// is far cheaper than rebuilding the list, so the dominant cost here is the
  /// per-point note lookup. Notes are usually sparse, so the whole loop is
  /// skipped when no note exists at all, and no intermediate copy of the
  /// evicted points is allocated.
  void _dropOldestPoints(int count) {
    if (count <= 0) {
      return;
    }
    final limit = math.min(count, _points.length);
    if (_notes.isNotEmpty) {
      for (var index = 0; index < limit; index++) {
        _notes.remove(_points[index].id);
      }
    }
    _points.removeRange(0, limit);
  }

  int _lowerBound(DateTime cutoff) {
    var low = 0;
    var high = _points.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (_points[middle].recordedAt.isBefore(cutoff)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _insertionIndexFor(DateTime recordedAt) {
    if (_points.isEmpty || !recordedAt.isBefore(_points.last.recordedAt)) {
      return _points.length;
    }
    var low = 0;
    var high = _points.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (_points[middle].recordedAt.isBefore(recordedAt)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _bucketFor(DateTime recordedAt) {
    final intervalMicros = sampleInterval.inMicroseconds;
    return recordedAt.microsecondsSinceEpoch ~/ intervalMicros * intervalMicros;
  }

  void _enforceMaxPoints() {
    if (_points.length <= maxPoints) {
      return;
    }
    final evictionBatch = math.max(1, (maxPoints * 0.05).ceil());
    final removeCount = math.min(evictionBatch, _points.length);
    _dropOldestPoints(removeCount);
    _compactionPending = true;
    _notesRevision++;
  }

  HeartRateHistoryPoint? _findPointById(String pointId) {
    final target = int.tryParse(pointId.split('-').first);
    if (target == null) {
      return null;
    }
    var low = 0;
    var high = _points.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      final pointKey = int.tryParse(_points[middle].id.split('-').first) ?? -1;
      if (pointKey < target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low >= _points.length) {
      return null;
    }
    return int.tryParse(_points[low].id.split('-').first) == target
        ? _points[low]
        : null;
  }
}
