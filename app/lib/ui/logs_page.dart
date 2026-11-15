import 'dart:async';

import 'package:flutter/material.dart';

import 'widgets.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  bool _follow = true;
  String _filter = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).refreshLogs();
    });
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_follow && mounted) AppScope.of(context).refreshLogs();
    });
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
    final lines = [
      for (final line in app.logs)
        if (_filter.isEmpty ||
            line.message.toLowerCase().contains(_filter.toLowerCase()))
          line,
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Panel(
        title: 'Logs',
        subtitle: 'The last ${app.logs.length} lines of the core process.',
        trailing: Wrap(
          spacing: 8,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Filter',
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                  border: OutlineInputBorder(),
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
        ),
        child: Column(
          children: [
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
            SizedBox(
              height: 420,
              child: lines.isEmpty
                  ? Center(
                      child: Text(
                        'Nothing yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      reverse: false,
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        final color = switch (line.level) {
                          'error' => theme.colorScheme.error,
                          'warn' => const Color(0xFFE0A030),
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
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  line.level.toUpperCase(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: color,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: SelectableText(
                                  line.message,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                  ),
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
    );
  }

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}
