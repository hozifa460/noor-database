// ════════════════════════════════════════════════════════════════
// sync_youtube.dart — YouTube sync with MERGE + AUTO-ARCHIVE
//
// Changes from the original:
//   1. MERGE instead of overwrite — new videos are added on top of
//      existing ones (NO data loss).
//   2. AUTO-ARCHIVE — when a section file exceeds ARCHIVE_THRESHOLD
//      items (default 5000), the oldest items are moved to a
//      .archive.json file.
//   3. Classification into 3 files per channel (live/videos/shorts).
//   4. index.json structure UNCHANGED — archive files are added to
//      the same "files" array.
//
// Usage:
//   dart run bin/sync_youtube.dart --folder ../../radio_database
//   dart run bin/sync_youtube.dart --folder ../../radio_database --limit 30
//   dart run bin/sync_youtube.dart --folder ../../radio_database --archive-threshold 3000
// ════════════════════════════════════════════════════════════════

library;

import 'dart:convert';
import 'dart:io';

import 'package:youtube_sync_dart/youtube_sync.dart';

const int defaultArchiveThreshold = 5000;
const String sep = '/';

String joinPath(String a, String b) => '$a$sep$b';

Future<int> main(List<String> args) async {
  if (Platform.isWindows) {
    try {
      stdout.encoding = utf8;
      stderr.encoding = utf8;
    } catch (_) {}
  }

  final folder = _parseArg(args, '--folder') ?? 'radio_database';
  final limit = int.tryParse(_parseArg(args, '--limit') ?? '') ?? 15;
  final archiveThreshold = int.tryParse(
        _parseArg(args, '--archive-threshold') ?? '',
      ) ??
      defaultArchiveThreshold;

  final folderDir = Directory(folder);
  if (!folderDir.existsSync()) {
    stderr.writeln('[ERROR] Folder not found: $folder');
    return 1;
  }
  print('[INFO] Data folder: $folder');
  print('[INFO] RSS limit per sync: $limit');
  print('[INFO] Archive threshold: $archiveThreshold');

  final manifestPath = joinPath(folder, 'youtube_channels.json');
  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('[ERROR] Manifest not found: $manifestPath');
    return 1;
  }

  final channels = loadManifest(manifestFile);
  if (channels.isEmpty) {
    print('[INFO] No channels in manifest, nothing to do');
    print('[INFO] Add channels to radio_database/youtube_channels.json');
    return 0;
  }
  print('[INFO] ${channels.length} channel(s) in manifest');

  final indexFilePath = joinPath(folder, 'index.json');
  final indexFile = File(indexFilePath);
  final index = loadIndex(indexFile);
  var indexChanged = false;
  final filesToDelete = <File>[];

  for (final ch in channels) {
    print('[OK] ${ch.categoryId}: fetching RSS...');
    List<RawEntry> raw;
    try {
      raw = await fetchRss(ch.channelId);
    } catch (e) {
      print('[ERROR] ${ch.categoryId}: RSS fetch failed: $e');
      continue;
    }
    if (raw.isEmpty) {
      print('[WARN] ${ch.categoryId}: no entries, skipping');
      continue;
    }
    print('  [INFO] RSS returned ${raw.length} entries (limit=$limit)');

    print('  [INFO] fetching live tab playlist (UULV)...');
    final liveIds = await fetchLiveTabVideoIds(ch.channelId);
    print('  [INFO] live tab: ${liveIds.length} videos');

    print('  [INFO] fetching shorts tab playlist (UUSH)...');
    final shortsIds = await fetchShortsTabVideoIds(ch.channelId);
    print('  [INFO] shorts tab: ${shortsIds.length} videos');

    print('  [INFO] fetching youtube_explode_dart metadata...');
    final meta = await fetchVideoMetadata(raw.map((e) => e.videoId));
    print('  [INFO] metadata: ${meta.length}/${raw.length} succeeded');

    final buckets = classifyEntries(
      entries: raw,
      channelName: ch.channelName,
      limit: limit,
      metadataMap: meta,
      liveVideoIds: liveIds,
      shortsVideoIds: shortsIds,
    );
    print(
      '  [INFO] classified: live=${buckets.live.length} '
      'videos=${buckets.videos.length} shorts=${buckets.shorts.length}',
    );

    final chPath = joinPath(folder, ch.categoryId);
    final chDir = Directory(chPath);
    if (!chDir.existsSync()) chDir.createSync(recursive: true);

    // Mark old single .youtube.json for deletion
    final oldFilePath = joinPath(chPath, '${ch.categoryId}.youtube.json');
    final oldFile = File(oldFilePath);
    final oldRel = joinPath(ch.categoryId, '${ch.categoryId}.youtube.json');
    if (oldFile.existsSync()) filesToDelete.add(oldFile);
    if (index.files.remove(oldRel)) {
      indexChanged = true;
      print('  [INFO] removed legacy $oldRel from index.json');
    }

    // ════════════════════════════════════════════════════════════
    // LIVE STREAM LIFECYCLE: Keep ALL streams (live + ended) in .live.json.
    // The isLiveNow flag distinguishes active streams from recordings.
    //   - isLiveNow=true: stream is currently broadcasting (in UULV playlist)
    //   - isLiveNow=false: stream has ended (recording)
    // The platform's live-check polling updates isLiveNow in real-time.
    // ════════════════════════════════════════════════════════════
    // (No need to move streams to .videos.json — they stay in .live.json
    // with isLiveNow flag. The platform shows only isLiveNow=true in the
    // "Live Now" section, and shows all .live.json items in the "Live"
    // section (including recordings).)

    // For each bucket: MERGE + AUTO-ARCHIVE
    Future<void> writeBucketMerged(
      String kind,
      String emoji,
      List<SubItem> newSubs,
      Map<String, dynamic> Function(String, String, List<SubItem>) builder,
    ) async {
      if (newSubs.isEmpty) {
        print('  [SKIP] $kind: no new items');
        return;
      }

      final mainRel = joinPath(ch.categoryId, '${ch.categoryId}.$kind.json');
      final mainFilePath = joinPath(chPath, '${ch.categoryId}.$kind.json');
      final mainFile = File(mainFilePath);
      final archiveRel = joinPath(ch.categoryId, '${ch.categoryId}.$kind.archive.json');
      final archiveFilePath = joinPath(chPath, '${ch.categoryId}.$kind.archive.json');
      final archiveFile = File(archiveFilePath);

      // Load existing main file
      final existingMainSubs = <SubItem>[];
      if (mainFile.existsSync()) {
        try {
          final oldJson = jsonDecode(mainFile.readAsStringSync()) as Map<String, dynamic>;
          for (final item in (oldJson['items'] as List?) ?? []) {
            for (final sub in (item['subItems'] as List?) ?? []) {
              final m = sub as Map<String, dynamic>;
              existingMainSubs.add(SubItem(
                title: (m['title'] ?? '').toString(),
                subtitle: (m['subtitle'] ?? '').toString(),
                audioUrl: (m['audioUrl'] ?? '').toString(),
                imageUrl: (m['imageUrl'] ?? '').toString(),
                videoUrl: (m['videoUrl'] ?? '').toString(),
              ));
            }
          }
        } catch (e) {
          print('  [WARN] could not parse existing $mainRel: $e');
        }
      }

      // Load existing archive file
      final existingArchiveSubs = <SubItem>[];
      if (archiveFile.existsSync()) {
        try {
          final arcJson = jsonDecode(archiveFile.readAsStringSync()) as Map<String, dynamic>;
          for (final item in (arcJson['items'] as List?) ?? []) {
            for (final sub in (item['subItems'] as List?) ?? []) {
              final m = sub as Map<String, dynamic>;
              existingArchiveSubs.add(SubItem(
                title: (m['title'] ?? '').toString(),
                subtitle: (m['subtitle'] ?? '').toString(),
                audioUrl: (m['audioUrl'] ?? '').toString(),
                imageUrl: (m['imageUrl'] ?? '').toString(),
                videoUrl: (m['videoUrl'] ?? '').toString(),
              ));
            }
          }
        } catch (e) {
          print('  [WARN] could not parse existing $archiveRel: $e');
        }
      }

      // Merge: new first (newest), then existing main, then archive.
      final merged = <SubItem>[];
      final seenUrls = <String>{};
      void addUnique(SubItem s) {
        final key = s.videoUrl.isNotEmpty ? s.videoUrl : s.audioUrl;
        if (key.isEmpty || seenUrls.add(key)) merged.add(s);
      }

      for (final s in newSubs) addUnique(s);
      for (final s in existingMainSubs) addUnique(s);
      for (final s in existingArchiveSubs) addUnique(s);

      print('  [INFO] $kind: merged ${merged.length} items '
          '(new=${newSubs.length}, existingMain=${existingMainSubs.length}, '
          'existingArchive=${existingArchiveSubs.length})');

      // Auto-archive
      final List<SubItem> mainSubs;
      final List<SubItem> archiveSubs;
      if (merged.length > archiveThreshold) {
        mainSubs = merged.sublist(0, archiveThreshold);
        archiveSubs = merged.sublist(archiveThreshold);
        print('  [ARCHIVE] $kind: main=${mainSubs.length}, archive=${archiveSubs.length}');
      } else {
        mainSubs = merged;
        archiveSubs = const [];
      }

      // Write main file
      await writeJson(mainFile, builder(ch.categoryId, ch.channelName, mainSubs));
      print('  [OK] $mainRel: ${mainSubs.length} subItems $emoji');
      if (index.add(mainRel)) {
        indexChanged = true;
        print('  [OK] index.json: added $mainRel');
      }

      // Write/update archive file
      if (archiveSubs.isNotEmpty) {
        await writeJson(archiveFile, builder(ch.categoryId, ch.channelName, archiveSubs));
        print('  [OK] $archiveRel: ${archiveSubs.length} archived subItems');
        if (index.add(archiveRel)) {
          indexChanged = true;
          print('  [OK] index.json: added $archiveRel (archive)');
        }
      } else if (archiveFile.existsSync()) {
        archiveFile.deleteSync();
        if (index.files.remove(archiveRel)) {
          indexChanged = true;
          print('  [DEL] removed empty $archiveRel');
        }
      }
    }

    await writeBucketMerged('live', '🔴', buckets.live, buildLiveFile);
    await writeBucketMerged('videos', '🎥', buckets.videos, buildVideosFile);
    await writeBucketMerged('shorts', '📱', buckets.shorts, buildShortsFile);
  }

  // Delete old .youtube.json files
  for (final old in filesToDelete) {
    try {
      old.deleteSync();
      print('  [DEL] deleted old file');
    } catch (e) {
      print('  [WARN] could not delete: $e');
    }
  }

  // Finalize index.json
  if (indexChanged) {
    await writeIndex(indexFile, index);
    print('\n[OK] index.json updated (${index.files.length} files)');
  } else {
    print('\n[INFO] index.json unchanged');
  }

  print('\n[DONE] Sync complete (with merge + auto-archive)');
  return 0;
}

String? _parseArg(List<String> args, String flag) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == flag) return args[i + 1];
  }
  return null;
}
