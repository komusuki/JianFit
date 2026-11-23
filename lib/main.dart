import 'package:flutter/material.dart';

import 'models/app_palette.dart';
import 'screens/main_shell.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SettingsService.palette.value = await SettingsService.loadPalette();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppPalette>(
      valueListenable: SettingsService.palette,
      builder: (context, palette, _) => MaterialApp(
        title: 'JianFit',
        theme: ThemeData(colorScheme: palette.colorScheme),
        home: const MainShell(),
      ),
    );
  }
}
