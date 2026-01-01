import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/ui/screens/call_screen.dart';
import 'package:cleona/ui/screens/group_call_screen.dart';
import 'package:cleona/ui/theme/skin.dart';
import 'package:cleona/ui/theme/skins.dart';
import 'package:cleona/ui/components/message_bubble.dart';
import 'package:cleona/ui/components/app_bar_scaffold.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/media/clipboard_helper.dart';
import 'package:cleona/core/media/link_preview_fetcher.dart';
import 'package:cleona/ui/components/poll_card.dart';
import 'package:cleona/ui/screens/poll_editor_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String displayName;
  final bool isGroup;
  final bool isChannel;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.displayName,
    this.isGroup = false,
    this.isChannel = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();

  // Edit mode state
  String? _editingMessageId;

  // Search state
  bool _isSearching = false;
  final _searchTextController = TextEditingController();
  String _chatSearchQuery = '';
  List<int> _searchMatchIndices = [];
  int _currentSearchIndex = -1;

  // Typing indicator: debounce sending
  DateTime? _lastTypingSent;
  ICleonaService? _cachedService;

  // Voice recording state
  bool _isRecording = false;
  DateTime? _recordingStartedAt;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  final AudioRecorder _recorder = AudioRecorder();

  // Drag & Drop state
  bool _isDragging = false;

  // Reply state
  UiMessage? _replyingToMessage;

  // Emoji picker state
  bool _showEmojiPicker = false;

  // Tracks the last rendered message count so build() can detect incoming
  // messages and auto-scroll to the bottom. A value of -1 means "first build
  // not yet run" — distinguishes it from the empty-conversation case where
  // length == 0 and we don't want to trigger scroll.
  int _lastRenderedMessageCount = -1;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    // Rebuild to toggle mic/send button when text changes
    _textController.addListener(() {
      if (mounted) setState(() {});
    });
    // Handle Enter-to-send and Ctrl+V on the TextField's own focus node.
    // onKeyEvent fires BEFORE TextInput processes the keystroke, so returning
    // KeyEventResult.handled prevents the newline from being inserted.
    _inputFocusNode.onKeyEvent = _handleInputKeyEvent;
    // Defer markRead to after first frame — scroll-to-bottom on first render
    // is driven by build() via _lastRenderedMessageCount, which handles the
    // lazy-layout race ListView.builder introduces for long histories.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cachedService = context.read<CleonaAppState>().service;
      _cachedService?.markConversationRead(widget.conversationId);
    });
  }

  /// Key handler for the message input field.
  /// Enter (without Shift) sends the message / saves edit.
  /// Shift+Enter inserts a newline (default TextField behaviour).
  /// Ctrl+V pastes from clipboard.
  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      final service = _cachedService;
      if (service != null) {
        if (_editingMessageId != null) {
          _saveEdit(service);
        } else {
          _send(service);
        }
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isControlPressed) {
      final service = _cachedService;
      if (service != null) _pasteFromClipboard(service);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _searchTextController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _recorder.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  /// Returns the subtitle as a plain [String] for use with [AppBarScaffold].
  String? _buildSubtitleText(BuildContext context, ICleonaService? service) {
    final locale = AppLocale.read(context);
    if (!widget.isGroup && !widget.isChannel && service is IpcClient) {
      if (service.isContactTyping(widget.conversationId)) {
        // Typing indicator — AppBarScaffold shows it as static text.
        // Search mode has no subtitle — the AppBar title is fully consumed by the search TextField.
        return locale.get('typing');
      }
    }
    if (widget.isChannel) {
      final channel = service?.channels[widget.conversationId];
      if (channel != null) {
        return locale.tr('subscribers_count', {'count': '${channel.members.length}'});
      }
    } else if (widget.isGroup) {
      final group = service?.groups[widget.conversationId];
      if (group != null) {
        return locale.tr('members_count', {'count': '${group.members.length}'});
      }
    } else {
      return widget.conversationId.substring(0, 16);
    }
    return null;
  }

  void _updateSearchResults(List<UiMessage> messages) {
    if (_chatSearchQuery.isEmpty) {
      _searchMatchIndices = [];
      _currentSearchIndex = -1;
      return;
    }
    final q = _chatSearchQuery.toLowerCase();
    _searchMatchIndices = [];
    for (var i = 0; i < messages.length; i++) {
      if (!messages[i].isDeleted && messages[i].text.toLowerCase().contains(q)) {
        _searchMatchIndices.add(i);
      }
    }
    if (_searchMatchIndices.isNotEmpty) {
      _currentSearchIndex = _searchMatchIndices.length - 1; // Start at latest match
      _scrollToMessage(_searchMatchIndices[_currentSearchIndex]);
    } else {
      _currentSearchIndex = -1;
    }
  }

  void _scrollToMessage(int index) {
    // Approximate: each message ~72px height
    final offset = index * 72.0;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _navigateSearchResult(int delta, List<UiMessage> messages) {
    if (_searchMatchIndices.isEmpty) return;
    setState(() {
      _currentSearchIndex = (_currentSearchIndex + delta) % _searchMatchIndices.length;
      if (_currentSearchIndex < 0) _currentSearchIndex = _searchMatchIndices.length - 1;
    });
    _scrollToMessage(_searchMatchIndices[_currentSearchIndex]);
  }

  void _onTextChanged() {
    if (_textController.text.isEmpty) return;
    final now = DateTime.now();
    // Debounce: max once per 3 seconds
    if (_lastTypingSent != null && now.difference(_lastTypingSent!).inSeconds < 3) return;
    _lastTypingSent = now;
    _cachedService?.sendTypingIndicator(widget.conversationId);
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final appState = context.watch<CleonaAppState>();
    final service = appState.service;
    final conv = service?.conversations[widget.conversationId];
    final messages = conv?.messages ?? [];

    // Auto-scroll on new incoming/outgoing messages while the chat is open.
    // Only scroll when the user is already near the bottom, so scrolled-up
    // reading of history isn't disturbed. The very first render (transition
    // from -1) also triggers a scroll so the initial view lands at the newest
    // message (ListView.builder's lazy maxScrollExtent makes the initState()
    // scroll unreliable for long histories).
    if (messages.length != _lastRenderedMessageCount) {
      final isFirstRender = _lastRenderedMessageCount < 0;
      final grew = messages.length > _lastRenderedMessageCount;
      _lastRenderedMessageCount = messages.length;
      if ((isFirstRender || grew) && (isFirstRender || _isNearBottom())) {
        _scrollToBottomAfterBuild();
      }
    }

    // Body content shared between normal and search scaffold variants.
    final chatBody = DropTarget(
      onDragDone: (details) async {
        for (final file in details.files) {
          final path = file.path;
          if (service != null) {
            await service.sendMediaMessage(widget.conversationId, path);
          }
        }
        _scrollToBottomAfterBuild();
      },
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      child: Stack(
        children: [
          Column(
            children: [
              // Pending DM config proposal banner (show when PEER proposed, not when WE proposed)
              if (!widget.isGroup && !widget.isChannel && conv?.pendingConfigProposal != null && conv?.pendingConfigProposer == widget.conversationId)
                _buildConfigProposalBanner(context, conv!, service),
              Expanded(
                child: _ChatBackground(
                  child: messages.isEmpty
                      ? Center(
                          child: Text(
                            locale.get('no_messages_yet'),
                            style: TextStyle(color: Theme.of(context).colorScheme.outline),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            final isHighlighted = _isSearching &&
                                _currentSearchIndex >= 0 &&
                                _currentSearchIndex < _searchMatchIndices.length &&
                                _searchMatchIndices[_currentSearchIndex] == index;
                            return _MessageBubble(
                              message: msg,
                              isEditing: _editingMessageId == msg.id,
                              isGroup: widget.isGroup || widget.isChannel,
                              senderDisplayName: _getSenderName(msg, service),
                              chatConfig: conv?.config,
                              onMessageAction: (action, m) => _handleMessageAction(action, m, service),
                              isSearchHighlight: isHighlighted,
                            );
                          },
                        ),
                ),
              ),
              _buildInputArea(context, service),
            ],
          ),
          if (_isDragging)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.file_upload, size: 64, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(locale.get('drop_files_here'),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    // Search mode: keep standard Scaffold+AppBar because the title area becomes
    // a full text-field widget, which AppBarScaffold (String-only title) does not
    // support. Body gets SafeArea(top:false) since the AppBar already covers top.
    if (_isSearching) {
      return Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchTextController,
                  autofocus: true,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: locale.get('search_messages'),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (v) {
                    setState(() => _chatSearchQuery = v.trim());
                    _updateSearchResults(messages);
                  },
                ),
              ),
              if (_searchMatchIndices.isNotEmpty)
                Text(
                  locale.tr('search_result_count', {
                    'current': '${_currentSearchIndex + 1}',
                    'total': '${_searchMatchIndices.length}',
                  }),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                onPressed: () => _navigateSearchResult(-1, messages),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                onPressed: () => _navigateSearchResult(1, messages),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() {
              _isSearching = false;
              _searchTextController.clear();
              _chatSearchQuery = '';
              _searchMatchIndices = [];
              _currentSearchIndex = -1;
            }),
          ),
          actions: const [],
        ),
        body: SafeArea(
          top: false, // AppBar handles top
          child: chatBody,
        ),
      );
    }

    // Normal mode: AppBarScaffold provides the skin-aware hero header.
    final actions = [
      IconButton(
        icon: const Icon(Icons.search),
        tooltip: locale.get('search_messages'),
        onPressed: () => setState(() => _isSearching = true),
      ),
      IconButton(
        icon: const Icon(Icons.tune),
        tooltip: locale.get('chat_settings'),
        onPressed: () => _showChatSettings(context, service),
      ),
      if (!widget.isGroup && !widget.isChannel)
        IconButton(
          icon: const Icon(Icons.call),
          tooltip: locale.get('call_tooltip'),
          onPressed: () => _startCall(context, appState),
        ),
      if (widget.isGroup)
        IconButton(
          icon: const Icon(Icons.call),
          tooltip: 'Gruppenanruf',
          onPressed: () => _startGroupCall(context, appState),
        ),
      // Bug #U7: AppBarScaffold renders actions in a plain Row without
      // overflow handling. On narrow Android screens (~360dp), 5 IconButtons
      // push rightmost actions (poll, info) off the visible edge, so members
      // could not reach the poll-create entry. Group & channel polls/info
      // now live in a single overflow menu that always fits.
      if (widget.isGroup || widget.isChannel)
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: locale.get('more_options'),
          onSelected: (v) {
            if (v == 'poll') _openPollEditor(context);
            if (v == 'info' && widget.isGroup) _showGroupInfo(context, service);
            if (v == 'info' && widget.isChannel) _showChannelInfo(context, service);
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'poll',
              child: Row(children: [
                const Icon(Icons.poll),
                const SizedBox(width: 12),
                Text(locale.get('poll_create')),
              ]),
            ),
            PopupMenuItem(
              value: 'info',
              child: Row(children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 12),
                Text(locale.get(widget.isGroup ? 'group_info' : 'channel_info')),
              ]),
            ),
          ],
        ),
    ];

    return AppBarScaffold(
      title: widget.displayName,
      subtitle: _buildSubtitleText(context, service),
      leading: const BackButton(),
      actions: actions,
      body: chatBody,
    );
  }

  void _handleMessageAction(String action, UiMessage msg, ICleonaService? service) {
    if (service == null) return;

    switch (action) {
      case 'edit':
        setState(() {
          _editingMessageId = msg.id;
          _textController.text = msg.text;
        });
        break;
      case 'delete':
        _confirmDelete(msg, service);
        break;
      case 'download':
        service.acceptMediaDownload(widget.conversationId, msg.id);
        break;
      case 'forward':
        _showForwardPicker(msg, service);
        break;
      case 'save_media':
        _saveMediaToDownloads(msg);
        break;
      case 'copy_media':
        _copyMediaToClipboard(msg);
        break;
      case 'copy_text':
        Clipboard.setData(ClipboardData(text: msg.text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Text copied'), duration: Duration(seconds: 1)),
          );
        }
        break;
      case 'reply':
        setState(() {
          _replyingToMessage = msg;
          _editingMessageId = null;
        });
        break;
      case 'react':
        _showReactionPicker(msg, service);
        break;
    }
  }

  Future<void> _saveMediaToDownloads(UiMessage msg) async {
    if (msg.filePath == null) return;
    final src = File(msg.filePath!);
    if (!src.existsSync()) return;

    // Determine download directory (configurable per-identity, Architecture 15.6.3)
    final customDir = _cachedService?.mediaSettings.downloadDirectory;
    final String downloadDirPath;
    if (customDir != null && customDir.isNotEmpty) {
      downloadDirPath = customDir;
    } else {
      final home = Platform.environment['HOME'] ?? '/tmp';
      downloadDirPath = Platform.isAndroid
          ? '/storage/emulated/0/Download'
          : '$home/Downloads';
    }
    final downloadDir = Directory(downloadDirPath);
    if (!downloadDir.existsSync()) downloadDir.createSync(recursive: true);

    final destPath = '${downloadDir.path}/${msg.filename ?? src.path.split('/').last}';

    // Self-copy protection: skip if source and destination are the same file
    if (File(destPath).existsSync()) {
      final srcResolved = src.resolveSymbolicLinksSync();
      final destResolved = File(destPath).resolveSymbolicLinksSync();
      if (srcResolved == destResolved) {
        if (mounted) {
          final locale = AppLocale.read(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(locale.tr('file_saved_to', {'path': destPath}))),
          );
        }
        return;
      }
    }

    await src.copy(destPath);

    if (mounted) {
      final locale = AppLocale.read(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.tr('file_saved_to', {'path': destPath}))),
      );
    }
  }

  Future<void> _copyMediaToClipboard(UiMessage msg) async {
    if (msg.filePath == null) return;
    final src = File(msg.filePath!);
    if (!src.existsSync()) return;

    // On Linux: use xclip/wl-copy for image clipboard
    if (Platform.isLinux) {
      final mimeType = msg.mimeType ?? 'image/png';
      // Try wl-copy first (Wayland), then xclip (X11)
      try {
        var result = await Process.run('wl-copy', ['--type', mimeType],
            stdoutEncoding: null, stderrEncoding: null);
        if (result.exitCode != 0) {
          result = await Process.run('xclip', ['-selection', 'clipboard', '-t', mimeType, '-i', msg.filePath!]);
        }
      } catch (_) {
        // Fallback: copy filename to clipboard
        await Clipboard.setData(ClipboardData(text: msg.filePath!));
      }
    } else {
      // Android/iOS: copy file path as text (system clipboard for images is complex)
      await Clipboard.setData(ClipboardData(text: msg.filePath!));
    }

    if (mounted) {
      final locale = AppLocale.read(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.get('copied_to_clipboard'))),
      );
    }
  }

  void _showForwardPicker(UiMessage msg, ICleonaService service) {
    final locale = AppLocale.read(context);
    // Build list of all contacts + groups + channels we can forward to
    final targets = <MapEntry<String, String>>[]; // id → displayName
    for (final c in service.acceptedContacts) {
      targets.add(MapEntry(c.nodeIdHex, c.displayName));
    }
    for (final g in service.groups.values) {
      targets.add(MapEntry(g.groupIdHex, '${g.name} (Gruppe)'));
    }
    for (final ch in service.channels.values) {
      // Only show channels where we can post
      final myRole = ch.members[service.nodeIdHex]?.role ?? 'subscriber';
      if (myRole == 'owner' || myRole == 'admin') {
        targets.add(MapEntry(ch.channelIdHex, '${ch.name} (Channel)'));
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('forward_to')),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView.builder(
            itemCount: targets.length,
            itemBuilder: (_, i) {
              final target = targets[i];
              return ListTile(
                title: Text(target.value),
                onTap: () {
                  Navigator.pop(ctx);
                  service.forwardMessage(widget.conversationId, msg.id, target.key);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(locale.get('cancel')),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(UiMessage msg, ICleonaService service) {
    final locale = AppLocale.read(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('delete_message_title')),
        content: Text(locale.get('delete_message_content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              service.deleteMessage(widget.conversationId, msg.id);
            },
            child: Text(locale.get('delete')),
          ),
        ],
      ),
    );
  }

  void _cancelEdit() {
    setState(() {
      _editingMessageId = null;
      _textController.clear();
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  void _showReactionPicker(UiMessage msg, ICleonaService? service) {
    if (service == null) return;
    // Quick-reactions row (most used) + full picker below
    const quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏', '🔥', '👏', '🎉', '💯'];
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        void react(String emoji) {
          Navigator.of(ctx).pop();
          final alreadyReacted = msg.reactions[emoji]?.contains(service.nodeIdHex) ?? false;
          service.sendReaction(
            conversationId: widget.conversationId,
            messageId: msg.id,
            emoji: emoji,
            remove: alreadyReacted,
          );
        }
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Quick-reaction row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: quickEmojis.map((emoji) {
                    final selected = msg.reactions[emoji]?.contains(service.nodeIdHex) ?? false;
                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => react(emoji),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: selected ? BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ) : null,
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              // Full emoji picker
              SizedBox(
                height: 300,
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) => react(emoji.emoji),
                  config: Config(
                    height: 300,
                    emojiViewConfig: EmojiViewConfig(
                      columns: 8,
                      emojiSizeMax: 28.0 * (Platform.isAndroid ? 1.2 : 1.0),
                      backgroundColor: colorScheme.surface,
                    ),
                    searchViewConfig: SearchViewConfig(
                      backgroundColor: colorScheme.surface,
                      buttonIconColor: colorScheme.primary,
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: colorScheme.surface,
                      iconColorSelected: colorScheme.primary,
                      indicatorColor: colorScheme.primary,
                      iconColor: colorScheme.onSurfaceVariant,
                    ),
                    bottomActionBarConfig: const BottomActionBarConfig(
                      enabled: false,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _canPostInChannel(ICleonaService? service) {
    if (!widget.isChannel || service == null) return true;
    final channel = service.channels[widget.conversationId];
    if (channel == null) return false;
    final myRole = channel.members[service.nodeIdHex]?.role ?? 'subscriber';
    return myRole == 'owner' || myRole == 'admin';
  }

  Widget _buildInputArea(BuildContext context, ICleonaService? service) {
    final locale = AppLocale.read(context);
    // Subscribers can't post in channels
    if (widget.isChannel && !_canPostInChannel(service)) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Center(
          child: Text(
            locale.get('only_owner_admin_can_post'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    final isEditing = _editingMessageId != null;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEditing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(locale.get('editing_message'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _cancelEdit,
                    child: Icon(Icons.close, size: 16, color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            ),
          if (_replyingToMessage != null && !isEditing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.reply, size: 16, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_replyingToMessage!.senderNodeIdHex.isNotEmpty)
                          Text(
                            _replyingToMessage!.isOutgoing ? locale.get('you') : _getSenderName(_replyingToMessage!, service),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary),
                          ),
                        Text(
                          _replyingToMessage!.text.length > 100 ? '${_replyingToMessage!.text.substring(0, 100)}...' : _replyingToMessage!.text,
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelReply,
                    child: Icon(Icons.close, size: 16, color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            ),
          if (_isRecording) ...[
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _cancelRecording,
                  tooltip: locale.get('cancel'),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                const SizedBox(width: 8),
                Text(
                  '${_recordingDuration.inMinutes.toString().padLeft(2, '0')}:${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                IconButton.filled(
                  onPressed: () => _stopAndSendRecording(service),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                if (!isEditing) ...[
                  IconButton(
                    icon: Icon(_showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined),
                    tooltip: 'Emoji',
                    onPressed: () => setState(() { _showEmojiPicker = !_showEmojiPicker; }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: locale.get('attach_file'),
                    onPressed: () => _pickAndSendFile(service),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste),
                    tooltip: locale.get('paste_from_clipboard'),
                    onPressed: () => _pasteFromClipboard(service),
                  ),
                ],
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _inputFocusNode,
                    decoration: InputDecoration(
                      hintText: isEditing ? locale.get('message_hint_editing') : locale.get('message_hint'),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    maxLines: 4,
                    minLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                if (_textController.text.isEmpty && !isEditing)
                  IconButton(
                    icon: const Icon(Icons.mic),
                    tooltip: locale.get('voice_message'),
                    onPressed: _startRecording,
                  )
                else
                  IconButton.filled(
                    onPressed: () => isEditing ? _saveEdit(service) : _send(service),
                    icon: Icon(isEditing ? Icons.check : Icons.send),
                  ),
              ],
            ),
          ],
          if (_showEmojiPicker && !isEditing)
            _buildEmojiPickerPanel(),
        ],
      ),
    );
  }

  Widget _buildEmojiPickerPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 260,
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) {
          final cursor = _textController.selection.baseOffset;
          final text = _textController.text;
          if (cursor >= 0) {
            _textController.text = text.substring(0, cursor) + emoji.emoji + text.substring(cursor);
            _textController.selection = TextSelection.collapsed(offset: cursor + emoji.emoji.length);
          } else {
            _textController.text = text + emoji.emoji;
            _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
          }
          if (!Platform.isAndroid) {
            _inputFocusNode.requestFocus();
          }
        },
        config: Config(
          height: 260,
          emojiViewConfig: EmojiViewConfig(
            columns: 8,
            emojiSizeMax: 28.0 * (Platform.isAndroid ? 1.2 : 1.0),
            backgroundColor: colorScheme.surface,
          ),
          searchViewConfig: SearchViewConfig(
            backgroundColor: colorScheme.surface,
            buttonIconColor: colorScheme.primary,
          ),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: colorScheme.surface,
            iconColorSelected: colorScheme.primary,
            indicatorColor: colorScheme.primary,
            iconColor: colorScheme.onSurfaceVariant,
          ),
          bottomActionBarConfig: const BottomActionBarConfig(
            enabled: false,
          ),
        ),
      ),
    );
  }

  String _getSenderName(UiMessage msg, ICleonaService? service) {
    if (msg.isOutgoing || (!widget.isGroup && !widget.isChannel) || service == null) return '';
    // System messages (invites, role changes, etc.) have no sender
    if (msg.senderNodeIdHex.isEmpty) return '';
    if (widget.isChannel) {
      final channel = service.channels[widget.conversationId];
      if (channel != null) {
        final member = channel.members[msg.senderNodeIdHex];
        if (member != null) return member.displayName;
      }
    } else {
      final group = service.groups[widget.conversationId];
      if (group != null) {
        final member = group.members[msg.senderNodeIdHex];
        if (member != null) return member.displayName;
      }
    }
    final contact = service.getContact(msg.senderNodeIdHex);
    if (contact != null) return contact.displayName;
    return msg.senderNodeIdHex.substring(0, 8);
  }

  void _openPollEditor(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PollEditorScreen(
        conversationId: widget.conversationId,
        isGroup: widget.isGroup,
        isChannel: widget.isChannel,
      ),
    ));
  }

  void _showGroupInfo(BuildContext context, ICleonaService? service) {
    final locale = AppLocale.read(context);
    if (service == null) return;
    final group = service.groups[widget.conversationId];
    if (group == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.get('group_unavailable'))),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final currentGroup = service.groups[widget.conversationId];
          if (currentGroup == null) return const SizedBox();
          final myRole = currentGroup.members[service.nodeIdHex]?.role ?? 'member';
          final canManage = myRole == 'owner' || myRole == 'admin';
          final isOwner = myRole == 'owner';

          return AlertDialog(
            title: Row(children: [
              const Icon(Icons.group),
              const SizedBox(width: 8),
              Expanded(child: Text(currentGroup.name)),
            ]),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(locale.tr('members_count', {'count': '${currentGroup.members.length}'}),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView(
                      shrinkWrap: true,
                      children: currentGroup.members.values.map((m) {
                        final isSelf = m.nodeIdHex == service.nodeIdHex;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            m.role == 'owner' ? Icons.star : m.role == 'admin' ? Icons.shield : Icons.person,
                            size: 20,
                            color: m.role == 'owner' ? Colors.amber : m.role == 'admin' ? Theme.of(context).colorScheme.primary : null,
                          ),
                          title: Text('${m.displayName}${isSelf ? " (Du)" : ""}'),
                          subtitle: Text(
                            m.role == 'owner' ? locale.get('role_owner') : m.role == 'admin' ? locale.get('role_admin') : locale.get('role_member'),
                            style: TextStyle(fontSize: 11, color: m.role == 'owner' ? Colors.amber.shade700 : null),
                          ),
                          trailing: !isSelf && canManage
                              ? PopupMenuButton<String>(
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  onSelected: (action) async {
                                    if (action == 'remove') {
                                      await service.removeMemberFromGroup(widget.conversationId, m.nodeIdHex);
                                      setDialogState(() {});
                                    } else if (action.startsWith('role_')) {
                                      final newRole = action.substring(5);
                                      await service.setMemberRole(widget.conversationId, m.nodeIdHex, newRole);
                                      setDialogState(() {});
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (isOwner && m.role != 'admin')
                                      PopupMenuItem(value: 'role_admin', child: Row(children: [
                                        const Icon(Icons.shield, size: 18), const SizedBox(width: 8), Text(locale.get('make_admin')),
                                      ])),
                                    if (isOwner && m.role != 'member')
                                      PopupMenuItem(value: 'role_member', child: Row(children: [
                                        const Icon(Icons.person, size: 18), const SizedBox(width: 8), Text(locale.get('make_member')),
                                      ])),
                                    if (isOwner)
                                      PopupMenuItem(value: 'role_owner', child: Row(children: [
                                        const Icon(Icons.star, size: 18, color: Colors.amber), const SizedBox(width: 8), Text(locale.get('transfer_ownership')),
                                      ])),
                                    if (canManage)
                                      PopupMenuItem(value: 'remove', child: Row(children: [
                                        const Icon(Icons.person_remove, size: 18, color: Colors.red),
                                        const SizedBox(width: 8),
                                        Text(locale.get('remove'), style: const TextStyle(color: Colors.red)),
                                      ])),
                                  ],
                                )
                              : null,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (canManage)
                TextButton.icon(
                  icon: const Icon(Icons.person_add, size: 18),
                  label: Text(locale.get('invite')),
                  onPressed: () {
                    final candidates = service.acceptedContacts
                        .where((c) => !currentGroup.members.containsKey(c.nodeIdHex))
                        .toList();
                    if (candidates.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(locale.get('all_contacts_in_group'))),
                      );
                      return;
                    }
                    showDialog(
                      context: context,
                      builder: (dlg) => AlertDialog(
                        title: Text(locale.get('invite_member')),
                        content: SizedBox(
                          width: 280,
                          child: ListView(
                            shrinkWrap: true,
                            children: candidates.map((c) => ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(c.displayName),
                              onTap: () async {
                                Navigator.pop(dlg);
                                await service.inviteToGroup(widget.conversationId, c.nodeIdHex);
                                setDialogState(() {});
                              },
                            )).toList(),
                          ),
                        ),
                        actions: [TextButton(onPressed: () => Navigator.pop(dlg), child: Text(locale.get('cancel')))],
                      ),
                    );
                  },
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(locale.get('cancel')),
              ),
              // Fix #U14: Destructive action gets Danger styling + confirmation
              // sub-dialog so "Leave" is no longer visually equivalent to "Cancel".
              FilledButton.icon(
                icon: const Icon(Icons.exit_to_app, size: 18),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                label: Text(locale.get('leave')),
                onPressed: () {
                  // Folgefix #U14: Owner-aware confirm body — warnt den Owner,
                  // dass die Ownership automatisch transferiert wird, und
                  // benennt das Transfer-Ziel (gleiche Logik wie in
                  // CleonaService.leaveGroup: erster Admin sonst erster
                  // verbleibender Member).
                  final bool iAmOwner = currentGroup.ownerNodeIdHex == service.nodeIdHex;
                  final Iterable<GroupMemberInfo> others = currentGroup.members.values
                      .where((m) => m.nodeIdHex != service.nodeIdHex);
                  String? ownerWarning;
                  if (iAmOwner) {
                    if (others.isEmpty) {
                      ownerWarning = locale.get('leave_last_member_warning');
                    } else {
                      final GroupMemberInfo target =
                          others.where((m) => m.role == 'admin').firstOrNull ?? others.first;
                      ownerWarning = locale.tr('leave_owner_warning', {'name': target.displayName});
                    }
                  }
                  showDialog(
                    context: ctx,
                    builder: (confirmCtx) => AlertDialog(
                      title: Text(locale.get('leave_group_title')),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(locale.tr('leave_confirm', {'name': currentGroup.name})),
                          if (ownerWarning != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              ownerWarning,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ],
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmCtx),
                          child: Text(locale.get('cancel')),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                          onPressed: () {
                            Navigator.pop(confirmCtx);
                            Navigator.pop(ctx);
                            service.leaveGroup(widget.conversationId);
                            Navigator.pop(context);
                          },
                          child: Text(locale.get('leave')),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showChannelInfo(BuildContext context, ICleonaService? service) {
    final locale = AppLocale.read(context);
    if (service == null) return;
    final channel = service.channels[widget.conversationId];
    if (channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.get('channel_unavailable'))),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final currentChannel = service.channels[widget.conversationId];
          if (currentChannel == null) return const SizedBox();
          final myRole = currentChannel.members[service.nodeIdHex]?.role ?? 'subscriber';
          final canManage = myRole == 'owner' || myRole == 'admin';
          final isOwner = myRole == 'owner';

          return AlertDialog(
            title: Row(children: [
              const Icon(Icons.campaign),
              const SizedBox(width: 8),
              Expanded(child: Text(currentChannel.name)),
            ]),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(locale.tr('members_count', {'count': '${currentChannel.members.length}'}),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView(
                      shrinkWrap: true,
                      children: currentChannel.members.values.map((m) {
                        final isSelf = m.nodeIdHex == service.nodeIdHex;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            m.role == 'owner' ? Icons.star : m.role == 'admin' ? Icons.shield : Icons.person,
                            size: 20,
                            color: m.role == 'owner' ? Colors.amber : m.role == 'admin' ? Theme.of(context).colorScheme.primary : null,
                          ),
                          title: Text('${m.displayName}${isSelf ? " (Du)" : ""}'),
                          subtitle: Text(
                            m.role == 'owner' ? locale.get('role_owner') : m.role == 'admin' ? locale.get('role_admin') : locale.get('role_subscriber'),
                            style: TextStyle(fontSize: 11, color: m.role == 'owner' ? Colors.amber.shade700 : null),
                          ),
                          trailing: !isSelf && canManage
                              ? PopupMenuButton<String>(
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  onSelected: (action) async {
                                    if (action == 'remove') {
                                      await service.removeFromChannel(widget.conversationId, m.nodeIdHex);
                                      setDialogState(() {});
                                    } else if (action.startsWith('role_')) {
                                      final newRole = action.substring(5);
                                      await service.setChannelRole(widget.conversationId, m.nodeIdHex, newRole);
                                      setDialogState(() {});
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (isOwner && m.role != 'admin')
                                      PopupMenuItem(value: 'role_admin', child: Row(children: [
                                        const Icon(Icons.shield, size: 18), const SizedBox(width: 8), Text(locale.get('make_admin')),
                                      ])),
                                    if (isOwner && m.role != 'subscriber')
                                      PopupMenuItem(value: 'role_subscriber', child: Row(children: [
                                        const Icon(Icons.person, size: 18), const SizedBox(width: 8), Text(locale.get('make_subscriber')),
                                      ])),
                                    if (isOwner)
                                      PopupMenuItem(value: 'role_owner', child: Row(children: [
                                        const Icon(Icons.star, size: 18, color: Colors.amber), const SizedBox(width: 8), Text(locale.get('transfer_ownership')),
                                      ])),
                                    if (canManage)
                                      PopupMenuItem(value: 'remove', child: Row(children: [
                                        const Icon(Icons.person_remove, size: 18, color: Colors.red),
                                        const SizedBox(width: 8),
                                        Text(locale.get('remove'), style: const TextStyle(color: Colors.red)),
                                      ])),
                                  ],
                                )
                              : null,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (canManage)
                TextButton.icon(
                  icon: const Icon(Icons.person_add, size: 18),
                  label: Text(locale.get('invite')),
                  onPressed: () {
                    final candidates = service.acceptedContacts
                        .where((c) => !currentChannel.members.containsKey(c.nodeIdHex))
                        .toList();
                    if (candidates.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(locale.get('all_contacts_in_channel'))),
                      );
                      return;
                    }
                    showDialog(
                      context: context,
                      builder: (dlg) => AlertDialog(
                        title: Text(locale.get('invite_subscriber')),
                        content: SizedBox(
                          width: 280,
                          child: ListView(
                            shrinkWrap: true,
                            children: candidates.map((c) => ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(c.displayName),
                              onTap: () async {
                                Navigator.pop(dlg);
                                await service.inviteToChannel(widget.conversationId, c.nodeIdHex);
                                setDialogState(() {});
                              },
                            )).toList(),
                          ),
                        ),
                        actions: [TextButton(onPressed: () => Navigator.pop(dlg), child: Text(locale.get('cancel')))],
                      ),
                    );
                  },
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(locale.get('cancel')),
              ),
              // Fix #U14: same treatment as group-info dialog — destructive
              // "Leave" now requires a confirmation so it cannot be confused
              // with the neutral dismiss action.
              FilledButton.icon(
                icon: const Icon(Icons.exit_to_app, size: 18),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                label: Text(locale.get('leave')),
                onPressed: () {
                  // Folgefix #U14 (symmetrisch zum Group-Leave): Channel-Owner
                  // wird vor Auto-Transfer der Owner-Rolle gewarnt. Transfer-
                  // Ziel-Logik mirrors CleonaService.leaveChannel (erster
                  // Admin sonst erster verbleibender Subscriber).
                  final bool iAmOwner = currentChannel.ownerNodeIdHex == service.nodeIdHex;
                  final Iterable<ChannelMemberInfo> others = currentChannel.members.values
                      .where((m) => m.nodeIdHex != service.nodeIdHex);
                  String? ownerWarning;
                  if (iAmOwner) {
                    if (others.isEmpty) {
                      ownerWarning = locale.get('leave_last_member_warning');
                    } else {
                      final ChannelMemberInfo target =
                          others.where((m) => m.role == 'admin').firstOrNull ?? others.first;
                      ownerWarning = locale.tr('leave_owner_warning', {'name': target.displayName});
                    }
                  }
                  showDialog(
                    context: ctx,
                    builder: (confirmCtx) => AlertDialog(
                      title: Text(locale.get('leave_channel_title')),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(locale.tr('leave_confirm', {'name': currentChannel.name})),
                          if (ownerWarning != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              ownerWarning,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ],
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmCtx),
                          child: Text(locale.get('cancel')),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                          onPressed: () {
                            Navigator.pop(confirmCtx);
                            Navigator.pop(ctx);
                            service.leaveChannel(widget.conversationId);
                            Navigator.pop(context);
                          },
                          child: Text(locale.get('leave')),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConfigProposalBanner(BuildContext context, Conversation conv, ICleonaService? service) {
    final locale = AppLocale.read(context);
    final proposal = conv.pendingConfigProposal!;
    final changes = <String>[];
    if (proposal.allowDownloads != conv.config.allowDownloads) {
      changes.add('${locale.get('allow_downloads')}: ${proposal.allowDownloads ? locale.get('on') : locale.get('off')}');
    }
    if (proposal.allowForwarding != conv.config.allowForwarding) {
      changes.add('${locale.get('allow_forwarding')}: ${proposal.allowForwarding ? locale.get('on') : locale.get('off')}');
    }
    if (proposal.editWindowMs != conv.config.editWindowMs) {
      changes.add('${locale.get('edit_window_label')}: ${_formatEditWindow(context, proposal.editWindowMs)}');
    }
    if (proposal.expiryDurationMs != conv.config.expiryDurationMs) {
      changes.add('${locale.get('auto_delete_label')}: ${_formatExpiry(context, proposal.expiryDurationMs)}');
    }
    final summary = changes.isEmpty ? locale.get('chat_settings') : changes.join(', ');

    return MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      content: Text(
        locale.tr('config_proposal_text', {'name': widget.displayName, 'summary': summary}),
        style: const TextStyle(fontSize: 13),
      ),
      leading: const Icon(Icons.tune, color: Colors.orange),
      actions: [
        TextButton(
          onPressed: () {
            service?.rejectConfigProposal(widget.conversationId);
          },
          child: Text(locale.get('reject')),
        ),
        FilledButton(
          onPressed: () {
            service?.acceptConfigProposal(widget.conversationId);
          },
          child: Text(locale.get('accept')),
        ),
      ],
    );
  }

  void _showChatSettings(BuildContext context, ICleonaService? service) {
    final locale = AppLocale.read(context);
    if (service == null) return;
    final conv = service.conversations[widget.conversationId];
    if (conv == null) return;

    // For groups/channels, owner or admin can change config
    final group = service.groups[widget.conversationId];
    final channel = service.channels[widget.conversationId];
    final myGroupRole = group?.members[service.nodeIdHex]?.role;
    final myChannelRole = channel?.members[service.nodeIdHex]?.role;
    final canEditGroup = myGroupRole == 'owner' || myGroupRole == 'admin';
    final canEditChannel = myChannelRole == 'owner' || myChannelRole == 'admin';
    final canEdit = (!widget.isGroup && !widget.isChannel) || canEditGroup || canEditChannel;
    final isDm = !widget.isGroup && !widget.isChannel;

    final config = ChatConfig(
      allowDownloads: conv.config.allowDownloads,
      allowForwarding: conv.config.allowForwarding,
      editWindowMs: conv.config.editWindowMs,
      expiryDurationMs: conv.config.expiryDurationMs,
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.tune),
            const SizedBox(width: 8),
            Text(locale.get('chat_settings')),
          ]),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: Text(locale.get('allow_downloads')),
                  subtitle: Text(locale.get('files_saveable')),
                  value: config.allowDownloads,
                  onChanged: canEdit ? (v) => setDialogState(() => config.allowDownloads = v) : null,
                ),
                SwitchListTile(
                  title: Text(locale.get('allow_forwarding')),
                  subtitle: Text(locale.get('messages_forwardable')),
                  value: config.allowForwarding,
                  onChanged: canEdit ? (v) => setDialogState(() => config.allowForwarding = v) : null,
                ),
                const Divider(),
                ListTile(
                  title: Text(locale.get('edit_window_label')),
                  subtitle: Text(_formatEditWindow(context, config.editWindowMs)),
                  trailing: canEdit ? PopupMenuButton<int?>(
                    onSelected: (v) => setDialogState(() => config.editWindowMs = v),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: null, child: Text(locale.get('default_1h'))),
                      PopupMenuItem(value: 5 * 60 * 1000, child: Text(locale.get('five_minutes'))),
                      PopupMenuItem(value: 15 * 60 * 1000, child: Text(locale.get('fifteen_minutes'))),
                      PopupMenuItem(value: 60 * 60 * 1000, child: Text(locale.get('one_hour'))),
                      PopupMenuItem(value: 0, child: Text(locale.get('disabled'))),
                    ],
                  ) : null,
                ),
                ListTile(
                  title: Text(locale.get('auto_delete_label')),
                  subtitle: Text(_formatExpiry(context, config.expiryDurationMs)),
                  trailing: canEdit ? PopupMenuButton<int?>(
                    onSelected: (v) => setDialogState(() => config.expiryDurationMs = v),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: null, child: Text(locale.get('off'))),
                      PopupMenuItem(value: 60 * 1000, child: Text(locale.get('one_minute'))),
                      PopupMenuItem(value: 5 * 60 * 1000, child: Text(locale.get('five_minutes'))),
                      PopupMenuItem(value: 60 * 60 * 1000, child: Text(locale.get('one_hour'))),
                      PopupMenuItem(value: 24 * 60 * 60 * 1000, child: Text(locale.get('one_day'))),
                      PopupMenuItem(value: 7 * 24 * 60 * 60 * 1000, child: Text(locale.get('seven_days'))),
                    ],
                  ) : null,
                ),
                SwitchListTile(
                  title: Text(locale.get('read_receipts')),
                  subtitle: Text(locale.get('read_status_visible')),
                  value: config.readReceipts,
                  onChanged: canEdit ? (v) => setDialogState(() => config.readReceipts = v) : null,
                ),
                SwitchListTile(
                  title: Text(locale.get('typing_indicator')),
                  subtitle: Text(locale.get('shows_when_typing')),
                  value: config.typingIndicators,
                  onChanged: canEdit ? (v) => setDialogState(() => config.typingIndicators = v) : null,
                ),
                if (!canEdit && (widget.isGroup || widget.isChannel))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      locale.get('only_owner_admin_can_change'),
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline, fontStyle: FontStyle.italic),
                    ),
                  ),
                if (isDm)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      locale.get('dm_config_proposal_note'),
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline, fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(locale.get('cancel')),
            ),
            if (canEdit)
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  service.updateChatConfig(widget.conversationId, config);
                },
                child: Text(isDm ? locale.get('propose') : locale.get('save')),
              ),
          ],
        ),
      ),
    );
  }

  String _formatEditWindow(BuildContext context, int? ms) {
    final locale = AppLocale.read(context);
    if (ms == null) return locale.get('default_1h');
    if (ms == 0) return locale.get('disabled');
    if (ms < 60 * 1000) return '${ms ~/ 1000} Sek';
    if (ms < 60 * 60 * 1000) return '${ms ~/ (60 * 1000)} Min';
    return '${ms ~/ (60 * 60 * 1000)} Std';
  }

  String _formatExpiry(BuildContext context, int? ms) {
    final locale = AppLocale.read(context);
    if (ms == null) return locale.get('off');
    if (ms < 60 * 1000) return '${ms ~/ 1000} Sek';
    if (ms < 60 * 60 * 1000) return '${ms ~/ (60 * 1000)} Min';
    if (ms < 24 * 60 * 60 * 1000) return '${ms ~/ (60 * 60 * 1000)} Std';
    return '${ms ~/ (24 * 60 * 60 * 1000)} Tage';
  }

  Future<void> _pickAndSendFile(ICleonaService? service) async {
    if (service == null) return;
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    if (widget.isGroup) {
      await service.sendMediaMessage(widget.conversationId, path);
    } else {
      await service.sendMediaMessage(widget.conversationId, path);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _saveEdit(ICleonaService? service) async {
    final newText = _textController.text.trim();
    final msgId = _editingMessageId;
    if (newText.isEmpty || service == null || msgId == null) return;

    _cancelEdit();
    // Fire-and-forget: don't block UI
    service.editMessage(widget.conversationId, msgId, newText).catchError((e) {
      debugPrint('Edit failed: $e');
      return false;
    });
  }

  Future<void> _startGroupCall(BuildContext context, CleonaAppState appState) async {
    final service = appState.service;
    if (service == null) return;

    final gcInfo = await service.startGroupCall(widget.conversationId);
    if (gcInfo != null && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: appState,
            child: GroupCallScreen(
              callInfo: gcInfo,
              groupName: widget.displayName,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _startCall(BuildContext context, CleonaAppState appState) async {
    final service = appState.service;
    if (service == null) return;

    final callInfo = await service.startCall(widget.conversationId);
    if (callInfo != null && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: appState,
            child: CallScreen(
              callInfo: callInfo,
              peerDisplayName: widget.displayName,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _send(ICleonaService? service) async {
    final text = _textController.text.trim();
    if (text.isEmpty || service == null) return;

    _textController.clear();

    // Capture reply state before clearing
    final replyMsg = _replyingToMessage;
    if (_replyingToMessage != null) {
      setState(() { _replyingToMessage = null; });
    }

    // Fire-and-forget: don't block UI waiting for crypto + network
    final Future<void> sendFuture;
    if (widget.isChannel) {
      sendFuture = service.sendChannelPost(widget.conversationId, text);
    } else if (widget.isGroup) {
      sendFuture = service.sendGroupTextMessage(widget.conversationId, text);
    } else {
      sendFuture = service.sendTextMessage(
        widget.conversationId, text,
        replyToMessageId: replyMsg?.id,
        replyToText: replyMsg != null ? (replyMsg.text.length > 200 ? replyMsg.text.substring(0, 200) : replyMsg.text) : null,
        replyToSender: replyMsg == null || replyMsg.isOutgoing ? null : _getSenderName(replyMsg, service),
      ).then((_) {});
    }
    // Log errors but don't block UI
    sendFuture.catchError((e) {
      debugPrint('Send failed: $e');
    });

    // Scroll to bottom after message appears
    _scrollToBottomAfterBuild();
  }

  // ── Voice Recording ──────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      final dir = Directory.systemTemp;
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() {
        _isRecording = true;
        _recordingStartedAt = DateTime.now();
        _recordingDuration = Duration.zero;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _recordingDuration = DateTime.now().difference(_recordingStartedAt!);
          });
        }
      });
    }
  }

  Future<void> _stopAndSendRecording(ICleonaService? service) async {
    _recordingTimer?.cancel();
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (path != null && service != null) {
      await service.sendMediaMessage(widget.conversationId, path);
      _scrollToBottomAfterBuild();
    }
  }

  void _cancelRecording() async {
    _recordingTimer?.cancel();
    await _recorder.stop();
    setState(() => _isRecording = false);
  }

  // ── Clipboard Paste (Ctrl+V or paste button) ──────────────────
  Future<void> _pasteFromClipboard(ICleonaService? service) async {
    if (service == null) return;

    final content = await ClipboardHelper.getContent();

    if (content.isEmpty) {
      if (mounted) {
        final locale = AppLocale.read(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(locale.get('clipboard_empty'))),
        );
      }
      return;
    }

    // Text content: insert into TextField (let system handle it for Ctrl+V)
    if (content.isText) {
      if (content.text != null) {
        final tc = _textController;
        final sel = tc.selection;
        final text = tc.text;
        if (sel.isValid) {
          tc.text = text.replaceRange(sel.start, sel.end, content.text!);
          tc.selection = TextSelection.collapsed(offset: sel.start + content.text!.length);
        } else {
          tc.text = text + content.text!;
          tc.selection = TextSelection.collapsed(offset: tc.text.length);
        }
      }
      return;
    }

    // Binary content: show confirmation dialog with preview
    if (!mounted) return;
    final confirmed = await _showPasteConfirmDialog(content);
    if (confirmed != true || !mounted) return;

    final tmpPath = await ClipboardHelper.saveToTempFile(content);
    if (tmpPath != null) {
      await service.sendMediaMessage(widget.conversationId, tmpPath);
      _scrollToBottomAfterBuild();
    }
  }

  Future<bool?> _showPasteConfirmDialog(ClipboardContent content) {
    final locale = AppLocale.read(context);

    // Determine type label and icon
    String typeLabel;
    IconData typeIcon;
    if (content.isImage) {
      typeLabel = locale.get('clipboard_image');
      typeIcon = Icons.image;
    } else if (content.isVideo) {
      typeLabel = locale.get('clipboard_video');
      typeIcon = Icons.videocam;
    } else if (content.isAudio) {
      typeLabel = locale.get('clipboard_audio');
      typeIcon = Icons.audiotrack;
    } else {
      typeLabel = locale.get('clipboard_file');
      typeIcon = Icons.insert_drive_file;
    }

    // Build image preview widget (from binary data or from file path)
    Widget? previewWidget;
    if (content.isImage) {
      if (content.data != null) {
        previewWidget = Image.memory(content.data!, fit: BoxFit.contain);
      } else if (content.filePath != null) {
        previewWidget = Image.file(File(content.filePath!), fit: BoxFit.contain);
      }
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('paste_confirm_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image preview (from memory or file)
            if (previewWidget != null)
              Container(
                constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(ctx).dividerColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: previewWidget,
                ),
              ),
            // Type + size
            Row(
              children: [
                Icon(typeIcon, size: 20, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('$typeLabel — ${content.sizeLabel}', overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            // Filename (especially useful for file-manager copies)
            if (content.suggestedFilename != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 28),
                    Expanded(
                      child: Text(
                        content.suggestedFilename!,
                        style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            // MIME type
            if (content.mimeType != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const SizedBox(width: 28),
                    Text(
                      content.mimeType!,
                      style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(locale.get('cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.send, size: 18),
            label: Text(locale.get('paste_confirm_send')),
          ),
        ],
      ),
    );
  }

  /// True if the scroll viewport is already at (or close to) the bottom.
  /// Returns `true` when the controller has no clients yet — that path is
  /// only hit during the very first render, where the desired behaviour is
  /// "scroll down" anyway.
  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    // 160px window: covers one bubble worth of slack so a user still counts as
    // "at bottom" right after sending a message, even if the new bubble
    // hasn't fully laid out yet.
    return pos.maxScrollExtent - pos.pixels < 160;
  }

  /// Scroll to the bottom after the next frame. ListView.builder lazily
  /// materialises items, so a single animateTo(maxScrollExtent) only reaches
  /// the extent of items that were built for the current viewport — not the
  /// real end of a long history. The repeated jumpTo below re-anchors at the
  /// bottom as more items build during each jump, until maxScrollExtent
  /// stabilises or the retry budget is exhausted.
  void _scrollToBottomAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _jumpToBottomRepeatedly(remainingAttempts: 4);
    });
  }

  void _jumpToBottomRepeatedly({required int remainingAttempts}) {
    if (!mounted || !_scrollController.hasClients) return;
    final before = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(before);
    if (remainingAttempts <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final after = _scrollController.position.maxScrollExtent;
      if (after > before + 0.5) {
        // More items have materialised — jump again until the extent settles.
        _jumpToBottomRepeatedly(remainingAttempts: remainingAttempts - 1);
      } else {
        // Stable. Final jump guarantees we sit on the true bottom even if the
        // last animate would otherwise leave us a fraction of a pixel short.
        _scrollController.jumpTo(after);
      }
    });
  }
}

// ── Video Player Widget ──────────────────────────────────────────
class _VideoPlayerWidget extends StatefulWidget {
  final String filePath;
  const _VideoPlayerWidget({required this.filePath});
  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Container(
        width: 240, height: 135,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final aspect = _controller.value.aspectRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 240,
        height: 240 / aspect,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller),
            // Play/Pause overlay
            GestureDetector(
              onTap: () {
                setState(() {
                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
              child: AnimatedOpacity(
                opacity: _controller.value.isPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white, size: 32,
                  ),
                ),
              ),
            ),
            // Duration bottom bar
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: VideoProgressIndicator(_controller, allowScrubbing: true,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Audio Player Widget ──────────────────────────────────────────
class _AudioPlayerWidget extends StatefulWidget {
  final String filePath;
  final bool isVoice;
  final String? filename;
  const _AudioPlayerWidget({required this.filePath, this.isVoice = false, this.filename});
  @override
  State<_AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<_AudioPlayerWidget> {
  final _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.setFilePath(widget.filePath).then((duration) {
      if (mounted && duration != null) setState(() => _duration = duration);
    });
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() => _playing = state.playing);
        if (state.processingState == ProcessingState.completed) {
          _player.seek(Duration.zero);
          _player.pause();
        }
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 240,
      child: Row(
        children: [
          IconButton(
            icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 36),
            color: colorScheme.primary,
            onPressed: () => _playing ? _player.pause() : _player.play(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: _duration.inMilliseconds > 0
                        ? _position.inMilliseconds / _duration.inMilliseconds
                        : 0,
                    onChanged: (v) => _player.seek(Duration(
                      milliseconds: (v * _duration.inMilliseconds).round(),
                    )),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(_position), style: TextStyle(fontSize: 10, color: colorScheme.outline)),
                      Text(_fmt(_duration), style: TextStyle(fontSize: 10, color: colorScheme.outline)),
                    ],
                  ),
                ),
                if (!widget.isVoice && widget.filename != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(widget.filename!, style: TextStyle(fontSize: 10, color: colorScheme.outline),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Image Fullscreen Viewer ──────────────────────────────────────
class _ImageViewer extends StatelessWidget {
  final String filePath;
  final String? filename;
  const _ImageViewer({required this.filePath, this.filename});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(filename ?? '', style: const TextStyle(fontSize: 14)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.file(File(filePath)),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final UiMessage message;
  final bool isEditing;
  final bool isGroup;
  final String senderDisplayName;
  final ChatConfig? chatConfig;
  final void Function(String action, UiMessage message)? onMessageAction;
  final bool isSearchHighlight;

  const _MessageBubble({
    required this.message,
    this.isEditing = false,
    this.isGroup = false,
    this.senderDisplayName = '',
    this.chatConfig,
    this.onMessageAction,
    this.isSearchHighlight = false,
  });

  /// Default edit window: 1 hour.
  static const _defaultEditWindowMs = 60 * 60 * 1000;

  bool get _canEdit {
    if (!message.isOutgoing || message.isDeleted) return false;
    final editWindowMs = chatConfig?.editWindowMs ?? _defaultEditWindowMs;
    if (editWindowMs == 0) return false; // editing disabled
    final ageMs = DateTime.now().millisecondsSinceEpoch - message.timestamp.millisecondsSinceEpoch;
    return ageMs <= editWindowMs;
  }

  bool get _canDelete => message.isOutgoing && !message.isDeleted;

  bool get _canForward => !message.isDeleted && (chatConfig?.allowForwarding ?? true);

  bool get _canSaveMedia => !message.isDeleted && message.isMedia &&
      message.filePath != null && (chatConfig?.allowDownloads ?? true);

  bool get _canCopyText => !message.isDeleted && message.text.isNotEmpty;

  bool get _canReply => !message.isDeleted;

  bool get _canReact => !message.isDeleted;

  bool get _hasMenu => _canEdit || _canDelete || _canForward || _canSaveMedia || _canCopyText || _canReply || _canReact;

  /// Shows the full action menu (reply / react / copy / save / forward / edit / delete)
  /// as a modal bottom sheet. Called from long-press on the MessageBubble path so that
  /// simple-text messages expose the same actions as the inline 3-dot PopupMenuButton.
  void _showMessageActions(BuildContext context) {
    if (!_hasMenu) return;
    final locale = AppLocale.read(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (_canReply)
                ListTile(
                  leading: const Icon(Icons.reply),
                  title: Text(locale.get('reply')),
                  onTap: () { Navigator.pop(sheetCtx); onMessageAction?.call('reply', message); },
                ),
              if (_canReact)
                ListTile(
                  leading: const Icon(Icons.add_reaction_outlined),
                  title: Text(locale.get('react')),
                  onTap: () { Navigator.pop(sheetCtx); onMessageAction?.call('react', message); },
                ),
              if (_canCopyText)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: Text(locale.get('copy_text')),
                  onTap: () { Navigator.pop(sheetCtx); onMessageAction?.call('copy_text', message); },
                ),
              if (_canSaveMedia)
                ListTile(
                  leading: const Icon(Icons.save_alt),
                  title: Text(locale.get('save_file')),
                  onTap: () { Navigator.pop(sheetCtx); onMessageAction?.call('save_media', message); },
                ),
              if (_canSaveMedia)
                ListTile(
                  leading: const Icon(Icons.copy_all),
                  title: Text(locale.get('copy_to_clipboard')),
                  onTap: () { Navigator.pop(sheetCtx); onMessageAction?.call('copy_media', message); },
                ),
              if (_canForward)
                ListTile(
                  leading: const Icon(Icons.forward),
                  title: Text(locale.get('forward')),
                  onTap: () { Navigator.pop(sheetCtx); onMessageAction?.call('forward', message); },
                ),
              if (_canEdit)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: Text(locale.get('edit')),
                  onTap: () { Navigator.pop(sheetCtx); onMessageAction?.call('edit', message); },
                ),
              if (_canDelete)
                ListTile(
                  leading: const Icon(Icons.delete),
                  title: Text(locale.get('delete')),
                  onTap: () { Navigator.pop(sheetCtx); onMessageAction?.call('delete', message); },
                ),
            ],
          ),
        );
      },
    );
  }

  static Skin _getActiveSkin() {
    final activeId = IdentityManager().getActiveIdentity();
    return Skins.byId(activeId?.skinId);
  }

  static double _activeSkinRadius(BuildContext context) => _getActiveSkin().borderRadius;
  static double _activeSkinBorderWidth(BuildContext context) => _getActiveSkin().borderWidth;
  static double _activeSkinElevation(BuildContext context) => _getActiveSkin().shadowElevation;

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final isOutgoing = message.isOutgoing;
    final colorScheme = Theme.of(context).colorScheme;
    final deleted = message.isDeleted;

    // System messages (e.g., member left)
    if (message.senderNodeIdHex.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            message.text,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.outline,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    // Simple plain-text messages: delegate to the design-system MessageBubble.
    // Complex message types (media, polls, deleted, link preview, forwarded,
    // search-highlight, edit mode, group sender label) retain the inline
    // implementation below because MessageBubble only handles plain text.
    final isSimpleText = !deleted &&
        !message.isMedia &&
        message.pollId == null &&
        !message.hasLinkPreview &&
        message.forwardedFrom == null &&
        !isEditing &&
        !isSearchHighlight &&
        !(isGroup && !isOutgoing && senderDisplayName.isNotEmpty);
    if (isSimpleText) {
      final ts = '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';
      final String? ticks = isOutgoing ? _statusTicksFor(message.status) : null;
      return MessageBubble(
        text: message.text,
        isOwn: isOutgoing,
        timestamp: ts,
        statusTicks: ticks,
        replyTo: message.replyToText,
        // reactions is Map<String,Set<String>>; MessageBubble takes List<String> emoji-only
        reactions: message.reactions.keys.toList(),
        onActionsPressed: _hasMenu
            ? () => _showMessageActions(context)
            : null,
        onLongPress: _hasMenu
            ? () => _showMessageActions(context)
            : null,
      );
    }

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isSearchHighlight
                ? colorScheme.tertiaryContainer
                : isEditing
                    ? colorScheme.primaryContainer.withValues(alpha: 0.6)
                    : deleted
                        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                        : isOutgoing
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(_activeSkinRadius(context)),
            border: isSearchHighlight
                ? Border.all(color: colorScheme.tertiary, width: 2)
                : isEditing
                    ? Border.all(color: colorScheme.primary, width: 1.5)
                    : _activeSkinBorderWidth(context) > 0
                        ? Border.all(color: colorScheme.outline.withValues(alpha: 0.3), width: _activeSkinBorderWidth(context))
                        : null,
            boxShadow: _activeSkinElevation(context) > 0
                ? [BoxShadow(color: colorScheme.shadow.withValues(alpha: 0.1), blurRadius: _activeSkinElevation(context) * 2, offset: Offset(0, _activeSkinElevation(context)))]
                : null,
          ),
          child: Stack(
            children: [
              if (_hasMenu)
                Positioned(
                  top: -8,
                  right: -8,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: Icon(Icons.more_vert, size: 16, color: colorScheme.outline),
                    onSelected: (action) => onMessageAction?.call(action, message),
                    itemBuilder: (_) => [
                      if (_canReply)
                        PopupMenuItem(value: 'reply', child: Row(children: [const Icon(Icons.reply, size: 18), const SizedBox(width: 8), Text(locale.get('reply'))])),
                      if (_canReact)
                        PopupMenuItem(value: 'react', child: Row(children: [const Icon(Icons.add_reaction_outlined, size: 18), const SizedBox(width: 8), Text(locale.get('react'))])),
                      if (_canCopyText)
                        PopupMenuItem(value: 'copy_text', child: Row(children: [const Icon(Icons.copy, size: 18), const SizedBox(width: 8), Text(locale.get('copy_text'))])),
                      if (_canSaveMedia)
                        PopupMenuItem(value: 'save_media', child: Row(children: [const Icon(Icons.save_alt, size: 18), const SizedBox(width: 8), Text(locale.get('save_file'))])),
                      if (_canSaveMedia)
                        PopupMenuItem(value: 'copy_media', child: Row(children: [const Icon(Icons.copy_all, size: 18), const SizedBox(width: 8), Text(locale.get('copy_to_clipboard'))])),
                      if (_canForward)
                        PopupMenuItem(value: 'forward', child: Row(children: [const Icon(Icons.forward, size: 18), const SizedBox(width: 8), Text(locale.get('forward'))])),
                      if (_canEdit)
                        PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit, size: 18), const SizedBox(width: 8), Text(locale.get('edit'))])),
                      if (_canDelete)
                        PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete, size: 18), const SizedBox(width: 8), Text(locale.get('delete'))])),
                    ],
                  ),
                ),
              Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.forwardedFrom != null && !deleted)
                Text(
                  locale.tr('forwarded_from', {'name': message.forwardedFrom!}),
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.outline),
                ),
              if (message.replyToText != null && !deleted)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: colorScheme.secondary, width: 2)),
                    color: colorScheme.secondaryContainer.withValues(alpha: 0.2),
                    borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.replyToSender != null && message.replyToSender!.isNotEmpty)
                        Text(message.replyToSender!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.secondary)),
                      Text(
                        message.replyToText!,
                        style: TextStyle(fontSize: 11, color: colorScheme.outline),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              if (isGroup && !isOutgoing && senderDisplayName.isNotEmpty && !deleted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    senderDisplayName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              if (deleted)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block, size: 14, color: colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(
                      locale.get('message_deleted'),
                      style: TextStyle(
                        color: colorScheme.outline,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                )
              else if (message.isMedia)
                _buildMediaContent(context)
              else if (message.pollId != null)
                PollCard(pollId: message.pollId!)
              else ...[
                _buildTextWithLinks(
                  message.text,
                  TextStyle(
                    color: isOutgoing
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface,
                    // Latin fonts FIRST so digits + ASCII land in a real text
                    // font; Emoji fonts AT THE END so they only kick in when
                    // the previous fonts have no glyph (real emoji codepoints).
                    // 'Roboto' alone wasn't enough — when Skia can't find it,
                    // it falls straight to the fallback list, picking the very
                    // first entry. That used to be Noto Color Emoji, which
                    // contains keycap-emoji glyphs for ASCII digits, hence the
                    // wide spacing.
                    fontFamily: 'Roboto',
                    fontFamilyFallback: const [
                      'Noto Sans',
                      'DejaVu Sans',
                      'Liberation Sans',
                      'Segoe UI',
                      'Helvetica',
                      'Arial',
                      'Noto Color Emoji',
                      'Segoe UI Emoji',
                      'Apple Color Emoji',
                    ],
                  ),
                  context,
                ),
                if (message.hasLinkPreview)
                  _buildLinkPreviewCard(context),
              ],
              if (message.reactions.isNotEmpty && !deleted)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: message.reactions.entries.map((entry) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${entry.key} ${entry.value.length}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.editedAt != null && !deleted) ...[
                    Text(
                      locale.get('edited'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                          fontSize: 10,
                        ),
                  ),
                  if (isOutgoing && !deleted) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _statusIcon(message.status),
                      size: 14,
                      color: _statusColor(message.status, colorScheme),
                    ),
                  ],
                ],
              ),
              ),
            ],
          ),
          ],
        ),
      ),
    );
  }

  // ── URL detection and clickable links ──────────────────────────
  static final _urlRegex = RegExp(
    r'https?://[^\s<>\[\]{}|\\^`"]+',
    caseSensitive: false,
  );

  Widget _buildTextWithLinks(String text, TextStyle style, BuildContext context) {
    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) return SelectableText(text, style: style);

    final spans = <InlineSpan>[];
    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      spans.add(WidgetSpan(
        child: InkWell(
          onTap: () => _openUrl(context, url),
          child: Text(url, style: style.copyWith(
            color: Colors.blue,
            decoration: TextDecoration.underline,
          )),
        ),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return SelectableText.rich(TextSpan(style: style, children: spans));
  }

  // ── Link Preview Card ─────────────────────────────────────────────────

  Widget _buildLinkPreviewCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final url = message.linkPreviewUrl!;
    final domain = Uri.tryParse(url)?.host ?? url;

    return GestureDetector(
      onTap: () => _openUrl(context, url),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withAlpha(128),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant.withAlpha(100)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            if (message.linkPreviewThumbnailBase64 != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150, maxWidth: double.infinity),
                child: Image.memory(
                  base64Decode(message.linkPreviewThumbnailBase64!),
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Site name
                  if (message.linkPreviewSiteName != null &&
                      message.linkPreviewSiteName!.isNotEmpty)
                    Text(
                      message.linkPreviewSiteName!,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  // Title
                  if (message.linkPreviewTitle != null)
                    Text(
                      message.linkPreviewTitle!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  // Description
                  if (message.linkPreviewDescription != null &&
                      message.linkPreviewDescription!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        message.linkPreviewDescription!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  // Domain
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      domain,
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── URL Opening with Incognito Support ────────────────────────────────

  void _openUrl(BuildContext context, String url) {
    final service = Provider.of<ICleonaService>(context, listen: false);
    final mode = service.linkPreviewSettings.browserOpenMode;

    switch (mode) {
      case BrowserOpenMode.normal:
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      case BrowserOpenMode.incognitoPreferred:
        _launchIncognito(url);
      case BrowserOpenMode.alwaysAsk:
        _showBrowserModeDialog(context, url);
    }
  }

  void _launchIncognito(String url) async {
    // Try platform-specific incognito launch
    if (Platform.isLinux) {
      // Try common Linux browsers in incognito mode
      for (final cmd in [
        ['xdg-open', url], // Fallback — no incognito, but works
        ['google-chrome', '--incognito', url],
        ['chromium-browser', '--incognito', url],
        ['firefox', '--private-window', url],
      ]) {
        try {
          final result = await Process.start(cmd[0], cmd.sublist(1),
              mode: ProcessStartMode.detached);
          result.stdout.drain();
          result.stderr.drain();
          return;
        } catch (_) {
          continue;
        }
      }
    } else if (Platform.isAndroid) {
      // Android: Chrome supports incognito via Intent extra
      // url_launcher doesn't support incognito, fallback to normal
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
    // Final fallback
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _showBrowserModeDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link öffnen'),
        content: Text(Uri.tryParse(url)?.host ?? url),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _launchIncognito(url);
            },
            child: const Text('Inkognito'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: const Text('Normal'),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent(BuildContext context) {
    final locale = AppLocale.read(context);
    final colorScheme = Theme.of(context).colorScheme;

    // Image with thumbnail or file preview
    if (message.isImage) {
      Widget? imageWidget;

      // Show actual file if downloaded
      if (message.filePath != null && File(message.filePath!).existsSync()) {
        imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(message.filePath!),
            width: 200,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 48),
          ),
        );
      } else if (message.thumbnailBase64 != null) {
        // Show thumbnail
        imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            base64Decode(message.thumbnailBase64!),
            width: 200,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.image, size: 48),
          ),
        );
      }

      // Wrap image with GestureDetector for fullscreen viewer
      if (imageWidget != null && message.filePath != null && File(message.filePath!).existsSync()) {
        imageWidget = GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _ImageViewer(filePath: message.filePath!, filename: message.filename)),
          ),
          child: imageWidget,
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?imageWidget,
          if (imageWidget == null)
            Container(
              width: 200,
              height: 100,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(child: Icon(Icons.image, size: 48)),
            ),
          if (message.mediaState == MediaDownloadState.announced)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _downloadButton(context),
            ),
          const SizedBox(height: 2),
          Text(
            message.filename ?? locale.get('image_fallback'),
            style: TextStyle(fontSize: 11, color: colorScheme.outline),
          ),
        ],
      );
    }

    // Video player
    if (message.isVideo) {
      if (message.filePath != null && File(message.filePath!).existsSync()) {
        return _VideoPlayerWidget(filePath: message.filePath!);
      }
      // Not yet downloaded
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 240, height: 135,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: Icon(Icons.videocam, size: 48)),
          ),
          if (message.mediaState == MediaDownloadState.announced)
            _downloadButton(context),
          Text(message.filename ?? 'Video', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
        ],
      );
    }

    // Audio player
    if (message.isAudio) {
      if (message.filePath != null && File(message.filePath!).existsSync()) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _AudioPlayerWidget(
              filePath: message.filePath!,
              isVoice: message.isVoiceMessage,
              filename: message.filename,
            ),
            if (message.transcriptText != null && message.transcriptText!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: Text(
                  message.transcriptText!,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface.withValues(alpha: 0.7)),
                ),
              ),
          ],
        );
      }
      // Audio not yet downloaded or file missing — show transcript if available
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(message.isVoiceMessage ? Icons.mic : Icons.audiotrack, size: 32, color: colorScheme.primary),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(message.filename ?? 'Audio', style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(_formatSize(message.fileSize ?? 0), style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                if (message.mediaState == MediaDownloadState.announced) _downloadButton(context),
              ]),
            ],
          ),
          if (message.transcriptText != null && message.transcriptText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Text(
                message.transcriptText!,
                style: TextStyle(fontSize: 13, color: colorScheme.onSurface.withValues(alpha: 0.7)),
              ),
            ),
        ],
      );
    }

    // Non-image file
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _fileIcon(message.mimeType ?? ''),
          size: 32,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.filename ?? locale.get('file_fallback'),
                style: const TextStyle(fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _formatSize(message.fileSize ?? 0),
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
              if (message.mediaState == MediaDownloadState.announced)
                _downloadButton(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _downloadButton(BuildContext context) {
    final locale = AppLocale.read(context);
    return TextButton.icon(
      onPressed: () {
        // Trigger download via the message action callback
        onMessageAction?.call('download', message);
      },
      icon: const Icon(Icons.download, size: 16),
      label: Text(locale.tr('download_button', {'size': _formatSize(message.fileSize ?? 0)})),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        textStyle: const TextStyle(fontSize: 12),
      ),
    );
  }

  IconData _fileIcon(String mimeType) {
    if (mimeType.startsWith('audio/')) return Icons.audiotrack;
    if (mimeType.startsWith('video/')) return Icons.videocam;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf;
    // Spezifische Office-Formate VOR dem generischen 'document' Check
    if (mimeType.contains('sheet') || mimeType.contains('excel')) return Icons.table_chart;
    if (mimeType.contains('presentation') || mimeType.contains('powerpoint')) return Icons.slideshow;
    if (mimeType.contains('word') || mimeType == 'application/msword') return Icons.description;
    // Generischer 'document' Fallback (z.B. ODF)
    if (mimeType.contains('document')) return Icons.description;
    if (mimeType.contains('zip') || mimeType.contains('archive') || mimeType.contains('compressed')) return Icons.folder_zip;
    if (mimeType.startsWith('text/')) return Icons.article;
    return Icons.insert_drive_file;
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _statusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return Icons.hourglass_empty;
      case MessageStatus.queued:
        return Icons.access_time;
      case MessageStatus.sent:
        return Icons.check;
      case MessageStatus.storedInNetwork:
        return Icons.cloud_done;
      case MessageStatus.delivered:
        return Icons.done_all;
      case MessageStatus.read:
        return Icons.done_all;
    }
  }

  Color? _statusColor(MessageStatus status, ColorScheme colorScheme) {
    if (status == MessageStatus.read) return Colors.blue;
    return colorScheme.outline;
  }

  /// Maps [MessageStatus] to a Unicode tick string for [MessageBubble.statusTicks].
  static String? _statusTicksFor(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return '⏳';
      case MessageStatus.queued:
        return '🕐';
      case MessageStatus.sent:
        return '✓';
      case MessageStatus.storedInNetwork:
        return '✓✓';
      case MessageStatus.delivered:
        return '✓✓';
      case MessageStatus.read:
        return '✓✓';
    }
  }
}

/// Chat background widget.
///
/// Pass-through — the AppBarScaffold now renders SkinSurface fullscreen
/// behind the entire body, so no extra background layer is needed here.
class _ChatBackground extends StatelessWidget {
  final Widget child;
  const _ChatBackground({required this.child});

  @override
  Widget build(BuildContext context) => child;
}
