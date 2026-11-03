import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../heart_rate/heart_rate_controller.dart';
import '../heart_rate/heart_rate_history.dart';
import '../theme/app_theme.dart';
import '../widgets/heart_rate_history_chart.dart';

Future<void> showHeartRateHistoryPage(
  BuildContext context,
  HeartRateController controller,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => HeartRateHistoryPage(controller: controller),
    ),
  );
}

class HeartRateHistoryPage extends StatefulWidget {
  const HeartRateHistoryPage({
    super.key,
    required this.controller,
    this.snapshotWorkerThreshold = 5000,
  });

  final HeartRateController controller;
  final int snapshotWorkerThreshold;

  @override
  State<HeartRateHistoryPage> createState() => _HeartRateHistoryPageState();
}

enum _HistoryRange { hour, day, week, all }

class _HistorySnapshot {
  const _HistorySnapshot({
    required this.sessionId,
    required this.revision,
    required this.range,
    required this.allPointCount,
    required this.points,
    required this.data,
  });

  final String? sessionId;
  final int revision;
  final _HistoryRange range;
  final int allPointCount;
  final List<HeartRateHistoryPoint> points;
  final _HistorySnapshotData data;
}

class _HistorySnapshotData {
  const _HistorySnapshotData({
    required this.displayPoints,
    required this.minimumBpm,
    required this.notePointsById,
    required this.notes,
    required this.notePointIds,
    required this.lowCount,
    required this.mediumCount,
    required this.highCount,
    required this.averageBpm,
    required this.maximumBpm,
  });

  final List<HeartRateHistoryPoint> displayPoints;
  final int? minimumBpm;
  final Map<String, HeartRateHistoryPoint> notePointsById;
  final List<HeartRateHistoryNote> notes;
  final Set<String> notePointIds;
  final int lowCount;
  final int mediumCount;
  final int highCount;
  final int? averageBpm;
  final int? maximumBpm;
}

class _HistorySnapshotRequest {
  const _HistorySnapshotRequest({required this.points, required this.allNotes});

  final List<HeartRateHistoryPoint> points;
  final List<HeartRateHistoryNote> allNotes;
}

Future<_HistorySnapshotData> _computeHistorySnapshot(
  _HistorySnapshotRequest request,
) {
  return Isolate.run(
    () => _buildHistorySnapshotData(
      points: request.points,
      allNotes: request.allNotes,
    ),
  );
}

_HistorySnapshotData _buildHistorySnapshotData({
  required List<HeartRateHistoryPoint> points,
  required List<HeartRateHistoryNote> allNotes,
}) {
  final noteIds = allNotes.map((note) => note.pointId).toSet();
  final notePointsById = <String, HeartRateHistoryPoint>{};
  var lowCount = 0;
  var mediumCount = 0;
  var highCount = 0;
  var totalBpm = 0;
  int? minimumBpm;
  int? maximumBpm;
  for (final point in points) {
    if (noteIds.contains(point.id)) {
      notePointsById[point.id] = point;
    }
    totalBpm += point.beatsPerMinute;
    minimumBpm = minimumBpm == null
        ? point.beatsPerMinute
        : math.min(minimumBpm, point.beatsPerMinute);
    maximumBpm = maximumBpm == null
        ? point.beatsPerMinute
        : math.max(maximumBpm, point.beatsPerMinute);
    switch (point.zone) {
      case HeartRateZone.low:
        lowCount++;
      case HeartRateZone.medium:
        mediumCount++;
      case HeartRateZone.high:
        highCount++;
    }
  }
  final notes =
      allNotes
          .where((note) => notePointsById.containsKey(note.pointId))
          .toList()
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  return _HistorySnapshotData(
    displayPoints: downsampleHeartRateHistoryPoints(
      points,
      pinnedPointIds: noteIds,
    ),
    minimumBpm: minimumBpm,
    notePointsById: notePointsById,
    notes: notes,
    notePointIds: notes.map((note) => note.pointId).toSet(),
    lowCount: lowCount,
    mediumCount: mediumCount,
    highCount: highCount,
    averageBpm: points.isEmpty ? null : (totalBpm / points.length).round(),
    maximumBpm: maximumBpm,
  );
}

