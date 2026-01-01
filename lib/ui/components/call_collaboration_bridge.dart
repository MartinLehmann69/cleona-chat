// Translation layer between the §10.5 collaboration managers (on
// [GroupCallSession], created per session by [GroupCallManager] — see
// group_call_manager.dart `_initCollaboration`) and the display models
// that the pure display widgets expect (`RenderStroke`,
// `ChatDisplayEntry`, `FileDisplayEntry`, `ParticipantDisplayEntry`).
//
// S367 (`docs/v4-redesign/S367-unerreichbare-dateien.md` §3.5): ONLY this
// translation layer is built, deliberately still WITHOUT visible effect
// — no file in `lib/ui/screens/` imports this class. Reason: the
// send path of the four managers currently has no carrier
// (`call_collaboration_panel.dart` header comment, `call_transport_v41.dart`
// l. 451-468). A screen that calls this class would promise a
// delivery to other participants that does not exist yet. As soon as
// the group topology (§17.5, C-9/C-10/C-11) is decided, a
// screen only needs to import this class — the translation itself
// is finished and correct independently of the carrier.
import 'dart:ui' show Color, Offset;

import 'package:cleona/core/calls/collaboration/call_chat_manager.dart';
import 'package:cleona/core/calls/collaboration/call_file_manager.dart';
import 'package:cleona/core/calls/collaboration/whiteboard_manager.dart';
import 'package:cleona/core/calls/group_call_manager.dart';
import 'package:cleona/core/calls/group_call_session.dart';
import 'package:cleona/ui/components/call_chat_widget.dart' show ChatDisplayEntry;
import 'package:cleona/ui/components/call_collaboration_panel.dart'
    show ParticipantDisplayEntry;
import 'package:cleona/ui/components/shared_files_panel.dart' show FileDisplayEntry;
import 'package:cleona/ui/components/whiteboard_canvas.dart'
    show RenderStroke, WbShape, WbTool;

/// Reads the collaboration state of the current group call and hands it
/// back as the display models the panel widgets expect. Holds no state of
/// its own beyond the listener wrapper below — every getter recomputes from
/// the live managers, so a caller only needs to react to [onChanged].
class CallCollaborationBridge {
  final GroupCallManager manager;

  /// Fired whenever any of the getters below may return something new.
  /// Wraps [GroupCallManager.onCollaborationChanged] rather than replacing
  /// it, so an existing listener (present or future) keeps firing too.
  void Function()? onChanged;

  CallCollaborationBridge(this.manager) {
    final previous = manager.onCollaborationChanged;
    manager.onCollaborationChanged = () {
      previous?.call();
      onChanged?.call();
    };
  }

  GroupCallSession? get _session => manager.currentGroupCall;
  String get _ownHex => manager.identity.userIdHex;

  // ── Whiteboard ─────────────────────────────────────────────────────

  int get whiteboardCurrentPage => _session?.whiteboard?.currentPage ?? 0;
  int get whiteboardTotalPages => _session?.whiteboard?.totalPages ?? 1;

  /// Whether the local user may clear the current page. Mirrors the
  /// Owner/Admin-only rule from `WhiteboardManager`'s doc comment
  /// (Architecture S10.5.2) — there is no per-group role lookup on
  /// [GroupCallSession] yet, so this stays conservative (own calls only)
  /// until that lookup exists; see `docs/v4-redesign/S367-unerreichbare-dateien.md`.
  bool get whiteboardCanClearAll => _session?.isOwner(_ownHex) ?? false;

  List<RenderStroke> whiteboardStrokesForPage(int page) {
    final wb = _session?.whiteboard;
    if (wb == null) return const [];
    return wb.strokesForPage(page).map(_toRenderStroke).toList();
  }

  RenderStroke _toRenderStroke(WhiteboardStrokeData s) {
    final points = <Offset>[];
    for (var i = 0; i + 1 < s.points.length; i += 2) {
      points.add(Offset(s.points[i], s.points[i + 1]));
    }
    final shape = s.shapeType == null
        ? null
        : WbShape.values.byName(s.shapeType!.name);
    return RenderStroke(
      strokeId: s.strokeIdHex,
      tool: WbTool.values.byName(s.tool.name),
      color: Color(s.color),
      strokeWidth: s.strokeWidth,
      points: points,
      text: s.text,
      shape: shape,
      isComplete: s.isComplete,
      isOwn: s.authorIdHex == _ownHex,
    );
  }

  // ── Chat ───────────────────────────────────────────────────────────

  int get unreadChatCount => _session?.callChat?.unreadCount ?? 0;

  List<ChatDisplayEntry> get chatMessages {
    final chat = _session?.callChat;
    if (chat == null) return const [];
    return chat.messages.map((m) => _toChatEntry(m, chat)).toList();
  }

  ChatDisplayEntry _toChatEntry(CallChatEntry m, CallChatManager chat) {
    final replyToId = m.replyToId;
    final replyTo = replyToId == null ? null : chat.findMessage(replyToId);
    return ChatDisplayEntry(
      messageId: m.messageIdHex,
      senderName: m.senderName,
      text: m.text,
      timestamp: m.timestamp,
      isOwn: m.senderIdHex == _ownHex,
      replyToText:
          replyTo == null ? null : '${replyTo.senderName}: ${replyTo.text}',
    );
  }

  // ── Files ──────────────────────────────────────────────────────────

  List<FileDisplayEntry> get sharedFiles {
    final fm = _session?.fileManager;
    if (fm == null) return const [];
    return fm.sharedFiles.map(_toFileEntry).toList();
  }

  FileDisplayEntry _toFileEntry(SharedFileEntry f) => FileDisplayEntry(
        fileId: f.fileIdHex,
        fileName: f.fileName,
        fileSizeFormatted: f.fileSizeFormatted,
        mimeType: f.mimeType,
        thumbnailData: f.thumbnailData,
        sharedByName: f.sharedByName,
        sharedAt: f.sharedAt,
        isOwn: f.sharedByHex == _ownHex,
        downloadState: f.downloadState.name,
      );

  // ── Participants ───────────────────────────────────────────────────

  List<ParticipantDisplayEntry> get participants {
    final session = _session;
    if (session == null) return const [];
    final sharerHex = session.screenShare?.activeSharerHex;
    return session.participants.values
        .map((p) => ParticipantDisplayEntry(
              nodeIdHex: p.nodeIdHex,
              displayName: p.displayName,
              state: p.state.name,
              isOwn: p.nodeIdHex == _ownHex,
              isMuted: p.isMuted,
              isScreenSharing: sharerHex != null && sharerHex == p.nodeIdHex,
            ))
        .toList();
  }

  // ── Screen share ───────────────────────────────────────────────────

  bool get isScreenSharing => _session?.screenShare?.isSharing ?? false;
  String? get screenSharerName => _session?.screenShare?.activeSharerName;
}
