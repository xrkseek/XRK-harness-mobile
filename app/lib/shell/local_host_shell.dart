import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../l10n/l10n.dart';
import '../links/launcher_entries.dart';
import '../links/share_intake.dart';
import '../runtime/local_footprint.dart';
import '../runtime/runtime_bridge.dart';
import '../runtime/runtime_state.dart';
import '../state/app_info.dart';
import '../state/attachments.dart';
import '../state/chat_reveal.dart';
import '../state/compose_inbox.dart';
import '../state/engine_control.dart';
import '../state/host_settings_opener.dart';
import '../state/hosts_state.dart';
import '../state/phone_state.dart';
import '../state/sessions_state.dart';
import '../state/settings_state.dart';
import '../ui/notify/chat_alert_host.dart';
import '../ui/phone/phone_control_screen.dart';
import '../ui/phone/phone_stop_watcher.dart';
import '../ui/settings/settings_screen.dart';
import '../ui/shell/brand_mark.dart';
import '../ui/web/local_web_screen.dart';
import '../pets/overlay_channel.dart';
import '../ui/web/web_file_chooser.dart';
import '../ui/web/web_keyboard.dart';
import '../ui/web/web_target.dart';
import 'shell_host_download.dart';
import 'shell_toast.dart';

/// Flutter→JS compose bridge base64 ceiling (WebView string OOM below Face's
/// ~20 MiB). Share / open-with that land via this bridge use this limit.
const _composeBase64BudgetBytes = 3 * 1024 * 1024;

/// Face / Web paperclip byte-attachment ceiling (same order as Desktop).
/// Larger picks: Desktop → `@path`; mobile local Host → copy into guest inbox.
const _webAttachBudgetBytes = 20 * 1024 * 1024;

/// Thin product shell: full-bleed WebView of xrkh UI after first-run setup.
/// No Flutter chat chrome, drawer, or Remote entry.
class LocalHostShell extends ConsumerStatefulWidget {
  const LocalHostShell({super.key});

  @override
  ConsumerState<LocalHostShell> createState() => _LocalHostShellState();
}

class _LocalHostShellState extends ConsumerState<LocalHostShell> {
  var _bootStarted = false;
  var _a11yGuideShown = false;

  /// Notification / stop left the Host idle — do not auto-start again.
  var _userStopped = false;
  String? _bootError;
  WebViewController? _controller;
  String? _loadedUrl;
  var _pageReady = false;
  String? _openBridgeJs;
  StreamSubscription<IncomingShare>? _shares;
  StreamSubscription<LauncherEntry>? _launcherEntries;
  ComposeRequest? _pendingCompose;
  final _files = WebFileChooser();
  EdgeInsets _padding = EdgeInsets.zero;
  /// Layout keyboard height from [WebKeyboard] (snap once per open/close).
  double _keyboard = 0;
  double _keyboardRaw = 0;
  final _webKeyboard = WebKeyboard();
  Timer? _keyboardRest;
  String? _appliedInsetKey;
  /// Coalesce WebView JS inset stamps: IME slides fire many MediaQuery ticks;
  /// awaiting every `runJavaScript` on the bridge is what made dismiss stutter.
  Future<void>? _insetFlight;
  var _insetQueued = false;
  var _ackBusy = false;

  @override
  void initState() {
    super.initState();
    // Product surface is LocalHostShell only — kill leftover XRK floating-pet
    // prefs so an old 「App 外显示」 cannot resurrect the desktop pet.
    unawaited(ref.read(petOverlayProvider.notifier).turnOff());
    unawaited(WebKeyboard.restore());
    unawaited(rootBundle.loadString('assets/web/xrk_web_open.js').then((js) {
      _openBridgeJs = js;
    }));
    _shares = ref.read(shareIntakeProvider).shares.listen((share) => unawaited(_onShare(share)));
    // Task-done reopen / notification "open chat" arrive as launcher entries.
    // HomeShell used to host SystemEntryHost; LocalHostShell must own this.
    _launcherEntries = ref.read(launcherBridgeProvider).entries.listen((entry) {
      unawaited(_onLauncherEntry(entry));
    });
    // Phone → native PhoneControlScreen. Other sections → native Settings hub.
    // Host Web settings stay reachable from the ball menu.
    ref.read(hostSettingsOpenerProvider.notifier).bind(({String sectionId = 'general'}) {
      if (sectionId == 'phone') return _openNativePhoneSettings();
      return _openNativeAppSettings();
    });
  }

  @override
  void deactivate() {
    ref.read(hostSettingsOpenerProvider.notifier).bind(null);
    super.deactivate();
  }

  @override
  void dispose() {
    _keyboardRest?.cancel();
    unawaited(_shares?.cancel());
    unawaited(_launcherEntries?.cancel());
    _files.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSafePadding();
    _followKeyboard();
  }

  void _syncSafePadding() {
    final mq = MediaQuery.of(context);
    // Prefer the larger of padding vs viewPadding so edge-to-edge / MuMu
    // zero-padding cases still stamp a real status-bar inset into --ds-safe-*.
    _padding = EdgeInsets.only(
      left: mq.padding.left > mq.viewPadding.left ? mq.padding.left : mq.viewPadding.left,
      top: mq.padding.top > mq.viewPadding.top ? mq.padding.top : mq.viewPadding.top,
      right: mq.padding.right > mq.viewPadding.right ? mq.padding.right : mq.viewPadding.right,
      bottom: mq.padding.bottom > mq.viewPadding.bottom ? mq.padding.bottom : mq.viewPadding.bottom,
    );
  }

