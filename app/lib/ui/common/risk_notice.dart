// Risk notices: what happens before an action that widens what AI may do on
// its own, or hands it private data (docs/design/risk-notices-and-ask-ai.md).
//
//   high    每次确认  every time; the main key in the danger colour, nothing
//                     to silence it
//   medium  首次确认  until confirmed with 「不再提示」 ticked — ticked by
//                     default, so it shows once unless the person unticks it
//
// The third tier, 就地说明, is a line next to the control (a tile's subtitle,
// a page footnote, `PluginTrustNote`) and needs nothing from here. Deletions
// keep their centred confirm dialogs: an object with a name and one verb.
//
// Both tiers look the same: a locked sheet (`SheetDismissal.button`: × and
// back mean no), the question as its title, the consequence in a sentence,
// one main key that names the action.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/risk_notice_store.dart';
import '../theme/theme.dart';
import 'app_sheet.dart';

enum RiskLevel {
  /// 每次确认.
  high,

  /// 首次确认, with 「不再提示」.
  medium,
}

/// One notice: what it asks and what the main key says.
@immutable
class RiskNotice {
  const RiskNotice({
    required this.id,
    required this.level,
    required this.title,
    required this.body,
    required this.action,
  });

  /// Stable: 「不再提示」 is stored under it.
  final String id;
  final RiskLevel level;

  /// The question, read whole (it wraps rather than being cut).
  final String title;

  /// The consequence, in a sentence.
  final String body;

  /// The main key: the action itself (「允许读写」), never 「确定」.
  final String action;
}

/// Every notice in one place, so the ids stay stable and the copy is read
/// together.
abstract final class RiskNotices {
  /// 手机操控 › 确认方式 › 始终免确认.
  static RiskNotice get phoneConfirmAlways => RiskNotice(
    id: 'phone.confirm-always',
    level: RiskLevel.high,
    title: appL10n.phoneConfirmAlwaysTitle,
    body: appL10n.phoneConfirmAlwaysBody,
    action: appL10n.riskConfirmAlwaysAction,
  );

  /// 应用名单: 不碰 → 照常 ([fromDeny]) or 每一步都确认 → 照常.
  static RiskNotice appRule(String app, {required bool fromDeny}) => RiskNotice(
    id: fromDeny ? 'phone.app-rule.allow' : 'phone.app-rule.skip-steps',
    level: RiskLevel.high,
    title: fromDeny ? appL10n.phoneAppRulesLoosenTitle(app) : appL10n.phoneAppRulesSkipStepsTitle(app),
    body: fromDeny ? appL10n.phoneAppRulesLoosenBody : appL10n.phoneAppRulesSkipStepsBody,
    action: appL10n.phoneAppRulesAcceptRisk,
  );

  /// 设置 › 自动执行命令, and the 完全权限 preset.
  static RiskNotice get fullAccess => RiskNotice(
    id: 'permission.full-access',
    level: RiskLevel.high,
    title: appL10n.hubSettingsFullAccessTitle,
    body: appL10n.hubSettingsFullAccessBody,
    action: appL10n.riskFullAccessAction,
  );

  /// The 自动审查 preset: the model still checks each action.
  static RiskNotice get autoReview => RiskNotice(
    id: 'permission.auto-review',
    level: RiskLevel.medium,
    title: appL10n.featuresPermissionAutoTitle,
    body: appL10n.featuresPermissionAutoWarning,
    action: appL10n.riskAutoReviewAction,
  );

  /// 设置 › 访问手机文件.
  static RiskNotice get phoneFiles => RiskNotice(
    id: 'settings.phone-files',
    level: RiskLevel.high,
    title: appL10n.hubSettingsStorageTitle,
    body: appL10n.hubSettingsStorageBody,
    action: appL10n.hubSettingsStorageAllow,
  );

