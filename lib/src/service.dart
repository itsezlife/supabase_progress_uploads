import 'package:cross_file/cross_file.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_progress_uploads/src/controller.dart';
import 'package:supabase_progress_uploads/src/logger.dart';
import 'package:supabase_progress_uploads/src/progress.dart';
import 'package:tusc/tusc.dart';
import 'package:uuid/uuid.dart';

class SupabaseUploadService {
  SupabaseUploadService(
    SupabaseClient supabase,
    String bucketName, {
    required this.supabaseAnonKey,
    this.enableDebugLogs = false,
    this.cacheControl = 3600,
    this.rootPath,
  }) : controller = SupabaseUploadController(
          supabase,
          bucketName,
          supabaseAnonKey: supabaseAnonKey,
          enableDebugLogs: enableDebugLogs,
          cacheControl: cacheControl,
          rootPath: rootPath,
        ) {
    'Initialized SupabaseUploadService with bucket: $bucketName'
        .logIf(enableDebugLogs);
  }

  final SupabaseUploadController controller;
  final String supabaseAnonKey;
  final bool enableDebugLogs;
  final int cacheControl;

  /// This is the path that will be used to store the uploaded files.
  ///
  /// If not provided, the root path will be the user's ID.
  /// e.g if the user's ID is `123`, the files will be stored in the `123`
  /// folder.
  final String? rootPath;

  Future<String?> uploadFile(
    XFile file, {
    ProgressCallback? onUploadProgress,
  }) async {
    'Uploading file: ${file.name}'.logIf(enableDebugLogs);
    final fileId = const Uuid().v4().hashCode;
    'File registered with ID: $fileId'.logIf(enableDebugLogs);

    await controller.startUpload(
        file: file,
        fileId: fileId,
        onUploadProgress: (count, total, response) {
          final progress = count / total;
          'Upload progress for file ${file.name}: '
                  '${(progress * 100).toStringAsFixed(1)}%'
              .logIf(enableDebugLogs);
          onUploadProgress?.call(count, total, response);
        });

    final url = await controller.getUploadedUrl(fileId);
    'Upload completed for ${file.name}. URL: $url'.logIf(enableDebugLogs);
    return url;
  }

  Future<List<String?>> uploadMultipleFiles(
    List<XFile> files, {
    ProgressCallback? onUploadProgress,
  }) async {
    'Starting multiple file upload for ${files.length} files'
        .logIf(enableDebugLogs);

    final fileIds = files.map((file) => const Uuid().v4().hashCode).toList();

    // Step 2: Create a map to track progress for each file.
    final progressMap = <int, ProgressResult>{};
    for (final id in fileIds) {
      progressMap[id] = const ProgressResult.empty();
    }

    // Step 3: Define a helper function to calculate and report total progress.
    void updateAndReportProgress(int fileId, ProgressResult progress) {
      progressMap[fileId] = progress;

      // Calculate total progress across all files
      var totalCount = 0;
      var totalSize = 0;

      for (final fileProgress in progressMap.values) {
        totalCount += fileProgress.count;
        totalSize += fileProgress.total;
      }

      final overallProgress = totalSize > 0 ? totalCount / totalSize : 0.0;

      'Total upload progress: ${(overallProgress * 100).toStringAsFixed(1)}%'
          .logIf(enableDebugLogs);

      onUploadProgress?.call(totalCount, totalSize, progress.response);
    }

    // Step 4: Start uploading files and track their progress.
    await Future.wait([
      for (var i = 0; i < files.length; i++)
        controller.startUpload(
          file: files[i],
          fileId: fileIds[i],
          onUploadProgress: (count, total, response) {
            'Upload progress for file ID ${fileIds[i]}: '
                    '${(count / total * 100).toStringAsFixed(1)}%'
                .logIf(enableDebugLogs);
            updateAndReportProgress(fileIds[i],
                ProgressResult(count: count, total: total, response: response));
          },
        ),
    ]);

    // Step 5: Retrieve and return upload URLs after uploads complete.
    final uploadUrls = await Future.wait(
      fileIds.map(controller.getUploadedUrl),
    );

    'Multiple file upload completed. Retrieved ${uploadUrls.length} URLs'
        .logIf(enableDebugLogs);
    return uploadUrls;
  }

  ProgressResult getUploadProgress(int fileId) {
    final progress = controller.getFileProgress(fileId);
    'Current progress for file ID '
            '$fileId: ${"${(progress.progress * 100).toStringAsFixed(1)}%"}'
        .logIf(enableDebugLogs);
    return progress;
  }

  Future<void> dispose() async {
    return controller.dispose();
  }
}
