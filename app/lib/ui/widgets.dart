import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

/// Gives every screen access to the shared state. Screens depend on it, so a
/// `notifyListeners` of [AppState] rebuilds them without a third-party
/// provider.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.notifier!;
  }
}

/// The frame of every page: the title block of the Android app bar, the
/// actions on the right and the scrolling body under it.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 16),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// The scrolling body of a page: one column, centred and capped on a wide
/// monitor so the cards do not stretch across the whole screen.
class PageScroll extends StatelessWidget {
  const PageScroll({
    super.key,
    required this.children,
    this.maxWidth = 1120,
    this.padding = const EdgeInsets.fromLTRB(28, 0, 28, 32),
  });

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth < maxWidth
                  ? constraints.maxWidth
                  : maxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// Two cards side by side on a wide window, stacked on a narrow one. The row
/// stretches both to the same height so the forms line up.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({
    super.key,
    required this.first,
    required this.second,
    this.breakpoint = 880,
    this.gap = 16,
  });

  final Widget first;
  final Widget second;
  final double breakpoint;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              SizedBox(height: gap),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            SizedBox(width: gap),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

/// A titled group of settings or information, the same card the Android client
/// draws for every section.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 8, 4, 8),
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        Card(
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

/// A coloured dot with a label, used for every state the app can be in.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(icon, size: 14, color: color),
            )
          else
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// One number with a caption, shown in a row of three on the tunnel screen.
class StatBlock extends StatelessWidget {
  const StatBlock({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurfaceVariant;
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: body,
    );
  }
}

/// A label on the left and a value on the right.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
    this.monospace = false,
    this.valueColor,
    this.copyHint,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool monospace;
  final Color? valueColor;
  final String? copyHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: SelectableText(
                      value,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: monospace ? 'monospace' : null,
                        color: valueColor,
                      ),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.copy_rounded,
                      size: 14,
                      color: theme.colorScheme.secondary,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A label with a long value that never wraps: the value scrolls sideways and a