  /// The same, picked on first run: no engine runs yet, nothing restarts.
  static RiskNotice get phoneFilesFirstRun => RiskNotice(
    id: 'settings.phone-files',
    level: RiskLevel.high,
    title: appL10n.hubSettingsStorageTitle,
    body: appL10n.accessFilesRiskBody,
    action: appL10n.hubSettingsStorageAllow,
  );

  /// The approval card's 本对话都允许: this conversation only, until restart.
  static RiskNotice get allowForChat => RiskNotice(
    id: 'chat.allow-for-chat',
    level: RiskLevel.medium,
    title: appL10n.riskAllowForChatTitle,
    body: appL10n.riskAllowForChatBody,
    action: appL10n.riskAllowForChatAction,
  );

  /// 不打扰模式 › Root and 自动恢复无障碍's 申请 root 授权: the root manager's
  /// own prompt comes next.
  static RiskNotice get rootChannel => RiskNotice(
    id: 'phone.root',
    level: RiskLevel.medium,
    title: appL10n.phonePrivilegedRootRiskTitle,
    body: appL10n.phonePrivilegedRootRiskBody,
    action: appL10n.phonePrivilegedRootPrepare,
  );

  /// 宠物设置 › App 外显示: system overlay permission.
  static RiskNotice get petOverlay => RiskNotice(
    id: 'pets.overlay-permission',
    level: RiskLevel.medium,
    title: appL10n.riskPetOverlayTitle,
    body: appL10n.riskPetOverlayBody,
    action: appL10n.riskPetOverlayAction,
  );
}

/// What the sheet was left with (null: × or back).
enum RiskChoice {
  /// The main key.
  proceed,

  /// The main key with 「不再提示」 ticked.
  proceedSilenced,
}

/// Shows [notice] (a medium one only until it was confirmed with 「不再提示」)
/// and resolves true to go ahead.
Future<bool> confirmRisk(BuildContext context, RiskNotice notice) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final store = container.read(riskNoticeStoreProvider);
  if (notice.level == RiskLevel.medium && await store.silenced(notice.id)) return true;
  if (!context.mounted) return false;
  final choice = await showAppSheet<RiskChoice>(
    context,
    dismissal: SheetDismissal.button,
    isScrollControlled: true,
    builder: (_) => RiskNoticeSheet(notice: notice),
  );
  switch (choice) {
    case RiskChoice.proceed:
      return true;
    case RiskChoice.proceedSilenced:
      await store.silence(notice.id);
      return true;
    case null:
      return false;
  }
}

/// The notice's sheet; pops a [RiskChoice].
class RiskNoticeSheet extends StatefulWidget {
  const RiskNoticeSheet({super.key, required this.notice});

  final RiskNotice notice;

  /// The main key's height at 1× text (it grows with larger text).
  static const buttonHeight = 48.0;

  @override
  State<RiskNoticeSheet> createState() => _RiskNoticeSheetState();
}

class _RiskNoticeSheetState extends State<RiskNoticeSheet> {
  var _silence = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final notice = widget.notice;
    final high = notice.level == RiskLevel.high;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(notice.title, maxLines: null),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: kSheetGutter),
                    child: Text(
                      notice.body,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  if (!high)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SilenceToggle(value: _silence, onChanged: (v) => setState(() => _silence = v)),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kSheetGutter, 20, kSheetGutter, 16),
            child: FilledButton(
              key: const ValueKey('risk-confirm'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(RiskNoticeSheet.buttonHeight),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                backgroundColor: high ? colors.danger : null,
                foregroundColor: high ? colors.onDanger : null,
              ),
              onPressed: () =>
                  Navigator.pop(context, !high && _silence ? RiskChoice.proceedSilenced : RiskChoice.proceed),
              child: Text(notice.action, textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「☑ 不再提示」: the box's visible square on the sheet's 20 gutter, the
/// whole line one tap target.
class SilenceToggle extends StatelessWidget {
  const SilenceToggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kSheetGutter, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.riskSilence,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
