// Native mirror of the official session-log download
// (`dsh-session-log-export`: the session header's "下载 Session 日志" and
// `/export`): the conversation tree as a ZIP, shared or saved to Downloads.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/connection_state.dart';
import '../../state/session_export.dart';
import '../common/app_sheet.dart';
import '../common/brief_notice.dart';
import '../common/list_page_row.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import 'feature_widgets.dart';

enum _Action { share, save }

enum _AfterSave { share, open }

class SessionExportPage extends ConsumerStatefulWidget {
  const SessionExportPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SessionExportPage> createState() => _SessionExportPageState();
}

class _SessionExportPageState extends ConsumerState<SessionExportPage> {
  _Action? _busy;

  Future<void> _run(_Action action) async {
    final l10n = context.l10n;
    if (_busy != null) return;
    setState(() => _busy = action);
    final exporter = ref.read(sessionLogExporterProvider);
    try {
      switch (action) {
        case _Action.share:
          await exporter.share(widget.sessionId);
        case _Action.save:
          final saved = await exporter.saveKeepingArchive(widget.sessionId);
          try {
            if (!mounted) return;
            // Drop the row spinner before the after-save sheet — otherwise
            // ProgressIndicator keeps pumping and blocks settle/tests.
            setState(() => _busy = null);
            await _afterSaved(saved.archive, saved.where);
          } finally {
            await saved.archive.dispose();
          }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(sessionExportErrorText(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// After Downloads: keep the cache file alive for open/share, then dispose.
  Future<void> _afterSaved(SessionLogArchive archive, String where) async {
    final l10n = context.l10n;
    final exporter = ref.read(sessionLogExporterProvider);
    final next = await showAppSheet<_AfterSave>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(l10n.featuresExportSavedTitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(l10n.featuresExportSavedTo(where), style: Theme.of(sheet).textTheme.bodyMedium),
            ),
            SheetGroup(
              children: [
                ListPageRow(
                  icon: AppIcons.share,
                  title: l10n.commonShare,
                  subtitle: l10n.featuresExportShareHint,
                  onTap: () => Navigator.pop(sheet, _AfterSave.share),
                ),
                ListPageRow(
                  icon: AppIcons.openExternal,
                  title: l10n.featuresExportOpenOther,
                  subtitle: l10n.featuresExportOpenHint,
                  onTap: () => Navigator.pop(sheet, _AfterSave.open),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (!mounted || next == null) {
      showBriefNotice(context, l10n.featuresExportSavedTo(where));
      return;
    }
    try {
      switch (next) {
        case _AfterSave.share:
          await exporter.shareArchive(archive);
        case _AfterSave.open:
          await exporter.openArchive(archive);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(sessionExportErrorText(error))));
      }
    }
  }

  Widget? _spinner(_Action action) => _busy == action
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2, strokeCap: StrokeCap.round),
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connected = ref.watch(activeConnectionProvider).value != null;
    final supported = ref.watch(sessionLogExporterProvider).supported;
    final idle = _busy == null;
    return AppPage.list(
      title: l10n.featuresExportTitle,
      subtitle: Text(l10n.featuresExportSubtitle),
      children: [
        if (!connected)
          const FeatureOffline()
        else if (!supported)
          FeatureMessage(
            icon: AppIcons.offline,
            title: l10n.featuresExportUnavailable,
            body: l10n.featuresExportRemoteHint,
          )
        else ...[
          ListPageCard(
            children: [
              ListPageRow(
                icon: AppIcons.share,
                title: l10n.commonShare,
                subtitle: l10n.featuresExportShareHint,
                trailing: _spinner(_Action.share),
                chevron: _busy != _Action.share,
                onTap: idle ? () => _run(_Action.share) : null,
              ),
              ListPageRow(
                icon: AppIcons.download,
                title: l10n.featuresExportSaveDownloads,
                subtitle: l10n.featuresExportDownloadsHint,
                trailing: _spinner(_Action.save),
                chevron: _busy != _Action.save,
                onTap: idle ? () => _run(_Action.save) : null,
              ),
            ],
          ),
          FeatureNote(l10n.featuresExportContents),
        ],
      ],
    );
  }
}
