import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/crypto/kem_benchmark.dart';

/// Performance Profile screen (Architecture section 23.2).
///
/// Three sections:
/// 1. KEM encryption/decryption throughput benchmark
/// 2. Database statistics (conversation/message counts)
/// 3. UI rendering frame-time measurement
class PerformanceScreen extends StatefulWidget {
  final ICleonaService service;
  const PerformanceScreen({super.key, required this.service});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  // KEM benchmark state
  KemBenchmarkResult? _kemResult;
  bool _kemRunning = false;

  // UI frame timing state
  final List<Duration> _frameTimes = [];
  bool _measuringFrames = false;
  int _frameSampleCount = 0;
  Stopwatch? _frameStopwatch;

  @override
  void dispose() {
    _frameStopwatch = null;
    super.dispose();
  }

  Future<void> _runKemBenchmark() async {
    if (_kemRunning) return;
    setState(() => _kemRunning = true);

    // Use a small iteration count (50) to keep the UI responsive on mobile.
    // The benchmark runs synchronously in the main isolate (diagnostic tool,
    // not production) — 50 iterations give stable averages while keeping the
    // blocking window under ~5s on most devices.
    try {
      final result = await KemBenchmark.runBenchmark(iterations: 50);
      if (mounted) setState(() => _kemResult = result);
    } catch (_) {
      // Benchmark may fail on devices without native libs (e.g. simulator).
      // Silently absorb — the "not yet run" state is shown.
    } finally {
      if (mounted) setState(() => _kemRunning = false);
    }
  }

  void _measureFrameTime() {
    if (_measuringFrames) return;
    setState(() {
      _measuringFrames = true;
      _frameTimes.clear();
      _frameSampleCount = 0;
    });

    // Measure 60 consecutive frame build times.
    _frameStopwatch = Stopwatch();
    _sampleFrame();
  }

  void _sampleFrame() {
    if (!mounted || _frameSampleCount >= 60) {
      if (mounted) setState(() => _measuringFrames = false);
      return;
    }
    _frameStopwatch!.reset();
    _frameStopwatch!.start();
    // Force a rebuild and measure how long it takes.
    setState(() {
      _frameSampleCount++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameStopwatch!.stop();
      _frameTimes.add(_frameStopwatch!.elapsed);
      // Schedule next sample after a short delay to avoid saturating the UI.
      Future.delayed(const Duration(milliseconds: 16), () => _sampleFrame());
    });
  }

  double get _avgFrameTimeMs {
    if (_frameTimes.isEmpty) return 0;
    final totalUs = _frameTimes.fold<int>(0, (s, d) => s + d.inMicroseconds);
    return totalUs / _frameTimes.length / 1000.0;
  }

  double get _maxFrameTimeMs {
    if (_frameTimes.isEmpty) return 0;
    return _frameTimes.map((d) => d.inMicroseconds).reduce((a, b) => a > b ? a : b) / 1000.0;
  }

  double get _p95FrameTimeMs {
    if (_frameTimes.isEmpty) return 0;
    final sorted = _frameTimes.map((d) => d.inMicroseconds).toList()..sort();
    final idx = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    return sorted[idx] / 1000.0;
  }

  // --- Database statistics (computed from in-memory conversation list) ---

  int get _totalMessages {
    var count = 0;
    for (final conv in widget.service.conversations.values) {
      count += conv.messages.length;
    }
    return count;
  }

  int get _conversationCount => widget.service.conversations.length;

