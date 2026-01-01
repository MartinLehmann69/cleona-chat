import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cleona/core/calendar/sync/sync_types.dart';

/// Minimal CalDAV client (RFC 4791 / RFC 4918 WebDAV).
///
/// Supports the subset needed for bi-directional calendar sync:
/// - PROPFIND `current-user-principal` to locate the user's principal URL
/// - PROPFIND `calendar-home-set` to find the calendar collection root
/// - PROPFIND on calendar-home to list all calendars
/// - REPORT `calendar-query` to list events in a time window (returns ETags)
/// - GET on individual event hrefs to fetch iCal data
/// - PUT to create/update events (conditional on If-Match / If-None-Match)
/// - DELETE to remove events
///
/// Authentication: HTTP Basic over HTTPS. Many providers (Nextcloud, iCloud,
/// Google Workspace) require app-specific passwords rather than the real
/// account password.
class CalDAVClient {
  final String serverUrl;
  final String username;
  final String password;
  final HttpClient _http;

  CalDAVClient({
    required this.serverUrl,
    required this.username,
    required this.password,
  }) : _http = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  void close() {
    _http.close(force: true);
  }

  String get _authHeader {
    final token = base64.encode(utf8.encode('$username:$password'));
    return 'Basic $token';
  }

  /// Send a raw CalDAV request. Returns the response status, headers, and
  /// body. Caller is responsible for parsing XML when applicable.
  Future<_CalDavResponse> _request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
    int followRedirects = 5,
  }) async {
    var currentUri = uri;
    for (var i = 0; i <= followRedirects; i++) {
      final req = await _http.openUrl(method, currentUri);
      req.followRedirects = false;
      req.headers.set('Authorization', _authHeader);
      req.headers.set('Depth', '0');
      if (headers != null) {
        headers.forEach((k, v) => req.headers.set(k, v));
      }
      if (body != null) {
        req.headers.contentType =
            headers != null && headers['Content-Type'] != null
                ? ContentType.parse(headers['Content-Type']!)
                : ContentType('application', 'xml', charset: 'utf-8');
        final bytes = utf8.encode(body);
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final resp = await req.close();
      final status = resp.statusCode;

      if (status >= 300 && status < 400 && i < followRedirects) {
        final loc = resp.headers.value('location');
        await resp.drain<void>();
        if (loc == null) {
          throw CalDAVException(
              'Redirect response without Location header from $currentUri');
        }
        final next = Uri.parse(loc).isAbsolute
            ? Uri.parse(loc)
            : currentUri.resolve(loc);
        // Refuse cross-origin redirects — otherwise a compromised CalDAV
        // server could bounce us to an attacker URL and we'd resend the
        // Basic-auth header there. Legitimate CalDAV setups always
        // redirect within the same scheme/host/port (e.g. .well-known →
        // /dav/). If a server genuinely needs cross-origin, the user can
        // configure the final URL directly.
        if (next.scheme != currentUri.scheme ||
            next.host != currentUri.host ||
            next.port != currentUri.port) {
          throw CalDAVException(
              'Refused cross-origin redirect ($currentUri → $next): '
              'would leak Basic-auth credentials.');
        }
        currentUri = next;
        continue;
      }

      final bodyText = await resp.transform(utf8.decoder).join();
      final respHeaders = <String, List<String>>{};
      resp.headers.forEach((name, values) {
        respHeaders[name.toLowerCase()] = values;
      });

      return _CalDavResponse(
        status: status,
        body: bodyText,
        headers: respHeaders,
        uri: currentUri,
      );
    }
    throw CalDAVException('Too many redirects starting from $uri');
  }

  /// Probe the server and return the principal URL for the authenticated user.
  Future<String> discoverPrincipal() async {
    const reqBody = '<?xml version="1.0" encoding="UTF-8"?>'
        '<d:propfind xmlns:d="DAV:">'
        '<d:prop><d:current-user-principal/></d:prop>'
        '</d:propfind>';

    // Try well-known URI first (RFC 6764).
    final base = Uri.parse(serverUrl);
    final wellKnown = base.replace(path: '${_trimTrailingSlash(base.path)}/.well-known/caldav');
    final candidates = <Uri>[wellKnown, base];

    for (final candidate in candidates) {
      try {
        final resp = await _request(
          'PROPFIND',
          candidate,
          headers: {'Depth': '0', 'Content-Type': 'application/xml; charset=utf-8'},
          body: reqBody,
        );
        if (resp.status == 207 || resp.status == 200) {
          final href = _extractSingleTagContent(
              resp.body, 'current-user-principal', inner: 'href');
          if (href != null && href.isNotEmpty) {
            return _absoluteUrl(resp.uri, href);
          }
        }
      } catch (e) {
        // Keep trying the next candidate.
        continue;
      }
    }
    throw CalDAVException(
        'Unable to discover current-user-principal at $serverUrl. '
        'Check server URL and credentials.');
  }

  /// Given a principal URL, return the calendar-home-set URL.
  Future<String> discoverCalendarHome(String principalUrl) async {
    const reqBody = '<?xml version="1.0" encoding="UTF-8"?>'
        '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '<d:prop><c:calendar-home-set/></d:prop>'
        '</d:propfind>';

    final resp = await _request(
      'PROPFIND',
      Uri.parse(principalUrl),
      headers: {'Depth': '0', 'Content-Type': 'application/xml; charset=utf-8'},
      body: reqBody,
    );
    if (resp.status != 207 && resp.status != 200) {
      throw CalDAVException(
          'calendar-home-set query failed: HTTP ${resp.status}');
    }
    final href = _extractSingleTagContent(resp.body, 'calendar-home-set',
        inner: 'href');
    if (href == null || href.isEmpty) {
      throw CalDAVException(
          'Server did not return a calendar-home-set href.');
    }
    return _absoluteUrl(resp.uri, href);
  }

  /// List all calendars under a calendar-home URL.
  /// Returns a list of (href, displayName) pairs.
  Future<List<CalDAVCalendar>> listCalendars(String calendarHomeUrl) async {
    const reqBody = '<?xml version="1.0" encoding="UTF-8"?>'
        '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '<d:prop>'
        '<d:displayname/>'
        '<d:resourcetype/>'
        '<c:supported-calendar-component-set/>'
        '</d:prop>'
        '</d:propfind>';

    final resp = await _request(
      'PROPFIND',
      Uri.parse(calendarHomeUrl),
      headers: {'Depth': '1', 'Content-Type': 'application/xml; charset=utf-8'},
      body: reqBody,
    );
    if (resp.status != 207) {
      throw CalDAVException('Calendar listing failed: HTTP ${resp.status}');
    }
    final responses = _splitMultistatus(resp.body);
    final result = <CalDAVCalendar>[];
    for (final r in responses) {
      final href = _extractInnerText(r, 'href');
      if (href == null) continue;
      // Skip if not a calendar collection.
      final isCalendar = r.contains('<cal:calendar') ||
          r.contains('<c:calendar') ||
          r.contains(':calendar/>');
      if (!isCalendar) continue;
      final display = _extractInnerText(r, 'displayname') ?? href;
      result.add(CalDAVCalendar(
        url: _absoluteUrl(resp.uri, href),
        displayName: display,
      ));
    }
    return result;
  }

  /// Query event ETags in the given time window.
  /// Returns list of (href, etag) entries.
  Future<List<CalDAVEventRef>> listEvents(
    String calendarUrl, {
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) async {
    final timeRange = (rangeStart != null && rangeEnd != null)
        ? '<c:time-range start="${_formatUtc(rangeStart)}" end="${_formatUtc(rangeEnd)}"/>'
        : '';
    final reqBody = '<?xml version="1.0" encoding="UTF-8"?>'
        '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '<d:prop><d:getetag/></d:prop>'
        '<c:filter>'
        '<c:comp-filter name="VCALENDAR">'
        '<c:comp-filter name="VEVENT">$timeRange</c:comp-filter>'
        '</c:comp-filter>'
        '</c:filter>'
        '</c:calendar-query>';

    final resp = await _request(
      'REPORT',
      Uri.parse(calendarUrl),
      headers: {'Depth': '1', 'Content-Type': 'application/xml; charset=utf-8'},
      body: reqBody,
    );
    if (resp.status != 207) {
      throw CalDAVException('Event listing failed: HTTP ${resp.status}');
    }
    final responses = _splitMultistatus(resp.body);
    final result = <CalDAVEventRef>[];
    for (final r in responses) {
      final href = _extractInnerText(r, 'href');
      if (href == null) continue;
      final etag = _extractInnerText(r, 'getetag') ?? '';
      result.add(CalDAVEventRef(
        href: _absoluteUrl(resp.uri, href),
        etag: _cleanEtag(etag),
      ));
    }
    return result;
  }

  /// Fetch the iCal (.ics) text for a single event href.
  Future<CalDAVEventData> getEvent(String eventHref) async {
    final resp = await _request('GET', Uri.parse(eventHref));
    if (resp.status != 200) {
      throw CalDAVException('GET $eventHref failed: HTTP ${resp.status}');
    }
    final etag = _cleanEtag(resp.headers['etag']?.first ?? '');
    return CalDAVEventData(href: eventHref, icalData: resp.body, etag: etag);
  }

  /// Create or update an event. Returns the new ETag if the server supplied one.
  /// Use [ifMatch] for conditional updates and [ifNoneMatch] = '*' for creates.
  Future<String?> putEvent(
    String eventHref, {
    required String icalData,
    String? ifMatch,
    String? ifNoneMatch,
  }) async {
    final headers = {
      'Content-Type': 'text/calendar; charset=utf-8',
    };
    if (ifMatch != null) headers['If-Match'] = ifMatch;
    if (ifNoneMatch != null) headers['If-None-Match'] = ifNoneMatch;

    final resp = await _request(
      'PUT',
      Uri.parse(eventHref),
      headers: headers,
      body: icalData,
    );
    if (resp.status != 201 && resp.status != 204 && resp.status != 200) {
      throw CalDAVException('PUT $eventHref failed: HTTP ${resp.status}');
    }
    final etag = resp.headers['etag']?.first;
    return etag == null ? null : _cleanEtag(etag);
  }

  /// Delete an event by href. Ignores 404 (already gone).
  Future<void> deleteEvent(String eventHref, {String? ifMatch}) async {
    final headers = <String, String>{};
    if (ifMatch != null) headers['If-Match'] = ifMatch;
    final resp = await _request('DELETE', Uri.parse(eventHref), headers: headers);
    if (resp.status != 204 && resp.status != 200 && resp.status != 404) {
      throw CalDAVException('DELETE $eventHref failed: HTTP ${resp.status}');
    }
  }

  // ── XML helpers ───────────────────────────────────────────────────────────
  //
  // We use regex-based extraction rather than pulling in a full XML dependency.
  // This is safe for CalDAV multistatus replies which have a well-defined
  // structure — we only look at specific WebDAV / CalDAV elements.

  static List<String> _splitMultistatus(String body) {
    final result = <String>[];
    final re = RegExp(
      r'<(?:\w+:)?response[\s>][\s\S]*?</(?:\w+:)?response>',
      caseSensitive: false,
    );
    for (final match in re.allMatches(body)) {
      result.add(match.group(0)!);
    }
    return result;
  }

  static String? _extractInnerText(String xml, String localName) {
    final re = RegExp(
      '<(?:\\w+:)?$localName(?:\\s[^>]*)?>([\\s\\S]*?)</(?:\\w+:)?$localName>',
      caseSensitive: false,
    );
    final match = re.firstMatch(xml);
    if (match == null) return null;
    return _decodeXmlEntities(match.group(1)!.trim());
  }

  static String? _extractSingleTagContent(String xml, String outerName,
      {required String inner}) {
    final outerRe = RegExp(
      '<(?:\\w+:)?$outerName(?:\\s[^>]*)?>([\\s\\S]*?)</(?:\\w+:)?$outerName>',
      caseSensitive: false,
    );
    final outerMatch = outerRe.firstMatch(xml);
    if (outerMatch == null) return null;
    return _extractInnerText(outerMatch.group(1)!, inner);
  }

  static String _decodeXmlEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  static String _absoluteUrl(Uri base, String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return href;
    }
    return base.resolve(href).toString();
  }

  static String _cleanEtag(String etag) {
    var e = etag.trim();
    if (e.startsWith('W/')) e = e.substring(2).trim();
    if (e.startsWith('"') && e.endsWith('"') && e.length >= 2) {
      e = e.substring(1, e.length - 1);
    }
    return e;
  }

  static String _formatUtc(DateTime dt) {
    final u = dt.toUtc();
    return '${u.year.toString().padLeft(4, '0')}'
        '${u.month.toString().padLeft(2, '0')}'
        '${u.day.toString().padLeft(2, '0')}'
        'T${u.hour.toString().padLeft(2, '0')}'
        '${u.minute.toString().padLeft(2, '0')}'
        '${u.second.toString().padLeft(2, '0')}Z';
  }

  static String _trimTrailingSlash(String p) {
    if (p.endsWith('/')) return p.substring(0, p.length - 1);
    return p;
  }

  /// Helper for callers that want to walk discover -> home -> listCalendars.
  static Future<List<CalDAVCalendar>> discoverAndList(CalDAVConfig cfg) async {
    final client = CalDAVClient(
      serverUrl: cfg.serverUrl,
      username: cfg.username,
      password: cfg.password,
    );
    try {
      final principal = await client.discoverPrincipal();
      final home = await client.discoverCalendarHome(principal);
      return await client.listCalendars(home);
    } finally {
      client.close();
    }
  }
}

class CalDAVCalendar {
  final String url;
  final String displayName;
  CalDAVCalendar({required this.url, required this.displayName});

  Map<String, dynamic> toJson() => {
        'url': url,
        'displayName': displayName,
      };
}

class CalDAVEventRef {
  final String href;
  final String etag;
  CalDAVEventRef({required this.href, required this.etag});
}

class CalDAVEventData {
  final String href;
  final String icalData;
  final String etag;
  CalDAVEventData(
      {required this.href, required this.icalData, required this.etag});
}

class _CalDavResponse {
  final int status;
  final String body;
  final Map<String, List<String>> headers;
  final Uri uri;
  _CalDavResponse({
    required this.status,
    required this.body,
    required this.headers,
    required this.uri,
  });
}

class CalDAVException implements Exception {
  final String message;
  CalDAVException(this.message);
  @override
  String toString() => 'CalDAVException: $message';
}
