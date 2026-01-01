import 'package:flutter/material.dart';

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/platform/linux_native_libraries.dart';

/// The window when a library Cleona opens by name is missing (S410, I-6).
///
/// Runs before the device database is open, so the language is the system
/// language ([AppLocale] detects it); the package names stay verbatim.
/// [locale] is given only by tests; the app passes none.
class NativeLibraryMissingApp extends StatelessWidget {
  final List<NativeLibraryMissingException> missing;
  final AppLocale? locale;

  const NativeLibraryMissingApp({super.key, required this.missing, this.locale});

  @override
  Widget build(BuildContext context) {
    final locale = this.locale ?? AppLocale();
    final rtl = locale.current.isRtl;
    final lines = <Widget>[];
    for (final m in missing) {
      lines
        ..add(const SizedBox(height: 16))
        ..add(Text(
          m.shipsWithCleona
              ? locale.tr('native_library_missing_bundled',
                  {'library': m.library.name})
              : locale.tr('native_library_missing_system',
                  {'library': m.library.name}),
          style: const TextStyle(fontSize: 15),
        ));
      for (final hint in m.library.packageHints) {
        lines.add(Padding(
          padding: const EdgeInsetsDirectional.only(start: 16, top: 4),
          child: SelectableText(hint,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
        ));
      }
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              // Full width, so that "start" is the start of the WINDOW. A
              // vertical SingleChildScrollView passes on the loose width it
              // gets from the Scaffold body and paints its child at x = 0
              // whatever the text direction (Flutter 3.44.6,
              // packages/flutter/lib/src/widgets/single_child_scroll_view.dart,
              // _RenderSingleChildViewport: _getInnerConstraints
              // `Axis.vertical => constraints.widthConstraints()`,
              // _paintOffsetForPosition `AxisDirection.down => Offset(0.0, -position)`).
              // Without this the Column was as wide as its widest text, and in
              // Arabic the block stood at the left edge (S410-I6-MESSUNG, finding 4).
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(locale.get('native_library_missing_title'),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    ...lines,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
