import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/ai_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';

/// Settings: level, theme, TTS, daily goal, AI server URL+token,
/// export/import of progress, full reset.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  String? _connStatus;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _url = TextEditingController(text: state.serverUrl);
    _token = TextEditingController(text: state.serverToken);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Обучение', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            title: const Text('Мой уровень'),
            trailing: DropdownButton<String>(
              value: state.level,
              items: [
                for (final l in kLevels)
                  DropdownMenuItem(value: l, child: Text(l)),
              ],
              onChanged: (v) {
                if (v != null) state.saveSettings(level: v);
              },
            ),
          ),
          ListTile(
            title: const Text('Дневная цель (действий)'),
            trailing: DropdownButton<int>(
              value: state.dailyGoal,
              items: const [
                DropdownMenuItem(value: 10, child: Text('10')),
                DropdownMenuItem(value: 20, child: Text('20')),
                DropdownMenuItem(value: 40, child: Text('40')),
                DropdownMenuItem(value: 80, child: Text('80')),
              ],
              onChanged: (v) {
                if (v != null) state.saveSettings(dailyGoal: v);
              },
            ),
          ),
          const Divider(),
          Text('Интерфейс и звук',
              style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            title: const Text('Тёмная тема'),
            value: state.darkTheme,
            onChanged: (v) => state.saveSettings(darkTheme: v),
          ),
          SwitchListTile(
            title: const Text('Автоозвучка слова в ленте'),
            value: state.autoSpeak,
            onChanged: (v) => state.saveSettings(autoSpeak: v),
          ),
          ListTile(
            title: const Text('Скорость речи'),
            subtitle: Slider(
              value: state.ttsRate,
              onChanged: (v) => state.saveSettings(ttsRate: v),
            ),
          ),
          const Divider(),
          Text('AI-сервер (мой VPS)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'URL сервера',
              hintText: 'http://1.2.3.4:8977',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Токен',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    await state.saveSettings(
                        serverUrl: _url.text, serverToken: _token.text);
                    _snack('Сохранено');
                  },
                  child: const Text('Сохранить'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    setState(() => _connStatus = '…');
                    final ok = await AiClient(
                      baseUrl: _url.text.trim(),
                      token: _token.text.trim(),
                    ).health();
                    setState(() =>
                        _connStatus = ok ? 'Соединение ОК ✅' : 'Нет связи ❌');
                  },
                  child: const Text('Проверить'),
                ),
              ),
            ],
          ),
          if (_connStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_connStatus!),
            ),
          const Divider(),
          Text('Данные', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            leading: const Icon(Icons.upload),
            title: const Text('Экспорт прогресса'),
            subtitle: const Text('JSON копируется в буфер обмена'),
            onTap: () async {
              await Clipboard.setData(
                  ClipboardData(text: state.exportJson()));
              _snack('Прогресс скопирован в буфер обмена');
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Импорт прогресса'),
            subtitle: const Text('JSON берётся из буфера обмена'),
            onTap: () async {
              final data = await Clipboard.getData('text/plain');
              final raw = data?.text ?? '';
              if (raw.isEmpty) {
                _snack('Буфер обмена пуст');
                return;
              }
              try {
                final msg = await state.importJson(raw);
                _snack(msg);
              } catch (e) {
                _snack('Не удалось импортировать: $e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Сбросить весь прогресс',
                style: TextStyle(color: Colors.red)),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Сбросить прогресс?'),
                  content: const Text(
                      'Удалится весь прогресс, активность и история чата. Отменить нельзя.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Отмена')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Сбросить')),
                  ],
                ),
              );
              if (ok == true) {
                await state.resetProgress();
                _snack('Прогресс сброшен');
              }
            },
          ),
        ],
      ),
    );
  }
}