  /// Keyboard → page: same algorithm as [WebViewPage] / XRK WebPageInsets.
  ///
  /// Do **not** drive `--xrk-keyboard-inset` from live [viewInsets]. That path
  /// pads the transcript by the IME band while sticky also lifts — scroll-to-
  /// bottom then shows a large empty gap above the keys, and mid-slide stamps
  /// stutter. Instead pin `#root { bottom: keyboard }` once per open/close
  /// ([WebKeyboard] snap) and leave the CSS inset at 0 so ConversationRoot
  /// does not invent blank padding.
  void _followKeyboard() {
    final raw = MediaQuery.viewInsetsOf(context).bottom;
    if (raw == _keyboardRaw) return;
    _keyboardRaw = raw;
    final width = MediaQuery.sizeOf(context).width;
    final chromeChanged = _webKeyboard.report(raw, width);
    final next = _webKeyboard.height;
    final ballBefore = _keyboard >= 48;
    _keyboard = next;
    final ballAfter = _keyboard >= 48;
    _keyboardRest?.cancel();
    _keyboardRest = Timer(WebKeyboard.rest, () {
      if (!mounted) return;
      if (_webKeyboard.settle(_keyboardRaw, width)) {
        final settled = _webKeyboard.height;
        final showBallChanged = (_keyboard >= 48) != (settled >= 48);
        _keyboard = settled;
        // Only rebuild Flutter chrome when the ball must show/hide.
        if (showBallChanged) setState(() {});
        if (_pageReady) unawaited(_applyInsets());
      }
    });
    if (chromeChanged) {
      // Height snap (open/close) — stamp JS. Rebuild only if ball visibility flips.
      if (ballBefore != ballAfter) setState(() {});
      if (_pageReady) unawaited(_applyInsets());
    }
  }

  /// Phone-task reopen / notification → switch the guest conversation.
  Future<void> _openWebSession(String sessionId) async {
    final controller = _controller;
    if (controller == null || !_pageReady || sessionId.isEmpty) return;
    try {
      await controller.runJavaScript(DshWebTarget(sessionId: sessionId).openScript);
    } catch (_) {}
  }

  Future<void> _onLauncherEntry(LauncherEntry entry) async {
    switch (entry) {
      case OpenChatEntry(:final host, :final sessionId):
        if (!mounted) return;
        final hosts = ref.read(hostsProvider);
        if (host.kind == HostKind.ssh && hosts.loaded && hosts.sshById(host.id) == null) {
          return;
        }
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
        ref.read(activeHostProvider.notifier).select(host);
        ref.read(currentSessionProvider.notifier).select(sessionId);
        await _openWebSession(sessionId);
      case NewChatEntry(:final text, :final voice):
        await _composeIntoWeb(ComposeRequest(text: text.trim(), voice: voice));
      case ScreenshotEntry():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(localRuntimeProvider);
    final status = runtime.status;
    final mq = MediaQuery.of(context);
    _syncSafePadding();

    ref.listen(localRuntimeProvider.select((s) => s.status.phase), (prev, next) {
      // User stop / intentional teardown: running|stopping → installed.
      // Do NOT treat crash→error the same way — and never auto-start from error
      // (that + native SafePolicy auto-restart = 启动失败循环).
      if (next == RuntimePhase.installed &&
          (prev == RuntimePhase.running || prev == RuntimePhase.stopping)) {
        _userStopped = true;
        return;
      }
      if (next == RuntimePhase.error) {
        final err = ref.read(localRuntimeProvider).status.error;
        if (mounted && err != null && err.isNotEmpty) {
          setState(() => _bootError = err);
        }
        return;
      }
      if (next == RuntimePhase.installed && !_userStopped) {
        unawaited(_ensureBoot());
      }
    });

    // 手机操控已开、无障碍未就绪：toast 引导去开系统无障碍（文案与 PhoneControl 一致）。
    // 机型可能卡在「受限制的设置」时，进 PhoneControl 看分步图示，不硬跳系统页。
    ref.listen(phoneProvider.select((s) => (s.status.enabled, s.status.a11y.ok)), (prev, next) {
      final (enabled, ok) = next;
      if (!enabled || ok) {
        _a11yGuideShown = false;
        return;
      }
      if (_a11yGuideShown || !mounted) return;
      _a11yGuideShown = true;
      final l10n = context.l10n;
      final mayRestricted = ref.read(phoneProvider).status.device.mayNeedRestrictedSettings;
      showShellToast(
        context,
        l10n.phoneControlNeedsAccessibility,
        actionLabel: l10n.phoneControlGoEnable,
        onAction: () => unawaited(
          mayRestricted ? _openNativePhoneSettings() : _openAccessibilityFromShell(),
        ),
      );
    });

    // 「完成后返回」→ chatReveal; notification / alert tap → currentSession.
    ref.listen(chatRevealProvider, (_, reveal) {
      final id = reveal?.sessionId;
      if (id != null) unawaited(_openWebSession(id));
    });
    ref.listen(currentSessionProvider, (prev, next) {
      if (next != null && next != prev) unawaited(_openWebSession(next));
    });

    if (!_bootStarted) {
      _bootStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_ensureBoot()));
    }

    if (!status.isRunning) {
      _files.invalidate();
      _controller = null;
      _loadedUrl = null;
      _pageReady = false;
      _appliedInsetKey = null;
    }

