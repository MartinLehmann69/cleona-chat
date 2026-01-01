import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cleona/core/contact/invitation_card_reader.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/components/invitation_card_view.dart';
import 'package:cleona/ui/components/invitation_messages.dart';
import 'package:cleona/ui/components/invitation_redeem.dart';

/// The own invitation card as a separate screen (FAB dialog → "My
/// QR code"). The same view as in the identity details.
///
/// V4.2 §12.4: the card needs no network — therefore no
/// convergence gate stands here any more (V4.1 waited for `ContactSeedBuilder.isReady`).
class QrShowScreen extends StatelessWidget {
  final ICleonaService service;
  const QrShowScreen({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(locale.get('qr_my_code'))),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: InvitationCardView(
            service: service,
            showShareCleonaButton: true,
          ),
        ),
      ),
    );
  }
}

/// Scan a foreign card or paste its text (V4.2 §15.2, §15.6).
class QrScanScreen extends StatefulWidget {
  final ICleonaService service;
  const QrScanScreen({super.key, required this.service});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

/// Whether the QR scanner is shown, and if not: why not.
///
/// Owner decision of 10.09.2026: "Scanning follows the camera, not the
/// platform." The camera is asked; only where `mobile_scanner` brings no
/// producer at all does the text input stand from the outset.
enum _ScannerSituation {
  /// The camera has not been asked yet (the start is running).
  checking,

  /// There is a camera, and the package can operate it.
  camera,

  /// No usable camera — named fallback to the text input.
  noCamera,
}

/// Whether `mobile_scanner` brings a producer for the running platform.
/// Looked up (S380) in
/// `~/.pub-cache/hosted/pub.dev/mobile_scanner-6.0.11/pubspec.yaml`,
/// `flutter: plugin: platforms:` — android, ios, macos, web. For Linux and
/// Windows there is no QR decoder in the tree; there the text input stays.
bool get _scannerPacketCarriesPlatform =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

class _QrScanScreenState extends State<QrScanScreen> {
  /// The finding of a found card — also of an expired or
  /// foreign one, so that the reason becomes visible instead of scanning on.
  InvitationReading? _reading;

  /// Exactly one of the two carries the found card.
  String? _text;
  Uint8List? _packed;

  bool _processing = false;
  String? _error;
  final _manualController = TextEditingController();
  _ScannerSituation _scannerSituation = _ScannerSituation.checking;

