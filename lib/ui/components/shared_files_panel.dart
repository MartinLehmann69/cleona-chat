import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';

/// A file entry for display in the panel.
class FileDisplayEntry {
  final String fileId;
  final String fileName;
  final String fileSizeFormatted;
  final String mimeType;
  final Uint8List? thumbnailData;
  final String sharedByName;
  final DateTime sharedAt;
  final bool isOwn;
  final String downloadState; // "available", "downloading", "completed", "failed"

  const FileDisplayEntry({
    required this.fileId,
    required this.fileName,
    required this.fileSizeFormatted,
    required this.mimeType,
    this.thumbnailData,
    required this.sharedByName,
    required this.sharedAt,
    this.isOwn = false,
    this.downloadState = 'available',
  });
}

/// Shared files panel for in-call collaboration (Architecture S10.5.3).
class SharedFilesPanel extends StatelessWidget {
  final List<FileDisplayEntry> files;
  final void Function()? onShareFile;
  final void Function()? onPasteClipboard;
  final void Function(String fileId)? onDownloadFile;
  final VoidCallback? onClose;

  const SharedFilesPanel({
    super.key,
    required this.files,
    this.onShareFile,
    this.onPasteClipboard,
    this.onDownloadFile,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = AppLocale.read(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_shared,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(locale.tr('collab_files'), style: theme.textTheme.titleSmall),
                const Spacer(),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: Text(locale.tr('collab_share_file')),
                    onPressed: onShareFile,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.content_paste, size: 16),
                    label: Text(locale.tr('collab_paste_clipboard')),
                    onPressed: onPasteClipboard,
                  ),
                ),
              ],
            ),
          ),

          // File list
          Expanded(
            child: files.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Text(
                          locale.tr('collab_no_files'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: files.length,
                    itemBuilder: (_, i) => _buildFileTile(context, files[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileTile(BuildContext context, FileDisplayEntry file) {
    final theme = Theme.of(context);
    final icon = _mimeIcon(file.mimeType);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: file.thumbnailData != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(file.thumbnailData!,
                    width: 40, height: 40, fit: BoxFit.cover),
              )
            : Icon(icon, size: 32, color: theme.colorScheme.primary),
        title: Text(
          file.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Text(
          '${file.fileSizeFormatted} - ${file.sharedByName}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: _buildDownloadButton(context, file),
      ),
    );
  }

  Widget _buildDownloadButton(BuildContext context, FileDisplayEntry file) {
    if (file.isOwn) {
      return Icon(Icons.check_circle,
          size: 20, color: Theme.of(context).colorScheme.primary);
    }

    switch (file.downloadState) {
      case 'downloading':
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case 'completed':
        return Icon(Icons.check_circle,
            size: 20, color: Theme.of(context).colorScheme.primary);
      case 'failed':
        return IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: () => onDownloadFile?.call(file.fileId),
          color: Colors.red,
        );
      default:
        return IconButton(
          icon: const Icon(Icons.download, size: 20),
          onPressed: () => onDownloadFile?.call(file.fileId),
        );
    }
  }

  IconData _mimeIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.videocam;
    if (mimeType.startsWith('audio/')) return Icons.audiotrack;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('text')) return Icons.description;
    return Icons.insert_drive_file;
  }
}
