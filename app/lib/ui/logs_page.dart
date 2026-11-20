import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// The log of the core process, the same view the Android Settings → View log
/// opens. The desktop keeps it as its own page in the side menu.
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  bool _follow = true;
  String _filter = '';
  Timer? _timer;
  AppState? _app;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = AppScope.of(context);
    _timer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (_follow && mounted) _app?.refreshLogs();
    });
    if (_app!.logs.isEmpty) {
      // The first read is deferred: refreshLogs notifies the scope, and a
      // notification while this page is still building would mark the tree
      // dirty during the build pass.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _app?.refreshLogs();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final logging = !app.config.loggingDisabled;
    final lines = [
      for (final line in app.logs)
        if (_filter.isEmpty ||
            line.message.toLowerCase().contains(_filter.toLowerCase()))
          line,
    ];

    return PageScaffold(
      title: 'Logs',
      subtitle: 'The last ${app.logs.length} lines of the core process.',
      actions: [
        SizedBox(
          width: 240,
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Filter',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _filter = value),
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: app.refreshLogs,
        ),
        IconButton(
          tooltip: 'Copy all',
          icon: const Icon(Icons.copy_rounded),
          onPressed: () => copyText(
            context,
            [
              for (final line in lines)
                '${line.time} ${line.level} ${line.message}',
            ].join('\n'),
            'Logs copied',
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Write a log'),
                  subtitle: const Text('The log file is capped at 512 KB'),
                  value: logging,
                  onChanged: (value) async {
                    await app.setLogging(value);
                    if (value) app.refreshLogs();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Follow the log'),
                  subtitle: const Text('Poll the core every two seconds'),
                  value: _follow,
                  onChanged: (value) {
                    setState(() => _follow = value);
                    if (value) app.refreshLogs();
                  },
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Expanded(
                  child: !logging
                      ? Center(
                          child: Text(
                            'The log is empty',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : lines.isEmpty
                      ? Center(
                          child: Text(
                            'Nothing yet',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: lines.length,
                          itemBuilder: (context, index) {
                            final line = lines[index];
                            final color = switch (line.level) {
                              'error' => theme.colorScheme.error,
                              'warn' => AppColors.pending,
                              _ => theme.colorScheme.onSurfaceVariant,
                            };
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 84,
                                    child: Text(
                                      _time(line.time),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontFamily: 'monospace',
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 56,
                                    child: Text(
                                      line.level.toUpperCase(),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontFamily: 'monospace',
                                            color: color,
                                          ),
                                    ),
                                  ),
                                  Expanded(
                                    child: SelectableText(
                                      line.message,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(fontFamily: 'monospace'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}
