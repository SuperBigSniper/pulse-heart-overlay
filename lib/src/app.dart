import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'heart_rate/heart_rate_controller.dart';
import 'screens/game_overlay_page.dart';
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
  late final HeartRateController _controller;
  _DashboardWindowState? _dashboardWindowState;
  bool _isGameOverlay = false;
  bool _isChangingWindowMode = false;

  @override
  void initState() {
    super.initState();
    _controller = HeartRateController();
    unawaited(_controller.initialize());
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
            )
          : MonitorPage(
              controller: _controller,
              onEnterGameOverlay: _enterGameOverlay,
            ),
    );
  }

  Future<void> _enterGameOverlay() async {
    if (_isGameOverlay || _isChangingWindowMode) {
      return;
    }
    _isChangingWindowMode = true;

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

      const overlaySize = GameOverlayPage.windowSize;
      await windowManager.setMinimumSize(overlaySize);
      await windowManager.setMaximumSize(overlaySize);
      await windowManager.setResizable(false);
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
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
      final dashboardState = _dashboardWindowState;
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
