import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app/app_state_scope.dart';
import '../services/receipt_scan_service.dart';

typedef _Stage = ({IconData icon, String label, double target});

const List<_Stage> _stages = [
  (icon: Icons.upload_rounded, label: 'Uploading image…', target: 0.25),
  (icon: Icons.document_scanner_outlined, label: 'Analyzing receipt…', target: 0.55),
  (icon: Icons.text_fields_rounded, label: 'Extracting data…', target: 0.82),
  (icon: Icons.auto_awesome_outlined, label: 'Almost done…', target: 0.95),
];

class ScanReceiptScreen extends StatefulWidget {
  const ScanReceiptScreen({super.key, required this.recordType});

  final String recordType;

  @override
  State<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

class _ScanReceiptScreenState extends State<ScanReceiptScreen>
    with SingleTickerProviderStateMixin {
  bool _isScanning = false;
  int _stageIndex = 0;
  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _startProgress() {
    _stageIndex = 0;
    _progressController.value = 0;
    _advanceStage(0);
  }

  Future<void> _advanceStage(int index) async {
    if (!mounted || !_isScanning || index >= _stages.length) return;
    setState(() => _stageIndex = index);
    await _progressController.animateTo(
      _stages[index].target,
      duration: Duration(milliseconds: index == 0 ? 700 : 1400),
      curve: Curves.easeOut,
    );
    if (mounted && _isScanning && index < _stages.length - 1) {
      await Future.delayed(const Duration(milliseconds: 500));
      await _advanceStage(index + 1);
    }
  }

  Future<void> _pickAndScan(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (image == null || !mounted) return;
    await _runScan(image.path);
  }

  Future<void> _pickFileScan() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: kIsWeb,
      withReadStream: false,
    );
    final file = picked?.files.firstOrNull;
    if (file == null || !mounted) return;

    final path = file.path;
    final bytes = file.bytes;

    if (path == null && bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read the selected file. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await _runScan(path ?? file.name, bytes: bytes);
  }

  Future<void> _runScan(String filePath, {Uint8List? bytes}) async {
    setState(() => _isScanning = true);
    _startProgress();

    try {
      final appState = AppStateScope.of(context);
      final token = await appState.getValidAuthToken();
      if (token == null) throw Exception('Not logged in');

      final service = ReceiptScanService(
        baseUrl: 'https://crm.kokonuts.my',
        headers: _buildHeaders(appState, token),
      );
      final result = await service.scan(filePath, bytes: bytes);

      if (!mounted) return;

      setState(() => _stageIndex = _stages.length - 1);
      await _progressController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );

      if (!mounted) return;

      Navigator.of(context).pop({'result': result, 'filePath': filePath});
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      _progressController.value = 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Map<String, String> _buildHeaders(dynamic appState, String token) {
    final rawToken = ((appState.rawAuthToken as String?) ?? token).trim();
    final sanitized = token
        .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
        .trim();
    final authValue = rawToken
        .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
        .trim();
    return {
      'authtoken': authValue.isNotEmpty ? authValue : sanitized,
      'Authorization': 'Bearer $sanitized',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Receipt')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.document_scanner_outlined,
                    size: 80,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text('Scan a receipt', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Take a photo or choose from gallery to extract receipt data automatically.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isScanning
                          ? null
                          : () => _pickAndScan(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Take Photo'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isScanning
                          ? null
                          : () => _pickAndScan(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose from Gallery'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isScanning ? null : _pickFileScan,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Choose PDF / File'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isScanning)
            ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                            scale: animation,
                            child: FadeTransition(
                                opacity: animation, child: child),
                          ),
                          child: Icon(
                            _stages[_stageIndex].icon,
                            key: ValueKey(_stageIndex),
                            size: 52,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, _) {
                            final pct =
                                (_progressController.value * 100).toInt();
                            return Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _progressController.value,
                                    minHeight: 8,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '$pct%',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          child: Text(
                            _stages[_stageIndex].label,
                            key: ValueKey(_stageIndex),
                            style: theme.textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_stages.length, (i) {
                            final active = i == _stageIndex;
                            final done = i < _stageIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              width: active ? 22 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: (active || done)
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
