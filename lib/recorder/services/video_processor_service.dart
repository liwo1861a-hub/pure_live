import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'package:path/path.dart' as p;
import 'package:pure_live/common/index.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';

class VideoProcessorService extends GetxService {
  VideoProcessorService._internal();

  static final VideoProcessorService _instance = VideoProcessorService._internal();

  static VideoProcessorService get to => _instance;

  final FFmpegManager _ffmpeg = FFmpegManager.to;

  final StreamController<VideoProcessEvent> _controller = StreamController<VideoProcessEvent>.broadcast();

  Stream<VideoProcessEvent> get stream => _controller.stream;

  final Map<String, StreamSubscription<FFmpegEvent>> _subscriptions = {};

  final Set<String> _processingTasks = {};

  bool isProcessing(String taskId) {
    return _processingTasks.contains(taskId);
  }

  Future<bool> convertToMp4({required LiveRecordTask task, bool deleteSourceTs = true}) async {
    final taskId = task.taskId;
    if (_processingTasks.contains(taskId)) {
      return false;
    }
    _processingTasks.add(taskId);
    try {
      final tsDir = Directory(task.outputDir ?? '');
      if (!tsDir.existsSync()) {
        _emitFailed(taskId, i18n("video_dir_not_exist"));
        return false;
      }
      final files = tsDir
          .listSync()
          .whereType<File>()
          .where((e) => e.path.endsWith('.ts') && e.lengthSync() > 0)
          .toList();

      files.sort((a, b) => a.path.compareTo(b.path));

      if (files.isEmpty) {
        _emitFailed(taskId, i18n("video_ts_empty"));
        return false;
      } else {
        log('$taskId： ${i18n("video_ts_total", args: {"count": files.length.toString()})}');
      }

      _controller.add(VideoProcessEvent(taskId: taskId, type: VideoProcessEventType.started));

      final listFile = File(p.join(tsDir.path, 'list.txt'));

      final buffer = StringBuffer();

      for (final f in files) {
        // Concat demuxer path escaping: normalize backslashes and escape single quotes
        final escapedPath = f.path.replaceAll(r'\', '/').replaceAll("'", r"'\''");
        buffer.writeln("file '$escapedPath'");
      }

      await listFile.writeAsString(buffer.toString());

      final t = task.createTime;

      final date =
          '${t.year}'
          '${t.month.toString().padLeft(2, '0')}'
          '${t.day.toString().padLeft(2, '0')}_'
          '${t.hour.toString().padLeft(2, '0')}'
          '${t.minute.toString().padLeft(2, '0')}'
          '${t.second.toString().padLeft(2, '0')}';

      final outputPath = p.join(tsDir.path, '$date.mp4');

      final success = await _executeMergeWithFallback(
        taskId: taskId,
        listFilePath: listFile.path,
        outputPath: outputPath,
        task: task,
      );

      if (success) {
        _controller.add(
          VideoProcessEvent(taskId: taskId, type: VideoProcessEventType.completed, outputPath: outputPath),
        );

        if (deleteSourceTs) {
          // Verify merged file validity before deleting source TS files
          final mergedFile = File(outputPath);
          if (mergedFile.existsSync() && mergedFile.lengthSync() > 1024) {
            _deleteTsFiles(tsDir, taskId);
          } else {
            log('$taskId: Merged MP4 verification failed, preserving TS sources.');
          }
        }
        return true;
      } else {
        _emitFailed(taskId, i18n("video_ffmpeg_failed"));
        return false;
      }
    } catch (e) {
      _emitFailed(taskId, e.toString());

      return false;
    } finally {
      _processingTasks.remove(taskId);
    }
  }

  /// Executes concat merge with stream-copy first, falling back to ultrafast transcode
  /// if stream parameters or timestamps mismatch across segments.
  Future<bool> _executeMergeWithFallback({
    required String taskId,
    required String listFilePath,
    required String outputPath,
    required LiveRecordTask task,
  }) async {
    // 1. Primary Attempt: High-speed Stream Copy with ADTS-to-ASC bitstream filter & PTS regeneration
    final fastCopyCmd = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'info',
      '-fflags',
      '+genpts+igndts',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      '"${listFilePath.replaceAll('"', r'\"')}"',
      '-c:v',
      'copy',
      '-c:a',
      'copy',
      '-bsf:a',
      'aac_adtstoasc',
      '-avoid_negative_ts',
      'make_zero',
      '-movflags',
      '+faststart',
      '"${outputPath.replaceAll('"', r'\"')}"',
    ].join(' ');

    final copyOk = await _runFfmpegMerge(
      taskId: 'merge_copy_$taskId',
      parentTaskId: taskId,
      command: fastCopyCmd,
      task: task,
    );

    final mergedFile = File(outputPath);
    if (copyOk && mergedFile.existsSync() && mergedFile.lengthSync() > 1024) {
      return true;
    }

    log('$taskId: Stream-copy concat merge failed or file too small, attempting fallback transcode...');

    // 2. Fallback Attempt: Ultrafast Transcode (handles codec parameter changes & broken PTS)
    if (mergedFile.existsSync()) {
      try {
        mergedFile.deleteSync();
      } catch (_) {}
    }

    final transcodeCmd = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'info',
      '-fflags',
      '+genpts+igndts',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      '"${listFilePath.replaceAll('"', r'\"')}"',
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-crf',
      '23',
      '-c:a',
      'aac',
      '-avoid_negative_ts',
      'make_zero',
      '-movflags',
      '+faststart',
      '"${outputPath.replaceAll('"', r'\"')}"',
    ].join(' ');

