import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'recordings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _recordingsKey = GlobalKey<RecordingsScreenState>();

  void _onSelect(int i) {
    setState(() => _index = i);
    if (i == 1) {
      _recordingsKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E13),
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: const Color(0xFF15151C),
            selectedIndex: _index,
            onDestinationSelected: _onSelect,
            labelType: NavigationRailLabelType.all,
            useIndicator: true,
            indicatorColor: const Color(0xFF7C4DFF).withValues(alpha: 0.18),
            selectedIconTheme: const IconThemeData(color: Color(0xFF7C4DFF)),
            unselectedIconTheme: const IconThemeData(color: Colors.white54),
            selectedLabelTextStyle: const TextStyle(color: Color(0xFF7C4DFF), fontWeight: FontWeight.w700, fontSize: 12),
            unselectedLabelTextStyle: const TextStyle(color: Colors.white54, fontSize: 12),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.home), selectedIcon: Icon(Icons.home), label: Text('صفحه اصلی')),
              NavigationRailDestination(icon: Icon(Icons.folder_open_rounded), selectedIcon: Icon(Icons.folder_rounded), label: Text('فایل‌های ضبط شده')),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1, color: Colors.white12),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                const HomeScreen(),
                RecordingsScreen(key: _recordingsKey),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
