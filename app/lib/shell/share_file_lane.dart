/// How a shared / open-with file should reach the active Host Face.
///
/// Local Host can stage oversized bytes into the on-device guest inbox and
/// inject a path the agent can read. Remote HTTP Face has no guest inbox —
/// within Face's paperclip budget the bytes must ride the compose bridge
/// (base64 → WebView File drop); above that budget we can only refuse.
enum ShareFileLane {
  /// Read bytes and pass through `__xrkAppCompose` as a File attachment.
  attachBytes,

  /// Copy into guest `$XRK_HOME/inbox/` and inject the path as composer text.
  stageGuestInbox,

  /// Remote Host + over Face budget — refuse with a workspace/@path hint.
  rejectRemoteTooLarge,
}

/// Flutter→JS compose bridge soft ceiling (WebView string OOM risk).
const shareComposeBridgeBudgetBytes = 3 * 1024 * 1024;

/// Face paperclip / message file ceiling (aligned with Host `maxFileBytes`).
const shareFaceAttachBudgetBytes = 20 * 1024 * 1024;

/// Pick a lane for one shared file.
///
/// [forceStagePack] is only meaningful on the local Host (agent-pack zips
/// that the roster imports by guest path). Remote always attaches when under
/// Face budget and never stages.
ShareFileLane shareFileLane({
  required bool isRemoteHttp,
  required int? lengthBytes,
  bool forceStagePack = false,
}) {
  if (isRemoteHttp) {
    if (lengthBytes != null && lengthBytes <= shareFaceAttachBudgetBytes) {
      return ShareFileLane.attachBytes;
    }
    return ShareFileLane.rejectRemoteTooLarge;
  }
  if (forceStagePack) return ShareFileLane.stageGuestInbox;
  if (lengthBytes != null && lengthBytes <= shareComposeBridgeBudgetBytes) {
    return ShareFileLane.attachBytes;
  }
  return ShareFileLane.stageGuestInbox;
}

/// User-facing refusal when a remote Face cannot take an oversized share.
String remoteShareTooLargeMessage(String name, {int budgetBytes = shareFaceAttachBudgetBytes}) {
  final mb = budgetBytes ~/ (1024 * 1024);
  return '远程 Host 上「$name」超过 ${mb}MB：不能直传（无断点续传）。'
      '请先放到 Host 工作区再用 @ 引用，或改用本机 Host。';
}