  (String name, int count) get _largestConversation {
    String name = '-';
    int maxCount = 0;
    for (final conv in widget.service.conversations.values) {
      if (conv.messages.length > maxCount) {
        maxCount = conv.messages.length;
        name = conv.displayName;
      }
    }
    return (name, maxCount);
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final colorScheme = Theme.of(context).colorScheme;
    final (largestName, largestCount) = _largestConversation;

    return Scaffold(
      appBar: AppBar(
        title: Text(locale.get('performance_title')),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          children: [
            // -- Section 1: KEM Encryption --
            _SectionHeader(locale.get('perf_kem_section')),
            const SizedBox(height: 4),
            if (_kemResult != null) ...[
              _PerfTile(
                icon: Icons.lock_outline,
                label: locale.get('perf_encrypt_ops'),
                value: '${_kemResult!.encryptOpsPerSec.toStringAsFixed(1)} ${locale.get('perf_ops_per_sec')}',
                subtitle: '${_kemResult!.encryptAvgMs.toStringAsFixed(2)} ${locale.get('perf_avg_ms')}',
                color: Colors.green,
              ),
              _PerfTile(
                icon: Icons.lock_open,
                label: locale.get('perf_decrypt_ops'),
                value: '${_kemResult!.decryptOpsPerSec.toStringAsFixed(1)} ${locale.get('perf_ops_per_sec')}',
                subtitle: '${_kemResult!.decryptAvgMs.toStringAsFixed(2)} ${locale.get('perf_avg_ms')}',
                color: Colors.blue,
              ),
              _PerfTile(
                icon: Icons.vpn_key_outlined,
                label: locale.get('perf_x25519_ops'),
                value: '${_kemResult!.x25519DhOpsPerSec.toStringAsFixed(1)} ${locale.get('perf_ops_per_sec')}',
                color: colorScheme.tertiary,
              ),
              _PerfTile(
                icon: Icons.security,
                label: locale.get('perf_mlkem_encaps_ops'),
                value: '${_kemResult!.mlKemEncapsOpsPerSec.toStringAsFixed(1)} ${locale.get('perf_ops_per_sec')}',
                color: colorScheme.tertiary,
              ),
              _PerfTile(
                icon: Icons.shield_outlined,
                label: locale.get('perf_mlkem_decaps_ops'),
                value: '${_kemResult!.mlKemDecapsOpsPerSec.toStringAsFixed(1)} ${locale.get('perf_ops_per_sec')}',
                color: colorScheme.tertiary,
              ),
              _PerfTile(
                icon: Icons.repeat,
                label: locale.get('perf_iterations'),
                value: '${_kemResult!.iterations}',
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  _kemRunning
                      ? locale.get('perf_running')
                      : locale.get('perf_not_run'),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            if (_kemRunning)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: LinearProgressIndicator(),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FilledButton.icon(
                onPressed: _kemRunning ? null : _runKemBenchmark,
                icon: const Icon(Icons.play_arrow),
                label: Text(locale.get('perf_run_benchmark')),
              ),
            ),

            const Divider(),

            // -- Section 2: Database --
            _SectionHeader(locale.get('perf_db_section')),
            const SizedBox(height: 4),
            _PerfTile(
              icon: Icons.message_outlined,
              label: locale.get('perf_db_message_count'),
              value: '$_totalMessages',
            ),
            _PerfTile(
              icon: Icons.chat_bubble_outline,
              label: locale.get('perf_db_conversation_count'),
              value: '$_conversationCount',
            ),
            _PerfTile(
              icon: Icons.leaderboard_outlined,
              label: locale.get('perf_db_largest_conv'),
              value: '$largestCount ${locale.get('perf_db_messages_label')}',
              subtitle: largestName,
            ),

            const Divider(),

            // -- Section 3: UI Rendering --
            _SectionHeader(locale.get('perf_ui_section')),
            const SizedBox(height: 4),
            if (_frameTimes.isNotEmpty) ...[
              _PerfTile(
                icon: Icons.speed,
                label: '${locale.get('perf_ui_frame_time')} (avg)',
                value: '${_avgFrameTimeMs.toStringAsFixed(2)} ms',
                color: _avgFrameTimeMs < 16.67 ? Colors.green : Colors.orange,
              ),
              _PerfTile(
                icon: Icons.speed,
                label: '${locale.get('perf_ui_frame_time')} (p95)',
                value: '${_p95FrameTimeMs.toStringAsFixed(2)} ms',
                color: _p95FrameTimeMs < 16.67 ? Colors.green : Colors.orange,
              ),
              _PerfTile(
                icon: Icons.speed,
                label: '${locale.get('perf_ui_frame_time')} (max)',
                value: '${_maxFrameTimeMs.toStringAsFixed(2)} ms',
                color: _maxFrameTimeMs < 16.67 ? Colors.green : Colors.orange,
              ),
              _PerfTile(
                icon: Icons.timer_outlined,
                label: locale.get('perf_iterations'),
                value: '${_frameTimes.length}',
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  _measuringFrames
                      ? '${locale.get('perf_running')} ($_frameSampleCount/60)'
                      : locale.get('perf_not_run'),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            if (_measuringFrames)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: LinearProgressIndicator(),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FilledButton.icon(
                onPressed: _measuringFrames ? null : _measureFrameTime,
                icon: const Icon(Icons.play_arrow),
                label: Text(locale.get('perf_run_benchmark')),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _PerfTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color? color;

  const _PerfTile({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: color ?? colorScheme.onSurfaceVariant),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: Text(
        value,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color ?? colorScheme.onSurface,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
    );
  }
}
