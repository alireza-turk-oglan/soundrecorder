import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_size/window_size.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/recorder_controller.dart';
import 'services/dll_downloader.dart';
import 'screens/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setWindowMinSize(const Size(900, 900));
  await DllDownloader.ensureDllExists();
  runApp(const RecorderApp());
}

class RecorderApp extends StatelessWidget {
  const RecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RecorderController(),
      child: MaterialApp(
        title: 'ضبط صدای ویندوز',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          textTheme: GoogleFonts.vazirmatnTextTheme(ThemeData(brightness: Brightness.dark).textTheme),
          scaffoldBackgroundColor: const Color(0xFF0E0E13),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF), brightness: Brightness.dark),
        ),
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa'), Locale('en')],
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const AppShell(),
      ),
    );
  }
}
