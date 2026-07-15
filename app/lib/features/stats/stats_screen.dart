import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../settings/settings_screen.dart';

/// Profile: activity heat map (GitHub-style), streak, word counters by
/// status and CEFR level, entry point to settings.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final learning = state.countByStatus(WordStatus.learning);
    final known = state.countByStatus(WordStatus.known);
    final mastered = state.countByStatus(WordStatus.mastered);

    // разбивка изученного по уровням
    final byLevel = <String, int>{for (final l in kLevels) l: 0};
    for (final w in state.words) {
      if (state.progressOf(w.word).status != WordStatus.unseen) {
        byLevel[w.level] = (byLevel[w.level] ?? 0) + 1;
      }
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text('Профиль',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _statCard(context, '🔥', '${state.streak}', 'дней подряд'),
              _statCard(context, '📅', '${state.todayCount}',
                  'сегодня (цель ${state.dailyGoal})'),
              _statCard(context, '🎓', '${state.level}', 'уровень'),
            ],
          ),
          const SizedBox(height: 16),
          Text('Активность', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _HeatMap(
                  activity: state.activity, dailyGoal: state.dailyGoal),
            ),
          ),
          const SizedBox(height: 16),
          Text('Слова', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('На изучении', learning, Colors.orange),
                  _row('Знаю', known, Colors.blue),
                  _row('Освоено (SRS ≥ 21 дня)', mastered, Colors.green),
                  const Divider(),
                  _row('Всего в базе', state.words.length, Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('По уровням', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final l in kLevels)
                    if (state.words.any((w) => w.level == l))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(width: 32, child: Text(l)),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: _levelShare(state, l, byLevel[l] ?? 0),
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                                '${byLevel[l]}/${state.words.where((w) => w.level == l).length}'),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _levelShare(AppState state, String level, int studied) {
    final total = state.words.where((w) => w.level == level).length;
    return total == 0 ? 0 : studied / total;
  }

  Widget _statCard(
      BuildContext context, String emoji, String value, String label) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text('$value',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// GitHub-style heat map of the last ~18 weeks.
class _HeatMap extends StatelessWidget {
  final Map<String, int> activity;
  final int dailyGoal;

  const _HeatMap({required this.activity, required this.dailyGoal});

  @override
  Widget build(BuildContext context) {
    const weeks = 18;
    final now = DateTime.now();
    // конец сетки — сегодня; начало — понедельник weeks назад
    final start = now.subtract(Duration(days: weeks * 7 + now.weekday - 1));
    final base = Theme.of(context).colorScheme.primary;

    Color cellColor(int count) {
      if (count == 0) {
        return Theme.of(context).colorScheme.surfaceContainerHighest;
      }
      final t = (count / dailyGoal).clamp(0.15, 1.0);
      return base.withOpacity(0.25 + 0.75 * t);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var row = 0; row < 7; row++)
            Row(
              children: [
                for (var col = 0; col <= weeks; col++)
                  _cell(start.add(Duration(days: col * 7 + row)), now,
                      cellColor),
              ],
            ),
          const SizedBox(height: 6),
          Text('Последние $weeks недель · ярче = ближе к дневной цели',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _cell(DateTime day, DateTime now, Color Function(int) cellColor) {
    if (day.isAfter(now)) {
      return const SizedBox(width: 14, height: 14);
    }
    final count = activity[dayKey(day)] ?? 0;
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: cellColor(count),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
