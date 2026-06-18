import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../utils/platform_file_loader.dart';

const Set<String> allowedAttachmentExtensions = {
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'gif',
  'bmp',
  'heic',
  'webp',
};

bool isAllowedAttachmentExtension(String? extension) {
  final sanitized = extension?.toLowerCase();
  if (sanitized == null || sanitized.isEmpty) {
    return false;
  }
  return allowedAttachmentExtensions.contains(sanitized);
}

String? attachmentExtension(String name) {
  final index = name.lastIndexOf('.');
  if (index == -1 || index == name.length - 1) {
    return null;
  }
  return name.substring(index + 1).toLowerCase();
}

class AttachmentPicker extends StatefulWidget {
  const AttachmentPicker({
    this.label,
    required this.description,
    required this.files,
    required this.onPick,
    required this.onFilesSelected,
    required this.onFileRemoved,
    this.enablePreview = false,
  });

  final String? label;
  final String description;
  final List<PlatformFile> files;
  final VoidCallback onPick;
  final ValueChanged<List<PlatformFile>> onFilesSelected;
  final ValueChanged<PlatformFile> onFileRemoved;
  final bool enablePreview;

  @override
  State<AttachmentPicker> createState() => _AttachmentPickerState();
}

class _AttachmentPickerState extends State<AttachmentPicker> {
  bool _isDragging = false;
  bool _isProcessingDrop = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const iconSize = 24.0;
    final borderColor = _isDragging
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    final surfaceColor =
        _isDragging ? theme.colorScheme.primary.withOpacity(0.08) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null && widget.label!.isNotEmpty) ...[
          Text(widget.label!, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        DropTarget(
          onDragEntered: (_) => setState(() => _isDragging = true),
          onDragExited: (_) => setState(() => _isDragging = false),
          onDragDone: _handleDrop,
          child: InkWell(
            onTap: widget.onPick,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.2),
                color: surfaceColor,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 520;

                  final descriptionSection = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.description,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      if (widget.files.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (int i = 0; i < widget.files.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              SelectedFileChip(
                                file: widget.files[i],
                                onPreview: widget.enablePreview
                                    ? () => _previewFile(widget.files[i])
                                    : null,
                                onClear: () =>
                                    widget.onFileRemoved(widget.files[i]),
                              ),
                            ],
                          ],
                        )
                      else
                        Text(
                          'No files selected. Drag and drop here or tap to choose.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      if (_isProcessingDrop) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Processing dropped file...',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ],
                  );

                  final browseButton = OutlinedButton.icon(
                    onPressed: widget.onPick,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Browse files'),
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _isDragging
                                  ? Icons.file_upload
                                  : Icons.attach_file,
                              color: theme.colorScheme.primary,
                              size: iconSize,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: descriptionSection),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(left: iconSize + 12),
                          child: browseButton,
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _isDragging ? Icons.file_upload : Icons.attach_file,
                        color: theme.colorScheme.primary,
                        size: iconSize,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            descriptionSection,
                            const SizedBox(height: 12),
                            browseButton,
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleDrop(DropDoneDetails details) {
    if (details.files.isEmpty) {
      setState(() => _isDragging = false);
      return;
    }

    setState(() {
      _isDragging = false;
      _isProcessingDrop = true;
    });

    Future.wait(
      details.files
          .where((file) =>
              isAllowedAttachmentExtension(attachmentExtension(file.name)))
          .map(_convertFile),
    ).then((files) {
      if (!mounted) {
        return;
      }
      final validFiles = files.whereType<PlatformFile>().toList();
      if (validFiles.isNotEmpty) {
        widget.onFilesSelected([...widget.files, ...validFiles]);
      }
    }).whenComplete(() {
      if (mounted) {
        setState(() => _isProcessingDrop = false);
      }
    });
  }

  Future<PlatformFile?> _convertFile(XFile xfile) async {
    if (!isAllowedAttachmentExtension(attachmentExtension(xfile.name))) {
      return null;
    }
    try {
      final size = await xfile.length();
      final bytes = kIsWeb ? await xfile.readAsBytes() : null;
      return PlatformFile(
        name: xfile.name,
        size: size,
        path: xfile.path,
        readStream: kIsWeb ? null : xfile.openRead(),
        bytes: bytes,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _previewFile(PlatformFile file) async {
    final previewType = _resolveLocalPreviewType(file.name);
    if (previewType == null) {
      _showPreviewError('Preview not available for this file type.');
      return;
    }

    final bytes = await loadPlatformFileBytes(file);
    if (!mounted) return;

    if (bytes == null || bytes.isEmpty) {
      _showPreviewError('Unable to load the selected file for preview.');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => _LocalAttachmentPreviewDialog(
        fileName: file.name,
        bytes: bytes,
        previewType: previewType,
      ),
    );
  }

  void _showPreviewError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class SelectedFileChip extends StatelessWidget {
  const SelectedFileChip({
    required this.file,
    required this.onClear,
    this.onPreview,
  });

  final PlatformFile file;
  final VoidCallback onClear;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sizeLabel = _formatBytes(file.size);
    final truncatedName = _truncateFileName(file.name);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.surfaceVariant,
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$truncatedName ($sizeLabel)',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          if (onPreview != null)
            IconButton(
              tooltip: 'Preview attachment',
              icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
              onPressed: onPreview,
            ),
          IconButton(
            tooltip: 'Remove attachment',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[suffixIndex]}';
  }

  String _truncateFileName(String name, {int maxLength = 32}) {
    if (name.length <= maxLength) {
      return name;
    }

    final dotIndex = name.lastIndexOf('.');
    final extension = dotIndex != -1 ? name.substring(dotIndex) : '';
    final remainingLength = maxLength - extension.length - 3;

    if (remainingLength <= 0) {
      return '${name.substring(0, maxLength - 3)}...';
    }

    return '${name.substring(0, remainingLength)}...$extension';
  }
}

enum _LocalPreviewType { image, pdf }

_LocalPreviewType? _resolveLocalPreviewType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return _LocalPreviewType.pdf;

  for (final ext in ['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.heic']) {
    if (lower.endsWith(ext)) return _LocalPreviewType.image;
  }

  return null;
}

class _LocalAttachmentPreviewDialog extends StatelessWidget {
  const _LocalAttachmentPreviewDialog({
    required this.fileName,
    required this.bytes,
    required this.previewType,
  });

  final String fileName;
  final Uint8List bytes;
  final _LocalPreviewType previewType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget content;

    switch (previewType) {
      case _LocalPreviewType.image:
        content = InteractiveViewer(
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Unable to load image preview.'),
                  ),
                );
              },
            ),
          ),
        );
        break;
      case _LocalPreviewType.pdf:
        content = SfPdfViewer.memory(bytes);
        break;
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$fileName preview',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
