// Name, description and image of a group or private channel (v4_2 §16.2.2
// "Settings (name, description, image, …) are changed by the owner or
// admin"; S407 group profile). Opened from the group and channel details by
// an owner or admin; the change goes to every member
// (`ICleonaService.updateGroupProfile`).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/ui/components/app_screenshot_button.dart';
import 'package:cleona/ui/components/picture_shrink.dart';
import 'package:cleona/ui/components/profile_avatar.dart';

class GroupProfileScreen extends StatefulWidget {
  final ICleonaService service;
  final String conversationId;

  const GroupProfileScreen({
    super.key,
    required this.service,
    required this.conversationId,
  });

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _about;
  late final bool _isChannel;
  String? _picture;
  bool _pictureChanged = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = widget.service.groups[widget.conversationId];
    final c = widget.service.channels[widget.conversationId];
    _isChannel = g == null;
    _name = TextEditingController(text: g?.name ?? c?.name ?? '');
    _about = TextEditingController(text: g?.description ?? c?.description ?? '');
    _picture = g?.pictureBase64 ?? c?.pictureBase64;
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final locale = AppLocale.read(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final path = result?.files.firstOrNull?.path;
      if (path == null) return;
      final Uint8List bytes =
          await pictureWithin(await File(path).readAsBytes(), kGroupPictureAtMost);
      if (!mounted) return;
      if (bytes.length > kGroupPictureAtMost) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(locale.tr('image_too_large',
              {'size': (bytes.length / 1024).toStringAsFixed(0)})),
        ));
        return;
      }
      setState(() {
        _picture = base64Encode(bytes);
        _pictureChanged = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(locale.tr('error_generic', {'error': '$e'})),
      ));
    }
  }

  Future<void> _save() async {
    final locale = AppLocale.read(context);
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(locale.get('please_enter_name'))));
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.service.updateGroupProfile(
      widget.conversationId,
      name: _name.text,
      description: _about.text,
      setPicture: _pictureChanged,
      pictureBase64: _picture,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(locale
          .get(ok ? 'group_profile_saved' : 'group_profile_failed')),
    ));
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(locale.get('group_profile_edit')),
        actions: const [AppScreenshotButton()],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                ProfileAvatar(
                  base64: _picture,
                  radius: 40,
                  fallback: Icon(_isChannel ? Icons.campaign : Icons.group,
                      size: 36),
                ),
                const SizedBox(width: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    IconButton.outlined(
                      icon: const Icon(Icons.photo_library),
                      tooltip: locale.get('choose_image'),
                      onPressed: _saving ? null : _pick,
                    ),
                    if (_picture != null)
                      IconButton.outlined(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: locale.get('remove_image'),
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                  _picture = null;
                                  _pictureChanged = true;
                                }),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: locale.get(
                    _isChannel ? 'channel_name_label' : 'group_name_label'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _about,
              maxLength: kGroupDescriptionAtMost,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: locale.get('channel_description'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                icon: const Icon(Icons.check),
                label: Text(locale.get('save')),
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
