import 'dart:async';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Whiteboard tool types -- matches proto WhiteboardStroke.tool enum.
enum WhiteboardTool { pen, highlighter, eraser, text, shape, laser }

/// Shape types for the SHAPE tool -- matches proto WhiteboardStroke.shape_type.
enum WhiteboardShapeType { rectangle, circle, line, arrow }

/// Action types -- matches proto WhiteboardStroke.action_type.
enum WhiteboardActionType { strokeData, begin, points, end, clearAll, undo, redo }

/// A local stroke representation with rendering data.
class WhiteboardStrokeData {
  final Uint8List strokeId;
  final String authorIdHex;
  final String authorName;
  final WhiteboardTool tool;
  final int color; // ARGB
  final double strokeWidth;
  final List<double> points; // x,y pairs flattened
  final String? text;
  final WhiteboardShapeType? shapeType;
  final int pageIndex;
  final DateTime timestamp;
  bool isComplete;

  WhiteboardStrokeData({
    required this.strokeId,
    required this.authorIdHex,
    required this.authorName,
    required this.tool,
    required this.color,
    required this.strokeWidth,
    required this.points,
    this.text,
    this.shapeType,
    required this.pageIndex,
    required this.timestamp,
    this.isComplete = false,
  });

  String get strokeIdHex => bytesToHex(strokeId);
}

/// Manages whiteboard state and real-time stroke streaming for in-call collaboration.
///
/// Architecture S10.5.2:
/// - Multi-page canvas with synchronized page navigation
/// - Real-time stroke streaming (Begin -> Points every 50ms -> End)
/// - Late-join snapshot sync
/// - UNDO only own strokes, CLEAR_ALL needs Owner/Admin
class WhiteboardManager {
  final String ownUserIdHex;
  final String ownDisplayName;
  final String profileDir;
  final CLogger _log;

  /// Current page index.
  int currentPage = 0;

  /// Total number of pages.
  int totalPages = 1;

  /// All strokes organized by page index.
  final Map<int, List<WhiteboardStrokeData>> _pages = {0: []};

  /// Undo stack per page (own strokes only).
  final Map<int, List<WhiteboardStrokeData>> _undoStack = {};

  /// Active stroke being drawn (not yet complete).
  WhiteboardStrokeData? _activeStroke;

  /// Timer for streaming stroke points every 50ms.
  Timer? _streamTimer;

  /// Pending points to send in next stream batch.
  final List<double> _pendingPoints = [];

  /// Callback to send collaboration data to call participants.
  /// Signature: (proto.MessageTypeV3 type, Uint8List payload) -> void
  void Function(proto.MessageTypeV3 type, Uint8List payload)? onSendToAll;

  /// UI callback when strokes change (repaint needed).
  void Function()? onStrokesChanged;

  /// UI callback when page changes.
  void Function(int pageIndex, int totalPages)? onPageChanged;

  WhiteboardManager({
    required this.ownUserIdHex,
    required this.ownDisplayName,
    required this.profileDir,
  }) : _log = CLogger.get('whiteboard', profileDir: profileDir);

  /// All strokes on the current page.
  List<WhiteboardStrokeData> get currentStrokes =>
      List.unmodifiable(_pages[currentPage] ?? []);

  /// All strokes on a specific page.
  List<WhiteboardStrokeData> strokesForPage(int page) =>
      List.unmodifiable(_pages[page] ?? []);

  // -- Drawing API -------------------------------------------------------

