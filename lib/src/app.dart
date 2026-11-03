import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'heart_rate/heart_rate_controller.dart';
import 'screens/game_overlay_page.dart';
import 'screens/game_overlay_settings.dart';
import 'screens/monitor_page.dart';
import 'theme/app_theme.dart';

class HeartRateApp extends StatefulWidget {
  const HeartRateApp({
    super.key,
    this.autoStartDemo = const bool.fromEnvironment('START_DEMO'),
  });

  final bool autoStartDemo;

  @override
  State<HeartRateApp> createState() => _HeartRateAppState();
}

class _HeartRateAppState extends State<HeartRateApp> with WindowListener {
  static const _overlayAnimationScaleKey = 'overlay.animationScale';
  static const _overlayTextScaleKey = 'overlay.textScale';
  static const _overlayAnimationSpeedKey = 'overlay.animationSpeed';
  static const _overlayWidthKey = 'overlay.width';
  static const _overlayHeightKey = 'overlay.height';
  static const _overlayPositionLeftKey = 'overlay.positionLeft';
  static const _overlayPositionTopKey = 'overlay.positionTop';

  late final HeartRateController _controller;
  GameOverlaySettings _overlaySettings = GameOverlaySettings.defaults;
  _DashboardWindowState? _dashboardWindowState;
  _OverlayResizeSession? _overlayResizeSession;
  Rect? _pendingOverlayBounds;
  Offset _pendingOverlayResizeDelta = Offset.zero;
  bool _isGameOverlay = false;
  bool _isChangingWindowMode = false;
  bool _isWritingOverlayBounds = false;
  bool _isScalingOverlay = false;
  double _pendingOverlayScale = 0;
  Timer? _overlaySettingsSaveTimer;
  Timer? _overlayMoveDebounce;
  int _overlayResizeGeneration = 0;
  Size _overlayMaximumSize = const Size(10000, 10000);

  /// AppKit answers every setFrame with a surface resize. Driving them at input
  /// rate (trackpad scroll, corner drag) outruns the macOS embedder's resize
  /// ack — it then logs "Resize timed out" and the raster thread starts
  /// reporting stale frame times. Both callers already coalesce to the latest
  /// target, so spacing the writes costs no accuracy.
  static const _minimumWindowWriteGap = Duration(milliseconds: 32);
  final Stopwatch _windowWriteClock = Stopwatch()..start();
  Duration _lastWindowBoundsWriteAt = Duration.zero;

