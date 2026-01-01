import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr/qr.dart' as qr_lib;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/components/profile_avatar.dart';
import 'package:cleona/ui/theme/skins.dart';

/// Fullscreen Identity Detail Screen.
/// Opened by tapping the active identity tab.
class IdentityDetailScreen extends StatefulWidget {
  final ICleonaService service;
  final Identity identity;

  const IdentityDetailScreen({
    super.key,
    required this.service,
    required this.identity,
  });

  @override
  State<IdentityDetailScreen> createState() => _IdentityDetailScreenState();
}

class _IdentityDetailScreenState extends State<IdentityDetailScreen> {
  late TextEditingController _descController;
  late TextEditingController _nameController;
  bool _descDirty = false;
  late Identity _identity;

  @override
  void initState() {
    super.initState();
    _identity = widget.identity;
    _descController = TextEditingController(text: widget.service.profileDescription ?? '');
    _descController.addListener(_onDescChanged);
    _nameController = TextEditingController(text: _identity.displayName);
  }

  void _onDescChanged() {
    final isDirty = _descController.text != (widget.service.profileDescription ?? '');
    if (isDirty != _descDirty) setState(() => _descDirty = isDirty);
  }

  @override
  void dispose() {
    _descController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final locale = AppLocale.read(context);
    final identities = IdentityManager().loadIdentities();
    final canDelete = identities.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(locale.get('identity_detail_title')),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // ── 1. QR Code ─────────────────────────────────────────
            _SectionHeader(locale.get('section_qr_code')),
            _buildQrSection(context),

            const Divider(height: 32),

            // ── 1b. Cleona teilen ─────────────────────────────────
            _SectionHeader(locale.get('share_cleona')),
            _buildShareSection(context),

            const Divider(height: 32),

            // ── 2. Profile Picture ─────────────────────────────────
            _SectionHeader(locale.get('section_profile_picture')),
            _buildProfilePictureSection(context),

            const Divider(height: 32),

            // ── 3. Description ─────────────────────────────────────
            _SectionHeader(locale.get('section_description')),
            _buildDescriptionSection(context),

            const Divider(height: 32),

            // ── 4. Rename ──────────────────────────────────────────
            _SectionHeader(locale.get('section_rename')),
            _buildRenameSection(context, appState),

            const Divider(height: 32),

            // ── 5. Skin ────────────��───────────────────────────────
            _SectionHeader(locale.get('section_skin')),
            _buildSkinSection(context, appState),

            const Divider(height: 32),

            // ── 6. Delete Identity ─────────────────────────────────
            _SectionHeader(locale.get('section_delete_identity')),
            _buildDeleteSection(context, appState, canDelete),

            const Divider(height: 32),

            // ── 7. "Ich bin über 18" Toggle (ganz unten) ──────────
            _SectionHeader(locale.get('section_age_declaration')),
            _buildAdultToggle(context),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  // ── QR Code Section ─────────��────────────────────────────────────────

  Widget _buildQrSection(BuildContext context) {
    final locale = AppLocale.read(context);
    final service = widget.service;

    final idNodeIdHex = widget.identity.nodeIdHex ?? service.nodeIdHex;
    final idDisplayName = widget.identity.displayName;
    final channelTag = NetworkSecret.channel == NetworkChannel.beta ? 'b' : 'l';

    final idHexSource = widget.identity.nodeIdHex != null ? 'identity' : 'service-FALLBACK';
    debugPrint('[ContactSeed:detail] identity="${idDisplayName}" '
        'nodeIdHex=${idNodeIdHex.substring(0, 8)} (from $idHexSource) '
        'service.nodeIdHex=${service.nodeIdHex.substring(0, 8)} '
        'match=${idNodeIdHex == service.nodeIdHex}');

    final seed = service.contactSeedBuilder.getContactSeedFor(
      nodeIdHex: idNodeIdHex,
      displayName: idDisplayName,
      channelTag: channelTag,
      userEd25519Pk: service.userEd25519Pk,
      foundingEd25519Pk: service.foundingEd25519Pk,
      deviceX25519Pk: service.deviceX25519Pk,
      deviceMlKemPk: service.deviceMlKemPk,
    );

    if (seed == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Column(
          children: [
            const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            Text(locale.get('qr_mesh_converging'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }

    final qrBytes = seed.toQrBytes();
    final shareUri = seed.toUri();
    final qrCode = qr_lib.QrCode.fromUint8List(
      data: qrBytes,
      errorCorrectLevel: qr_lib.QrErrorCorrectLevel.L,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView.withQr(
              qr: qrCode,
              size: 400,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          // Problem 1 (S119): Node-ID natively selectable (long-press).
          SelectableText(
            'Node-ID: ${idNodeIdHex.substring(0, 16)}...',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text(locale.get('copy')),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: shareUri));
              // §4.11.10: start the owner-side First-Contact rendezvous
              // session for the copied URI (transport-side, no UI).
              final rn = seed.rendezvousNonce;
              if (rn != null) {
                service.notifyContactSeedUriShared(
                    base64Url.encode(rn).replaceAll('=', ''));
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(locale.get('copied_to_clipboard'))),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Share Cleona Section ─────────────────────────────────────────────

  Widget _buildShareSection(BuildContext context) {
    final locale = AppLocale.read(context);
    final service = widget.service;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.link, size: 18),
            label: Text(locale.get('share_cleona_download_link')),
            onPressed: () {
              Clipboard.setData(const ClipboardData(
                text: 'https://github.com/MartinLehmann69/cleona-chat/releases/latest',
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(locale.get('copied_to_clipboard'))),
              );
            },
          ),
          const SizedBox(height: 8),
          FutureBuilder<String?>(
            future: _getLanUrl(service.port),
            builder: (context, snap) {
              if (snap.data == null) return const SizedBox.shrink();
              return OutlinedButton.icon(
                icon: const Icon(Icons.wifi, size: 18),
                label: Text(locale.get('share_cleona_lan_url')),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: snap.data!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${locale.get('copied_to_clipboard')}\n${snap.data}')),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  static Future<String?> _getLanUrl(int port) async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('10.') ||
              ip.startsWith('192.168.') ||
              (ip.startsWith('172.') && _isPrivate172(ip))) {
            return 'http://$ip:$port/cleona/binary/${Platform.operatingSystem}';
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _isPrivate172(String ip) {
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? 0;
    return second >= 16 && second <= 31;
  }

  // ── Profile Picture Section ──────────────��────────────────────���──────

  Widget _buildProfilePictureSection(BuildContext context) {
    final locale = AppLocale.read(context);
    final pic = widget.service.profilePictureBase64;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ProfileAvatar(
            base64: pic,
            radius: 40,
            fallback: CircleAvatar(
              radius: 40,
              child: Text(
                widget.identity.displayName.isNotEmpty
                    ? widget.identity.displayName[0].toUpperCase()
                    : '?',
                style: const TextStyle(fontSize: 32),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pic != null ? locale.get('change_profile_picture') : locale.get('set_profile_picture'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (pic != null)
                      IconButton.outlined(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: locale.get('remove_profile_picture'),
                        onPressed: () => _removeProfilePicture(context),
                      ),
                    IconButton.outlined(
                      icon: const Icon(Icons.photo_camera),
                      tooltip: locale.get('camera'),
                      onPressed: () => _captureFromCamera(context),
                    ),
                    IconButton.outlined(
                      icon: const Icon(Icons.photo_library),
                      tooltip: locale.get('choose_image'),
                      onPressed: () => _pickProfilePicture(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Description Section ──────────────────────────────────────────────

  Widget _buildDescriptionSection(BuildContext context) {
    final locale = AppLocale.read(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _descController,
              maxLength: 500,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: locale.get('profile_description'),
                hintText: locale.get('profile_description_hint'),
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ),
          if (_descDirty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.green),
                tooltip: locale.get('save'),
                onPressed: _saveDescription,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveDescription() async {
    final locale = AppLocale.read(context);
    final text = _descController.text.trim();
    final success = await widget.service.setProfileDescription(text.isEmpty ? null : text);
    if (mounted && success) {
      setState(() => _descDirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.get('profile_description_saved'))),
      );
    }
  }

  // ── Rename Section ────────────────────────────────────────────��──────

  Widget _buildRenameSection(BuildContext context, CleonaAppState appState) {
    final locale = AppLocale.read(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: locale.get('rename_current_name'),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) => _submitRename(appState),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _submitRename(appState),
            child: Text(locale.get('rename')),
          ),
        ],
      ),
    );
  }

  void _submitRename(CleonaAppState appState) {
    final locale = AppLocale.read(context);
    final name = _nameController.text.trim();
    if (name.isNotEmpty && name != _identity.displayName) {
      // Service.updateDisplayName is authoritative: it persists to
      // identities.json via IdentityManager AND broadcasts PROFILE_UPDATE.
      widget.service.updateDisplayName(name);
      appState.refresh();
      setState(() {
        _identity = IdentityManager().getActiveIdentity() ?? _identity;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.get('name_updated'))),
      );
    }
  }

  // ─��� Skin Section ───────────────────────��─────────────────────────────

  Widget _buildSkinSection(BuildContext context, CleonaAppState appState) {
    final locale = AppLocale.read(context);
    final currentSkinId = _identity.skinId ?? 'teal';
    final showCrimsonBanner = IdentityManager().crimsonMigrationShouldShow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showCrimsonBanner)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: MaterialBanner(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              content: Text(locale.get('crimson_migrated_to_fire')),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              actions: [
                TextButton(
                  onPressed: () {
                    IdentityManager().dismissCrimsonBanner();
                    setState(() {});
                  },
                  child: Text(locale.get('got_it')),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: Skins.all.map((skin) {
              final isSelected = skin.id == currentSkinId;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  IdentityManager().setSkinId(_identity.id, skin.id);
                  appState.refresh();
                  if (mounted) {
                    setState(() {
                      _identity = IdentityManager().getActiveIdentity() ?? _identity;
                    });
                  }
                },
                child: Container(
                  width: 90,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? skin.seedColor : Colors.transparent,
                      width: isSelected ? 2.5 : 1,
                    ),
                    color: isSelected ? skin.seedColor.withValues(alpha: 0.1) : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: skin.seedColor,
                          border: skin.id == 'contrast'
                              ? Border.all(color: Theme.of(context).colorScheme.outline, width: 1)
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        locale.get('skin_${skin.id}'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── Delete Section ─────────────��───────────────────────────────���─────

  Widget _buildDeleteSection(BuildContext context, CleonaAppState appState, bool canDelete) {
    final locale = AppLocale.read(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: canDelete ? Colors.red : Colors.grey,
        ),
        icon: const Icon(Icons.delete_forever),
        label: Text(locale.get('delete_permanently')),
        onPressed: canDelete
            ? () => _showDeleteDialog(context, appState)
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(locale.get('only_one_identity'))),
                );
              },
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, CleonaAppState appState) {
    final locale = AppLocale.read(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('delete_identity_title')),
        content: Text(
          locale.tr('delete_identity_content', {'name': _identity.displayName}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await appState.deleteIdentity(_identity);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) Navigator.of(context).pop();
              });
            },
            child: Text(locale.get('delete_permanently')),
          ),
        ],
      ),
    );
  }

  // ── Adult Toggle Section ───────────────────────��─────────────────────

  Widget _buildAdultToggle(BuildContext context) {
    final locale = AppLocale.read(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          title: Text(locale.get('is_adult_label')),
          subtitle: Text(locale.get('is_adult_subtitle')),
          value: _identity.isAdult,
          onChanged: (value) {
            IdentityManager().setIsAdult(_identity.id, value);
            if (!value) {
              // Disable review when turning off adult
              IdentityManager().setReviewEnabled(_identity.id, false);
            }
            setState(() {
              _identity = IdentityManager().getActiveIdentity() ?? _identity;
            });
          },
        ),
        // "Kanal-Meldungen bewerten" — only visible when isAdult is true
        if (_identity.isAdult)
          SwitchListTile(
            title: Text(locale.get('review_enabled_label')),
            subtitle: Text(locale.get('review_enabled_subtitle')),
            value: _identity.reviewEnabled,
            onChanged: (value) {
              IdentityManager().setReviewEnabled(_identity.id, value);
              setState(() {
                _identity = IdentityManager().getActiveIdentity() ?? _identity;
              });
            },
          ),
      ],
    );
  }

  // ── Profile Picture Helpers ──────────────────────────────────────────

  Future<void> _pickProfilePicture(BuildContext context) async {
    final locale = AppLocale.read(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.first.path;
      if (path == null) return;

      var bytes = await File(path).readAsBytes();
      if (bytes.length > 64 * 1024) {
        bytes = await _resizeImage(bytes, 200, 75);
        if (bytes.length > 64 * 1024) {
          bytes = await _resizeImage(bytes, 128, 50);
        }
      }

      if (bytes.length > 64 * 1024) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(locale.tr('image_too_large', {'size': (bytes.length / 1024).toStringAsFixed(0)})),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final base64 = base64Encode(bytes);
      final success = await widget.service.setProfilePicture(base64);
      if (context.mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? locale.get('profile_picture_set') : locale.get('profile_picture_failed'))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(locale.tr('error_generic', {'error': '$e'}))),
        );
      }
    }
  }

  Future<void> _captureFromCamera(BuildContext context) async {
    final locale = AppLocale.read(context);

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final picker = ImagePicker();
        final photo = await picker.pickImage(source: ImageSource.camera, maxWidth: 512, imageQuality: 75);
        if (photo == null) return;

        var bytes = await File(photo.path).readAsBytes();
        if (bytes.length > 64 * 1024) {
          bytes = await _resizeImage(bytes, 200, 75);
          if (bytes.length > 64 * 1024) {
            bytes = await _resizeImage(bytes, 128, 50);
          }
        }
        final b64 = base64Encode(bytes);
        final success = await widget.service.setProfilePicture(b64);
        if (context.mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(success ? locale.get('profile_picture_from_camera') : locale.get('profile_picture_failed'))),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(locale.tr('error_generic', {'error': '$e'}))),
          );
        }
      }
      return;
    }

    try {
      final tmpPath = '${AppPaths.tempDir}/cleona_camera_capture.jpg';
      final proc = await Process.run('fswebcam', ['-r', '320x240', '--jpeg', '75', '--no-banner', tmpPath]);
      if (proc.exitCode != 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(locale.get('camera_unavailable'))),
          );
        }
        return;
      }

      if (!await File(tmpPath).exists()) return;
      var bytes = await File(tmpPath).readAsBytes();
      if (bytes.length > 64 * 1024) {
        bytes = await _resizeImage(bytes, 200, 75);
        if (bytes.length > 64 * 1024) {
          bytes = await _resizeImage(bytes, 128, 50);
        }
      }
      final b64 = base64Encode(bytes);
      final success = await widget.service.setProfilePicture(b64);
      if (context.mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? locale.get('profile_picture_from_camera') : locale.get('profile_picture_failed'))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(locale.tr('error_generic', {'error': '$e'}))),
        );
      }
    }
  }

  Future<void> _removeProfilePicture(BuildContext context) async {
    await widget.service.setProfilePicture(null);
    if (mounted) setState(() {});
  }

  static Future<Uint8List> _resizeImage(Uint8List bytes, int maxSize, int quality) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final scale = maxSize / (image.width > image.height ? image.width : image.height);
    final newW = (image.width * scale).round();
    final newH = (image.height * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, newW.toDouble(), newH.toDouble()));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, newW.toDouble(), newH.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final resized = await picture.toImage(newW, newH);
    final byteData = await resized.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    resized.dispose();

    return byteData!.buffer.asUint8List();
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

