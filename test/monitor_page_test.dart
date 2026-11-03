import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/heart_rate/heart_rate_controller.dart';
import 'package:heartbeat_monitor/src/screens/game_overlay_settings.dart';
import 'package:heartbeat_monitor/src/screens/monitor_page.dart';
import 'package:heartbeat_monitor/src/theme/app_theme.dart';

void main() {
  testWidgets('wide monitor layout renders with the split detail panel', (
    tester,
  ) async {
    final controller = HeartRateController();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MonitorPage(
          controller: controller,
          onEnterGameOverlay: () {},
          overlaySettings: GameOverlaySettings.defaults,
          onOverlaySettingsChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('读数详情'), findsOneWidget);
    expect(find.text('R-R 间期'), findsOneWidget);
    expect(find.text('皮肤接触'), findsOneWidget);
    expect(find.text('数据源'), findsOneWidget);
    expect(find.text('心率趋势'), findsOneWidget);

    await tester.runAsync(() => controller.toggleDemo());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('模拟心率'), findsWidgets);
    expect(find.text('BPM'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