  Future<void> _writeWindowBounds(Rect bounds) async {
    final sinceLast = _windowWriteClock.elapsed - _lastWindowBoundsWriteAt;
    if (sinceLast < _minimumWindowWriteGap) {
      await Future<void>.delayed(_minimumWindowWriteGap - sinceLast);
    }
    _lastWindowBoundsWriteAt = _windowWriteClock.elapsed;
    await windowManager.setBounds(bounds);
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _controller = HeartRateController();
    unawaited(_controller.initialize());
    unawaited(_loadOverlaySettings());
    if (widget.autoStartDemo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_controller.toggleDemo());
      });
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _overlayMoveDebounce?.cancel();
    final hasPendingSettingsSave = _overlaySettingsSaveTimer?.isActive ?? false;
    _overlaySettingsSaveTimer?.cancel();
    if (hasPendingSettingsSave) {
      unawaited(_saveOverlaySettings(_overlaySettings));
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  void onWindowMoved() {
    // 角落模式拖动结束（防抖）后记录窗口位置，这样即使直接退出应用，
    // 下次进入角落模式也能回到上次位置。
    if (!_isGameOverlay || _isChangingWindowMode) {
      return;
    }
    _overlayMoveDebounce?.cancel();
    _overlayMoveDebounce = Timer(const Duration(milliseconds: 250), () {
      _overlayMoveDebounce = null;
      unawaited(_captureOverlayPosition());
    });
  }

  Future<void> _captureOverlayPosition() async {
    if (!_isGameOverlay || _isChangingWindowMode) {
      return;
    }
    try {
      final bounds = await windowManager.getBounds();
      if (!_isGameOverlay || _isChangingWindowMode) {
        return;
      }
      _overlaySettings = _overlaySettings.copyWith(
        overlayLeft: bounds.left,
        overlayTop: bounds.top,
      );
      _scheduleOverlaySettingsSave();
    } on Object catch (error) {
      debugPrint('Unable to record overlay position: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pulse 心率',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAppTheme(),
      home: _isGameOverlay
          ? GameOverlayPage(
              controller: _controller,
              onRestore: _restoreDashboard,
              onStartDragging: _startDraggingOverlay,
              onResizeStart: _startResizingOverlay,
              onResize: _resizeOverlay,
              onScale: _scaleOverlay,
              settings: _overlaySettings,
            )
          : MonitorPage(
              controller: _controller,
              onEnterGameOverlay: _enterGameOverlay,
              overlaySettings: _overlaySettings,
              onOverlaySettingsChanged: _updateOverlaySettings,
            ),
    );
  }

  Future<void> _enterGameOverlay() async {
    if (_isGameOverlay || _isChangingWindowMode) {
      return;
    }
    _isChangingWindowMode = true;
    final maximumSize = overlayMaximumSizeFor(context);
    // 后面有一长串 await，屏幕尺寸在进入 try 前先取好，避免跨异步使用 context。
    final view = View.of(context);
    final displaySize = view.display.size / view.devicePixelRatio;

    try {
      _dashboardWindowState = await _captureDashboardWindowState();
      if (_dashboardWindowState!.isFullScreen) {
        await windowManager.setFullScreen(false);
      } else if (_dashboardWindowState!.isMaximized) {
        await windowManager.unmaximize();
      }

      // 窗口形态切换期间先隐藏：此时 Flutter 树和窗口尺寸会短暂不一致
      // （大窗口渲染角落布局会闪出巨型爱心），藏起来等形态与内容都就位
      // 后再显示，避免可见的闪帧。
      await windowManager.hide();

      _overlayMaximumSize = maximumSize;
      final overlaySize = Size(
        _overlaySettings.overlayWidth
            .clamp(GameOverlayPage.minimumWindowSize.width, maximumSize.width)
            .toDouble(),
        _overlaySettings.overlayHeight
            .clamp(GameOverlayPage.minimumWindowSize.height, maximumSize.height)
            .toDouble(),
      );
      await windowManager.setMinimumSize(GameOverlayPage.minimumWindowSize);
      await windowManager.setMaximumSize(maximumSize);
      await windowManager.setResizable(true);
      if (Platform.isWindows) {
        await windowManager.setAsFrameless();
      } else {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
      }
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      if (Platform.isMacOS) {
        await windowManager.setVisibleOnAllWorkspaces(
          true,
          visibleOnFullScreen: true,
        );
      }

      await windowManager.setSize(overlaySize);
      final savedLeft = _overlaySettings.overlayLeft;
      final savedTop = _overlaySettings.overlayTop;
      if (savedLeft == null || savedTop == null) {
        // 从未记录过位置：默认吸附到右上角。
        await windowManager.setAlignment(Alignment.topRight);
        final position = await windowManager.getPosition();
        await windowManager.setPosition(
          position.translate(-18, Platform.isMacOS ? 18 : 12),
        );
      } else {
        // 恢复上次位置；显示器或分辨率变了时做可见性钳制，至少保留
        // 24 逻辑像素在屏幕内，避免整个浮层漂出屏幕找不到。
        await windowManager.setPosition(
          _clampedOverlayPosition(
            Offset(savedLeft, savedTop),
            overlaySize,
            displaySize,
          ),
        );
      }
      // 窗口已经是角落尺寸后才切 Flutter 树，等角落布局真正渲染完成再显示。
      if (mounted) {
        setState(() => _isGameOverlay = true);
        await _waitForNextFrame(const Duration(milliseconds: 120));
      }
      await windowManager.show(inactive: true);
    } on Object catch (error) {
      debugPrint('Unable to enter game overlay: $error');
      if (mounted) {
        setState(() => _isGameOverlay = false);
      }
      await _restoreDashboardWindow();
      // 入口处已把窗口隐藏，失败回退后要确保它重新可见。
      await windowManager.show();
    } finally {
      _isChangingWindowMode = false;
    }
  }

  Future<void> _restoreDashboard() async {
    if (!_isGameOverlay || _isChangingWindowMode) {
      return;
    }
    _isChangingWindowMode = true;

    try {
      try {
        final overlayBounds = await windowManager.getBounds();
        _rememberOverlaySize(overlayBounds.size);
        _rememberOverlayPosition(overlayBounds.topLeft);
      } on Object catch (error) {
        debugPrint('Unable to read overlay size: $error');
      }
      final dashboardState = _dashboardWindowState;
      _overlayResizeSession = null;
      _pendingOverlayBounds = null;
      _pendingOverlayScale = 0;
      _overlayResizeGeneration++;
      // 同进入角落模式：先隐藏窗口，等窗口形态与仪表盘内容都就位再显示，
      // 否则会看到角落布局被拉进大窗口的闪帧。
      await windowManager.hide();
      await windowManager.setAlwaysOnTop(
        dashboardState?.isAlwaysOnTop ?? false,
      );
      await windowManager.setSkipTaskbar(
        dashboardState?.isSkipTaskbar ?? false,
      );
      if (Platform.isMacOS) {
        await windowManager.setVisibleOnAllWorkspaces(false);
      }
      await windowManager.setMaximumSize(const Size(10000, 10000));
      await windowManager.setResizable(dashboardState?.isResizable ?? true);
      await windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      );
      await windowManager.setBackgroundColor(AppColors.paper);

      final bounds = dashboardState?.bounds;
      if (bounds != null) {
        await windowManager.setBounds(bounds);
      }
      await windowManager.setMinimumSize(const Size(900, 640));

      if (mounted) {
        setState(() => _isGameOverlay = false);
        await _waitForNextFrame(const Duration(milliseconds: 120));
      }
      if (dashboardState?.isFullScreen ?? false) {
        await windowManager.setFullScreen(true);
      } else if (dashboardState?.isMaximized ?? false) {
        await windowManager.maximize();
      }
      await windowManager.show();
    } on Object catch (error) {
      debugPrint('Unable to restore dashboard: $error');
      if (mounted && _isGameOverlay) {
        setState(() => _isGameOverlay = false);
      }
      // 入口处已把窗口隐藏，失败回退后要确保它重新可见。
      await windowManager.show();
    } finally {
      _isChangingWindowMode = false;
    }
  }

  Future<void> _restoreDashboardWindow() async {
    final dashboardState = _dashboardWindowState;
    if (dashboardState == null) {
      return;
    }

    try {
      await windowManager.setMaximumSize(const Size(10000, 10000));
      await windowManager.setMinimumSize(const Size(900, 640));
      await windowManager.setResizable(dashboardState.isResizable);
      await windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      );
      await windowManager.setBackgroundColor(AppColors.paper);
      await windowManager.setAlwaysOnTop(dashboardState.isAlwaysOnTop);
      await windowManager.setSkipTaskbar(dashboardState.isSkipTaskbar);
      if (Platform.isMacOS) {
        await windowManager.setVisibleOnAllWorkspaces(false);
      }
      await windowManager.setBounds(dashboardState.bounds);
    } on Object catch (error) {
      debugPrint('Unable to recover dashboard window: $error');
    }
  }

  /// 等待下一帧渲染完成后再继续；若窗口隐藏导致引擎暂停 vsync（endOfFrame
  /// 永远不来），用超时兜底，最坏情况也只是显示上一帧，不会卡死切换流程。
  Future<void> _waitForNextFrame(Duration timeout) {
    return WidgetsBinding.instance.endOfFrame.timeout(
      timeout,
      onTimeout: () {},
    );
  }

  /// 把上次保存的浮层位置钳制到屏幕内：至少保留 24 逻辑像素可见。
  /// 若屏幕比浮层还小（极端情况），钳制区间会退化，用 min/max 保证有效。
  Offset _clampedOverlayPosition(
    Offset position,
    Size overlaySize,
    Size displaySize,
  ) {
    double clampAxis(double value, double overlayExtent, double extent) {
      final lower = math.min(-overlayExtent + 24, extent - 24);
      final upper = math.max(-overlayExtent + 24, extent - 24);
      return value.clamp(lower, upper).toDouble();
    }

    return Offset(
      clampAxis(position.dx, overlaySize.width, displaySize.width),
      clampAxis(position.dy, overlaySize.height, displaySize.height),
    );
  }

  void _rememberOverlayPosition(Offset position) {
    _overlaySettings = _overlaySettings.copyWith(
      overlayLeft: position.dx,
      overlayTop: position.dy,
    );
    _scheduleOverlaySettingsSave();
  }

  Future<_DashboardWindowState> _captureDashboardWindowState() async {
    return _DashboardWindowState(
      bounds: await windowManager.getBounds(),
      isResizable: await windowManager.isResizable(),
      isAlwaysOnTop: await windowManager.isAlwaysOnTop(),
      isSkipTaskbar: await windowManager.isSkipTaskbar(),
      isMaximized: await windowManager.isMaximized(),
      isFullScreen: await windowManager.isFullScreen(),
    );
  }

  void _startDraggingOverlay() {
    unawaited(windowManager.startDragging());
  }

  void _startResizingOverlay(OverlayResizeCorner corner) {
    if (!_isGameOverlay || _isChangingWindowMode) {
      return;
    }
    final generation = ++_overlayResizeGeneration;
    _pendingOverlayResizeDelta = Offset.zero;
    unawaited(_captureOverlayResizeStart(corner, generation));
  }

  Future<void> _captureOverlayResizeStart(
    OverlayResizeCorner corner,
    int generation,
  ) async {
    try {
      final bounds = await windowManager.getBounds();
      if (!_isGameOverlay || generation != _overlayResizeGeneration) {
        return;
      }
      _overlayResizeSession = _OverlayResizeSession(
        corner: corner,
        startBounds: bounds,
      );
      if (_pendingOverlayResizeDelta != Offset.zero) {
        _resizeOverlay(corner, _pendingOverlayResizeDelta);
      }
    } on Object catch (error) {
      debugPrint('Unable to begin overlay resize: $error');
    }
  }

  void _resizeOverlay(OverlayResizeCorner corner, Offset totalDelta) {
    final session = _overlayResizeSession;
    if (!_isGameOverlay || session == null || session.corner != corner) {
      _pendingOverlayResizeDelta = totalDelta;
      return;
    }

    _pendingOverlayBounds = resizedOverlayBounds(
      startBounds: session.startBounds,
      corner: corner,
      totalDelta: totalDelta,
      maximumSize: _overlayMaximumSize,
    );
    if (!_isWritingOverlayBounds) {
      unawaited(_flushOverlayBounds());
    }
  }

  Future<void> _flushOverlayBounds() async {
    _isWritingOverlayBounds = true;
    Rect? latestBounds;
    try {
      while (true) {
        final bounds = _pendingOverlayBounds;
        if (bounds == null) {
          break;
        }
        _pendingOverlayBounds = null;
        latestBounds = bounds;
        await _writeWindowBounds(bounds);
      }
    } on Object catch (error) {
      debugPrint('Unable to resize overlay: $error');
    } finally {
      _isWritingOverlayBounds = false;
      if (_pendingOverlayBounds != null) {
        unawaited(_flushOverlayBounds());
      } else if (latestBounds != null) {
        _rememberOverlaySize(latestBounds.size);
        _rememberOverlayPosition(latestBounds.topLeft);
      }
    }
  }

  void _scaleOverlay(double amount) {
    if (!_isGameOverlay || _isChangingWindowMode) {
      return;
    }
    _pendingOverlayScale += amount;
    if (!_isScalingOverlay) {
      unawaited(_flushOverlayScale());
    }
  }

  Future<void> _flushOverlayScale() async {
    _isScalingOverlay = true;
    try {
      while (true) {
        final amount = _pendingOverlayScale;
        _pendingOverlayScale = 0;
        if (amount.abs() < 0.1) {
          // Drop the sub-threshold remainder: keeping it would make a much
          // later wheel event resize the window by a visible jump.
          break;
        }
        final bounds = await windowManager.getBounds();
        if (!_isGameOverlay || _isChangingWindowMode) {
          return;
        }
        final minScale = math.max(
          GameOverlayPage.minimumWindowSize.width / bounds.width,
          GameOverlayPage.minimumWindowSize.height / bounds.height,
        );
        final maxScale = math.min(
          _overlayMaximumSize.width / bounds.width,
          _overlayMaximumSize.height / bounds.height,
        );
        final scale = ((bounds.shortestSide + amount) / bounds.shortestSide)
            .clamp(minScale, maxScale)
            .toDouble();
        final newSize = Size(bounds.width * scale, bounds.height * scale);
        final newBounds = Rect.fromCenter(
          center: bounds.center,
          width: newSize.width,
          height: newSize.height,
        );
        await _writeWindowBounds(newBounds);
        _rememberOverlaySize(newBounds.size);
        _rememberOverlayPosition(newBounds.topLeft);
      }
    } on Object catch (error) {
      debugPrint('Unable to scale overlay: $error');
    } finally {
      _isScalingOverlay = false;
      // A wheel event may have landed while the last iteration was awaiting;
      // it did not start a flush because the flag was still set.
      if (_pendingOverlayScale.abs() >= 0.1) {
        unawaited(_flushOverlayScale());
      } else {
        _pendingOverlayScale = 0;
      }
    }
  }

  Future<void> _loadOverlaySettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedLeft = preferences.getDouble(_overlayPositionLeftKey);
      final savedTop = preferences.getDouble(_overlayPositionTopKey);
      // 位置必须成对生效，只存了半个就当没有记录过。
      final hasSavedPosition = savedLeft != null && savedTop != null;
      final settings = GameOverlaySettings(
        animationScale:
            preferences.getDouble(_overlayAnimationScaleKey) ??
            GameOverlaySettings.defaults.animationScale,
        textScale:
            preferences.getDouble(_overlayTextScaleKey) ??
            GameOverlaySettings.defaults.textScale,
        animationSpeed:
            preferences.getDouble(_overlayAnimationSpeedKey) ??
            GameOverlaySettings.defaults.animationSpeed,
        overlayWidth:
            preferences.getDouble(_overlayWidthKey) ??
            GameOverlaySettings.defaults.overlayWidth,
        overlayHeight:
            preferences.getDouble(_overlayHeightKey) ??
            GameOverlaySettings.defaults.overlayHeight,
        overlayLeft: hasSavedPosition ? savedLeft : null,
        overlayTop: hasSavedPosition ? savedTop : null,
      );
      if (mounted) {
        setState(() => _overlaySettings = settings);
      }
    } on Object catch (error) {
      debugPrint('Unable to load overlay settings: $error');
    }
  }

  void _updateOverlaySettings(GameOverlaySettings settings) {
    if (settings == _overlaySettings) {
      return;
    }
    setState(() => _overlaySettings = settings);
    _scheduleOverlaySettingsSave();
  }

  void _rememberOverlaySize(Size size) {
    final width = size.width
        .clamp(
          GameOverlayPage.minimumWindowSize.width,
          _overlayMaximumSize.width,
        )
        .toDouble();
    final height = size.height
        .clamp(
          GameOverlayPage.minimumWindowSize.height,
          _overlayMaximumSize.height,
        )
        .toDouble();
    if ((_overlaySettings.overlayWidth - width).abs() < 0.5 &&
        (_overlaySettings.overlayHeight - height).abs() < 0.5) {
      return;
    }
    _overlaySettings = _overlaySettings.copyWith(
      overlayWidth: width,
      overlayHeight: height,
    );
    _scheduleOverlaySettingsSave();
  }

  void _scheduleOverlaySettingsSave() {
    _overlaySettingsSaveTimer?.cancel();
    _overlaySettingsSaveTimer = Timer(const Duration(milliseconds: 450), () {
      _overlaySettingsSaveTimer = null;
      unawaited(_saveOverlaySettings(_overlaySettings));
    });
  }

  Future<void> _saveOverlaySettings(GameOverlaySettings settings) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final left = settings.overlayLeft;
      final top = settings.overlayTop;
      await Future.wait([
        preferences.setDouble(
          _overlayAnimationScaleKey,
          settings.animationScale,
        ),
        preferences.setDouble(_overlayTextScaleKey, settings.textScale),
        preferences.setDouble(
          _overlayAnimationSpeedKey,
          settings.animationSpeed,
        ),
        preferences.setDouble(_overlayWidthKey, settings.overlayWidth),
        preferences.setDouble(_overlayHeightKey, settings.overlayHeight),
        if (left != null && top != null) ...[
          preferences.setDouble(_overlayPositionLeftKey, left),
          preferences.setDouble(_overlayPositionTopKey, top),
        ] else ...[
          preferences.remove(_overlayPositionLeftKey),
          preferences.remove(_overlayPositionTopKey),
        ],
      ]);
    } on Object catch (error) {
      debugPrint('Unable to save overlay settings: $error');
    }
  }
}

class _DashboardWindowState {
  const _DashboardWindowState({
    required this.bounds,
    required this.isResizable,
    required this.isAlwaysOnTop,
    required this.isSkipTaskbar,
    required this.isMaximized,
    required this.isFullScreen,
  });

  final Rect bounds;
  final bool isResizable;
  final bool isAlwaysOnTop;
  final bool isSkipTaskbar;
  final bool isMaximized;
  final bool isFullScreen;
}

class _OverlayResizeSession {
  const _OverlayResizeSession({
    required this.corner,
    required this.startBounds,
  });

  final OverlayResizeCorner corner;
  final Rect startBounds;
}
