import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/vault_ops_provider.dart';
import 'package:kivo_player/ui/vault/widgets/vault_thumbnail.dart';
import '../../fakes/fakes.dart';

// A real 1x1 PNG: the image has to decode.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main() {
  // Selecting a video in the Vault rebuilds the whole grid. A thumbnail
  // fetched again on every rebuild comes back as new bytes, the image
  // reloads, and every tile blinks.
  testWidgets('a rebuild does not fetch the thumbnail again', (t) async {
    final ops = FakeVaultOps()..thumb = _png;
    final c = ProviderContainer(
      overrides: [vaultOpsProvider.overrideWithValue(ops)],
    );
    addTearDown(c.dispose);
    final selected = ValueNotifier(false);
    var path = '/p/a.mp4';
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: selected,
            builder: (_, sel, __) => ColoredBox(
              color: sel ? Colors.amber : Colors.black,
              // Not const, like the Vault grid's tiles: it rebuilds with its parent.
              child: SizedBox(
                width: 100,
                height: 60,
                child: VaultThumbnail(path: path),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    selected.value = true;
    await t.pump();
    selected.value = false;
    await t.pump();
    expect(ops.thumbnailRequests, ['/p/a.mp4']);
  });
}