/// tap copies it.
class ScrollableInfoRow extends StatelessWidget {
  const ScrollableInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
    this.copyHint,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? copyHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onTap != null) ...[
                  Text(
                    copyHint ?? '',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: theme.colorScheme.secondary,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder shown when a list has nothing in it yet.
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        children: [
          Icon(icon, size: 44, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// A small round button used for the connect action.
class PowerButton extends StatelessWidget {
  const PowerButton({
    super.key,
    required this.connected,
    required this.busy,
    required this.onPressed,
    required this.tooltip,
    this.enabled = true,
  });

  final bool connected;
  final bool busy;
  final VoidCallback onPressed;
  final String tooltip;

  /// A locked button keeps its place in the layout but does not react: the
  /// first launch uses it while the peer discovery has nothing to connect to
  /// yet.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = connected ? AppColors.copper : scheme.primary;
    // The gradient ends almost at the colour of the dark background, so the
    // circle needs a crisp rim of its own. The material clip draws the round
    // edge once instead of stacking a shadow over it, which was the ragged
    // outline the plain container showed.
    final button = Container(
      width: 106,
      height: 106,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: connected
                  ? [AppColors.copperLight, AppColors.copperDeep]
                  : [AppColors.tealSoft, AppColors.tealDeep],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: InkWell(
            onTap: busy || !enabled ? null : onPressed,
            customBorder: const CircleBorder(),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      connected ? Icons.lock_open_rounded : Icons.lock_rounded,
                      size: 42,
                      color: Colors.white,
                    ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled && !busy,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        // A locked button is drawn with one opacity layer, not every frame: an
        // extra composite of an already dark gradient is what made the rim of
        // the enabled button look uneven.
        child: enabled ? button : Opacity(opacity: 0.55, child: button),
      ),
    );
  }
}

/// A peer row shared by the tunnel and the peers page.
class PeerTile extends StatelessWidget {
  const PeerTile({
    super.key,
    required this.uri,
    required this.status,
    this.title,
    this.place,
    this.flag = '',
    this.pinned = false,
    this.highlight = false,
    this.onTap,
    this.trailing,
  });

  final String uri;
  final PeerStatus? status;
  final String? title;

  /// The city and the country of the node, when the public list knows it.
  final String? place;
  final String flag;
  final bool pinned;
  final bool highlight;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = status?.up ?? false;
    final latency = status?.latencyMs ?? 0;
    final dead = status != null && !up && status!.lastError.isNotEmpty;
    final color = up
        ? AppColors.online
        : dead
        ? AppColors.offline
        : AppColors.pending;
    final state = up
        ? 'connected'
        : dead
        ? 'offline'
        : latency > 0
        ? 'online'
        : 'waiting';

    return ListTile(
      onTap: onTap,
      tileColor: highlight
          ? theme.colorScheme.primary.withValues(alpha: 0.07)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          if (flag.isNotEmpty)
            FlagBadge(flag: flag)
          else
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Icon(
                up ? Icons.hub_rounded : Icons.hub_outlined,
                size: 17,
                color: color,
              ),
            ),
          if (pinned)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: 9,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              title ?? place ?? uriHost(uri),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (pinned) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'EXIT NODE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        shortUri(uri),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFamily: 'monospace',
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatLatency(latency),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                state,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A slider that only writes when the drag ends, like the Android settings.
class SliderTile extends StatefulWidget {
  const SliderTile({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final void Function(double value) onChanged;

  @override
  State<SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<SliderTile> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = (_dragging ?? widget.value).clamp(widget.min, widget.max);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.label, style: theme.textTheme.bodyMedium),
              ),
              Text(
                _dragging == null ? widget.display : value.round().toString(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: (next) => setState(() => _dragging = next),
            onChangeEnd: (next) {
              setState(() => _dragging = null);
              widget.onChanged(next);
            },
          ),
          if (widget.hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                widget.hint!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> copyText(BuildContext context, String text, String message) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showSnack(context, message);
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
  String? helper,
  String confirm = 'Add',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(hintText: hint, helperText: helper),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: Text(confirm),
        ),
      ],
    ),
  );
}

void showMessage(BuildContext context, String title, String body) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(child: SelectableText(body)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

void showSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
}

/// Shows the messages of [AppState] as snack bars at the bottom of the window,
/// the way the "Name saved" line of the Exit node screen appears. The window
/// used to show a banner above the page: it pushed the content down on every
/// message and moved it back three seconds later.
class NoticeHost extends StatefulWidget {
  const NoticeHost({super.key, required this.child});

  final Widget child;

  @override
  State<NoticeHost> createState() => NoticeHostState();
}

class NoticeHostState extends State<NoticeHost> {
  String? _notice;
  String? _error;
  bool _searching = false;
  bool _bound = false;

  /// The line the window shows while the first launch looks for peers.
  static const searchingMessage =
      'No peers yet: looking for the best nodes. The Connect button unlocks '
      'as soon as a live node answers.';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    final notice = app.notice;
    final error = app.error;
    final searching = app.searchingPeers;
    // The first build must not replay a message that is already up: only a
    // change shows a snack bar.
    final first = !_bound;
    _bound = true;
    if (first) {
      _notice = notice;
      _error = error;
      _searching = searching;
      return;
    }
    String? message;
    var isError = false;
    if (notice != null && notice != _notice) {
      message = notice;
    } else if (app.ready && error != null && error != _error) {
      message = error;
      isError = true;
    } else if (searching && !_searching) {
      message = searchingMessage;
    }
    _notice = notice;
    _error = error;
    _searching = searching;
    if (message == null) return;
    _show(message, isError: isError);
  }

  void _show(String message, {required bool isError}) {
    // The state notifies during a frame; the messenger needs the next one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: Duration(seconds: isError ? 6 : 3),
          ),
        );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String uriHostLabel(String uri) => uriHost(uri);

/// The catalogue row of a peer URI. The list keys by host as well, so a link
/// the node normalised still finds its country and city.
CatalogPeer? catalogPeerOf(AppState app, String uri) {
  if (uri.isEmpty) return null;
  final host = uriHost(uri);
  for (final peer in app.candidates) {
    if (peer.uri == uri || peer.host == host) return peer;
  }
  return null;
}

/// "City, Country" for the row of a peer.
String catalogPlace(CatalogPeer? peer) {
  if (peer == null) return '';
  return [
    if (peer.city.isNotEmpty) peer.city,
    if (peer.countryName.isNotEmpty) peer.countryName,
  ].join(', ');
}

String formatLatency(double ms) {
  if (ms <= 0) return '—';
  if (ms < 10) return '${ms.toStringAsFixed(1)} ms';
  return '${ms.toStringAsFixed(0)} ms';
}

/// The two-letter country code of a flag emoji, empty when the string is not
/// one. Windows has no flag glyphs: Segoe UI Emoji draws the two regional
/// indicators as boxed letters, so the app ships the flag images and maps the
/// emoji the core sends to the file name of the country.
String countryCodeOf(String flag) {
  final letters = <int>[];
  for (final rune in flag.runes) {
    if (rune < 0x1F1E6 || rune > 0x1F1FF) continue;
    letters.add(rune - 0x1F1E6 + 0x41);
  }
  if (letters.length != 2) return '';
  return String.fromCharCodes(letters).toLowerCase();
}

/// A country flag drawn as a small rounded rectangle. The Android client puts
/// the flag emoji at half the badge size, so the glyph occupies about 56 % of
/// the circle; drawing the shipped image edge to edge made every flag look
/// twice as large as the phone version.
class FlagPicture extends StatelessWidget {
  const FlagPicture({super.key, required this.flag, required this.size});

  final String flag;
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = countryCodeOf(flag);
    if (code.isEmpty) {
      return Text(
        flag.isEmpty ? '•' : flag,
        style: TextStyle(fontSize: size * 0.5),
      );
    }
    final width = size * 0.56;
    final height = size * 0.38;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height * 0.22),
      child: Image.asset(
        'assets/flags/$code.png',
        width: width,
        height: height,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) =>
            Text(flag, style: TextStyle(fontSize: size * 0.5)),
      ),
    );
  }
}

/// A country flag inside a soft circle.
class FlagBadge extends StatelessWidget {
  const FlagBadge({super.key, required this.flag, this.size = 34});

  final String flag;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: FlagPicture(flag: flag, size: size),
    );
  }
}

/// The time since the last discovery, the way the Peers page shows it.
String formatAgo(DateTime? moment) {
  if (moment == null) return 'Not checked yet';
  final delta = DateTime.now().difference(moment);
  if (delta.inSeconds < 60) return 'Checked just now';
  if (delta.inMinutes < 60) return 'Checked ${delta.inMinutes} min ago';
  if (delta.inHours < 24) return 'Checked ${delta.inHours} h ago';
  return 'Checked ${delta.inDays} d ago';
}

/// A tabular number style for the counters.
TextStyle tabular(BuildContext context) =>
    (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
