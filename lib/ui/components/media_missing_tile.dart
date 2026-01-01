// The tile a received file gets whose local copy is gone (S399 O-1).
//
// A file that was collected and acknowledged stays `delivered` at the sender
// and `completed` here (§9.2: the acknowledgement is final); it is never sent
// again (§9.3). When the copy on this device is lost afterwards — deleted
// outside the app, a damaged media store — the chat drew the fallbacks meant
// for a DIFFERENT fact, "not downloaded yet": the sender's transmission
// thumbnail, a grey video box, or the name and size of the file as if it
// were there. This tile says what is true: the file is no longer on this
// device.
//
// Split like `archive_placeholder_tile.dart` into a decision and a drawing:
//
//   [mediaLocalCopyLost] — pure, no widgets; the statement a probe measures.
//   [MediaMissingTile]   — the drawing; wording through [translate]
//                          (key `media_file_missing`, working rule 7).
//
// An ARCHIVED medium never reaches this: `chat_screen.dart` draws the
// archive tile first (§21.6), because that file is not lost but on the share.

import 'package:flutter/material.dart';

import 'package:cleona/core/service/service_types.dart'
    show MediaDownloadState, UiMessage;

/// Whether [m] is a received file that completed but whose local copy is
/// gone. [there] answers "is the attachment at this path" (encrypted or
/// plain, `MediaStore.existsEitherWay` in the app).
bool mediaLocalCopyLost(UiMessage m, bool Function(String path) there) {
  if (m.isOutgoing || !m.isMedia) return false;
  if (m.mediaState != MediaDownloadState.completed) return false;
  final path = m.filePath;
  return path == null || !there(path);
}

class MediaMissingTile extends StatelessWidget {
  final UiMessage message;
  final String Function(String key) translate;

  const MediaMissingTile(
      {super.key, required this.message, required this.translate});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = message.filename;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.hide_source, size: 32, color: colorScheme.outline),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (name != null && name.isNotEmpty)
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(
                translate('media_file_missing'),
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
