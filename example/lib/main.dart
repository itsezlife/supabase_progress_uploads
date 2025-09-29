import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_progress_uploads/supabase_progress_uploads.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: UploadExample());
  }
}

class UploadExample extends StatefulWidget {
  const UploadExample({super.key});

  @override
  _UploadExampleState createState() => _UploadExampleState();
}

class _UploadExampleState extends State<UploadExample> {
  final ImagePicker _picker = ImagePicker();
  late SupabaseUploadService _uploadService;
  late SupabaseUploadController _uploadController;
  ProgressResult _singleProgress = const ProgressResult.empty();
  ProgressResult _multipleProgress = const ProgressResult.empty();

  @override
  void initState() {
    super.initState();
    final supabase = Supabase.instance.client;
    supabase.auth.signInAnonymously();
    _uploadService = SupabaseUploadService(
      supabase,
      'your_bucket_name',
      supabaseAnonKey: 'your_supabase_anon_key',
    );
    _uploadController = SupabaseUploadController(
      supabase,
      'your_bucket_name',
      supabaseAnonKey: 'your_supabase_anon_key',
    );
  }

  Future<void> _uploadSingleFile() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      String? url = await _uploadService.uploadFile(
        image,
        onUploadProgress: (count, total, response) {
          setState(() => _singleProgress =
              ProgressResult(count: count, total: total, response: response));
        },
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('File Uploaded')));
      print('Uploaded file URL: $url');
    }
  }

  Future<void> _uploadMultipleFiles() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      List<String?> urls = await _uploadService.uploadMultipleFiles(
        images,
        onUploadProgress: (count, total, response) {
          setState(() => _multipleProgress =
              ProgressResult(count: count, total: total, response: response));
        },
      );

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Files Uploaded')));
      print('Uploaded files URLs: $urls');
    }
  }

  Future<void> _uploadWithController() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      int fileId = _uploadController.generateFileId();
      String? url = await _uploadController.startUpload(
        file: image,
        fileId: fileId,
        onUploadProgress: (count, total, response) {
          setState(() => _singleProgress =
              ProgressResult(count: count, total: total, response: response));
        },
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('File Uploaded')));
      print('Uploaded file URL: $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supabase Upload Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _uploadSingleFile,
              child: const Text('Upload Single File'),
            ),
            Text(
                'Single Progress: ${(_singleProgress.progress * 100).toStringAsFixed(2)}%'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _uploadMultipleFiles,
              child: const Text('Upload Multiple Files'),
            ),
            Text(
                'Multiple Progress: ${(_multipleProgress.progress * 100).toStringAsFixed(2)}%'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _uploadWithController,
              child: const Text('Upload with Controller'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _uploadService.dispose();
    super.dispose();
  }
}