    final Widget body;
    if (status.isRunning && status.baseUrl != null) {
      final url = localWebUri(status.baseUrl!, status.token ?? '').toString();
      _ensureWebView(url);
      final interruption = ref.watch(phoneProvider.select((s) => s.status.taskInterruption));
      // Full-bleed WebView. Soft keyboard: pin #root bottom to WebKeyboard
      // snap (DSH); CSS inset stays 0. Ball hides while typing.
      body = Scaffold(
        backgroundColor: const Color(0xFF0B0B0C),
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: const Color(0xFF0B0B0C),
              child: WebViewWidget(controller: _controller!),
            ),
            if (interruption.visible)
              Positioned(
                top: mq.padding.top + 8,
                left: 12,
                right: 12,
                child: _InterruptBanner(
                  interruption: interruption,
                  busy: _ackBusy,
                  onAck: () => unawaited(_ackInterruption(interruption.batchToken)),
                  onOpenSettings: () => unawaited(_openNativePhoneSettings()),
                ),
              ),
            if (_pageReady && _keyboard < 48)
              _ShellBall(
                safeBottom: mq.padding.bottom,
                safeTop: mq.padding.top,
                onTap: () => unawaited(_openShellMenu()),
              ),
          ],
        ),
      );
    } else {
      body = _BootScaffold(
        status: status,
        progress: runtime.progress,
        loaded: runtime.loaded,
        stopped: _userStopped && status.phase == RuntimePhase.installed,
        error: _bootError ?? status.error,
        onRetry: () {
          setState(() {
            _bootError = null;
            _userStopped = false;
            _bootStarted = false;
          });
          unawaited(_ensureBoot(force: true));
        },
      );
    }

    // Keep phone turn-end / stop / confirm watchers + chat alerts alive under
    // the product shell (they used to live only under retired HomeShell).
    return PhoneStopWatcher(
      child: ChatAlertHost(child: body),
    );
  }

  Future<void> _ackInterruption(String? batchToken) async {
    if (_ackBusy) return;
    setState(() => _ackBusy = true);
    try {
      final phone = ref.read(phoneProvider.notifier);
      final ok = batchToken == null
          ? await phone.retryTaskInterruptionStorage()
          : await phone.acknowledgeTaskInterruption(batchToken);
      if (!mounted) return;
      if (ok) {
        _toast('已确认中断，手机工具可继续');
      } else {
        _toast(
          '确认失败，请到手机操控页重试',
          actionLabel: '打开手机操控',
          onAction: () => unawaited(_openNativePhoneSettings()),
        );
      }
    } finally {
      if (mounted) setState(() => _ackBusy = false);
    }
  }

  Future<void> _ensureBoot({bool force = false}) async {
    if (force) {
      _userStopped = false;
      _bootError = null;
    }
    final runtime = ref.read(localRuntimeProvider.notifier);
    final status = ref.read(localRuntimeProvider).status;
    if (!force && status.isRunning) return;
    if (status.phase.isBusy) return;
    if (!force && _userStopped) return;
    // Crash / start failure stays on the boot scaffold until the user taps 重试.
    // Auto-calling start() from error raced native SafePolicy and looped.
    if (!force && status.phase == RuntimePhase.error) return;
    // Settings › 引擎 › 打开 App 时自动启动 — Retry / forced path still starts.
    if (!force && !ref.read(settingsProvider).autoStartLocal) {
      if (status.phase == RuntimePhase.installed) {
        _userStopped = true;
      }
      return;
    }
    // Two strikes + auto-safe off: wait for the failure / Retry UI (same as RootGate).
    if (!force && !EngineControl.shouldAutoStart(status)) return;

    try {
      if (status.phase == RuntimePhase.notInstalled || status.runtimeMissing) {
        await runtime.install();
      }
      final after = ref.read(localRuntimeProvider).status;
      if (after.isRunning) return;
      if (after.phase == RuntimePhase.error && after.runtimeMissing) {
        if (mounted) setState(() => _bootError = after.error ?? 'runtime install failed');
        return;
      }
      if (!force && !EngineControl.shouldAutoStart(after)) return;
      final canStart = after.phase == RuntimePhase.installed ||
          after.phase == RuntimePhase.notInstalled ||
          (force && after.phase == RuntimePhase.error);
      if (canStart) {
        await runtime.start();
      }
    } catch (e) {
      if (mounted) setState(() => _bootError = e.toString());
    }
  }

  void _ensureWebView(String url) {
    if (_controller != null && _loadedUrl == url) return;
    _files.invalidate();
    _loadedUrl = url;
    _pageReady = false;
    _appliedInsetKey = null;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0B0C))
      ..setNavigationDelegate(
        NavigationDelegate(
          // DownloadListener is forwarded as a main-frame navigation; without
          // this callback webview_flutter drops session.export ZIP saves.
          onNavigationRequest: (request) {
            if (isHostSessionExportUrl(request.url)) {
              unawaited(_onHostDownload(url: request.url));
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) => _files.invalidate(),
          onPageFinished: (_) => unawaited(_onPageFinished()),
        ),
      )
      ..addJavaScriptChannel(
        'XrkShell',
        onMessageReceived: (message) => unawaited(_onShellMessage(message.message)),
      );
    // TTS / <audio> bars in Host UI must play on tap without the Android
    // WebView default "requires user gesture" gate swallowing play().
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      unawaited(platform.setMediaPlaybackRequiresUserGesture(false));
    }
    unawaited(controller.loadRequest(Uri.parse(url)));
    _controller = controller;
    unawaited(_attachMobileFileChooser(controller));
  }

  /// Intercept paperclip picks: oversized files → guest inbox path, not Desktop toast.
  Future<void> _attachMobileFileChooser(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is! AndroidWebViewController) {
      await _files.attach(controller);
      return;
    }
    await platform.setOnShowFileSelector((params) async {
      final uris = await _files.choose(
        params,
        webViewId: platform.webViewIdentifier,
        currentUrl: controller.currentUrl,
      );
      if (uris.isEmpty) return uris;
      final bridge = ref.read(runtimeBridgeProvider);
      final teamImport = _isTeamImportAccept(params.acceptTypes);
      final pass = <String>[];
      final notes = <String>[];
      final stagedPacks = <StagedInboxFile>[];
      for (final uri in uris) {
        final probe = await bridge.probeContentUri(uri);
        final bytes = probe?.bytes ?? -1;
        final name = probe?.name ?? 'file';
        if (bytes > _webAttachBudgetBytes) {
          final staged = await bridge.stageInboxUri(uri: uri, name: name);
          if (staged == null) {
            notes.add('复制进机内工作区失败：$name');
            continue;
          }
          if (teamImport) {
            stagedPacks.add(staged);
          } else {
            notes.add(_stagedPathNote(staged));
          }
        } else {
          pass.add(uri);
        }
      }
      // Roster import: Face `team.importPack({ zipPath })` — same install as UI base64.
      if (stagedPacks.isNotEmpty) {
        try {
          await controller.runJavaScript(
            'window.dispatchEvent(new CustomEvent("xrk-staged-pack",{detail:${jsonEncode({
              'packs': [
                for (final s in stagedPacks)
                  {'zipPath': s.guestPath, 'name': s.name, 'bytes': s.bytes},
              ],
            })}}));',
          );
        } catch (_) {}
        if (mounted) {
          _toast(
            stagedPacks.length == 1
                ? '已放入工作区，正在交给名册导入…'
                : '已放入工作区 ${stagedPacks.length} 个文件',
          );
        }
      }
      if (notes.isNotEmpty && mounted) {
        final text = notes.join('\n');
        final request = ComposeRequest(text: text, attachments: const [], problems: const []);
        if (_pageReady) {
          await _composeIntoWeb(request);
        } else {
          _pendingCompose = request;
        }
        final copied = notes.where((n) => n.startsWith('已复制')).length;
        _toast(
          notes.length == 1 && notes.first.startsWith('已复制')
              ? notes.first.split('\n').first
              : copied > 0
                  ? '已复制 $copied 个大文件进机内工作区'
                  : notes.first,
        );
      }
      return pass;
    });
  }

  /// Team roster `<input accept=json,zip>` — not chat paperclip (`*/*`).
  static bool _isTeamImportAccept(List<String> acceptTypes) {
    if (acceptTypes.isEmpty) return false;
    var sawZipOrJson = false;
    for (final raw in acceptTypes) {
      final t = raw.toLowerCase().trim();
      if (t == '*/*' || t.startsWith('image/')) return false;
      if (t.contains('zip') || t.contains('json') || t.endsWith('.zip') || t.endsWith('.json')) {
        sawZipOrJson = true;
      }
    }
    return sawZipOrJson;
  }

  Future<void> _onShellMessage(String raw) async {
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        payload = decoded;
      } else if (decoded is Map) {
        payload = decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      payload = null;
    }
    final op = payload?['op']?.toString();
    if (op == 'restartEngine') {
      _toast('正在重启引擎以使手机工具生效…');
      final ok = await EngineControl.restart(ref.container);
      if (!mounted) return;
      if (!ok) _toast('引擎重启未完成，请到引擎页手动重启');
      return;
    }
    if (op == 'download') {
      final url = payload?['url']?.toString() ?? '';
      if (url.isEmpty) return;
      await _onHostDownload(url: url, filename: payload?['filename']?.toString());
      return;
    }
    if (op == 'downloadBytes') {
      final b64 = payload?['base64']?.toString() ?? '';
      if (b64.isEmpty) return;
      Uint8List bytes;
      try {
        bytes = base64Decode(b64);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text('${context.l10n.stateExportFailed}: 附件字节解码失败')),
          );
        }
        return;
      }
      if (!mounted) return;
      await handleHostShellDownloadBytes(
        context,
        bytes: bytes,
        filename: payload?['filename']?.toString() ?? 'download.bin',
        mime: payload?['mime']?.toString(),
      );
      return;
    }
    if (op == 'downloadError') {
      final message = payload?['message']?.toString().trim();
      if (!mounted || message == null || message.isEmpty) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${context.l10n.stateExportFailed}: $message')),
      );
    }
  }

  Future<void> _onHostDownload({required String url, String? filename}) async {
    if (!mounted) return;
    await handleHostShellDownload(
      context,
      url: url,
      filename: filename,
      // Relative `/api/session.export…` from the WebView needs the loaded Host origin.
      pageUrl: _loadedUrl,
    );
  }

  Future<void> _onPageFinished() async {
    final js = _openBridgeJs ?? await rootBundle.loadString('assets/web/xrk_web_open.js');
    _openBridgeJs = js;
    final controller = _controller;
    if (controller == null) return;
    await controller.runJavaScript(js);
    // Host Settings › phone can request an engine restart after enable/disable.
    await controller.runJavaScript(r'''
(function(){
  window.__xrkRestartEngine = function(){
    try {
      if (typeof XrkShell !== 'undefined' && XrkShell && typeof XrkShell.postMessage === 'function') {
        XrkShell.postMessage(JSON.stringify({op:'restartEngine'}));
        return true;
      }
    } catch (e) {}
    return false;
  };
})();''');
    // Session log / `<a download>` → XrkShell (Android WebView otherwise no-ops).
    await controller.runJavaScript(hostDownloadBridgeJs);
    // Must rebuild — otherwise the settings ball stays out of the tree until
    // the next MediaQuery change (opening/closing the soft keyboard).
    if (mounted) setState(() => _pageReady = true);
    await _applyInsets(force: true);
    final pending = _pendingCompose;
    if (pending != null) {
      _pendingCompose = null;
      await _composeIntoWeb(pending);
    }
  }

  Future<void> _applyInsets({bool force = false}) async {
    if (_insetFlight != null) {
      _insetQueued = true;
      return _insetFlight!;
    }
    final run = () async {
      do {
        _insetQueued = false;
        await _stampInsetsOnce(force: force);
        // Only the first pass may force (page-ready / bridge rebind).
        force = false;
      } while (_insetQueued);
    }();
    _insetFlight = run;
    try {
      await run;
    } finally {
      if (identical(_insetFlight, run)) _insetFlight = null;
    }
  }

  Future<void> _stampInsetsOnce({bool force = false}) async {
    final controller = _controller;
    if (controller == null || !_pageReady) return;
    final top = _padding.top;
    final right = _padding.right;
    final left = _padding.left;
    // Same floor as WebChromeMetrics.gestureFloor — some ROMs omit inset.
    final gesture = math.max(_padding.bottom, 12.0);
    // Snap height only ([WebKeyboard]) — never mid-slide raw.
    final kb = _keyboard;
    final open = kb >= 48;
    // While the IME covers the gesture bar, zero safe-bottom so InputBar /
    // AppFrame do not stack a second band above the keys.
    final safeBottom = open ? 0.0 : gesture;
    final key = '$top|$right|$safeBottom|$left|$kb|root-pin';
    if (!force && key == _appliedInsetKey) return;
    _appliedInsetKey = key;
    // XRK path: WebView full-bleed; pin #root bottom to the keyboard top so
    // the SPA shortens once. Keep --xrk-keyboard-inset at 0 and never set
    // data-xrk-keyboard — ConversationRoot's padding-bottom:inset is what
    // produced the black void between the last bubble and the keys.
    final topPx = top.toStringAsFixed(1);
    final rightPx = right.toStringAsFixed(1);
    final leftPx = left.toStringAsFixed(1);
    final safeBottomPx = safeBottom.toStringAsFixed(1);
    final kbPx = kb.toStringAsFixed(1);
    // top:0 (NOT safeTop) — AppFrame already consumes --ds-safe-top.
    final rootLockCss =
        '#root{position:fixed!important;top:0!important;right:0!important;'
        'bottom:${kbPx}px!important;left:0!important;height:auto!important;'
        'min-height:0!important;margin:0!important}'
        'html,body{overflow:hidden!important;overscroll-behavior:none!important}';
    // InputBar pads with env(safe-area-inset-bottom) while the IME is up
    // (guest used to keep a 4px band even with data-xrk-keyboard). Zero it
    // so the stats row sits flush on the keys without waiting for a new guest.
    final keyboardFlushCss = open
        ? 'html[data-xrk-shell-keyboard] #root *:has(>[data-composer-stats])'
            '{padding-bottom:0!important}'
        : '';
    final script = """
(function(){
  var r=document.documentElement; if(!r) return;
  var meta=document.querySelector('meta[name="viewport"]');
  if(meta){
    var c=meta.getAttribute("content")||"";
    if(c.indexOf("interactive-widget=overlays-content")<0){
      c=c.replace(/interactive-widget\\s*=\\s*[^,\\s]+/,"interactive-widget=overlays-content");
      if(c.indexOf("interactive-widget=")<0){
        c=c+(c?",":"")+"interactive-widget=overlays-content";
      }
      meta.setAttribute("content",c);
    }
  }
  r.style.setProperty("--ds-safe-top","${topPx}px");
  r.style.setProperty("--ds-safe-right","${rightPx}px");
  r.style.setProperty("--ds-safe-bottom","${safeBottomPx}px");
  r.style.setProperty("--ds-safe-left","${leftPx}px");
  r.style.setProperty("--ds-safe-h","calc(var(--ds-safe-left) + var(--ds-safe-right))");
  r.style.setProperty("--ds-safe-v","calc(var(--ds-safe-top) + var(--ds-safe-bottom))");
  // Always 0: layout shortened via #root bottom, not sticky CSS inset.
  // data-xrk-keyboard marks "IME open" for InputBar / hero CSS only.
  r.style.setProperty("--xrk-keyboard-inset","0px");
  function sheet(id, css) {
    var s = document.getElementById(id);
    if (!s) {
      if (!css) return;
      s = document.createElement("style"); s.id = id; document.head.appendChild(s);
    }
    if (!css) { s.remove(); return; }
    if (s.textContent !== css) s.textContent = css;
  }
  var root = document.getElementById("root");
  sheet("xrk-shell-root", root ? ${jsonEncode(rootLockCss)} : "");
  sheet("xrk-shell-keyboard", root ? ${jsonEncode(keyboardFlushCss)} : "");
  // Claim ownership so the guest VV binder never rewrites the CSS inset.
  r.setAttribute("data-xrk-shell-keyboard","");
  if (${open}) r.setAttribute("data-xrk-keyboard","");
  else r.removeAttribute("data-xrk-keyboard");
  // Kill residual document scroll from WebView focus-pan.
  if (window.scrollY || window.scrollX) window.scrollTo(0, 0);
  if (root) root.scrollTop = 0;
})();
""";
    try {
      await controller.runJavaScript(script);
    } catch (_) {}
  }

  Future<bool> _openNativePhoneSettings() async {
    if (!mounted) return false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PhoneControlScreen()),
    );
    return true;
  }

  Future<bool> _openNativeAppSettings() async {
    if (!mounted) return false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    return true;
  }

  /// Open system Accessibility; toast again if the intent fails.
  Future<void> _openAccessibilityFromShell() async {
    final ok = await ref.read(phoneProvider.notifier).openAccessibilitySettings();
    if (!mounted) return;
    if (!ok) {
      final l10n = context.l10n;
      showShellToast(
        context,
        l10n.phoneOpenAccessibilityFailed,
        actionLabel: l10n.phoneControlGoSettings,
        onAction: () => unawaited(_openNativePhoneSettings()),
      );
    }
  }

  Future<void> _openShellMenu() async {
    if (!mounted) return;
    final l10n = context.l10n;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF161618),
      // Material 3 draws its own drag handle; we paint one — keep a single bar.
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        Widget tile({
          required IconData icon,
          required String title,
          required String subtitle,
          required String value,
        }) {
          return ListTile(
            leading: Icon(icon, color: const Color(0xFFE8E8E6)),
            title: Text(title, style: const TextStyle(color: Color(0xFFE8E8E6), fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFFB8B8B4), fontSize: 12)),
            onTap: () => Navigator.pop(ctx, value),
          );
        }

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom > 0 ? 0 : 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A3E),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.shellQuickPanel,
                      style: const TextStyle(color: Color(0xFFE8E8E6), fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                tile(
                  icon: Icons.accessibility_new,
                  title: l10n.phoneControlTitle,
                  subtitle: '开关 · 无障碍 · Root · 自检',
                  value: 'phone-settings',
                ),
                tile(
                  icon: Icons.settings_outlined,
                  title: l10n.commonSettings,
                  subtitle: '引擎 · 保活 · 外观 · 关于 · 更新',
                  value: 'app-settings',
                ),
                tile(
                  icon: Icons.tune_outlined,
                  title: '对话设置',
                  subtitle: '模型 · 权限 · 插件 · Host 面板',
                  value: 'host-settings',
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    if (choice == 'phone-settings') {
      await _openNativePhoneSettings();
      return;
    }
    if (choice == 'app-settings') {
      await _openNativeAppSettings();
      return;
    }
    if (choice == 'host-settings') {
      await _openWebSettings(sectionId: 'general');
    }
  }

  Future<bool> _openWebSettings({String sectionId = 'general'}) async {
    final controller = _controller;
    if (controller == null || !_pageReady) {
      _toast(
        '页面还没就绪，稍后再试',
        actionLabel: sectionId == 'phone' ? '重试' : null,
        onAction: sectionId == 'phone' ? () => unawaited(_openWebSettings(sectionId: 'phone')) : null,
      );
      return false;
    }
    // Prefer the Host bridge; fall back to clicking the sidebar Settings gear.
    final sectionJson = jsonEncode(sectionId);
    final script = '''
(function(){
  try {
    if (typeof window.__xrkOpenSettings === 'function') {
      window.__xrkOpenSettings($sectionJson);
      return 'bridge';
    }
  } catch (e) {}
  var gear = document.querySelector('button[aria-haspopup="dialog"][aria-label*="设置"], button[aria-haspopup="dialog"][aria-label*="Settings"]');
  if (gear) { gear.click(); return 'gear'; }
  return 'missing';
})();''';
    try {
      final result = await controller.runJavaScriptReturningResult(script);
      final text = '$result';
      if (text.contains('bridge') || text.contains('gear')) return true;
      _toast(
        '打不开 Host 设置：请先打开左侧菜单，点底部「设置」',
        actionLabel: sectionId == 'phone' ? '再试一次' : null,
        onAction: sectionId == 'phone' ? () => unawaited(_openWebSettings(sectionId: 'phone')) : null,
      );
      return false;
    } catch (_) {
      _toast(
        '打开 Host 设置失败',
        actionLabel: sectionId == 'phone' ? '打开手机操控' : null,
        onAction: sectionId == 'phone' ? () => unawaited(_openWebSettings(sectionId: 'phone')) : null,
      );
      return false;
    }
  }

  Future<void> _onShare(IncomingShare share) async {
    final outcome = await _ingestShare(share);
    if (!mounted) return;
    if (outcome.message != null) _toast(outcome.message!);
    if (outcome.request == null) return;
    if (_pageReady) {
      await _composeIntoWeb(outcome.request!);
    } else {
      _pendingCompose = outcome.request;
    }
  }

  /// Attachment lanes (local Host):
  /// - small → base64 into composer
  /// - large / agent-pack zip → guest `$XRK_HOME/inbox/` + path text
  /// Agent-pack import stays in the roster UI — no special prompt text here.
  Future<_ShareOutcome> _ingestShare(IncomingShare share) async {
    final problems = <String>[for (final s in share.skipped) skippedText(s)];
    final attachments = <DraftAttachment>[];
    final pathNotes = <String>[];
    final bridge = ref.read(runtimeBridgeProvider);

    for (final file in share.files) {
      final length = _fileLength(file.path) ?? file.size;
      // Packs always stage so roster import can see a guest path (even if small).
      final forceStage = await _isAgentPack(file.path, file.name, length);
      final pasteSafe = !forceStage && length != null && length <= _composeBase64BudgetBytes;

      if (pasteSafe) {
        try {
          final bytes = await File(file.path).readAsBytes();
          if (bytes.length > _composeBase64BudgetBytes) {
            // Unexpected growth — fall through to stage while the cache file still exists.
          } else {
            final attachment = DraftAttachment.sniff(file.name, bytes);
            final problem = attachmentProblem(attachment) ??
                attachmentBudgetProblem(0, attachment, limit: _composeBase64BudgetBytes);
            if (problem != null) {
              problems.add(problem);
            } else {
              attachments.add(attachment);
            }
            _discard(file.path);
            continue;
          }
        } catch (_) {
          problems.add(appL10n.stateShareReadFailed(file.name));
          _discard(file.path);
          continue;
        }
      }

      final staged = await bridge.stageInbox(hostPath: file.path, name: file.name);
      _discard(file.path);
      if (staged == null) {
        problems.add('复制进机内工作区失败：${file.name}');
        continue;
      }
      pathNotes.add(_stagedPathNote(staged));
    }

    final textParts = <String>[
      if ((share.composedText).trim().isNotEmpty) share.composedText.trim(),
      ...pathNotes,
    ];
    final text = textParts.join('\n\n');
    if (attachments.isEmpty && text.isEmpty && problems.isEmpty) {
      return const _ShareOutcome(message: '没有可导入的内容');
    }
    if (attachments.isEmpty && text.isEmpty) {
      return _ShareOutcome(message: problems.first);
    }
    final request = ComposeRequest(
      text: text,
      attachments: attachments,
      problems: problems,
    );
    final okMsg = pathNotes.isNotEmpty
        ? (pathNotes.length == 1 ? pathNotes.first.split('\n').first : '已复制 ${pathNotes.length} 个文件进机内工作区')
        : (attachments.isNotEmpty ? '已加入附件 ${attachments.length} 个' : null);
    final warn = problems.isNotEmpty ? problems.first : null;
    return _ShareOutcome(request: request, message: warn ?? okMsg);
  }

  static String _stagedPathNote(StagedInboxFile staged) {
    final mb = staged.bytes > 0 ? '（${(staged.bytes / (1024 * 1024)).toStringAsFixed(1)} MB）' : '';
    return '已复制进机内工作区：${staged.guestPath}$mb';
  }

  Future<void> _composeIntoWeb(ComposeRequest request) async {
    final controller = _controller;
    if (controller == null) {
      _pendingCompose = request;
      return;
    }
    if (request.problems.isNotEmpty && request.attachments.isEmpty && request.text.trim().isEmpty) {
      _toast(request.problems.first);
      return;
    }
    final files = [
      for (final a in request.attachments)
        {
          'name': a.name,
          'type': a.mediaType ?? 'application/octet-stream',
          'data': base64Encode(a.bytes),
        },
    ];
    final draft = {'text': request.text, 'files': files};
    try {
      await controller.runJavaScript(
        'var _c=window.__xrkAppCompose||window.__dshAppCompose; _c && _c(${jsonEncode(draft)});',
      );
    } catch (_) {
      _toast('写入对话失败，请重试');
      return;
    }
    if (request.problems.isNotEmpty) {
      _toast(request.problems.first);
    }
  }

  void _toast(String message, {String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    showShellToast(context, message, actionLabel: actionLabel, onAction: onAction);
  }

  static int? _fileLength(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }

  static void _discard(String path) {
    try {
      final file = File(path);
      final slot = file.parent;
      file.deleteSync();
      if (slot.listSync().isEmpty) slot.deleteSync();
    } catch (_) {}
  }

  /// Agent pack = product zip with the `.xrk-agent-pack` marker (or that extension).
  /// Do **not** treat ordinary filenames that merely contain「干员」as packs.
  static Future<bool> _isAgentPack(String path, String name, int? length) async {
    final lower = name.toLowerCase();
    if (lower.endsWith('.xrk-agent-pack')) return true;
    if (!lower.endsWith('.zip') && !lower.endsWith('.xrk-agent-pack')) return false;
    // Huge zips: skip full decode (RAM); only the dedicated extension counts as pack.
    if (length != null && length > _composeBase64BudgetBytes) return false;
    try {
      final input = InputFileStream(path);
      try {
        final archive = ZipDecoder().decodeStream(input);
        for (final f in archive.files) {
          final n = f.name.replaceAll('\\', '/');
          if (n == '.xrk-agent-pack' || n.endsWith('/.xrk-agent-pack')) return true;
        }
      } finally {
        input.close();
      }
    } catch (_) {}
    return false;
  }
}

class _ShareOutcome {
  const _ShareOutcome({this.request, this.message});
  final ComposeRequest? request;
  final String? message;
}

class _InterruptBanner extends StatelessWidget {
  const _InterruptBanner({
    required this.interruption,
    required this.busy,
    required this.onAck,
    required this.onOpenSettings,
  });

  final PhoneTaskInterruption interruption;
  final bool busy;
  final VoidCallback onAck;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final subtitle = interruption.state == 'loading'
        ? l10n.phoneInterruptionLoading
        : interruption.state == 'error'
        ? l10n.phoneInterruptionStorageError
        : l10n.phoneInterruptionHint(interruption.count);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: const Color(0xFF1C1C1E),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.phoneInterruptionTitle,
              style: const TextStyle(color: Color(0xFFE8E8E6), fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Color(0xFFB8B8B4), fontSize: 12, height: 1.35)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: onOpenSettings,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB8B8B4),
                      minimumSize: const Size(44, 44),
                    ),
                    child: const Text('打开手机操控'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy || interruption.state == 'loading' ? null : onAck,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE8E8E6),
                    foregroundColor: const Color(0xFF0B0B0C),
                    minimumSize: const Size(44, 44),
                  ),
                  child: Text(
                    interruption.canAcknowledge
                        ? l10n.phoneInterruptionAcknowledge
                        : l10n.phoneInterruptionRetry,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BootScaffold extends StatelessWidget {
  const _BootScaffold({
    required this.status,
    required this.progress,
    required this.loaded,
    required this.onRetry,
    this.stopped = false,
    this.error,
  });

  static const _black = Color(0xFF0B0B0C);
  static const _ink = Color(0xFFE8E8E6);
  static const _muted = Color(0xFFB8B8B4);

  final RuntimeStatus status;
  final RuntimeProgressEvent? progress;
  final bool loaded;
  final bool stopped;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final busy = status.phase.isBusy || !loaded;
    final failed = error != null && error!.isNotEmpty && !busy;
    final idle = stopped && !busy && !failed;
    final label = idle
        ? '引擎已停止'
        : switch (status.phase) {
            RuntimePhase.installing => '正在安装运行环境',
            RuntimePhase.starting => '正在启动',
            RuntimePhase.stopping => '正在停止',
            RuntimePhase.error => '启动失败',
            RuntimePhase.notInstalled => '正在准备',
            RuntimePhase.installed => '正在启动',
            RuntimePhase.running => '正在打开',
          };
    final pct = progress?.fraction;

    // SizedBox.expand: boot must paint edge-to-edge (MuMu size-compat otherwise
    // leaves black pillars around a narrow Flutter strip).
    return ColoredBox(
      color: _black,
      child: SizedBox.expand(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 2),
                const ClipRect(child: BrandMark(tile: true, size: 72)),
              const SizedBox(height: 16),
              Text(
                AppInfo.wordmark,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  decoration: TextDecoration.none,
                  decorationColor: Colors.transparent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppInfo.name,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 13,
                  decoration: TextDecoration.none,
                  decorationColor: Colors.transparent,
                ),
              ),
              const Spacer(),
              if (failed || idle) ...[
                if (failed)
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF8E8E), fontSize: 14, height: 1.4),
                  )
                else
                  Text(label, style: const TextStyle(color: _muted, fontSize: 14)),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: _black,
                    minimumSize: const Size(44, 44),
                  ),
                  child: Text(failed ? '重试' : '启动 Host'),
                ),
              ] else ...[
                if (pct != null)
                  LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    backgroundColor: const Color(0xFF222226),
                    color: _ink,
                  )
                else
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _ink),
                  ),
                const SizedBox(height: 16),
                Text(
                  label,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                    decorationColor: Colors.transparent,
                  ),
                ),
              ],
              const Spacer(flex: 2),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Draggable / collapsible shell ball — opens Go settings + phone control.
