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

class _HeartRateAppState extends State<HeartRateApp> {
  static const _overlayAnimationScaleKey = 'overlay.animationScale';
  static const _overlayTextScaleKey = 'overlay.textScale';
  static const _overlayAnimationSpeedKey = 'overlay.animationSpeed';
  static const _overlayWidthKey = 'overlay.width';
  static const _overlayHeightKey = 'overlay.height';

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
  int _overlayResizeGeneration = 0;
  Size _overlayMaximumSize = const Size(10000, 10000);

  @override
  void initState() {
    super.initState();
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
    _controller.dispose();
    super.dispose();
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

    try {
      _dashboardWindowState = await _captureDashboardWindowState();
      if (_dashboardWindowState!.isFullScreen) {
        await windowManager.setFullScreen(false);
      } else if (_dashboardWindowState!.isMaximized) {
        await windowManager.unmaximize();
      }

      if (mounted) {
        setState(() => _isGameOverlay = true);
      }

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
      await windowManager.setAlignment(Alignment.topRight);
      final position = await windowManager.getPosition();
      await windowManager.setPosition(
        position.translate(-18, Platform.isMacOS ? 18 : 12),
      );
      await windowManager.show(inactive: true);
    } on Object catch (error) {
      debugPrint('Unable to enter game overlay: $error');
      if (mounted) {
        setState(() => _isGameOverlay = false);
      }
      await _restoreDashboardWindow();
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
      } on Object catch (error) {
        debugPrint('Unable to read overlay size: $error');
      }
      final dashboardState = _dashboardWindowState;
      _overlayResizeSession = null;
      _pendingOverlayBounds = null;
      _pendingOverlayScale = 0;
      _overlayResizeGeneration++;
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
        await windowManager.setBounds(bounds);
      }
    } on Object catch (error) {
      debugPrint('Unable to resize overlay: $error');
    } finally {
      _isWritingOverlayBounds = false;
      if (_pendingOverlayBounds != null) {
        unawaited(_flushOverlayBounds());
      } else if (latestBounds != null) {
        _rememberOverlaySize(latestBounds.size);
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
      while (_pendingOverlayScale.abs() >= 0.1) {
        final amount = _pendingOverlayScale;
        _pendingOverlayScale = 0;
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
        await windowManager.setBounds(
          Rect.fromCenter(
            center: bounds.center,
            width: newSize.width,
            height: newSize.height,
          ),
        );
        _rememberOverlaySize(newSize);
      }
    } on Object catch (error) {
      debugPrint('Unable to scale overlay: $error');
    } finally {
      _isScalingOverlay = false;
    }
  }

  Future<void> _loadOverlaySettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
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
      );
      if (mounted) {
        setState(() => _overlaySettings = settings);
      }
    } on Object catch (error) {
      debugPrint('Unable to load overlay settings: $error');
    }
  }

  void _updateOverlaySettings(GameOverlaySettings settings) {
    setState(() => _overlaySettings = settings);
    unawaited(_saveOverlaySettings(settings));
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
    _updateOverlaySettings(
      _overlaySettings.copyWith(overlayWidth: width, overlayHeight: height),
    );
  }

  Future<void> _saveOverlaySettings(GameOverlaySettings settings) async {
    try {
      final preferences = await SharedPreferences.getInstance();
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
