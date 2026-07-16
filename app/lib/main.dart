import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'features/dictionary/dictionary_screen.dart';
import 'features/feed/feed_screen.dart';
import 'features/placement/placement_screen.dart';
import 'features/stats/stats_screen.dart';
import 'features/training/training_screen.dart';
import 'features/tutor/tutor_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const LangMeApp(),
    ),
  );
}

class LangMeApp extends StatelessWidget {
  const LangMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'LangMe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      themeMode: state.darkTheme ? ThemeMode.dark : ThemeMode.light,
      home: !state.loaded
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : state.placementDone
              ? const HomeShell()
              : const PlacementScreen(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dueCount = state.dueReviews().length;

    final screens = const [
      FeedScreen(),
      TutorScreen(),
      TrainingScreen(),
      DictionaryScreen(),
      StatsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _tab, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.style_outlined),
              selectedIcon: Icon(Icons.style),
              label: 'Лента'),
          const NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              selectedIcon: Icon(Icons.forum),
              label: 'Диалог'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: dueCount > 0,
              label: Text('$dueCount'),
              child: const Icon(Icons.fitness_center_outlined),
            ),
            selectedIcon: const Icon(Icons.fitness_center),
            label: 'Тренировка',
          ),
          const NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Словарь'),
          const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Профиль'),
        ],
      ),
    );
  }
}