class _ShellBall extends StatefulWidget {
  const _ShellBall({
    required this.safeBottom,
    required this.safeTop,
    required this.onTap,
  });

  final double safeBottom;
  final double safeTop;
  final VoidCallback onTap;

  static const _kDx = 'shell.ball.dx';
  static const _kDy = 'shell.ball.dy';
  static const _kCollapsed = 'shell.ball.collapsed';
  static const size = 48.0;
  static const collapsed = 28.0;

  @override
  State<_ShellBall> createState() => _ShellBallState();
}

class _ShellBallState extends State<_ShellBall> {
  double? _dx;
  double? _dy;
  var _collapsed = false;
  var _loaded = false;
  Offset? _dragOrigin;
  Offset? _startPos;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _dx = p.getDouble(_ShellBall._kDx);
        _dy = p.getDouble(_ShellBall._kDy);
        _collapsed = p.getBool(_ShellBall._kCollapsed) ?? false;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_dx != null) await p.setDouble(_ShellBall._kDx, _dx!);
      if (_dy != null) await p.setDouble(_ShellBall._kDy, _dy!);
      await p.setBool(_ShellBall._kCollapsed, _collapsed);
    } catch (_) {}
  }

  void _clamp(Size size) {
    final w = _collapsed ? _ShellBall.collapsed : _ShellBall.size;
    final h = _collapsed ? _ShellBall.collapsed * 2.2 : _ShellBall.size;
    final maxX = (size.width - w).clamp(0.0, size.width);
    final maxY = (size.height - h - widget.safeBottom).clamp(0.0, size.height);
    final minY = widget.safeTop + 8;
    _dx = (_dx ?? (size.width - w - 14)).clamp(0.0, maxX);
    _dy = (_dy ?? (size.height - h - widget.safeBottom - 18)).clamp(minY, maxY);
  }

  void _snapToEdge(Size size) {
    final w = _collapsed ? _ShellBall.collapsed : _ShellBall.size;
    final mid = size.width / 2;
    _dx = ((_dx ?? 0) + w / 2) < mid ? 0.0 : size.width - w;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    _clamp(size);
    final w = _collapsed ? _ShellBall.collapsed : _ShellBall.size;
    final h = _collapsed ? _ShellBall.collapsed * 2.2 : _ShellBall.size;
    return Positioned(
      left: _dx,
      top: _dy,
      child: GestureDetector(
        onPanStart: (d) {
          _dragOrigin = d.globalPosition;
          _startPos = Offset(_dx!, _dy!);
        },
        onPanUpdate: (d) {
          if (_dragOrigin == null || _startPos == null) return;
          setState(() {
            _dx = _startPos!.dx + (d.globalPosition.dx - _dragOrigin!.dx);
            _dy = _startPos!.dy + (d.globalPosition.dy - _dragOrigin!.dy);
            _clamp(size);
          });
        },
        onPanEnd: (_) {
          setState(() {
            if (_collapsed) {
              _snapToEdge(size);
            }
          });
          unawaited(_persist());
          _dragOrigin = null;
          _startPos = null;
        },
        onTap: () {
          if (_collapsed) {
            setState(() => _collapsed = false);
            unawaited(_persist());
            return;
          }
          widget.onTap();
        },
        onLongPress: () {
          setState(() {
            _collapsed = !_collapsed;
            if (_collapsed) _snapToEdge(size);
            _clamp(size);
          });
          unawaited(_persist());
        },
        child: RepaintBoundary(
          child: Material(
            color: const Color(0xE6161618),
            elevation: 0,
            shape: _collapsed
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFF3A3A3E)),
                  )
                : const CircleBorder(side: BorderSide(color: Color(0xFF3A3A3E))),
            child: SizedBox(
              width: w,
              height: h,
              child: Icon(
                _collapsed
                    ? ((_dx ?? 0) < size.width / 2 ? Icons.chevron_right : Icons.chevron_left)
                    : Icons.apps,
                color: const Color(0xFFE8E8E6),
                size: _collapsed ? 18 : 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
