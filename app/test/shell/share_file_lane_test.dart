import 'package:flutter_test/flutter_test.dart';
import 'package:xrk_app/shell/share_file_lane.dart';

void main() {
  group('shareFileLane', () {
    test('remote under Face budget attaches bytes (not local inbox)', () {
      expect(
        shareFileLane(isRemoteHttp: true, lengthBytes: 16 * 1024 * 1024),
        ShareFileLane.attachBytes,
      );
      expect(
        shareFileLane(isRemoteHttp: true, lengthBytes: shareFaceAttachBudgetBytes),
        ShareFileLane.attachBytes,
      );
    });

    test('remote over Face budget is refused', () {
      expect(
        shareFileLane(isRemoteHttp: true, lengthBytes: shareFaceAttachBudgetBytes + 1),
        ShareFileLane.rejectRemoteTooLarge,
      );
      expect(
        shareFileLane(isRemoteHttp: true, lengthBytes: null),
        ShareFileLane.rejectRemoteTooLarge,
      );
    });

    test('local small files attach; large / packs stage into guest inbox', () {
      expect(
        shareFileLane(isRemoteHttp: false, lengthBytes: shareComposeBridgeBudgetBytes),
        ShareFileLane.attachBytes,
      );
      expect(
        shareFileLane(isRemoteHttp: false, lengthBytes: shareComposeBridgeBudgetBytes + 1),
        ShareFileLane.stageGuestInbox,
      );
      expect(
        shareFileLane(isRemoteHttp: false, lengthBytes: 100, forceStagePack: true),
        ShareFileLane.stageGuestInbox,
      );
    });
  });

  test('remoteShareTooLargeMessage names the file and Face budget', () {
    final msg = remoteShareTooLargeMessage('pack.zip');
    expect(msg, contains('pack.zip'));
    expect(msg, contains('20MB'));
    expect(msg, contains('远程 Host'));
  });
}