class _HeartRateHistoryPageState extends State<HeartRateHistoryPage> {
  final TextEditingController _noteController = TextEditingController();
  _HistoryRange _range = _HistoryRange.day;
  String? _selectedSessionId;
  HeartRateHistoryPoint? _selectedPoint;
  bool _isSavingNote = false;
  _HistorySnapshot? _snapshot;
  bool _snapshotInFlight = false;
  bool _snapshotQueued = false;
  bool _refreshing = false;
  bool _listeningForInitialLoad = false;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.pauseLiveUiNotifications();
    widget.controller.savedHistoryChanges.addListener(
      _handleSavedHistoryChanged,
    );
    if (widget.controller.savedHistoryIsLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_requestSnapshot());
        }
      });
    } else {
      _listeningForInitialLoad = true;
      widget.controller.savedHistoryChanges.addListener(
        _handleInitialHistoryLoaded,
      );
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    widget.controller.savedHistoryChanges.removeListener(
      _handleSavedHistoryChanged,
    );
    if (_listeningForInitialLoad) {
      widget.controller.savedHistoryChanges.removeListener(
        _handleInitialHistoryLoaded,
      );
    }
    widget.controller.resumeLiveUiNotifications();
    _noteController.dispose();
    super.dispose();
  }

  /// Follows the history revision while the page stays open.
  ///
  /// An active session appends a point every few seconds, so without this the
  /// page silently shows a stale snapshot until the user taps 刷新. The
  /// revision arrives in bursts; debounce so a notification storm cannot queue
  /// repeated snapshot rebuilds (the request itself also coalesces).
  void _handleSavedHistoryChanged() {
    if (!mounted || !widget.controller.savedHistoryIsLoaded) {
      return;
    }
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer(const Duration(milliseconds: 900), () {
      _autoRefreshTimer = null;
      if (!mounted) {
        return;
      }
      unawaited(_requestSnapshot());
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (!widget.controller.savedHistoryIsLoaded) {
      return const Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final selectedPoint = _selectedPoint;
    final sessions = widget.controller.savedHistorySessions;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            _HistoryHeader(
              pointCount: snapshot?.allPointCount ?? 0,
              retentionDays: widget.controller.historyRetention.inDays,
              maxPoints: widget.controller.historyMaxPoints,
              onBack: () => Navigator.of(context).pop(),
              refreshing: _refreshing,
              onRefresh: _refreshSnapshot,
              onClear: widget.controller.savedHistory.isEmpty
                  ? null
                  : _confirmClearHistory,
            ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sessionWidth = constraints.maxWidth >= 1100
                      ? 280.0
                      : 240.0;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: sessionWidth,
                        child: _SessionListPanel(
                          sessions: sessions,
                          selectedSessionId:
                              _selectedSessionId ?? snapshot?.sessionId,
                          onChanged: _setSession,
                          onDelete: _confirmDeleteSession,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: snapshot == null
                            ? const Center(child: CircularProgressIndicator())
                            : SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  28,
                                  24,
                                  28,
                                  36,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _HistoryToolbar(
                                      snapshot: snapshot,
                                      range: _range,
                                      onRangeChanged: _setRange,
                                    ),
                                    const SizedBox(height: 22),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final chart = _HistoryChartSection(
                                          points: snapshot.points,
                                          displayPoints:
                                              snapshot.data.displayPoints,
                                          minimumBpm: snapshot.data.minimumBpm,
                                          maximumBpm: snapshot.data.maximumBpm,
                                          dataVersion: snapshot.revision,
                                          selectedPointId: selectedPoint?.id,
                                          notePointIds:
                                              snapshot.data.notePointIds,
                                          onPointSelected: _selectPoint,
                                        );
                                        final panel = _PointNotesPanel(
                                          selectedPoint: selectedPoint,
                                          pointsById:
                                              snapshot.data.notePointsById,
                                          noteController: _noteController,
                                          note: selectedPoint == null
                                              ? null
                                              : widget.controller
                                                    .noteForHistoryPoint(
                                                      selectedPoint.id,
                                                    ),
                                          notes: snapshot.data.notes,
                                          isSaving: _isSavingNote,
                                          onSave: _saveNote,
                                          onRemove: _removeNote,
                                          onSelectPoint: _selectPoint,
                                        );
                                        if (constraints.maxWidth >= 800) {
                                          return Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(child: chart),
                                              const SizedBox(width: 24),
                                              SizedBox(
                                                width: 330,
                                                child: panel,
                                              ),
                                            ],
                                          );
                                        }
                                        return Column(
                                          children: [
                                            chart,
                                            const SizedBox(height: 22),
                                            panel,
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleInitialHistoryLoaded() {
    if (!mounted || !widget.controller.savedHistoryIsLoaded) {
      return;
    }
    widget.controller.savedHistoryChanges.removeListener(
      _handleInitialHistoryLoaded,
    );
    _listeningForInitialLoad = false;
    unawaited(_requestSnapshot());
  }

  Future<void> _refreshSnapshot() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      await _requestSnapshot(force: true);
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _requestSnapshot({bool force = false}) async {
    if (!widget.controller.savedHistoryIsLoaded || !mounted) {
      return;
    }
    if (_snapshotInFlight) {
      _snapshotQueued = true;
      return;
    }
    final revision = widget.controller.savedHistoryRevision;
    final cached = _snapshot;
    if (!force &&
        cached != null &&
        cached.revision == revision &&
        cached.range == _range) {
      return;
    }
    _snapshotInFlight = true;
    try {
      do {
        _snapshotQueued = false;
        final requestedRevision = widget.controller.savedHistoryRevision;
        final range = _range;
        final allPoints = widget.controller.savedHistory;
        final sessions = widget.controller.savedHistorySessions;
        HeartRateHistorySession? session;
        for (final candidate in sessions) {
          if (candidate.id == _selectedSessionId) {
            session = candidate;
            break;
          }
        }
        session ??= sessions.isEmpty ? null : sessions.first;
        final requestedSessionId = session?.id;
        _selectedSessionId = requestedSessionId;
        final cutoffMicros = switch (range) {
          _HistoryRange.hour =>
            DateTime.now()
                .subtract(const Duration(hours: 1))
                .microsecondsSinceEpoch,
          _HistoryRange.day =>
            DateTime.now()
                .subtract(const Duration(hours: 24))
                .microsecondsSinceEpoch,
          _HistoryRange.week =>
            DateTime.now()
                .subtract(const Duration(days: 7))
                .microsecondsSinceEpoch,
          _HistoryRange.all => null,
        };
        final sessionStart = session == null
            ? 0
            : _lowerBound(allPoints, session.startedAt.microsecondsSinceEpoch);
        final sessionEnd = session == null
            ? 0
            : session.endedAt == null
            ? allPoints.length
            : _upperBound(allPoints, session.endedAt!.microsecondsSinceEpoch);
        final rangeStart = cutoffMicros == null
            ? sessionStart
            : math.max(sessionStart, _lowerBound(allPoints, cutoffMicros));
        final rangePoints = rangeStart >= sessionEnd
            ? const <HeartRateHistoryPoint>[]
            : allPoints.sublist(rangeStart, sessionEnd);
        final sessionPointCount = math.max(0, sessionEnd - sessionStart);
        final allNotes = widget.controller.savedHistoryNotes;
        final data = rangePoints.length <= widget.snapshotWorkerThreshold
            ? _buildHistorySnapshotData(points: rangePoints, allNotes: allNotes)
            : await _computeHistorySnapshot(
                _HistorySnapshotRequest(
                  points: rangePoints,
                  allNotes: allNotes,
                ),
              );
        if (!mounted) {
          return;
        }
        if (range != _range ||
            requestedSessionId != _selectedSessionId ||
            requestedRevision != widget.controller.savedHistoryRevision) {
          _snapshotQueued = true;
          continue;
        }
        setState(() {
          _snapshot = _HistorySnapshot(
            sessionId: requestedSessionId,
            revision: requestedRevision,
            range: range,
            allPointCount: sessionPointCount,
            points: rangePoints,
            data: data,
          );
        });
      } while (_snapshotQueued && mounted);
    } finally {
      _snapshotInFlight = false;
      if (_snapshotQueued && mounted) {
        _snapshotQueued = false;
        unawaited(_requestSnapshot());
      }
    }
  }

  int _lowerBound(List<HeartRateHistoryPoint> points, int cutoffMicros) {
    var low = 0;
    var high = points.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (points[middle].recordedAt.microsecondsSinceEpoch < cutoffMicros) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _upperBound(List<HeartRateHistoryPoint> points, int cutoffMicros) {
    var low = 0;
    var high = points.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (points[middle].recordedAt.microsecondsSinceEpoch <= cutoffMicros) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  void _setSession(String sessionId) {
    if (sessionId == _selectedSessionId) {
      return;
    }
    setState(() {
      _selectedSessionId = sessionId;
      _selectedPoint = null;
      _noteController.clear();
      _snapshot = null;
    });
    unawaited(_requestSnapshot(force: true));
  }

  Future<void> _confirmDeleteSession(HeartRateHistorySession session) async {
    if (session.isActive) {
      return;
    }
    final source = session.source.isEmpty ? '未知设备' : session.source;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除这个连接会话？'),
          content: Text(
            '$source · ${_formatDateTime(session.startedAt)}\n'
            '该会话的心率点和备注都会被删除，操作无法撤销。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    final deleted = await widget.controller.deleteHistorySession(session.id);
    if (!mounted) {
      return;
    }
    if (!deleted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('正在记录的会话不能删除')));
      return;
    }
    if (_selectedSessionId == session.id) {
      final remaining = widget.controller.savedHistorySessions;
      setState(() {
        _selectedSessionId = remaining.isEmpty ? null : remaining.first.id;
        _selectedPoint = null;
        _noteController.clear();
        _snapshot = null;
      });
      unawaited(_requestSnapshot(force: true));
    } else {
      setState(() {});
    }
  }

  void _setRange(_HistoryRange range) {
    if (range == _range) {
      return;
    }
    setState(() {
      _range = range;
      _selectedPoint = null;
      _noteController.clear();
      _snapshot = null;
    });
    unawaited(_requestSnapshot(force: true));
  }

  void _selectPoint(HeartRateHistoryPoint point) {
    if (_selectedPoint?.id == point.id) {
      return;
    }
    setState(() {
      _selectedPoint = point;
      _noteController.text =
          widget.controller.noteForHistoryPoint(point.id)?.text ?? '';
    });
  }

  Future<void> _saveNote() async {
    final point = _selectedPoint;
    if (point == null || _isSavingNote) {
      return;
    }
    setState(() => _isSavingNote = true);
    try {
      await widget.controller.saveHistoryNote(point.id, _noteController.text);
      if (!mounted) {
        return;
      }
      setState(() => _syncSnapshotNote(point.id));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('备注已保存到本地')));
    } finally {
      if (mounted) {
        setState(() => _isSavingNote = false);
      }
    }
  }

  Future<void> _removeNote() async {
    final point = _selectedPoint;
    if (point == null || _isSavingNote) {
      return;
    }
    await widget.controller.removeHistoryNote(point.id);
    if (mounted) {
      setState(() {
        _noteController.clear();
        _syncSnapshotNote(point.id);
      });
    }
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清空本地心率记录？'),
          content: const Text('所有心率点和备注都会从这台设备删除，操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await widget.controller.clearSavedHistory();
    if (mounted) {
      setState(() {
        _selectedSessionId = null;
        _selectedPoint = null;
        _noteController.clear();
        _snapshot = _HistorySnapshot(
          sessionId: null,
          revision: widget.controller.savedHistoryRevision,
          range: _range,
          allPointCount: 0,
          points: const <HeartRateHistoryPoint>[],
          data: const _HistorySnapshotData(
            displayPoints: <HeartRateHistoryPoint>[],
            minimumBpm: null,
            notePointsById: <String, HeartRateHistoryPoint>{},
            notes: <HeartRateHistoryNote>[],
            notePointIds: <String>{},
            lowCount: 0,
            mediumCount: 0,
            highCount: 0,
            averageBpm: null,
            maximumBpm: null,
          ),
        );
      });
    }
  }

  void _syncSnapshotNote(String pointId) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    final note = widget.controller.noteForHistoryPoint(pointId);
    final notes = snapshot.data.notes
        .where((entry) => entry.pointId != pointId)
        .toList();
    if (note != null) {
      notes.add(note);
    }
    notes.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final notePointsById = Map<String, HeartRateHistoryPoint>.of(
      snapshot.data.notePointsById,
    );
    if (note == null) {
      notePointsById.remove(pointId);
    } else {
      final point =
          snapshot.data.notePointsById[pointId] ??
          (_selectedPoint?.id == pointId ? _selectedPoint : null);
      if (point != null) {
        notePointsById[pointId] = point;
      }
    }
    _snapshot = _HistorySnapshot(
      sessionId: snapshot.sessionId,
      revision: widget.controller.savedHistoryRevision,
      range: snapshot.range,
      allPointCount: snapshot.allPointCount,
      points: snapshot.points,
      data: _HistorySnapshotData(
        displayPoints: snapshot.data.displayPoints,
        minimumBpm: snapshot.data.minimumBpm,
        notePointsById: notePointsById,
        notes: notes,
        notePointIds: notes.map((entry) => entry.pointId).toSet(),
        lowCount: snapshot.data.lowCount,
        mediumCount: snapshot.data.mediumCount,
        highCount: snapshot.data.highCount,
        averageBpm: snapshot.data.averageBpm,
        maximumBpm: snapshot.data.maximumBpm,
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.pointCount,
    required this.retentionDays,
    required this.maxPoints,
    required this.onBack,
    required this.refreshing,
    required this.onRefresh,
    required this.onClear,
  });

  final int pointCount;
  final int retentionDays;
  final int maxPoints;
  final VoidCallback onBack;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 24, 16),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.coralWash,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.timeline,
                size: 21,
                color: AppColors.coralDark,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('心率历史', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    '本地保存 · $pointCount 个心率点 · '
                    '最多 $retentionDays 天 / ${_compactCount(maxPoints)} 点',
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: refreshing ? null : onRefresh,
              tooltip: '刷新历史',
              icon: refreshing
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 19),
            ),
            const SizedBox(width: 4),
            IconButton.outlined(
              onPressed: onClear,
              tooltip: '清空本地记录',
              icon: const Icon(Icons.delete_outline, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionListPanel extends StatelessWidget {
  const _SessionListPanel({
    required this.sessions,
    required this.selectedSessionId,
    required this.onChanged,
    required this.onDelete,
  });

  final List<HeartRateHistorySession> sessions;
  final String? selectedSessionId;
  final ValueChanged<String> onChanged;
  final ValueChanged<HeartRateHistorySession> onDelete;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
            child: Row(
              children: [
                const Icon(Icons.link, size: 18, color: AppColors.inkMuted),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    '连接会话',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${sessions.length}',
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 10,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: sessions.isEmpty
                ? const Center(
                    child: Text(
                      '暂无连接会话',
                      style: TextStyle(color: AppColors.inkMuted, fontSize: 11),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    itemCount: sessions.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      return _SessionListTile(
                        session: session,
                        selected: session.id == selectedSessionId,
                        onTap: () => onChanged(session.id),
                        onDelete: session.isActive
                            ? null
                            : () => onDelete(session),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionListTile extends StatelessWidget {
  const _SessionListTile({
    required this.session,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  final HeartRateHistorySession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final source = session.source.isEmpty ? '未知设备' : session.source;
    return Material(
      color: selected ? AppColors.coralWash : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppColors.coralDark : AppColors.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (session.isActive) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.mint,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  if (onDelete != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: onDelete,
                      tooltip: '删除会话',
                      icon: const Icon(Icons.delete_outline, size: 16),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 26,
                        height: 26,
                      ),
                      padding: EdgeInsets.zero,
                      color: selected
                          ? AppColors.coralDark
                          : AppColors.inkMuted,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 5),
              Text(
                _formatSessionTime(session.startedAt),
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 10,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                session.isActive
                    ? '进行中'
                    : '结束于 ${_formatClock(session.endedAt!)}',
                style: TextStyle(
                  color: session.isActive
                      ? AppColors.mint
                      : AppColors.inkMuted.withValues(alpha: 0.8),
                  fontSize: 9,
                  fontWeight: session.isActive
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryToolbar extends StatelessWidget {
  const _HistoryToolbar({
    required this.snapshot,
    required this.range,
    required this.onRangeChanged,
  });

  final _HistorySnapshot snapshot;
  final _HistoryRange range;
  final ValueChanged<_HistoryRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final points = snapshot.points;
    final coverage = points.length < 2
        ? Duration.zero
        : points.last.recordedAt.difference(points.first.recordedAt);
    return Wrap(
      spacing: 28,
      runSpacing: 18,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ToolbarMetric(label: '当前范围', value: '${points.length}', unit: '点'),
        _ToolbarMetric(
          label: '实际覆盖',
          value: _formatCoverage(coverage),
          unit: '',
        ),
        _ToolbarMetric(
          label: '平均',
          value: snapshot.data.averageBpm?.toString() ?? '--',
          unit: 'BPM',
        ),
        _ToolbarMetric(
          label: '最高',
          value: snapshot.data.maximumBpm?.toString() ?? '--',
          unit: 'BPM',
        ),
        Wrap(
          spacing: 13,
          runSpacing: 8,
          children: [
            _ZoneCount(
              zone: HeartRateZone.high,
              count: snapshot.data.highCount,
              range: '> $highHeartRateThreshold',
            ),
            _ZoneCount(
              zone: HeartRateZone.medium,
              count: snapshot.data.mediumCount,
              range: '$lowHeartRateThreshold–$highHeartRateThreshold',
            ),
            _ZoneCount(
              zone: HeartRateZone.low,
              count: snapshot.data.lowCount,
              range: '< $lowHeartRateThreshold',
            ),
          ],
        ),
        SegmentedButton<_HistoryRange>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _HistoryRange.hour, label: Text('1 小时')),
            ButtonSegment(value: _HistoryRange.day, label: Text('24 小时')),
            ButtonSegment(value: _HistoryRange.week, label: Text('最多 7 天')),
            ButtonSegment(value: _HistoryRange.all, label: Text('本次全部')),
          ],
          selected: {range},
          onSelectionChanged: (selection) => onRangeChanged(selection.first),
        ),
      ],
    );
  }
}

class _ToolbarMetric extends StatelessWidget {
  const _ToolbarMetric({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 10),
        ),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 21,
                height: 1,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ZoneCount extends StatelessWidget {
  const _ZoneCount({
    required this.zone,
    required this.count,
    required this.range,
  });

  final HeartRateZone zone;
  final int count;
  final String range;

  @override
  Widget build(BuildContext context) {
    final color = _zoneColor(zone);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '${zone.label} $count',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          range,
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 9),
        ),
      ],
    );
  }
}

class _HistoryChartSection extends StatelessWidget {
  const _HistoryChartSection({
    required this.points,
    required this.displayPoints,
    required this.minimumBpm,
    required this.maximumBpm,
    required this.dataVersion,
    required this.selectedPointId,
    required this.notePointIds,
    required this.onPointSelected,
  });

  final List<HeartRateHistoryPoint> points;
  final List<HeartRateHistoryPoint> displayPoints;
  final int? minimumBpm;
  final int? maximumBpm;
  final int dataVersion;
  final String? selectedPointId;
  final Set<String> notePointIds;
  final ValueChanged<HeartRateHistoryPoint> onPointSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('心率折线', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text(
              '${notePointIds.length} 个备注',
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 12),
        HeartRateHistoryChart(
          points: points,
          displayPoints: displayPoints,
          minimumBpm: minimumBpm,
          maximumBpm: maximumBpm,
          dataVersion: dataVersion,
          selectedPointId: selectedPointId,
          onPointSelected: onPointSelected,
          notePointIds: notePointIds,
        ),
        if (points.isNotEmpty) ...[
          const SizedBox(height: 9),
          Row(
            children: [
              Text(
                _formatDateTime(points.first.recordedAt),
                style: const TextStyle(color: AppColors.inkMuted, fontSize: 9),
              ),
              const Spacer(),
              Text(
                _formatDateTime(points.last.recordedAt),
                style: const TextStyle(color: AppColors.inkMuted, fontSize: 9),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PointNotesPanel extends StatelessWidget {
  const _PointNotesPanel({
    required this.selectedPoint,
    required this.pointsById,
    required this.noteController,
    required this.note,
    required this.notes,
    required this.isSaving,
    required this.onSave,
    required this.onRemove,
    required this.onSelectPoint,
  });

  final HeartRateHistoryPoint? selectedPoint;
  final Map<String, HeartRateHistoryPoint> pointsById;
  final TextEditingController noteController;
  final HeartRateHistoryNote? note;
  final List<HeartRateHistoryNote> notes;
  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onRemove;
  final ValueChanged<HeartRateHistoryPoint> onSelectPoint;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('点位备注', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            if (selectedPoint case final point?) ...[
              _SelectedPointHeader(point: point),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                minLines: 3,
                maxLines: 5,
                maxLength: 180,
                decoration: const InputDecoration(
                  labelText: '备注',
                  hintText: '记录当时发生了什么',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isSaving ? null : onSave,
                      icon: isSaving
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: Text(note == null ? '添加备注' : '更新备注'),
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      onPressed: isSaving ? null : onRemove,
                      tooltip: '删除备注',
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ],
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      size: 25,
                      color: AppColors.inkMuted,
                    ),
                    SizedBox(height: 9),
                    Text(
                      '选择一个心率点',
                      style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            const Divider(height: 1),
            const SizedBox(height: 17),
            Row(
              children: [
                Text('已标记', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Text(
                  '${notes.length}',
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 10,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (notes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '当前范围暂无备注',
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 11),
                ),
              )
            else
              for (final entry in notes.take(8))
                _NoteListTile(
                  note: entry,
                  point: _pointForNote(entry),
                  isSelected: entry.pointId == selectedPoint?.id,
                  onTap: () {
                    final point = _pointForNote(entry);
                    if (point != null) {
                      onSelectPoint(point);
                    }
                  },
                ),
          ],
        ),
      ),
    );
  }

  HeartRateHistoryPoint? _pointForNote(HeartRateHistoryNote entry) {
    return pointsById[entry.pointId];
  }
}

class _SelectedPointHeader extends StatelessWidget {
  const _SelectedPointHeader({required this.point});

  final HeartRateHistoryPoint point;

  @override
  Widget build(BuildContext context) {
    final color = _zoneColor(point.zone);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Text(
            '${point.beatsPerMinute}',
            style: TextStyle(
              color: color,
              fontSize: 34,
              height: 0.95,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 5),
          Padding(
            padding: const EdgeInsets.only(top: 13),
            child: Text(
              'BPM',
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${point.zone.label}心率',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _formatDateTime(point.recordedAt),
                style: const TextStyle(color: AppColors.inkMuted, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoteListTile extends StatelessWidget {
  const _NoteListTile({
    required this.note,
    required this.point,
    required this.isSelected,
    required this.onTap,
  });

  final HeartRateHistoryNote note;
  final HeartRateHistoryPoint? point;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.coralWash : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.bookmark,
                size: 14,
                color: point == null
                    ? AppColors.inkMuted
                    : _zoneColor(point!.zone),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      point == null
                          ? _formatDateTime(note.updatedAt)
                          : '${point!.beatsPerMinute} BPM · '
                                '${_formatDateTime(point!.recordedAt)}',
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 9,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      note.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _zoneColor(HeartRateZone zone) {
  return switch (zone) {
    HeartRateZone.low => AppColors.amber,
    HeartRateZone.medium => AppColors.mint,
    HeartRateZone.high => AppColors.coral,
  };
}

String _formatDateTime(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}

String _formatSessionTime(DateTime time) => _formatDateTime(time);

String _formatClock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _compactCount(int value) {
  if (value >= 10000) {
    return '${(value / 10000).round()} 万';
  }
  return '$value';
}

String _formatCoverage(Duration duration) {
  if (duration <= Duration.zero) {
    return '--';
  }
  if (duration.inDays >= 2) {
    return '${(duration.inHours / 24).toStringAsFixed(1)} 天';
  }
  if (duration.inHours >= 1) {
    return '${duration.inHours} 小时';
  }
  return '${duration.inMinutes.clamp(1, 59)} 分钟';
}