  /// Begin a new stroke on the current page.
  void beginStroke({
    required WhiteboardTool tool,
    required int color,
    required double strokeWidth,
    required double x,
    required double y,
    String? text,
    WhiteboardShapeType? shapeType,
  }) {
    final strokeId = SodiumFFI().randomBytes(16);
    _activeStroke = WhiteboardStrokeData(
      strokeId: strokeId,
      authorIdHex: ownUserIdHex,
      authorName: ownDisplayName,
      tool: tool,
      color: color,
      strokeWidth: strokeWidth,
      points: [x, y],
      text: text,
      shapeType: shapeType,
      pageIndex: currentPage,
      timestamp: DateTime.now(),
    );

    // Add to page
    _pages.putIfAbsent(currentPage, () => []);
    _pages[currentPage]!.add(_activeStroke!);

    // Send BEGIN
    _sendStrokeAction(_activeStroke!, WhiteboardActionType.begin);

    // Start streaming timer for continuous points
    _pendingPoints.clear();
    _streamTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _flushPendingPoints();
    });

    // Laser: auto-remove after 2s
    if (tool == WhiteboardTool.laser) {
      final laserStroke = _activeStroke;
      Timer(const Duration(seconds: 2), () {
        _pages[currentPage]?.remove(laserStroke);
        onStrokesChanged?.call();
      });
    }

    onStrokesChanged?.call();
  }

  /// Add points to the active stroke (called on pointer move).
  void addPoints(double x, double y) {
    if (_activeStroke == null) return;
    _activeStroke!.points.addAll([x, y]);
    _pendingPoints.addAll([x, y]);
    onStrokesChanged?.call();
  }

  /// End the active stroke.
  void endStroke() {
    if (_activeStroke == null) return;
    _flushPendingPoints();
    _streamTimer?.cancel();
    _streamTimer = null;

    _activeStroke!.isComplete = true;
    _sendStrokeAction(_activeStroke!, WhiteboardActionType.end);
    _activeStroke = null;
    onStrokesChanged?.call();
  }

  /// Undo the last own stroke on the current page.
  void undo() {
    final strokes = _pages[currentPage];
    if (strokes == null || strokes.isEmpty) return;

    // Find last own stroke
    for (var i = strokes.length - 1; i >= 0; i--) {
      if (strokes[i].authorIdHex == ownUserIdHex) {
        final removed = strokes.removeAt(i);
        _undoStack.putIfAbsent(currentPage, () => []);
        _undoStack[currentPage]!.add(removed);

        // Send UNDO action
        _sendStrokeAction(removed, WhiteboardActionType.undo);
        onStrokesChanged?.call();
        return;
      }
    }
  }

  /// Redo the last undone own stroke on the current page.
  void redo() {
    final undone = _undoStack[currentPage];
    if (undone == null || undone.isEmpty) return;

    final stroke = undone.removeLast();
    _pages.putIfAbsent(currentPage, () => []);
    _pages[currentPage]!.add(stroke);

    _sendStrokeAction(stroke, WhiteboardActionType.redo);
    onStrokesChanged?.call();
  }

  /// Clear all strokes on the current page (Owner/Admin only).
  void clearAll() {
    _pages[currentPage]?.clear();
    _undoStack[currentPage]?.clear();

    final clearStroke = WhiteboardStrokeData(
      strokeId: SodiumFFI().randomBytes(16),
      authorIdHex: ownUserIdHex,
      authorName: ownDisplayName,
      tool: WhiteboardTool.pen,
      color: 0,
      strokeWidth: 0,
      points: [],
      pageIndex: currentPage,
      timestamp: DateTime.now(),
      isComplete: true,
    );
    _sendStrokeAction(clearStroke, WhiteboardActionType.clearAll);
    onStrokesChanged?.call();
  }

  // -- Page Management ---------------------------------------------------

  /// Add a new page.
  void addPage() {
    totalPages++;
    _pages[totalPages - 1] = [];

    final page = proto.WhiteboardPage()
      ..action = 0 // ADD_PAGE
      ..pageIndex = totalPages - 1
      ..totalPages = totalPages;
    onSendToAll?.call(
      proto.MessageTypeV3.MTV3_WHITEBOARD_PAGE,
      page.writeToBuffer(),
    );
    onPageChanged?.call(currentPage, totalPages);
  }

  /// Switch to a specific page.
  void switchPage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= totalPages) return;
    currentPage = pageIndex;

    final page = proto.WhiteboardPage()
      ..action = 1 // SWITCH_PAGE
      ..pageIndex = pageIndex
      ..totalPages = totalPages;
    onSendToAll?.call(
      proto.MessageTypeV3.MTV3_WHITEBOARD_PAGE,
      page.writeToBuffer(),
    );
    onPageChanged?.call(currentPage, totalPages);
    onStrokesChanged?.call();
  }

  /// Request a full snapshot for late joining.
  void requestSnapshot(String requesterIdHex) {
    final req = proto.WhiteboardPage()
      ..action = 2 // SNAPSHOT_REQUEST
      ..requesterId = hexToBytes(requesterIdHex);
    onSendToAll?.call(
      proto.MessageTypeV3.MTV3_WHITEBOARD_PAGE,
      req.writeToBuffer(),
    );
  }

  /// Send full snapshot response to a specific requester.
  void sendSnapshot() {
    for (var pageIdx = 0; pageIdx < totalPages; pageIdx++) {
      final strokes = _pages[pageIdx] ?? [];
      final page = proto.WhiteboardPage()
        ..action = 3 // SNAPSHOT_RESPONSE
        ..pageIndex = pageIdx
        ..totalPages = totalPages;

      for (final s in strokes) {
        page.strokes.add(_strokeToProto(s, WhiteboardActionType.strokeData));
      }

      onSendToAll?.call(
        proto.MessageTypeV3.MTV3_WHITEBOARD_PAGE,
        page.writeToBuffer(),
      );
    }
  }

  // -- Incoming Message Handling -----------------------------------------

  /// Handle incoming whiteboard stroke from a remote participant.
  void handleRemoteStroke(proto.WhiteboardStroke stroke) {
    final actionType = WhiteboardActionType.values[
        stroke.actionType.clamp(0, WhiteboardActionType.values.length - 1)];
    final pageIndex = stroke.pageIndex;
    final strokeIdHex = bytesToHex(Uint8List.fromList(stroke.strokeId));
    final authorIdHex = bytesToHex(Uint8List.fromList(stroke.authorId));

    // Ignore own echoed strokes
    if (authorIdHex == ownUserIdHex) return;

    switch (actionType) {
      case WhiteboardActionType.begin:
        final strokeData = _protoToStroke(stroke);
        _pages.putIfAbsent(pageIndex, () => []);
        _pages[pageIndex]!.add(strokeData);

      case WhiteboardActionType.points:
        // Find active stroke and append points
        final existing = _findStroke(pageIndex, strokeIdHex);
        if (existing != null) {
          existing.points.addAll(stroke.points.map((f) => f.toDouble()));
        }

      case WhiteboardActionType.end:
        final existing = _findStroke(pageIndex, strokeIdHex);
        if (existing != null) {
          existing.isComplete = true;
        }

      case WhiteboardActionType.clearAll:
        _pages[pageIndex]?.clear();

      case WhiteboardActionType.undo:
        // Remove the specified stroke from page
        _pages[pageIndex]?.removeWhere(
            (s) => s.strokeIdHex == strokeIdHex && s.authorIdHex == authorIdHex);

      case WhiteboardActionType.redo:
        final strokeData = _protoToStroke(stroke);
        _pages.putIfAbsent(pageIndex, () => []);
        _pages[pageIndex]!.add(strokeData);

      case WhiteboardActionType.strokeData:
        // Full stroke from snapshot
        final strokeData = _protoToStroke(stroke);
        strokeData.isComplete = true;
        _pages.putIfAbsent(pageIndex, () => []);
        _pages[pageIndex]!.add(strokeData);
    }

    onStrokesChanged?.call();
  }

  /// Handle incoming whiteboard page action.
  void handleRemotePage(proto.WhiteboardPage page) {
    switch (page.action) {
      case 0: // ADD_PAGE
        totalPages = page.totalPages;
        _pages.putIfAbsent(page.pageIndex, () => []);
        onPageChanged?.call(currentPage, totalPages);
      case 1: // SWITCH_PAGE
        // Don't force page switch -- only update the sender's view.
        // We just note that total pages may have changed.
        if (page.totalPages > totalPages) {
          totalPages = page.totalPages;
          onPageChanged?.call(currentPage, totalPages);
        }
      case 2: // SNAPSHOT_REQUEST
        // Someone needs a snapshot -- send it
        sendSnapshot();
      case 3: // SNAPSHOT_RESPONSE
        // Received a page snapshot
        if (page.totalPages > totalPages) {
          totalPages = page.totalPages;
        }
        _pages[page.pageIndex] = [];
        for (final s in page.strokes) {
          handleRemoteStroke(s);
        }
        onPageChanged?.call(currentPage, totalPages);
      default:
        _log.warn('Unknown whiteboard page action: ${page.action}');
    }
  }

  // -- Export ------------------------------------------------------------

  /// Get all stroke data for PNG export (called by UI layer).
  List<WhiteboardStrokeData> getExportStrokes(int pageIndex) =>
      List.unmodifiable(_pages[pageIndex] ?? []);

  // -- Cleanup -----------------------------------------------------------

  void dispose() {
    _streamTimer?.cancel();
    _pages.clear();
    _undoStack.clear();
    _activeStroke = null;
  }

  // -- Private Helpers ---------------------------------------------------

  void _flushPendingPoints() {
    if (_pendingPoints.isEmpty || _activeStroke == null) return;

    final stroke = proto.WhiteboardStroke()
      ..strokeId = _activeStroke!.strokeId
      ..authorId = hexToBytes(ownUserIdHex)
      ..actionType = WhiteboardActionType.points.index
      ..pageIndex = currentPage;
    stroke.points.addAll(_pendingPoints);

    onSendToAll?.call(
      proto.MessageTypeV3.MTV3_WHITEBOARD_STROKE,
      stroke.writeToBuffer(),
    );
    _pendingPoints.clear();
  }

  void _sendStrokeAction(
      WhiteboardStrokeData stroke, WhiteboardActionType action) {
    final protoStroke = _strokeToProto(stroke, action);
    onSendToAll?.call(
      proto.MessageTypeV3.MTV3_WHITEBOARD_STROKE,
      protoStroke.writeToBuffer(),
    );
  }

  proto.WhiteboardStroke _strokeToProto(
      WhiteboardStrokeData stroke, WhiteboardActionType action) {
    final p = proto.WhiteboardStroke()
      ..strokeId = stroke.strokeId
      ..authorId = hexToBytes(stroke.authorIdHex)
      ..authorName = stroke.authorName
      ..tool = stroke.tool.index
      ..color = stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..actionType = action.index
      ..pageIndex = stroke.pageIndex
      ..timestamp = Int64(stroke.timestamp.millisecondsSinceEpoch);

    p.points.addAll(stroke.points);
    if (stroke.text != null) p.text = stroke.text!;
    if (stroke.shapeType != null) p.shapeType = stroke.shapeType!.index;
    return p;
  }

  WhiteboardStrokeData _protoToStroke(proto.WhiteboardStroke s) {
    return WhiteboardStrokeData(
      strokeId: Uint8List.fromList(s.strokeId),
      authorIdHex: bytesToHex(Uint8List.fromList(s.authorId)),
      authorName: s.authorName,
      tool: WhiteboardTool
          .values[s.tool.clamp(0, WhiteboardTool.values.length - 1)],
      color: s.color,
      strokeWidth: s.strokeWidth,
      points: s.points.map((f) => f.toDouble()).toList(),
      text: s.text.isEmpty ? null : s.text,
      shapeType: s.tool == WhiteboardTool.shape.index || s.shapeType != 0
          ? WhiteboardShapeType.values[
              s.shapeType.clamp(0, WhiteboardShapeType.values.length - 1)]
          : null,
      pageIndex: s.pageIndex,
      timestamp: DateTime.fromMillisecondsSinceEpoch(s.timestamp.toInt()),
    );
  }

  WhiteboardStrokeData? _findStroke(int pageIndex, String strokeIdHex) {
    final strokes = _pages[pageIndex];
    if (strokes == null) return null;
    for (final s in strokes) {
      if (s.strokeIdHex == strokeIdHex) return s;
    }
    return null;
  }
}
