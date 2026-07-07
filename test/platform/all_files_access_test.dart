import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/all_files_access.dart';
import '../fakes/fakes.dart';

void main() {
  test('shouldOfferAllFilesAccess: only when not granted and not yet offered', () {
    expect(shouldOfferAllFilesAccess(false, false), true);
    expect(shouldOfferAllFilesAccess(true, false), false);  // already granted
    expect(shouldOfferAllFilesAccess(false, true), false);  // already offered once
    expect(shouldOfferAllFilesAccess(true, true), false);
  });

  test('FakeAllFilesAccess reports and flips on request', () async {
    final a = FakeAllFilesAccess();
    expect(await a.isGranted(), false);
    expect(await a.request(), true);
    expect(a.requestCount, 1);
    expect(await a.isGranted(), true);
  });

  test('FakeAllFilesAccess can simulate a declined request', () async {
    final a = FakeAllFilesAccess()..grantOnRequest = false;
    expect(await a.request(), false);
    expect(await a.isGranted(), false);
  });
}
