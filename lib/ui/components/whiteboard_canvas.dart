import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Whiteboard tool types (mirrors core enum).
enum WbTool { pen, highlighter, eraser, text, shape, laser }

/// Shape types (mirrors core enum).
enum WbShape { rectangle, circle, line, arrow }

/// A stroke for rendering.
class RenderStroke {
  final String strokeId;
  final WbTool tool;
  final Color color;
  final double strokeWidth;
  final List<Offset> points;
  final String? text;
  final WbShape? shape;
  final bool isComplete;
  final bool isOwn;

  const RenderStroke({
    required this.strokeId,
    required this.tool,
    required this.color,
    required this.strokeWidth,
    required this.points,
    this.text,
    this.shape,
    this.isComplete = false,
    this.isOwn = false,
  });
}

/// Shared whiteboard canvas with drawing tools (Architecture S10.5.2).
///
/// Features:
/// - Multi-touch drawing with CustomPainter
/// - Tools: PEN, HIGHLIGHTER, ERASER, TEXT, SHAPE, LASER
/// - Color picker with preset palette + custom color
/// - Multi-page support
/// - Export to PNG
class WhiteboardCanvas extends StatefulWidget {
  /// All strokes to render on the current page.
  final List<RenderStroke> strokes;

  /// Current page index.
  final int currentPage;

  /// Total number of pages.
  final int totalPages;

  /// Callbacks
  final void Function(WbTool tool, Color color, double width, double x,
      double y,
      {String? text,
      WbShape? shape})? onStrokeBegin;
  final void Function(double x, double y)? onStrokeUpdate;
  final void Function()? onStrokeEnd;
  final void Function()? onUndo;
  final void Function()? onRedo;
  final void Function()? onClearAll;
  final void Function()? onAddPage;
  final void Function(int pageIndex)? onSwitchPage;
  final void Function()? onExport;
  final void Function()? onClose;

  /// Whether the current user can clear all (Owner/Admin).
  final bool canClearAll;

  const WhiteboardCanvas({
    super.key,
    required this.strokes,
    this.currentPage = 0,
    this.totalPages = 1,
    this.onStrokeBegin,
    this.onStrokeUpdate,
    this.onStrokeEnd,
    this.onUndo,
    this.onRedo,
    this.onClearAll,
    this.onAddPage,
    this.onSwitchPage,
    this.onExport,
    this.onClose,
    this.canClearAll = false,
  });

  @override
  State<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends State<WhiteboardCanvas> {
  WbTool _currentTool = WbTool.pen;
  Color _currentColor = Colors.black;
  double _currentWidth = 3.0;
  bool _showColorPicker = false;

  static const _presetColors = [
    Colors.black,
    Colors.white,
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.pink,
    Colors.brown,
    Colors.grey,
    Colors.cyan,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        _buildToolbar(context),

        // Color picker overlay
        if (_showColorPicker) _buildColorPicker(context),

        // Canvas
        Expanded(
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: ClipRect(
              child: CustomPaint(
                painter: _WhiteboardPainter(strokes: widget.strokes),
                size: Size.infinite,
              ),
            ),
          ),
        ),

        // Page navigation
        _buildPageBar(context),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          // Tool buttons
          _toolButton(WbTool.pen, Icons.edit, 'Pen'),
          _toolButton(WbTool.highlighter, Icons.highlight, 'Highlighter'),
          _toolButton(WbTool.eraser, Icons.auto_fix_high, 'Eraser'),
          _toolButton(WbTool.text, Icons.text_fields, 'Text'),
          _toolButton(WbTool.shape, Icons.crop_square, 'Shape'),
          _toolButton(WbTool.laser, Icons.flashlight_on, 'Laser'),

          const SizedBox(width: 8),
          // Vertical divider
          Container(width: 1, height: 24, color: theme.dividerColor),
          const SizedBox(width: 8),

          // Color selector
          GestureDetector(
            onTap: () => setState(() => _showColorPicker = !_showColorPicker),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _currentColor,
                shape: BoxShape.circle,
                border: Border.all(color: theme.dividerColor, width: 2),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Stroke width slider
          SizedBox(
            width: 80,
            child: Slider(
              value: _currentWidth,
              min: 1,
              max: 20,
              onChanged: (v) => setState(() => _currentWidth = v),
            ),
          ),

          const Spacer(),

          // Actions
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            onPressed: widget.onUndo,
            tooltip: 'Undo',
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 20),
            onPressed: widget.onRedo,
            tooltip: 'Redo',
          ),
          if (widget.canClearAll)
            IconButton(
              icon: const Icon(Icons.delete_sweep, size: 20),
              onPressed: widget.onClearAll,
              tooltip: 'Clear all',
            ),
          IconButton(
            icon: const Icon(Icons.save_alt, size: 20),
            onPressed: widget.onExport,
            tooltip: 'Export PNG',
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _presetColors.map((color) {
          final isSelected = _currentColor == color;
          return GestureDetector(
            onTap: () => setState(() {
              _currentColor = color;
              _showColorPicker = false;
            }),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                  width: isSelected ? 3 : 1,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _toolButton(WbTool tool, IconData icon, String tooltip) {
    final isActive = _currentTool == tool;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: () => setState(() => _currentTool = tool),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
        ),
      ),
    );
  }

  Widget _buildPageBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: widget.currentPage > 0
                ? () => widget.onSwitchPage?.call(widget.currentPage - 1)
                : null,
          ),
          Text(
            '${widget.currentPage + 1} / ${widget.totalPages}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: widget.currentPage < widget.totalPages - 1
                ? () => widget.onSwitchPage?.call(widget.currentPage + 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: widget.onAddPage,
            tooltip: 'Add page',
          ),
        ],
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    final pos = details.localPosition;
    widget.onStrokeBegin?.call(
      _currentTool,
      _currentColor,
      _currentWidth,
      pos.dx,
      pos.dy,
    );
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final pos = details.localPosition;
    widget.onStrokeUpdate?.call(pos.dx, pos.dy);
  }

  void _onPanEnd(DragEndDetails details) {
    widget.onStrokeEnd?.call();
  }
}

