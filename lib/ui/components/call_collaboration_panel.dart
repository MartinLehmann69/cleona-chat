import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/ui/components/whiteboard_canvas.dart';
import 'package:cleona/ui/components/call_chat_widget.dart';
import 'package:cleona/ui/components/shared_files_panel.dart';

/// Which collaboration panel is active.
enum CollaborationTab { whiteboard, files, chat, participants }

/// Main collaboration side panel for in-call use (Architecture S10.5.5).
///
/// Contains tabs for:
/// - Whiteboard (drawing canvas)
/// - Shared Files (file exchange + clipboard)
/// - Chat (ephemeral in-call messaging)
/// - Participants (member list)
class CallCollaborationPanel extends StatefulWidget {
  /// Initial active tab.
  final CollaborationTab initialTab;

  /// Whiteboard props
  final List<RenderStroke> whiteboardStrokes;
  final int currentPage;
  final int totalPages;
  final bool canClearAll;
  final void Function(WbTool tool, Color color, double width, double x,
      double y,
      {String? text,
      WbShape? shape})? onWbStrokeBegin;
  final void Function(double x, double y)? onWbStrokeUpdate;
  final void Function()? onWbStrokeEnd;
  final void Function()? onWbUndo;
  final void Function()? onWbRedo;
  final void Function()? onWbClearAll;
  final void Function()? onWbAddPage;
  final void Function(int pageIndex)? onWbSwitchPage;
  final void Function()? onWbExport;

  /// Chat props
  final List<ChatDisplayEntry> chatMessages;
  final int unreadChatCount;
  final void Function(String text, {String? replyToId})? onSendChatMessage;

  /// File props
  final List<FileDisplayEntry> sharedFiles;
  final void Function()? onShareFile;
  final void Function()? onPasteClipboard;
  final void Function(String fileId)? onDownloadFile;

  /// Participants
  final List<ParticipantDisplayEntry> participants;

  /// Screen sharing state
  final bool isScreenSharing;
  final String? screenSharerName;

  /// Close callback
  final VoidCallback? onClose;

  const CallCollaborationPanel({
    super.key,
    this.initialTab = CollaborationTab.whiteboard,
    this.whiteboardStrokes = const [],
    this.currentPage = 0,
    this.totalPages = 1,
    this.canClearAll = false,
    this.onWbStrokeBegin,
    this.onWbStrokeUpdate,
    this.onWbStrokeEnd,
    this.onWbUndo,
    this.onWbRedo,
    this.onWbClearAll,
    this.onWbAddPage,
    this.onWbSwitchPage,
    this.onWbExport,
    this.chatMessages = const [],
    this.unreadChatCount = 0,
    this.onSendChatMessage,
    this.sharedFiles = const [],
    this.onShareFile,
    this.onPasteClipboard,
    this.onDownloadFile,
    this.participants = const [],
    this.isScreenSharing = false,
    this.screenSharerName,
    this.onClose,
  });

  @override
  State<CallCollaborationPanel> createState() =>
      _CallCollaborationPanelState();
}

class _CallCollaborationPanelState extends State<CallCollaborationPanel> {
  late CollaborationTab _activeTab;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        _buildTabBar(context),

        // Active panel content
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final theme = Theme.of(context);
    final locale = AppLocale.read(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          _tabButton(CollaborationTab.whiteboard, Icons.brush,
              locale.tr('collab_whiteboard')),
          _tabButton(CollaborationTab.files, Icons.folder_shared,
              locale.tr('collab_files')),
          _tabButton(CollaborationTab.chat, Icons.chat, locale.tr('collab_chat'),
              badge: widget.unreadChatCount),
          _tabButton(CollaborationTab.participants, Icons.people,
              locale.tr('collab_participants')),
          const Spacer(),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _tabButton(CollaborationTab tab, IconData icon, String label,
      {int badge = 0}) {
    final isActive = _activeTab == tab;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => setState(() => _activeTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color:
                  isActive ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isActive ? FontWeight.bold : null,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badge',
                  style:
                      const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_activeTab) {
      case CollaborationTab.whiteboard:
        return WhiteboardCanvas(
          strokes: widget.whiteboardStrokes,
          currentPage: widget.currentPage,
          totalPages: widget.totalPages,
          canClearAll: widget.canClearAll,
          onStrokeBegin: widget.onWbStrokeBegin,
          onStrokeUpdate: widget.onWbStrokeUpdate,
          onStrokeEnd: widget.onWbStrokeEnd,
          onUndo: widget.onWbUndo,
          onRedo: widget.onWbRedo,
          onClearAll: widget.onWbClearAll,
          onAddPage: widget.onWbAddPage,
          onSwitchPage: widget.onWbSwitchPage,
          onExport: widget.onWbExport,
        );

      case CollaborationTab.files:
        return SharedFilesPanel(
          files: widget.sharedFiles,
          onShareFile: widget.onShareFile,
          onPasteClipboard: widget.onPasteClipboard,
          onDownloadFile: widget.onDownloadFile,
        );

      case CollaborationTab.chat:
        return CallChatWidget(
          messages: widget.chatMessages,
          onSendMessage: widget.onSendChatMessage,
        );

      case CollaborationTab.participants:
        return _buildParticipantsList();
    }
  }

  Widget _buildParticipantsList() {
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: widget.participants.length,
      itemBuilder: (_, i) {
        final p = widget.participants[i];
        return ListTile(
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              p.displayName.isNotEmpty
                  ? p.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontSize: 14,
              ),
            ),
          ),
          title:
              Text(p.displayName, style: theme.textTheme.bodyMedium),
          subtitle: Text(
            p.isOwn ? 'You' : p.state,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p.isMuted)
                Icon(Icons.mic_off,
                    size: 16, color: theme.colorScheme.error),
              if (p.isScreenSharing)
                Icon(Icons.screen_share,
                    size: 16, color: theme.colorScheme.primary),
            ],
          ),
        );
      },
    );
  }
}

/// Display data for a call participant.
class ParticipantDisplayEntry {
  final String nodeIdHex;
  final String displayName;
  final String state;
  final bool isOwn;
  final bool isMuted;
  final bool isScreenSharing;

  const ParticipantDisplayEntry({
    required this.nodeIdHex,
    required this.displayName,
    this.state = 'joined',
    this.isOwn = false,
    this.isMuted = false,
    this.isScreenSharing = false,
  });
}
