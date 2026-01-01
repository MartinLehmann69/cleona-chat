// lib/ui/components/profile_avatar.dart
//
// Flicker-free profile-picture avatar.
//
// Previously, callers did this in build():
//
//     CircleAvatar(backgroundImage: MemoryImage(base64Decode(pic)))
//
// Every rebuild (peer list change, typing indicator, unread update, ...)
// allocated a fresh Uint8List and a fresh MemoryImage. Flutter's image cache
// keys ImageProvider instances by value-equality; MemoryImage(bytes) only
// equals another MemoryImage if the underlying Uint8List is identical.
// A freshly decoded Uint8List is never identical → cache miss → re-decode →
// white frame = visible flicker (Bug #U11).
//
// This widget decodes once and holds the ImageProvider stable until the
// base64 string actually changes, so subsequent rebuilds hit the cache.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class ProfileAvatar extends StatefulWidget {
  final String? base64;
  final double radius;
  final Widget? fallback;
  final Color? backgroundColor;

  const ProfileAvatar({
    super.key,
    required this.base64,
    this.radius = 20,
    this.fallback,
    this.backgroundColor,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  MemoryImage? _image;
  String? _decodedFrom;

  @override
  void initState() {
    super.initState();
    _rebuildImage();
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.base64 != _decodedFrom) {
      _rebuildImage();
    }
  }

  void _rebuildImage() {
    final b64 = widget.base64;
    if (b64 == null || b64.isEmpty) {
      _image = null;
    } else {
      try {
        final Uint8List bytes = base64Decode(b64);
        _image = MemoryImage(bytes);
      } catch (_) {
        _image = null;
      }
    }
    _decodedFrom = b64;
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor,
      backgroundImage: _image,
      child: _image == null ? widget.fallback : null,
    );
  }
}
