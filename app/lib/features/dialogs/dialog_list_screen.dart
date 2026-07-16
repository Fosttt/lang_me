import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/db.dart';
import '../../core/dialogs_repo.dart';
import '../../core/models.dart';
import '../tutor/tutor_screen.dart';
import 'scene_dialog_screen.dart';

/// Вкладка «Диалог»: каталог диалогов-сценок по уровням с прогрессом
/// (механика word-flow) + свободный разговор с ИИ-репетитором сверху.
class DialogListScreen extends StatefulWidget {
  const DialogListScreen({super.key});

  @override
  State<DialogListScreen> createState() => _DialogListScreenState();
}

class _DialogListScreenState extends State<DialogListScreen> {
  List<SceneDialog> _dialogs = [];
  Map<String, int> _progress = {};

  static const _levelColors = <String, Color>{
    'A1': Colors.green,
    'A2': Colors.teal,
    'B1': Colors.blue,
    'B2': Colors.indigo,
    'C1': Colors.purple,
    'C2': Colors.deepOrange,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dialogs = await DialogsRepo.load();
    final progress = await AppDb.dialogProgress();
    if (mounted) {
      setState(() {
        _dialogs = dialogs;
        _progress = progress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final byLevel = DialogsRepo.byLevel(_dialogs);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Диалоги', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (state.aiConfigured)
            Card(
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                leading: const Text('🤖', style: TextStyle(fontSize: 26)),
                title: const Text('Свободный разговор с ИИ',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Репетитор спрашивает — ты отвечаешь, ошибки поправляются'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Разговор с ИИ')),
                      body: const TutorScreen(showHeader: false),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (final level in kLevels)
            if ((byLevel[level] ?? []).isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (_levelColors[level] ?? Colors.grey)
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(level,
                          style: TextStyle(
                              color: _levelColors[level],
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${byLevel[level]!.where((d) => _progress.containsKey(d.id)).length}'
                      ' / ${byLevel[level]!.length} пройдено',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              for (final d in byLevel[level]!)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading:
                        Text(d.emoji, style: const TextStyle(fontSize: 26)),
                    title: Text(d.titleRu,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${d.userTurnCount} твоих реплик'),
                    trailing: _progress.containsKey(d.id)
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle,
                                  color: (_progress[d.id] ?? 0) >= 80
                                      ? Colors.green
                                      : Colors.orange),
                              Text('${_progress[d.id]}',
                                  style: theme.textTheme.labelSmall),
                            ],
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => SceneDialogScreen(dialog: d)));
                      _load();
                    },
                  ),
                ),
            ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
