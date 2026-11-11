// Shared destructive confirm dialog (was in deleted bots/bot_sheets.dart).

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

Future<bool> confirmDelete(BuildContext context, {required String title, required String body}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(context.l10n.commonCancel)),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(context.l10n.commonDelete),
        ),
      ],
    ),
  );
  return ok ?? false;
}
