import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_progress_uploads/src/logger.dart';
import 'package:supabase_progress_uploads/src/progress.dart';
import 'package:tusc/tusc.dart';
import 'package:uuid/uuid.dart';

class SupabaseUploadController {
  SupabaseUploadController(
    this._supabase,
    this.bucketName, {
    required this.supabaseAnonKey,
    this.enableDebugLogs = false,
    this.cacheControl = 3600,
    this.rootPath,
    this.persistentCache = false,
    this.upsert = true,
  }) {
    'Initialized SupabaseUploadController for bucket: $bucketName'
        .logIf(enableDebugLogs);
  }
  final SupabaseClient _supabase;
  final String bucketName;
  final String supabaseAnonKey;
  final Map<int, TusClient> _clients = {};
  final Map<int, ProgressResult> _progressMap = {};
  final bool enableDebugLogs;
  final int cacheControl;
  final String? rootPath;
  final bool persistentCache;
  final bool upsert;

  final Map<int, Completer<String>> _urlCompleters = {};

  final _progressController = StreamController<ProgressResult>.broadcast();
  final _completionController = StreamController<int>.broadcast();
  static const _uuid = Uuid();

  Future<TusCache> get cache async => persistentCache
      ? TusPersistentCache(path.join(
          (await getTemporaryDirectory()).path, 'supabase_progress_uploads'))
      : TusMemoryCache();

  Stream<int> get completionStream => _completionController.stream;

  int generateFileId() => _uuid.v4().hashCode;

  Future<void> removeFile(int fileId) async {
    'Removing file with ID: $fileId'.logIf(enableDebugLogs);
    _clients.remove(fileId);
  }

  Future<String?> startUpload({
    required XFile file,
    int? fileId,
    String? fileName,
    String? contentType,
    int? chunkSize,
    ProgressCallback? onUploadProgress,
  }) async {
    final newFileId = fileId ?? generateFileId();

    // final accessToken =
    //     _supabase.auth.currentSession?.accessToken ?? supabaseAnonKey;

    final headers = {
      'x-upsert': upsert.toString(),
      ..._supabase.storage.from(bucketName).headers,
    };

    final userId = _supabase.auth.currentUser?.id;
    final filename = fileName ?? file.name;
    final $fileName = path.basename(filename);
    final fileType =
        file.mimeType ?? contentType ?? 'image/${file.extension()}';
    final objectName = _buildRootPath(userId, $fileName);

    _progressMap[newFileId] = const ProgressResult.empty();

    final metadata = {
      'bucketName': bucketName,
      'objectName': objectName,
      'contentType': fileType,
      'cacheControl': cacheControl,
    };

    final uploadUrl = '${_supabase.storage.url}/upload/resumable';
    final uri = Uri.parse(uploadUrl);
    final client = TusClient(
      file: file,
      url: uploadUrl,
      headers: headers,
      metadata: metadata,
      cache: await cache,
      chunkSize: chunkSize,
    );

    _clients[file.hashCode] = client;

    'Starting upload for file ID: $newFileId'.logIf(enableDebugLogs);

    // Create a completer for this upload
    _urlCompleters[newFileId] = Completer<String>();

    'Upload configuration - URI: $uri'.logIf(enableDebugLogs);
    'Upload metadata: $metadata'.logIf(enableDebugLogs);

    await client.startUpload(
      onProgress: (count, total, response) {
        'Progress: $count of $total | ${(count / total * 100).toInt()}%'
            .logIf(enableDebugLogs);

        onUploadProgress?.call(count, total, response);

        final progress =
            ProgressResult(count: count, total: total, response: response);
        _progressMap[newFileId] = progress;
        _progressController.add(progress);
      },
      onComplete: (response) {
        try {
          final publicUrl =
              _supabase.storage.from(bucketName).getPublicUrl(objectName);

          'Upload completed for file ID: $newFileId - URL: $publicUrl'
              .logIf(enableDebugLogs);

          final progress = _progressMap[newFileId]!;
          final completedProgress = progress.copyWith(
            count: progress.total,
            response: response,
          );

          _progressMap[newFileId] = completedProgress;
          _progressController.add(completedProgress);

          _urlCompleters[newFileId]!.complete(publicUrl);
          _completionController.add(newFileId);
        } catch (error, stackTrace) {
          if (enableDebugLogs) {
            dev.log(
              'Error completing upload for file ID: $newFileId ',
              error: error,
              stackTrace: stackTrace,
              name: 'supabase_progress_uploads',
            );
          }
        }
      },
    );

    return _urlCompleters[newFileId]!.future;
  }

  String _buildRootPath(String? userId, String fileName) {
    if (rootPath == null) {
      if (userId == null) return fileName;
      return '$userId/$fileName';
    }
    if (rootPath!.isEmpty) return fileName;
    return '$rootPath/$fileName';
  }

  void pauseUpload(int fileId) {
    'Pausing upload for file ID: $fileId'.logIf(enableDebugLogs);
    _clients[fileId]?.pauseUpload();
  }

  void resumeUpload(int fileId) {
    'Resuming upload for file ID: $fileId'.logIf(enableDebugLogs);
    _clients[fileId]?.resumeUpload();
  }

  Future<void> cancelUpload(int fileId) async {
    'Canceling upload for file ID: $fileId'.logIf(enableDebugLogs);
    await _clients[fileId]?.cancelUpload();
    _clients.remove(fileId);
    _progressMap.remove(fileId);
    _urlCompleters.remove(fileId);
  }

  ProgressResult getFileProgress(int fileId) {
    final progress = _progressMap[fileId] ?? const ProgressResult.empty();
    'Current progress for file ID '
            '$fileId: ${(progress.progress * 100).toStringAsFixed(1)}%'
        .logIf(enableDebugLogs);
    return progress;
  }

  Future<String?> getUploadedUrl(int fileId) async {
    'Retrieving uploaded URL for file ID: $fileId'.logIf(enableDebugLogs);
    if (_urlCompleters.containsKey(fileId)) {
      return _urlCompleters[fileId]?.future;
    }
    'No URL completer found for file ID: $fileId'.logIf(enableDebugLogs);
    return null;
  }

  Future<void> dispose() async {
    'Disposing SupabaseUploadController'.logIf(enableDebugLogs);
    for (final client in _clients.values) {
      await client.cancelUpload();
    }
    _clients.clear();
    _progressMap.clear();
    for (final completer in _urlCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError('Upload cancelled due to controller disposal');
      }
    }
    _urlCompleters.clear();
    await _progressController.close();
    await _completionController.close();
  }
}

/// {@template file_extension}
/// Extension on [File] to check if it is a video file.
/// {@endtemplate}
extension FileExtension on XFile {
  /// Returns [File] extension in `.xxx` format
  String extension({bool removeDot = true}) => path
      .extension(this.path)
      .toLowerCase()
      .replaceFirst(removeDot ? '.' : '', '');
}
