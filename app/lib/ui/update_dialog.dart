import 'dart:io';

import 'package:flutter/material.dart';

import '../update_service.dart';
import 'widgets.dart';

/// Shows the "new version available" dialog. When the user accepts, the release
/// page is opened in the browser, where the new package can be downloaded.
Future<void> showUpdatePrompt(BuildContext context, UpdateInfo info) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Update available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Y-Node ${info.version} has been released.'),
          if (info.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              info.notes,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Later'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Open the release page'),
        ),
      ],
    ),
  );
  if (accepted != true || !context.mounted) return;
  await openReleasePage(context, info);
}

/// Opens the release page in the default browser.
Future<void> openReleasePage(BuildContext context, UpdateInfo info) async {
  final opened = await openExternalUrl(info.releaseUrl);
  if (!opened && context.mounted) {
    showSnack(context, 'The browser did not open the release page');
  }
}

/// Opens a URL without a platform plugin.
Future<bool> openExternalUrl(String url) async {
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