  @override
  void initState() {
    super.initState();
    // The camera answers by running or failing
    // (`MobileScanner.errorBuilder`); a separate pre-start took away
    // the camera image on Android (S380, measured in the field).
    _scannerSituation = _scannerPacketCarriesPlatform
        ? _ScannerSituation.camera
        : _ScannerSituation.noCamera;
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(locale.get('qr_scan_title'))),
      body: SafeArea(
        top: false,
        child: _reading != null
            ? _buildResult(context, locale, _reading!)
            : switch (_scannerSituation) {
                _ScannerSituation.checking =>
                  const Center(child: CircularProgressIndicator()),
                _ScannerSituation.camera => _buildCameraScanner(context, locale),
                _ScannerSituation.noCamera => _buildManualInput(context, locale),
              },
      ),
    );
  }

  void _found(InvitationReading r, {String? text, Uint8List? packed}) {
    setState(() {
      _reading = r;
      _text = text;
      _packed = packed;
      _error = null;
    });
  }

  void _onDetect(BarcodeCapture capture, AppLocale locale) {
    if (_reading != null) return;
    for (final barcode in capture.barcodes) {
      // §15.2: the card stands in binary form in the QR code.
      final raw = barcode.rawBytes;
      if (raw != null && raw.isNotEmpty) {
        final bytes = Uint8List.fromList(raw);
        final r = InvitationRedeem.readBytes(bytes);
        if (InvitationRedeem.isCard(r)) {
          _found(r, packed: bytes);
          return;
        }
      }
      // A QR code that carries the TEXT FORM (§15.2: "or 128–195 base64url
      // characters") comes as a string.
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        final r = InvitationRedeem.readText(value);
        if (InvitationRedeem.isCard(r)) {
          _found(r, text: value);
          return;
        }
        // A blurry image is not a finding; a recognisably broken
        // invitation is — it is named, scanning continues anyway.
        if (r.error != InvitationReadError.notFound && mounted) {
          setState(() => _error = InvitationRedeem.errorOf(locale, r));
        }
      }
    }
  }

  Widget _buildCameraScanner(BuildContext context, AppLocale locale) {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            // NO `controller:` — only a self-created controller attaches
            // the lifecycle observer (mobile_scanner 6.0.11, S380).
            errorBuilder: (context, error, _) {
              debugPrint('[QR-SCAN] camera not available: '
                  '${error.errorCode} ${error.errorDetails?.message ?? ""}');
              return _buildManualInput(context, AppLocale.read(context));
            },
            onDetect: (capture) => _onDetect(capture, locale),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(locale.get('qr_scan_instruction'),
                  textAlign: TextAlign.center),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _ManualInputScreen(
                      onParsed: (r, text) {
                        _found(r, text: text);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ),
                child: Text(locale.get('qr_manual_input')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildManualInput(BuildContext context, AppLocale locale) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
              _scannerSituation == _ScannerSituation.noCamera
                  ? Icons.no_photography_outlined
                  : Icons.qr_code_2,
              size: 64,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(locale.get('qr_manual_input'),
              style: Theme.of(context).textTheme.titleMedium),
          if (_scannerSituation == _ScannerSituation.noCamera) ...[
            const SizedBox(height: 8),
            Text(locale.get('qr_no_camera'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _manualController,
            decoration: InputDecoration(
              labelText: locale.get('card_paste_label'),
              hintText: 'cleona:1:…',
              border: const OutlineInputBorder(),
            ),
            minLines: 2,
            maxLines: 4,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final input = _manualController.text;
              final r = InvitationRedeem.readText(input);
              if (InvitationRedeem.isCard(r)) {
                _found(r, text: input);
              } else {
                setState(() => _error = InvitationRedeem.errorOf(locale, r));
              }
            },
            child: Text(locale.get('card_send_request')),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(
      BuildContext context, AppLocale locale, InvitationReading r) {
    final scheme = Theme.of(context).colorScheme;
    // The reason stands BEFORE the button, not behind it (S380): a button that
    // certainly fails is not an offer.
    final lock = InvitationRedeem.errorOf(locale, r);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add, size: 64, color: scheme.primary),
            const SizedBox(height: 16),
            Text(locale.get('card_scan_found'),
                style: Theme.of(context).textTheme.headlineSmall),
            if (r.card != null) ...[
              const SizedBox(height: 8),
              Text(invitationFingerprintText(locale, r.card!.fingerprint),
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ],
            if (lock != null) ...[
              const SizedBox(height: 8),
              Text(lock,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error)),
            ] else if (r.expiresSoon) ...[
              // §15.3: „reading the card warns … rather than proceeding
              // without comment".
              const SizedBox(height: 8),
              Text(invitationExpiryWarning(locale, r.daysLeft!),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: (_processing || lock != null) ? null : _send,
              icon: _processing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.person_add),
              label: Text(locale.get('card_send_request')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {
                _reading = null;
                _text = null;
                _packed = null;
                _error = null;
              }),
              child: Text(locale.get('qr_scan_again')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final locale = AppLocale.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final navigator = Navigator.of(context);
    setState(() => _processing = true);
    final ok = await InvitationRedeem.send(
      service: widget.service,
      messenger: messenger,
      locale: locale,
      errorColor: errorColor,
      text: _text,
      packed: _text == null ? _packed : null,
    );
    if (!mounted) return;
    if (ok) {
      navigator.pop();
    } else {
      setState(() => _processing = false);
    }
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }
}

/// Text input as a separate screen (reachable from the camera scanner).
class _ManualInputScreen extends StatefulWidget {
  final void Function(InvitationReading reading, String text) onParsed;
  const _ManualInputScreen({required this.onParsed});

  @override
  State<_ManualInputScreen> createState() => _ManualInputScreenState();
}

class _ManualInputScreenState extends State<_ManualInputScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(locale.get('qr_manual_input'))),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: locale.get('card_paste_label'),
                  hintText: 'cleona:1:…',
                  border: const OutlineInputBorder(),
                ),
                minLines: 2,
                maxLines: 4,
                autofocus: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final input = _controller.text;
                  final r = InvitationRedeem.readText(input);
                  if (InvitationRedeem.isCard(r)) {
                    widget.onParsed(r, input);
                  } else {
                    setState(
                        () => _error = InvitationRedeem.errorOf(locale, r));
                  }
                },
                child: Text(locale.get('card_send_request')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
