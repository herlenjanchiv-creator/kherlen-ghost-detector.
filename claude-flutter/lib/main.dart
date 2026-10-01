import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/measurement_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Радарын тооцоолол portrait чиглэлд тохируулагдсан
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const GhostApp());
}

class GhostApp extends StatelessWidget {
  const GhostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Сүнс илрүүлэгч',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF39FFC8),
          secondary: Color(0xFFFF3B3B),
        ),
      ),
      home: const MeasurementScreen(),
    );
  }
}
