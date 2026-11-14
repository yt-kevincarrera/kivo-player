import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/l10n.dart';
import '../../platform/all_files_access_provider.dart';
import '../../platform/interfaces/storage_browser.dart';
import '../../platform/storage_browser_provider.dart';
import '../../player/library/media_index.dart';
import '../../player/library/media_permission.dart';
import 'tv_focusable.dart';
import 'tv_library_screen.dart';

class TvStorageScreen extends ConsumerStatefulWidget {
  const TvStorageScreen({super.key});
  @override
  ConsumerState<TvStorageScreen> createState() => _TvStorageScreenState();
}

class _TvStorageScreenState extends ConsumerState<TvStorageScreen>
    with WidgetsBindingObserver {
  late Future<AsyncValue<List<StorageVolume>>> _volumes;
  Future<AsyncValue<List<StorageEntry>>>? _entries;
  final _parents = <String>[];
  String? _path;
  String? _volumeName;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(_reload);
  }

  void _reload() {
    _volumes = AsyncValue.guard(
      () => ref.read(storageBrowserProvider).volumes(),
    );
    if (_path != null) {
      _entries = AsyncValue.guard(
        () => ref.read(storageBrowserProvider).list(_path!),
      );
    }
  }

  void _enter(String path, {String? volumeName}) {
    if (_path != null) _parents.add(_path!);
    setState(() {
      _path = path;
      _volumeName = volumeName ?? _volumeName;
      _entries = AsyncValue.guard(
        () => ref.read(storageBrowserProvider).list(path),
      );
    });
  }

  void _back() {
    setState(() {
      if (_parents.isEmpty) {
        _path = null;
        _entries = null;
        _volumeName = null;
      } else {
        _path = _parents.removeLast();
        _entries = AsyncValue.guard(
          () => ref.read(storageBrowserProvider).list(_path!),
        );
      }
    });
  }

  Future<void> _access() async {
    setState(() => _requesting = true);
    var granted = false;
    try {
      await ref.read(mediaPermissionProvider.notifier).request();
      granted = await ref.read(allFilesAccessProvider).request();
    } catch (_) {
      /* OEM may have no permission activity. Recovery remains visible. */
    }
    if (!mounted) return;
    setState(() {
      _requesting = false;
      _reload();
    });
    ref.read(mediaIndexProvider.notifier).refresh();
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.tvPermissionStillMissing),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(storageChangesProvider, (_, event) {
      if (event.hasValue) {
        setState(() {
          _path = null;
          _entries = null;
          _parents.clear();
          _volumeName = null;
          _reload();
        });
        ref.read(mediaIndexProvider.notifier).refresh();
      }
    });
    final l = context.l10n;
    return PopScope(
      canPop: _path == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(42, 28, 42, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 18,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TvButton(
                      label: l.commonGoBack,
                      icon: Icons.arrow_back,
                      onPressed: () {
                        if (_path == null) {
                          Navigator.of(context).pop();
                        } else {
                          _back();
                        }
                      },
                    ),
                    Text(
                      _volumeName ?? l.tvUsb,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TvButton(
                      label: l.tvRefresh,
                      icon: Icons.refresh,
                      onPressed: () => setState(_reload),
                    ),
                  ],
                ),
                if (_path != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _path!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Expanded(child: _path == null ? _volumeList() : _directory()),
                const SizedBox(height: 16),
                Text(
                  l.tvNavigationHint,
                  style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _volumeList() => FutureBuilder<AsyncValue<List<StorageVolume>>>(
    future: _volumes,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.data?.hasError ?? false) return _error(snapshot.data!.error);
      final volumes = snapshot.data?.valueOrNull ?? [];
      final removable = volumes.where((v) => v.removable);
      return ListView(
        padding: const EdgeInsets.all(6),
        children: [
          if (removable.isEmpty) ...[
            Text(
              context.l10n.tvNoUsb,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.tvNoUsbBody,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 26),
          ],
          ...volumes.indexed.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: TvButton(
                key: ValueKey(e.$2.path),
                autofocus: e.$1 == 0,
                label: e.$2.removable
                    ? e.$2.name
                    : context.l10n.tvInternalStorage,
                subtitle: e.$2.path,
                icon: e.$2.removable ? Icons.usb : Icons.storage_outlined,
                trailing: const Icon(Icons.chevron_right),
                onPressed: () => _enter(
                  e.$2.path,
                  volumeName: e.$2.removable
                      ? e.$2.name
                      : context.l10n.tvInternalStorage,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TvButton(
              label: context.l10n.tvStorageAccess,
              icon: Icons.folder_open,
              onPressed: _requesting ? null : _access,
            ),
          ),
        ],
      );
    },
  );

  Widget _directory() => FutureBuilder<AsyncValue<List<StorageEntry>>>(
    key: ValueKey(_path),
    future: _entries,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.data?.hasError ?? false) return _error(snapshot.data!.error);
      final entries = snapshot.data?.valueOrNull ?? [];
      final videos = entries
          .where((e) => e.video != null)
          .map((e) => e.video!)
          .toList();
      if (entries.isEmpty) {
        return Center(
          child: Text(
            context.l10n.tvEmptyFolder,
            style: const TextStyle(fontSize: 26),
          ),
        );
      }
      return ListView.separated(
        key: PageStorageKey(_path),
        padding: const EdgeInsets.all(6),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) {
          final entry = entries[i];
          return TvButton(
            key: ValueKey(entry.path),
            autofocus: i == 0,
            label: entry.name,
            icon: entry.directory
                ? Icons.folder_outlined
                : Icons.play_circle_outline,
            subtitle: entry.directory
                ? context.l10n.tvFolder
                : context.l10n.tvUnknownDuration,
            trailing: const Icon(Icons.chevron_right),
            onPressed: () {
              if (entry.directory) {
                _enter(entry.path);
              } else {
                openTvVideo(context, ref, entry.video!, videos);
              }
            },
          );
        },
      );
    },
  );

  Widget _error(Object? error) {
    final l = context.l10n;
    final denied = error is PlatformException && error.code == 'ACCESS_DENIED';
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(denied ? Icons.folder_off_outlined : Icons.usb_off, size: 58),
            const SizedBox(height: 20),
            Text(
              denied ? l.tvStorageAccess : l.tvStorageUnavailable,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text(
              denied ? l.tvStorageAccessBody : l.tvStorageUnavailableBody,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                TvButton(
                  label: l.tvStorageAccess,
                  autofocus: true,
                  primary: true,
                  onPressed: _requesting ? null : _access,
                ),
                TvButton(
                  label: l.tvRefresh,
                  icon: Icons.refresh,
                  onPressed: () => setState(_reload),
                ),
                TvButton(
                  label: l.commonGoBack,
                  onPressed: () {
                    if (_path != null) {
                      _back();
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