/// CustomPainter that renders all strokes.
class _WhiteboardPainter extends CustomPainter {
  final List<RenderStroke> strokes;

  _WhiteboardPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    // White background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      switch (stroke.tool) {
        case WbTool.highlighter:
          paint.color = stroke.color.withValues(alpha: 0.4);
          paint.strokeWidth = stroke.strokeWidth * 3;
          _drawPath(canvas, stroke.points, paint);

        case WbTool.eraser:
          paint.color = Colors.white;
          paint.strokeWidth = stroke.strokeWidth * 2;
          paint.blendMode = BlendMode.srcOver;
          _drawPath(canvas, stroke.points, paint);

        case WbTool.text:
          if (stroke.text != null && stroke.points.isNotEmpty) {
            final textPainter = TextPainter(
              text: TextSpan(
                text: stroke.text!,
                style: TextStyle(
                  color: stroke.color,
                  fontSize: stroke.strokeWidth * 4,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            textPainter.paint(canvas, stroke.points.first);
          }

        case WbTool.shape:
          if (stroke.points.length >= 2) {
            _drawShape(canvas, stroke, paint);
          }

        case WbTool.laser:
          paint.color = Colors.red.withValues(alpha: 0.7);
          paint.strokeWidth = 3;
          _drawPath(canvas, stroke.points, paint);

        case WbTool.pen:
          _drawPath(canvas, stroke.points, paint);
      }
    }
  }

  void _drawPath(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length == 1) {
      canvas.drawCircle(points.first, paint.strokeWidth / 2, paint);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  void _drawShape(Canvas canvas, RenderStroke stroke, Paint paint) {
    final start = stroke.points.first;
    final end = stroke.points.last;
    final rect = Rect.fromPoints(start, end);

    switch (stroke.shape) {
      case WbShape.rectangle:
        canvas.drawRect(rect, paint);
      case WbShape.circle:
        canvas.drawOval(rect, paint);
      case WbShape.line:
        canvas.drawLine(start, end, paint);
      case WbShape.arrow:
        canvas.drawLine(start, end, paint);
        // Arrow head
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final angle = math.atan2(dy, dx);
        const arrowLength = 15.0;
        const arrowAngle = 0.5;
        canvas.drawLine(
          end,
          Offset(
            end.dx - arrowLength * math.cos(angle - arrowAngle),
            end.dy - arrowLength * math.sin(angle - arrowAngle),
          ),
          paint,
        );
        canvas.drawLine(
          end,
          Offset(
            end.dx - arrowLength * math.cos(angle + arrowAngle),
            end.dy - arrowLength * math.sin(angle + arrowAngle),
          ),
          paint,
        );
      default:
        canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter old) {
    return old.strokes != strokes || old.strokes.length != strokes.length;
  }
}
