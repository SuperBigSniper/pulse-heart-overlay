import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  runApp(const HeartRateApp());
}
