// S395 (S394-11): the one place where a contact or conversation name
// becomes text on the screen.
//
// The service keeps `kPendingContactName` as a MARK until the contact's own
// introduction arrives — the data model knows no language, so it cannot hold
// the text itself. Until S395 the surface showed the mark unchanged, and a
// German surface read "Pending..." (CLAUDE.md rule 7: i18n complete).

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_types.dart';

/// [name] as the user sees it: the pending mark translated, every other name
/// unchanged.
String shownContactName(String name, AppLocale locale) =>
    name == kPendingContactName ? locale.get('contact_name_pending') : name;
