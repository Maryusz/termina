import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:logging/logging.dart';

import 'src/settings/settings.dart';
import 'src/ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureLogging(level: Level.WARNING).onRecord.listen((record) {
    debugPrint('${record.loggerName}: ${record.message}');
  });
  final TerminaSettings settings = await TerminaSettings.load();
  runApp(TerminaApp(settings: settings));
}

class TerminaApp extends StatelessWidget {
  const TerminaApp({super.key, required this.settings});

  final TerminaSettings settings;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return MaterialApp(
      title: 'Termina',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomePage(initialSettings: settings),
    );
  }
}
