import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'widgets.dart';

class ExitPage extends StatelessWidget {
  const ExitPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final state = app.state;
    final active = _activeProfile(app);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Panel(
          title: 'Exit node',
          subtitle:
              'Route the traffic of the local proxy through an X-Node exit '
              'node. Paste the yggnode://exit link printed by X-Node.',
          trailing: FilledButton.tonalIcon(
            onPressed: app.busy
                ? null
                : () async {
                    final link = await promptText(
                      context,
                      title: 'Add exit node',
                      hint: 'yggnode://exit?a=...&p=1080&api=1080&token=...',
                      helper: 'The link is shown on the X-Node dashboard.',
                    );
                    if (link == null || link.trim().isEmpty) return;
                    await app.addExitLink(link);
                  },
            icon: const Icon(Icons.add_link_rounded, size: 18),
            label: const Text('Add link'),
          ),
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use the exit node'),
                subtitle: Text(
                  state.exitEnabled
                      ? 'State: ${state.exitState.isEmpty ? 'starting' : state.exitState}'
                            '${state.exitDns.isEmpty ? '' : ' · DNS ${state.exitDns}'}'
                      : 'Off: the local proxy exits through the Yggdrasil network',
                ),
                value: app.exitEnabled,
                onChanged: app.exits.isEmpty || app.busy
                    ? null
                    : (value) => app.setExitEnabled(value),
              ),
              if (app.exitEnabled && state.exitName.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(
                    label: state.exitName,
                    color: theme.colorScheme.primary,
                    icon: Icons.exit_to_app_rounded,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Exit profiles (${app.exits.length})',
          trailing: active == null
              ? null
              : OutlinedButton.icon(
                  onPressed: () async {
                    final report = await app.checkExit();
                    if (!context.mounted) return;
                    showMessage(context, 'Exit node check', report);
                  },
                  icon: const Icon(Icons.network_check_rounded, size: 18),
                  label: const Text('Check'),
                ),
          child: app.exits.isEmpty
              ? Text(
                  'No exit nodes yet. Press Add link and paste the link from '
                  'X-Node.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Column(
                  children: [
                    for (final profile in app.exits)
                      _ExitRow(
                        profile: profile,
                        active: profile.id == app.activeExitId,
                        busy: app.busy,
                        onSelect: () => app.setActiveExit(profile.id),
                        onRemove: () => app.removeExit(profile.id),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'How it works',
          child: Text(
            'The desktop build has no TUN device. The app starts a local HTTP '
            'and SOCKS5 proxy; every connection is opened inside the '
            'Yggdrasil network. With an exit node enabled, the proxy asks the '
            'X-Node to open the connection to the public internet, and DNS is '
            'resolved by the exit node.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  ExitProfile? _activeProfile(AppState app) {
    for (final profile in app.exits) {
      if (profile.id == app.activeExitId) return profile;
    }
    return app.exits.isEmpty ? null : app.exits.first;
  }
}

class _ExitRow extends StatelessWidget {
  const _ExitRow({
    required this.profile,
    required this.active,
    required this.busy,
    required this.onSelect,
    required this.onRemove,
  });

  final ExitProfile profile;
  final bool active;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy ? null : onSelect,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: active
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : null,
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary.withValues(alpha: 0.6)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                active
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.address}:${profile.socksPort}'
                      '${profile.token.isEmpty ? '' : ' · token'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                onPressed: busy ? null : onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
