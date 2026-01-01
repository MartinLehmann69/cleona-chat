import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cleona/main.dart';
import 'package:cleona/ui/components/invitation_card_view.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/media/link_preview_fetcher.dart'
    show BrowserOpenMode, LinkPreviewSettings;
import 'package:cleona/core/media/transient_files.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/components/picture_shrink.dart';
import 'package:cleona/ui/components/profile_avatar.dart';
import 'package:cleona/ui/theme/skins.dart';
import 'package:cleona/ui/screens/settings_screen.dart';
import 'package:cleona/ui/screens/device_management_screen.dart';
import 'package:cleona/ui/components/app_screenshot_button.dart';

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
        actions: const [AppScreenshotButton()],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // ── 1. QR Code ─────────────────────────────────────────
            _SectionHeader(locale.get('section_qr_code')),
            // V4.2 §12.4: card as QR and as text line, without a network condition.
            // The card belongs to the active identity — this screen
            // opens only for it (tap on the already active chip).
            InvitationCardView(
              service: widget.service,
              showShareCleonaButton: true,
            ),

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

            // ── Settings of this identity (S407-E9) ────────────────
            IdentitySettingsList(service: widget.service),

            // ── 6. Delete Identity ─────────────────────────────────
            _SectionHeader(locale.get('section_delete_identity')),
            _buildDeleteSection(context, appState, canDelete),

            const Divider(height: 32),

            // ── 7. "I am over 18" toggle (at the very bottom) ──────────
            _SectionHeader(locale.get('section_age_declaration')),
            _buildAdultToggle(context),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
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
      // the list of identities (device database) via IdentityManager AND
      // broadcasts PROFILE_UPDATE.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // S368: here stood a `MaterialBanner` "crimson_migrated_to_fire"
        // for profiles with the old appearance `crimson`. Such
        // profiles do not exist on this line.
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
            // §15.10, §14.7 Type 8 (D-72): the service stores it and tells
            // the other own devices; switching off also switches the
            // review opt-in off. The record here follows at once.
            widget.service.setIsAdult(value);
            setState(() {
              _identity.isAdult = value;
              if (!value) _identity.reviewEnabled = false;
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
              widget.service.setReviewEnabled(value);
              setState(() => _identity.reviewEnabled = value);
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
        bytes = await resizePicture(bytes, 200);
        if (bytes.length > 64 * 1024) {
          bytes = await resizePicture(bytes, 128);
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

  /// Reads the picture the camera laid down as a file and deletes that
  /// file: from here on the picture lives in memory and, once set, in the
  /// store (area `profile`). The ONE place for both platforms' branches of
  /// [_captureFromCamera]. `discardSurface` deletes only the surface's own
  /// plaintext in transit (the transient directory; on Android/iOS also
  /// the app's cache, where the picker puts the photo).
  Future<Uint8List> _readCameraPicture(String path) async {
    try {
      return await File(path).readAsBytes();
    } finally {
      TransientFiles.discardSurface(path);
    }
  }

  Future<void> _captureFromCamera(BuildContext context) async {
    final locale = AppLocale.read(context);

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final picker = ImagePicker();
        final photo = await picker.pickImage(source: ImageSource.camera, maxWidth: 512, imageQuality: 75);
        if (photo == null) return;

        var bytes = await _readCameraPicture(photo.path);
        if (bytes.length > 64 * 1024) {
          bytes = await resizePicture(bytes, 200);
          if (bytes.length > 64 * 1024) {
            bytes = await resizePicture(bytes, 128);
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
      // The picture lies in the surface's transient directory, not in the
      // system temp directory (S401).
      final tmpPath = TransientFiles.surfacePath(
          'camera_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final proc = await Process.run('fswebcam', ['-r', '320x240', '--jpeg', '75', '--no-banner', tmpPath]);
      if (proc.exitCode != 0) {
        TransientFiles.discardSurface(tmpPath);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(locale.get('camera_unavailable'))),
          );
        }
        return;
      }

      if (!await File(tmpPath).exists()) return;
      var bytes = await _readCameraPicture(tmpPath);
      if (bytes.length > 64 * 1024) {
        bytes = await resizePicture(bytes, 200);
        if (bytes.length > 64 * 1024) {
          bytes = await resizePicture(bytes, 128);
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

/// How a tapped link opens (owner decision 30.10.2026,
/// gui-09 9.16 = A): normally, in a private window where the platform can
/// (`chat_screen.dart` `_launchIncognito`, otherwise normally), or asking
/// every time. Stored with the identity's link-preview settings
/// (`LinkPreviewSettings.browserOpenMode`; desktop over IPC
/// `update_link_preview_settings`, Android in-process). Default: normal.
class LinkOpenModeTile extends StatefulWidget {
  final ICleonaService service;
  const LinkOpenModeTile({super.key, required this.service});

  @override
  State<LinkOpenModeTile> createState() => _LinkOpenModeTileState();
}

class _LinkOpenModeTileState extends State<LinkOpenModeTile> {
  static const _labelKeys = {
    BrowserOpenMode.normal: 'link_open_mode_normal',
    BrowserOpenMode.incognitoPreferred: 'link_open_mode_private',
    BrowserOpenMode.alwaysAsk: 'link_open_mode_ask',
  };

  void _set(BrowserOpenMode mode) {
    final settings = LinkPreviewSettings.fromJson(
        widget.service.linkPreviewSettings.toJson())
      ..browserOpenMode = mode;
    widget.service.updateLinkPreviewSettings(settings);
    setState(() {});
  }

  Future<void> _choose(BuildContext context, AppLocale locale) async {
    final current = widget.service.linkPreviewSettings.browserOpenMode;
    final chosen = await showDialog<BrowserOpenMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(locale.get('link_open_mode')),
        children: [
          for (final mode in BrowserOpenMode.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, mode),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(mode == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(locale.get(_labelKeys[mode]!)),
                subtitle: mode == BrowserOpenMode.incognitoPreferred
                    ? Text(locale.get('link_open_mode_private_sub'))
                    : null,
              ),
            ),
        ],
      ),
    );
    if (chosen != null && chosen != current) _set(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final mode = widget.service.linkPreviewSettings.browserOpenMode;
    return ListTile(
      leading: const Icon(Icons.open_in_browser),
      title: Text(locale.get('link_open_mode')),
      subtitle: Text(locale.get(_labelKeys[mode]!)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _choose(context, locale),
    );
  }
}

/// The settings stored per identity (the identity's database): media,
/// notifications, archive, transcription, devices and the rescue bundle.
/// Owner decision 08.10.2026 (S407-E9): what is stored per identity is set
/// on the identity screen; the general settings screen keeps only what
/// applies to the whole device. The identity screen opens only for the
/// active identity, so [service] is that identity's service.
class IdentitySettingsList extends StatelessWidget {
  final ICleonaService service;
  const IdentitySettingsList({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    Widget tile(IconData icon, String titleKey, String subtitle,
        Widget Function() page) {
      return ListTile(
        leading: Icon(icon),
        title: Text(locale.get(titleKey)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => page()),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(locale.get('section_media')),
        tile(Icons.download, 'media_settings_title',
            locale.get('media_settings_subtitle'),
            () => MediaSettingsScreen(service: service)),
        LinkOpenModeTile(service: service),
        tile(Icons.notifications_outlined, 'notification_settings_title',
            locale.get('notification_settings_subtitle'),
            () => NotificationSettingsScreen(service: service)),
        const Divider(height: 32),
        _SectionHeader(locale.get('section_archive')),
        tile(Icons.archive_outlined, 'archive_settings_title',
            'SMB / SFTP / FTPS / HTTP',
            () => ArchiveSettingsScreen(service: service)),
        const Divider(height: 32),
        _SectionHeader(locale.get('section_transcription')),
        tile(Icons.record_voice_over_outlined, 'transcription_settings_title',
            locale.get('whisper_engine'),
            () => TranscriptionSettingsScreen(service: service)),
        const Divider(height: 32),
        _SectionHeader(locale.get('section_devices')),
        tile(Icons.devices, 'device_management_title',
            locale.get('device_management_subtitle'),
            () => DeviceManagementScreen(service: service)),
        const Divider(height: 32),
        _SectionHeader(locale.get('section_backup')),
        RecoveryBundleTile(service: service),
        const Divider(height: 32),
      ],
    );
  }
}
