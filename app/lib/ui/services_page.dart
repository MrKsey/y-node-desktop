import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// The Services page: the same address book the Android client shows — search,
/// reorderable cards, multi-select delete and the web directory import.
class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final _search = TextEditingController();
  final Set<String> _selected = {};
  String _query = '';
  bool _selecting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ServiceEntry> _visible(AppState app) {
    if (_query.isEmpty) return app.resources;
    final needle = _query.toLowerCase();
    return [
      for (final item in app.resources)
        if (item.title.toLowerCase().contains(needle) ||
            item.url.toLowerCase().contains(needle) ||
            item.description.toLowerCase().contains(needle))
          item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final items = _visible(app);
    final allSelected =
        items.isNotEmpty && items.every((item) => _selected.contains(item.id));

    return PageScaffold(
      title: _selecting ? '${_selected.length} selected' : 'Services',
      actions: _selecting
          ? [
              IconButton(
                tooltip: 'Select all',
                onPressed: items.isEmpty
                    ? null
                    : () => setState(() {
                        if (allSelected) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(items.map((item) => item.id));
                        }
                      }),
                icon: const Icon(Icons.select_all_rounded),
              ),
              IconButton(
                tooltip: 'Delete selected',
                onPressed: _selected.isEmpty
                    ? null
                    : () => _deleteSelected(app),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              IconButton(
                tooltip: 'Done',
                onPressed: () => setState(() {
                  _selecting = false;
                  _selected.clear();
                }),
                icon: const Icon(Icons.close_rounded),
              ),
            ]
          : [
              IconButton(
                tooltip: 'Select',
                onPressed: items.isEmpty
                    ? null
                    : () => setState(() {
                        _selecting = true;
                        _selected.clear();
                      }),
                icon: const Icon(Icons.checklist_rounded),
              ),
              // The catalogue entries the user deleted stay deleted across
              // restarts; this action is the way back.
              if (app.config.hiddenServices.isNotEmpty)
                IconButton(
                  tooltip:
                      'Restore built-in resources '
                      '(${app.config.hiddenServices.length})',
                  onPressed: app.busy ? null : app.restoreBuiltIns,
                  icon: const Icon(Icons.restore_rounded),
                ),
              IconButton(
                tooltip: app.loadingDirectory
                    ? 'Reading the directory through the tunnel…'
                    : 'Browse the web directory',
                onPressed: app.loadingDirectory
                    ? null
                    : () => _browseDirectory(app),
                icon: app.loadingDirectory
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined),
              ),
              const SizedBox(width: 4),
              FilledButton.tonalIcon(
                onPressed: () => _edit(app, null),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add a resource'),
              ),
            ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search by title or address',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
              ),
            ),
          ),
          if (app.loadingDirectory)
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 0, 28, 8),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          if (items.isNotEmpty && !_selecting && _query.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.drag_indicator_rounded,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Drag a card to move it',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: EmptyHint(
                      icon: Icons.book_outlined,
                      title: 'The list is empty',
                      body:
                          'Resources published in the Yggdrasil web directory',
                      action: FilledButton.tonalIcon(
                        onPressed: app.loadingDirectory
                            ? null
                            : () => _browseDirectory(app),
                        icon: app.loadingDirectory
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.cloud_download_outlined,
                                size: 18,
                              ),
                        label: const Text('Browse the web directory'),
                      ),
                    ),
                  )
                : _query.isEmpty && !_selecting
                ? ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                    buildDefaultDragHandles: false,
                    itemCount: items.length,
                    onReorderItem: (oldIndex, newIndex) {
                      final list = [...items];
                      final item = list.removeAt(oldIndex);
                      list.insert(newIndex, item);
                      app.reorderResources([
                        for (final entry in list) entry.id,
                      ]);
                    },
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Padding(
                        key: ValueKey(item.id),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ResourceCard(
                          resource: item,
                          dragIndex: index,
                          onOpen: () => _open(item),
                          onCopy: () async {
                            await Clipboard.setData(
                              ClipboardData(text: item.url),
                            );
                            if (context.mounted) {
                              showSnack(context, 'Copied');
                            }
                          },
                          onEdit: () => _edit(app, item),
                          onDelete: () => _delete(app, item),
                        ),
                      );
                    },
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _ResourceCard(
                        resource: item,
                        selecting: _selecting,
                        selected: _selected.contains(item.id),
                        onSelect: () => setState(() {
                          if (!_selected.add(item.id)) {
                            _selected.remove(item.id);
                          }
                        }),
                        onOpen: () => _open(item),
                        onCopy: () async {
                          await Clipboard.setData(
                            ClipboardData(text: item.url),
                          );
                          if (context.mounted) showSnack(context, 'Copied');
                        },
                        onEdit: () => _edit(app, item),
                        onDelete: () => _delete(app, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected(AppState app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete selected'),
        content: const Text('Delete the selected resources from Services?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final count = await app.deleteResources(_selected);
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    showSnack(context, 'Resources deleted: $count');
  }

  Future<void> _open(ServiceEntry entry) async {
    final opened = await _openExternal(entry.url);
    if (!opened && mounted) {
      showSnack(context, 'The browser did not open the address');
    }
  }

  /// Opens a URL in the default browser without a platform plugin.
  static Future<bool> _openExternal(String url) async {
    try {
      final result = Platform.isWindows
          ? await Process.run('rundll32', ['url.dll,FileProtocolHandler', url])
          : Platform.isMacOS
          ? await Process.run('open', [url])
          : await Process.run('xdg-open', [url]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _delete(AppState app, ServiceEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this resource?'),
        content: Text(entry.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await app.removeService(entry.id);
      if (mounted) showSnack(context, 'Resource deleted');
    }
  }

  Future<void> _edit(AppState app, ServiceEntry? existing) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final url = TextEditingController(text: existing?.url ?? '');
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add a resource' : 'Edit resource'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Address',
                    hintText: 'http://[200::1]/',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final address = url.text.trim();
                if (!_validUrl(address)) {
                  setLocal(
                    () => error =
                        'The address must start with http:// or https://',
                  );
                  return;
                }
                final name = title.text.trim();
                await app.addService(
                  ServiceEntry(
                    id: existing?.id ?? '',
                    title: name.isEmpty ? address : name,
                    url: address,
                    description: description.text.trim(),
                  ),
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    url.dispose();
    description.dispose();
  }

  static bool _validUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (!uri.hasScheme) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    return uri.host.isNotEmpty;
  }

  /// The cloud button reads the Yggdrasil web directory through the node. The
  /// read runs before the dialog opens: the button turns into a spinner while
  /// it lasts, and a failure is reported with a snackbar on this page instead
  /// of the tunnel card. The sheet only picks the entries; the import happens
  /// after it closes.
  Future<void> _browseDirectory(AppState app) async {
    if (app.loadingDirectory) return;
    if (!app.state.running) {
      final connect = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Yggdrasil is off'),
          content: const Text(
            'Connect the client first: the web directory lives inside the '
            'Yggdrasil network and is not reachable without the tunnel.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Connect now'),
            ),
          ],
        ),
      );
      if (connect == true) await app.connect();
      return;
    }
    if (app.directoryResources.isEmpty) {
      await app.loadDirectory();
      if (!mounted) return;
      final failure = app.directoryError;
      if (failure != null) {
        showSnack(
          context,
          failure == 'directoryEmpty'
              ? 'The directory has no resources that are not in Services yet'
              : 'Could not read the directory. Check the tunnel and try again.',
        );
        return;
      }
    }
    final chosen = await showDialog<List<ServiceEntry>>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 700),
          child: AppScope(state: app, child: const _DirectoryDialog()),
        ),
      ),
    );
    if (chosen == null || chosen.isEmpty) return;
    final added = await app.importResources(chosen);
    if (!mounted) return;
    showSnack(
      context,
      added > 0 ? 'Resources added: $added' : 'No new resources found',
    );
  }
}