    final transcodeOk = await _runFfmpegMerge(
      taskId: 'merge_transcode_$taskId',
      parentTaskId: taskId,
      command: transcodeCmd,
      task: task,
    );

    return transcodeOk && mergedFile.existsSync() && mergedFile.lengthSync() > 1024;
  }

  Future<bool> _runFfmpegMerge({
    required String taskId,
    required String parentTaskId,
    required String command,
    required LiveRecordTask task,
  }) async {
    final completer = Completer<bool>();
    await _subscriptions[taskId]?.cancel();

    _subscriptions[taskId] = _ffmpeg.stream.listen((event) async {
      if (event.taskId != taskId) return;

      switch (event.type) {
        case FFmpegEventType.progress:
          final data = event.data;
          final time = (data['time'] ?? 0).toDouble();
          final duration = task.recordedSeconds <= 0 ? 1 : task.recordedSeconds * 1000;
          final progress = (time / duration).clamp(0.0, 1.0);
          _controller.add(
            VideoProcessEvent(taskId: parentTaskId, type: VideoProcessEventType.progress, progress: progress),
          );
          break;

        case FFmpegEventType.complete:
          await _subscriptions[taskId]?.cancel();
          _subscriptions.remove(taskId);
          if (!completer.isCompleted) completer.complete(true);
          break;

        case FFmpegEventType.error:
          await _subscriptions[taskId]?.cancel();
          _subscriptions.remove(taskId);
          if (!completer.isCompleted) completer.complete(false);
          break;

        default:
          break;
      }
    });

    try {
      await _ffmpeg.start(taskId: taskId, command: command);
      return await completer.future;
    } catch (e) {
      log('$taskId merge execution exception: $e');
      await _subscriptions[taskId]?.cancel();
      _subscriptions.remove(taskId);
      return false;
    }
  }

  void _deleteTsFiles(Directory dir, String taskId) {
    try {
      if (!dir.existsSync()) {
        return;
      }
      log('$taskId： ${i18n("video_delete_temp_files")}');
      for (final file in dir.listSync()) {
        if (file.path.endsWith('.ts') || file.path.endsWith('list.txt')) {
          file.deleteSync();
        }
      }
    } catch (_) {}
  }

  void _emitFailed(String taskId, String message) {
    _controller.add(VideoProcessEvent(taskId: taskId, type: VideoProcessEventType.failed, error: message));
  }

  @override
  void onClose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _controller.close();
    super.onClose();
  }
}

class VideoProcessEvent {
  final String taskId;

  final VideoProcessEventType type;

  final double progress;

  final String? outputPath;

  final String? error;

  const VideoProcessEvent({required this.taskId, required this.type, this.progress = 0, this.outputPath, this.error});
}

enum VideoProcessEventType { started, progress, completed, failed }
