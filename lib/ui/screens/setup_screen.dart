// ignore_for_file: depend_on_referenced_packages, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/crypto/seed_phrase.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/ui/components/language_selector.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _nameController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);

    return Scaffold(
      body: SafeArea(child: Stack(
        children: [
          // Language selector top-right
          Positioned(
            top: 8,
            right: 16,
            child: const LanguageSelector(),
          ),
          Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Cleona Chat',
                  style: Theme.of(context).textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  locale.get('app_subtitle'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: locale.get('your_name'),
                    hintText: locale.get('your_name_hint'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person),
                  ),
                  autofocus: true,
                  onSubmitted: (_) => _start(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _loading ? null : _start,
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_loading ? locale.get('starting') : locale.get('start')),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _showRestore,
                  icon: const Icon(Icons.restore),
                  label: Text(locale.get('restore')),
                ),
              ],
            ),
          ),
        ),
          ), // Center
        ], // Stack children
      )), // SafeArea + Stack
    );
  }

  Future<void> _start() async {
    final locale = AppLocale.read(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = locale.get('please_enter_name'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // Diagnostic timestamps (E2E gui-00 0.06 91.5s timeout analysis).
    // debugPrint survives Flutter Linux Release; stderr.writeln is swallowed.
    final sw = Stopwatch()..start();
    void log(String phase) {
      debugPrint('[setup-timing] t=${sw.elapsedMilliseconds}ms $phase');
    }
    log('start');

    try {
      // Create identity via IdentityManager
      final identityMgr = IdentityManager();

      // Kick off PQ keygen immediately — runs in a background isolate and
      // overlaps with the seed-phrase dialog. On slow VMs the keygen takes
      // 15-30s; without prewarming the user would wait for it *after*
      // confirming the seed phrase, so the Home screen appears much later.
      identityMgr.preWarmPqKeys();
      log('preWarmPqKeys kicked');

      // Generate seed phrase for recovery
      if (!identityMgr.hasMasterSeed()) {
        final words = identityMgr.generateSeedPhrase();
        log('seed-phrase generated');
        // Show the seed phrase to the user
        if (mounted) {
          await _showSeedPhraseBackup(words);
          log('seed-dialog dismissed');
        }
      }

      final identity = await identityMgr.createIdentity(name);
      log('createIdentity returned (nodeIdHex=${identity.nodeIdHex ?? "null"})');
      identityMgr.setActiveIdentity(identity);

      final appState = context.read<CleonaAppState>();
      await appState.initialize();
      log('appState.initialize returned');
    } catch (e, st) {
      debugPrint('[setup-timing] t=${sw.elapsedMilliseconds}ms EXCEPTION: $e');
      debugPrint('$st');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = locale.tr('error_generic', {'error': '$e'});
        });
      }
    }
  }

  Future<void> _showSeedPhraseBackup(List<String> words) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final locale = AppLocale.of(ctx);
        return AlertDialog(
          title: Text(locale.get('your_recovery_phrase')),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    locale.get('seed_phrase_backup_warning'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(words.length, (i) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${i + 1}. ${words[i]}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: Text(locale.get('copy')),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: words.join(' ')));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(locale.get('copied_to_clipboard'))),
                );
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.print, size: 16),
              label: Text(locale.get('print')),
              onPressed: () => _printSeedPhrase(words),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(locale.get('i_have_noted_them')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _printSeedPhrase(List<String> words) async {
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Cleona Recovery Phrase', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('Keep this safe! Anyone with these words can restore your identity.', style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 20),
            pw.Wrap(
              spacing: 16,
              runSpacing: 8,
              children: List.generate(words.length, (i) {
                return pw.Container(
                  width: 120,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                  child: pw.Text('${i + 1}. ${words[i]}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                );
              }),
            ),
            pw.SizedBox(height: 30),
            pw.Text('Date: ${DateTime.now().toString().substring(0, 10)}', style: const pw.TextStyle(fontSize: 10)),
          ],
        );
      },
    ));
    await Printing.layoutPdf(onLayout: (format) => doc.save());
  }

  void _showRestore() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _RestoreScreen()),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}

/// Screen for restoring identity from a 24-word seed phrase.
class _RestoreScreen extends StatefulWidget {
  const _RestoreScreen();

  @override
  State<_RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<_RestoreScreen> {
  final List<TextEditingController> _wordControllers =
      List.generate(24, (_) => TextEditingController());
  final _nameController = TextEditingController();
  bool _loading = false;
  String? _error;
  int _contactsRestored = 0;
  int _messagesRestored = 0;
  bool _restoreStarted = false;

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);

    return Scaffold(
      appBar: AppBar(title: Text(locale.get('restore'))),
      body: SafeArea(top: false, child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.restore,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  locale.get('enter_recovery_phrase'),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  locale.get('enter_24_words'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // 24 word input fields in a 3-column grid
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 3.0,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: 24,
                  itemBuilder: (ctx, i) {
                    return TextField(
                      controller: _wordControllers[i],
                      decoration: InputDecoration(
                        labelText: '${i + 1}',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      textInputAction: i < 23 ? TextInputAction.next : TextInputAction.done,
                    );
                  },
                ),

                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: locale.get('your_name'),
                    hintText: locale.get('your_name_hint'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],

                if (_restoreStarted) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(locale.get('restore_in_progress'),
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Text(locale.tr('contacts_restored', {'count': '$_contactsRestored'})),
                          Text(locale.tr('messages_restored', {'count': '$_messagesRestored'})),
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _loading ? null : _restore,
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restore),
                  label: Text(_loading ? locale.get('restoring') : locale.get('restore')),
                ),
              ],
            ),
          ),
        ),
      )),
    );
  }

  Future<void> _restore() async {
    final locale = AppLocale.read(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = locale.get('please_enter_name'));
      return;
    }

    final words = _wordControllers.map((c) => c.text.trim().toLowerCase()).toList();
    if (words.any((w) => w.isEmpty)) {
      setState(() => _error = locale.get('please_enter_all_words'));
      return;
    }

    // Validate seed phrase
    if (!SeedPhrase.isValid(words)) {
      setState(() => _error = locale.get('invalid_recovery_phrase'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final identityMgr = IdentityManager();
      identityMgr.restoreFromPhrase(words);
      await identityMgr.createIdentity(name);

      setState(() => _restoreStarted = true);

      final appState = context.read<CleonaAppState>();
      await appState.initialize();

      // Listen for restore progress
      appState.service?.onRestoreProgress = (phase, contacts, messages) {
        if (mounted) {
          setState(() {
            _contactsRestored += contacts;
            _messagesRestored += messages;
          });
        }
      };
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = locale.tr('error_generic', {'error': '$e'});
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in _wordControllers) {
      c.dispose();
    }
    _nameController.dispose();
    super.dispose();
  }
}