/// One address-book card, the same shape the Android Services screen draws.
class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.resource,
    required this.onOpen,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
    this.dragIndex,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
  });

  final ServiceEntry resource;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final int? dragIndex;
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ygg = resource.url.contains('[');
    final description = resource.description.trim();
    final showDescription =
        description.isNotEmpty &&
        description != resource.title &&
        description != uriHost(resource.url);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: selecting ? onSelect : onOpen,
        child: Padding(
          padding: EdgeInsets.fromLTRB(selecting ? 4 : 8, 12, 8, 12),
          child: Row(
            children: [
              if (selecting)
                Checkbox(value: selected, onChanged: (_) => onSelect?.call())
              else if (dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex!,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (ygg ? AppColors.teal : AppColors.copper).withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  ygg ? Icons.lan_rounded : Icons.public_rounded,
                  size: 20,
                  color: ygg ? AppColors.teal : AppColors.copperDeep,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            resource.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (resource.builtIn)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'built in',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (showDescription) ...[
                      const SizedBox(height: 2),
                      Text(
                        resource.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      resource.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!selecting)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (value) {
                    switch (value) {
                      case 'open':
                        onOpen();
                      case 'copy':
                        onCopy();
                      case 'edit':
                        onEdit();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'open',
                      child: Text('Open in browser'),
                    ),
                    PopupMenuItem(value: 'copy', child: Text('Copy')),
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The preview of the web directory: the user picks what to add.
class _DirectoryDialog extends StatefulWidget {
  const _DirectoryDialog();

  @override
  State<_DirectoryDialog> createState() => _DirectoryDialogState();
}

class _DirectoryDialogState extends State<_DirectoryDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final items = app.directoryResources;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Browse the web directory',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      app.loadingDirectory
                          ? 'Reading the directory through the tunnel…'
                          : 'Resources found: ${items.length}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: items.isEmpty
                    ? null
                    : () => setState(() {
                        if (_selected.length == items.length) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(items.map((item) => item.id));
                        }
                      }),
                child: const Text('Select all'),
              ),
            ],
          ),
          const Divider(height: 16),
          Expanded(
            child: app.loadingDirectory
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? EmptyHint(
                    icon: Icons.cloud_off_rounded,
                    title: app.directoryError == 'directoryEmpty'
                        ? 'The directory has no resources that are not in '
                              'Services yet'
                        : 'Could not read the directory. Check the tunnel and '
                              'try again.',
                    body: 'Resources published in the Yggdrasil web directory',
                    action: FilledButton.tonalIcon(
                      onPressed: app.loadDirectory,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final checked = _selected.contains(item.id);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _selected.add(item.id);
                          } else {
                            _selected.remove(item.id);
                          }
                        }),
                        title: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          item.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        secondary: const Icon(Icons.language_rounded),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () {
                          final chosen = [
                            for (final item in items)
                              if (_selected.contains(item.id)) item,
                          ];
                          Navigator.of(context).pop(chosen);
                        },
                  child: const Text('Add selected'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
