// Local CalDAV server for desktop calendar apps (Thunderbird / Outlook /
// Apple Calendar / Evolution / GNOME Calendar / KDE Korganizer).
//
// Binds to 127.0.0.1 only — this is strictly for desktop-app integration
// on the same machine as the Cleona daemon. There is no TLS; HTTP Basic
// auth over loopback is acceptable because the traffic never leaves the
// kernel's loopback pseudo-interface (and 127.0.0.1 is reachable only to
// local processes, not to the LAN).
//
// Architecture:
//   - One HttpServer for all identities. Per-identity principal URLs.
//   - Username = short hex prefix of the identity's node-id (first 16
//     chars, which is unambiguous within any realistic daemon).
//   - Password = daemon-wide token, regeneratable on demand. Displayed
//     to the user in the Calendar Sync settings screen so they can paste
//     it into their desktop calendar app.
//
// CalDAV surface implemented (subset of RFC 4791 / RFC 4918):
//   - OPTIONS: advertise `DAV: 1, 2, 3, calendar-access`
//   - PROPFIND Depth:0 on `/`, `/dav/` → current-user-principal
//   - PROPFIND Depth:0 on principal → calendar-home-set + displayname
//   - PROPFIND Depth:1 on calendar-home → list of calendars
//   - PROPFIND Depth:0 on a calendar → calendar properties incl. ctag
//   - PROPFIND Depth:1 on a calendar → list of event hrefs + ETags
//   - REPORT `calendar-query`: event hrefs + ETags (optional filter used
//     by Thunderbird is ignored — we always return the full set; the
//     client does its own filtering on GET)
//   - REPORT `calendar-multiget`: batch GET of multiple hrefs
//   - GET on event → iCal body
//   - PUT on event → create/update (with If-Match / If-None-Match)
//   - DELETE on event
//
// Deliberately NOT implemented (not needed by any of the common desktop
// clients for read-write sync):
//   - WebDAV ACL / owner / permissions (single-user)
//   - calendar-multiget with expanded RRULE (Thunderbird does local expand)
//   - sync-collection / sync-token (clients fall back to ctag polling)
//   - Free/Busy REPORT (Cleona handles that over its own protocol)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/calendar/ical_engine.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/service/service_types.dart';

class CalDAVServerIdentity {
  /// Full hex node-id.
  final String fullNodeId;

  /// Display name shown in desktop apps (usually the identity's display name).
  final String displayName;

  /// The CalendarManager backing this identity's calendar.
  final CalendarManager calendar;

  CalDAVServerIdentity({
    required this.fullNodeId,
    required this.displayName,
    required this.calendar,
  });

  /// Short identifier used in URLs and as the HTTP Basic username.
  /// Picking 16 hex chars (~= 64 bits) makes collisions between identities
  /// on the same daemon effectively impossible.
  String get shortId => fullNodeId.length <= 16
      ? fullNodeId
      : fullNodeId.substring(0, 16);
}

class CalDAVServer {
  static const int defaultPort = 19324;
  static const String _calendarPathSegment = 'default';

  final CLogger _log = CLogger.get('caldav-server');
  final InternetAddress _bindAddress;
  int _configuredPort;

  /// Daemon-wide auth token. Set via [setToken], null if not configured.
  String? _token;

  /// Map: shortId → identity. Populated via [registerIdentity].
  final Map<String, CalDAVServerIdentity> _byShortId = {};

  HttpServer? _server;
  bool _running = false;

  CalDAVServer({
    int port = defaultPort,
    InternetAddress? bindAddress,
  })  : _configuredPort = port,
        _bindAddress = bindAddress ?? InternetAddress.loopbackIPv4;

  // ── Lifecycle ────────────────────────────────────────────────────────

  bool get isRunning => _running;
  int? get boundPort => _server?.port;

  Future<int> start() async {
    if (_running) return _server!.port;
    _server = await HttpServer.bind(_bindAddress, _configuredPort);
    _running = true;
    _server!.listen(
      _dispatch,
      onError: (e, st) {
        _log.warn('HTTP listener error: $e');
      },
      cancelOnError: false,
    );
    _log.info('Local CalDAV server listening on '
        '${_bindAddress.address}:${_server!.port}');
    return _server!.port;
  }

  Future<void> stop() async {
    if (!_running) return;
    await _server?.close(force: true);
    _server = null;
    _running = false;
    _log.info('Local CalDAV server stopped');
  }

  /// Update the port for the next [start] call. If already running, the
  /// server is restarted on the new port.
  Future<void> setPort(int port) async {
    _configuredPort = port;
    if (_running) {
      await stop();
      await start();
    }
  }

  /// Set (or clear) the daemon-wide authentication token. Passing null
  /// disables the server's auth check — do not use in production.
  void setToken(String? token) {
    _token = token;
  }

  String? get token => _token;

  // ── Identity registration ────────────────────────────────────────────

  void registerIdentity(CalDAVServerIdentity id) {
    _byShortId[id.shortId] = id;
    _log.info('Registered identity ${id.shortId} '
        '(${id.displayName}, ${id.calendar.events.length} events)');
  }

  void unregisterIdentity(String fullNodeId) {
    final short = fullNodeId.length <= 16
        ? fullNodeId
        : fullNodeId.substring(0, 16);
    _byShortId.remove(short);
    _log.info('Unregistered identity $short');
  }

  List<CalDAVServerIdentity> get identities =>
      List.unmodifiable(_byShortId.values);

  // ── HTTP dispatch ────────────────────────────────────────────────────

  Future<void> _dispatch(HttpRequest req) async {
    final method = req.method.toUpperCase();
    final path = req.uri.path;
    _log.debug('$method $path');

    try {
      // DNS-rebinding defense: a browser on a malicious site that resolves
      // an attacker domain to 127.0.0.1 would send Host: attacker.tld. We
      // bind only to loopback, so a legitimate local client always reaches
      // us via 127.0.0.1 / ::1 / localhost. Reject anything else.
      if (!_isLoopbackHost(req.headers.value('host'))) {
        await _send(req, 421, body: 'Misdirected Request');
        return;
      }

      // Some clients (Apple Calendar.app) send a bare OPTIONS to discover
      // capabilities before presenting credentials. Answer unconditionally.
      if (method == 'OPTIONS') {
        await _handleOptions(req);
        return;
      }

      final authedShort = _checkAuth(req);
      if (authedShort == null) {
        req.response.headers
            .set('WWW-Authenticate', 'Basic realm="Cleona CalDAV"');
        await _send(req, 401, body: 'Unauthorized');
        return;
      }

      switch (method) {
        case 'PROPFIND':
          await _handlePropfind(req, path, authedShort);
          break;
        case 'REPORT':
          await _handleReport(req, path, authedShort);
          break;
        case 'GET':
          await _handleGet(req, path, authedShort);
          break;
        case 'PUT':
          await _handlePut(req, path, authedShort);
          break;
        case 'DELETE':
          await _handleDelete(req, path, authedShort);
          break;
        case 'MKCALENDAR':
          // Clients occasionally probe for calendar-collection creation.
          // We always have exactly one calendar per identity, so answer 405.
          await _send(req, 405, body: 'Method Not Allowed');
          break;
        default:
          await _send(req, 405, body: 'Method Not Allowed');
      }
    } on _BodyTooLarge {
      _log.warn('Rejected oversized body on $method $path');
      await _send(req, 413, body: 'Payload Too Large');
    } catch (e, st) {
      _log.warn('Dispatch error on $method $path: $e\n$st');
      await _send(req, 500, body: 'Internal server error');
    }
  }

  /// Returns the authenticated identity's shortId, or null if auth fails.
  String? _checkAuth(HttpRequest req) {
    if (_token == null || _token!.isEmpty) {
      // No token configured — refuse all requests. Safer than allowing
      // anonymous access when this file is shipped by default.
      return null;
    }
    final header = req.headers.value('Authorization');
    if (header == null || !header.startsWith('Basic ')) return null;
    final decoded = utf8.decode(base64.decode(header.substring(6)));
    final colon = decoded.indexOf(':');
    if (colon < 0) return null;
    final user = decoded.substring(0, colon);
    final pass = decoded.substring(colon + 1);
    if (!_constantTimeEquals(pass, _token!)) return null;
    if (!_byShortId.containsKey(user)) return null;
    return user;
  }

  /// Timing-safe string comparison — prevents an attacker on the loopback
  /// from deriving the token char-by-char via response-time measurement.
  static bool _constantTimeEquals(String a, String b) {
    final ab = utf8.encode(a);
    final bb = utf8.encode(b);
    final len = ab.length > bb.length ? ab.length : bb.length;
    var diff = ab.length ^ bb.length;
    for (var i = 0; i < len; i++) {
      final av = i < ab.length ? ab[i] : 0;
      final bv = i < bb.length ? bb[i] : 0;
      diff |= av ^ bv;
    }
    return diff == 0;
  }

  /// True iff the client's Host header names a loopback destination.
  /// Accepts 127.0.0.1, ::1, localhost (with or without port).
  static bool _isLoopbackHost(String? host) {
    if (host == null || host.isEmpty) return false;
    // Strip port. IPv6 literals come bracketed: [::1]:19324.
    String h = host;
    if (h.startsWith('[')) {
      final close = h.indexOf(']');
      if (close < 0) return false;
      h = h.substring(1, close);
    } else {
      final colon = h.lastIndexOf(':');
      if (colon > 0) h = h.substring(0, colon);
    }
    h = h.toLowerCase();
    return h == '127.0.0.1' || h == 'localhost' || h == '::1';
  }

  // ── OPTIONS ──────────────────────────────────────────────────────────

  Future<void> _handleOptions(HttpRequest req) async {
    req.response.statusCode = 200;
    // `1, 2, 3` enable the base WebDAV behaviours Thunderbird probes for;
    // `calendar-access` is the RFC 4791 capability flag.
    req.response.headers.set('DAV', '1, 2, 3, calendar-access');
    req.response.headers.set('Allow',
        'OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, REPORT');
    req.response.headers.set('Content-Length', '0');
    await req.response.close();
  }

  // ── PROPFIND ─────────────────────────────────────────────────────────

  Future<void> _handlePropfind(
      HttpRequest req, String path, String authedShort) async {
    final body = await _readBody(req);
    final depth = req.headers.value('Depth') ?? '0';

    // Discover: root or /dav/ → return the user's principal URL.
    if (path == '/' || path == '/dav' || path == '/dav/') {
      if (body.contains('current-user-principal')) {
        await _respondPrincipalDiscovery(req, authedShort);
        return;
      }
      // Some clients do PROPFIND on /dav/ for a resourcetype check.
      await _respondRootResource(req);
      return;
    }

    // Principal resource: /dav/principals/<short>/
    final principalPrefix = '/dav/principals/$authedShort';
    if (path == '$principalPrefix/' || path == principalPrefix) {
      await _respondPrincipal(req, authedShort);
      return;
    }

    // Calendar home: /dav/calendars/<short>/
    final calHomePrefix = '/dav/calendars/$authedShort';
    if (path == '$calHomePrefix/' || path == calHomePrefix) {
      if (depth == '1') {
        await _respondCalendarHomeDepth1(req, authedShort);
      } else {
        await _respondCalendarHome(req, authedShort);
      }
      return;
    }

    // Calendar collection: /dav/calendars/<short>/default/
    final calPrefix = '$calHomePrefix/$_calendarPathSegment';
    if (path == '$calPrefix/' || path == calPrefix) {
      if (depth == '1') {
        await _respondCalendarDepth1(req, authedShort);
      } else {
        await _respondCalendar(req, authedShort);
      }
      return;
    }

    // Individual event resource.
    if (path.startsWith('$calPrefix/') && path.endsWith('.ics')) {
      final eventId = _eventIdFromPath(path, calPrefix);
      await _respondEventProps(req, authedShort, eventId);
      return;
    }

    await _send(req, 404, body: 'Not Found');
  }

  Future<void> _respondPrincipalDiscovery(
      HttpRequest req, String authedShort) async {
    final principalHref = '/dav/principals/$authedShort/';
    final body =
        '<?xml version="1.0" encoding="UTF-8"?>\n<d:multistatus xmlns:d="DAV:">\n'
        '  <d:response>\n'
        '    <d:href>${req.uri.path}</d:href>\n'
        '    <d:propstat>\n'
        '      <d:prop>\n'
        '        <d:current-user-principal><d:href>$principalHref</d:href></d:current-user-principal>\n'
        '      </d:prop>\n'
        '      <d:status>HTTP/1.1 200 OK</d:status>\n'
        '    </d:propstat>\n'
        '  </d:response>\n'
        '</d:multistatus>';
    await _send(req, 207, body: body, contentType: 'application/xml');
  }

  Future<void> _respondRootResource(HttpRequest req) async {
    final body =
        '<?xml version="1.0" encoding="UTF-8"?>\n<d:multistatus xmlns:d="DAV:">\n'
        '  <d:response>\n'
        '    <d:href>${req.uri.path}</d:href>\n'
        '    <d:propstat>\n'
        '      <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>\n'
        '      <d:status>HTTP/1.1 200 OK</d:status>\n'
        '    </d:propstat>\n'
        '  </d:response>\n'
        '</d:multistatus>';
    await _send(req, 207, body: body, contentType: 'application/xml');
  }

  Future<void> _respondPrincipal(
      HttpRequest req, String authedShort) async {
    final identity = _byShortId[authedShort]!;
    final calendarHomeHref = '/dav/calendars/$authedShort/';
    final body =
        '<?xml version="1.0" encoding="UTF-8"?>\n<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">\n'
        '  <d:response>\n'
        '    <d:href>${req.uri.path}</d:href>\n'
        '    <d:propstat>\n'
        '      <d:prop>\n'
        '        <d:displayname>${_xmlEscape(identity.displayName)}</d:displayname>\n'
        '        <d:resourcetype><d:principal/></d:resourcetype>\n'
        '        <c:calendar-home-set><d:href>$calendarHomeHref</d:href></c:calendar-home-set>\n'
        '      </d:prop>\n'
        '      <d:status>HTTP/1.1 200 OK</d:status>\n'
        '    </d:propstat>\n'
        '  </d:response>\n'
        '</d:multistatus>';
    await _send(req, 207, body: body, contentType: 'application/xml');
  }

  Future<void> _respondCalendarHome(
      HttpRequest req, String authedShort) async {
    final body =
        '<?xml version="1.0" encoding="UTF-8"?>\n<d:multistatus xmlns:d="DAV:">\n'
        '  <d:response>\n'
        '    <d:href>${req.uri.path}</d:href>\n'
        '    <d:propstat>\n'
        '      <d:prop>\n'
        '        <d:displayname>Calendars</d:displayname>\n'
        '        <d:resourcetype><d:collection/></d:resourcetype>\n'
        '      </d:prop>\n'
        '      <d:status>HTTP/1.1 200 OK</d:status>\n'
        '    </d:propstat>\n'
        '  </d:response>\n'
        '</d:multistatus>';
    await _send(req, 207, body: body, contentType: 'application/xml');
  }

  Future<void> _respondCalendarHomeDepth1(
      HttpRequest req, String authedShort) async {
    final identity = _byShortId[authedShort]!;
    final ctag = _computeCtag(identity);
    final calendarHref = '/dav/calendars/$authedShort/$_calendarPathSegment/';
    final buf = StringBuffer();
    buf.write('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">\n');
    // Self (the calendar home collection itself).
    buf.write(_responseCalendarHomeSelf(req.uri.path));
    // The single calendar collection.
    buf.write(_responseCalendar(
      calendarHref,
      displayName: identity.displayName,
      ctag: ctag,
    ));
    buf.write('</d:multistatus>');
    await _send(req, 207, body: buf.toString(), contentType: 'application/xml');
  }

  String _responseCalendarHomeSelf(String href) => '  <d:response>\n'
      '    <d:href>$href</d:href>\n'
      '    <d:propstat>\n'
      '      <d:prop>\n'
      '        <d:displayname>Calendars</d:displayname>\n'
      '        <d:resourcetype><d:collection/></d:resourcetype>\n'
      '      </d:prop>\n'
      '      <d:status>HTTP/1.1 200 OK</d:status>\n'
      '    </d:propstat>\n'
      '  </d:response>\n';

  String _responseCalendar(
    String href, {
    required String displayName,
    required String ctag,
  }) =>
      '  <d:response>\n'
      '    <d:href>$href</d:href>\n'
      '    <d:propstat>\n'
      '      <d:prop>\n'
      '        <d:displayname>${_xmlEscape(displayName)}</d:displayname>\n'
      '        <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>\n'
      '        <c:supported-calendar-component-set>\n'
      '          <c:comp name="VEVENT"/>\n'
      '          <c:comp name="VTODO"/>\n'
      '        </c:supported-calendar-component-set>\n'
      '        <cs:getctag>$ctag</cs:getctag>\n'
      '      </d:prop>\n'
      '      <d:status>HTTP/1.1 200 OK</d:status>\n'
      '    </d:propstat>\n'
      '  </d:response>\n';

  Future<void> _respondCalendar(
      HttpRequest req, String authedShort) async {
    final identity = _byShortId[authedShort]!;
    final ctag = _computeCtag(identity);
    final body =
        '<?xml version="1.0" encoding="UTF-8"?>\n<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">\n'
        '${_responseCalendar(req.uri.path, displayName: identity.displayName, ctag: ctag)}'
        '</d:multistatus>';
    await _send(req, 207, body: body, contentType: 'application/xml');
  }

  Future<void> _respondCalendarDepth1(
      HttpRequest req, String authedShort) async {
    final identity = _byShortId[authedShort]!;
    final ctag = _computeCtag(identity);
    final calendarHref = req.uri.path;
    final buf = StringBuffer();
    buf.write('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">\n');
    buf.write(_responseCalendar(calendarHref,
        displayName: identity.displayName, ctag: ctag));
    for (final event in identity.calendar.events.values) {
      if (event.cancelled) continue;
      buf.write(_responseEventProps(
        calendarHref: calendarHref,
        event: event,
      ));
    }
    buf.write('</d:multistatus>');
    await _send(req, 207, body: buf.toString(), contentType: 'application/xml');
  }

  String _responseEventProps({
    required String calendarHref,
    required CalendarEvent event,
  }) {
    final href = '$calendarHref${event.eventId}.ics';
    final etag = _etagOf(event);
    return '  <d:response>\n'
        '    <d:href>$href</d:href>\n'
        '    <d:propstat>\n'
        '      <d:prop>\n'
        '        <d:getetag>"$etag"</d:getetag>\n'
        '        <d:getcontenttype>text/calendar; charset=utf-8; component=vevent</d:getcontenttype>\n'
        '      </d:prop>\n'
        '      <d:status>HTTP/1.1 200 OK</d:status>\n'
        '    </d:propstat>\n'
        '  </d:response>\n';
  }

  Future<void> _respondEventProps(
      HttpRequest req, String authedShort, String eventId) async {
    final identity = _byShortId[authedShort]!;
    final event = identity.calendar.events[eventId];
    if (event == null) {
      await _send(req, 404, body: 'Not Found');
      return;
    }
    final calendarHref = '/dav/calendars/$authedShort/$_calendarPathSegment/';
    final body =
        '<?xml version="1.0" encoding="UTF-8"?>\n<d:multistatus xmlns:d="DAV:">\n'
        '${_responseEventProps(calendarHref: calendarHref, event: event)}'
        '</d:multistatus>';
    await _send(req, 207, body: body, contentType: 'application/xml');
  }

  // ── REPORT ───────────────────────────────────────────────────────────

  Future<void> _handleReport(
      HttpRequest req, String path, String authedShort) async {
    final body = await _readBody(req);
    final identity = _byShortId[authedShort]!;
    final calPrefix = '/dav/calendars/$authedShort/$_calendarPathSegment';
    if (path != '$calPrefix/' && path != calPrefix) {
      await _send(req, 404, body: 'Not Found');
      return;
    }
    final calendarHref = '$calPrefix/';

    // Two REPORTs are commonly issued:
    //   - <c:calendar-query>  → list events (with optional time-range filter,
    //     which we ignore and return all — Thunderbird filters locally).
    //   - <c:calendar-multiget>  → fetch iCal bodies of the listed hrefs.
    if (body.contains('calendar-multiget')) {
      await _respondMultiget(req, identity, body, calendarHref);
    } else {
      // Default: calendar-query (even on unknown REPORTs, return the event
      // list — matches what Baikal does for forward compatibility).
      await _respondCalendarQuery(req, identity, calendarHref);
    }
  }

  Future<void> _respondCalendarQuery(HttpRequest req,
      CalDAVServerIdentity identity, String calendarHref) async {
    final buf = StringBuffer();
    buf.write('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<d:multistatus xmlns:d="DAV:">\n');
    for (final event in identity.calendar.events.values) {
      if (event.cancelled) continue;
      buf.write(_responseEventProps(
        calendarHref: calendarHref,
        event: event,
      ));
    }
    buf.write('</d:multistatus>');
    await _send(req, 207, body: buf.toString(), contentType: 'application/xml');
  }

  Future<void> _respondMultiget(HttpRequest req,
      CalDAVServerIdentity identity, String body, String calendarHref) async {
    // Extract <d:href>...</d:href> elements from the REQUEST body, not
    // the server response. These tell us which events the client wants.
    final hrefRe = RegExp(r'<(?:\w+:)?href(?:\s[^>]*)?>([^<]+)</(?:\w+:)?href>',
        caseSensitive: false);
    final hrefs = hrefRe
        .allMatches(body)
        .map((m) => m.group(1)!.trim())
        .where((h) => h.startsWith('/dav/calendars/'))
        .toList();
    final buf = StringBuffer();
    buf.write('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">\n');
    for (final h in hrefs) {
      if (!h.startsWith(calendarHref) || !h.endsWith('.ics')) {
        buf.write('  <d:response>\n'
            '    <d:href>$h</d:href>\n'
            '    <d:status>HTTP/1.1 404 Not Found</d:status>\n'
            '  </d:response>\n');
        continue;
      }
      final eventId = _eventIdFromPath(h, calendarHref.substring(0, calendarHref.length - 1));
      final event = identity.calendar.events[eventId];
      if (event == null) {
        buf.write('  <d:response>\n'
            '    <d:href>$h</d:href>\n'
            '    <d:status>HTTP/1.1 404 Not Found</d:status>\n'
            '  </d:response>\n');
        continue;
      }
      final etag = _etagOf(event);
      final ical = _xmlEscape(ICalEngine.exportEventToIcs(event));
      buf.write('  <d:response>\n'
          '    <d:href>$h</d:href>\n'
          '    <d:propstat>\n'
          '      <d:prop>\n'
          '        <d:getetag>"$etag"</d:getetag>\n'
          '        <c:calendar-data>$ical</c:calendar-data>\n'
          '      </d:prop>\n'
          '      <d:status>HTTP/1.1 200 OK</d:status>\n'
          '    </d:propstat>\n'
          '  </d:response>\n');
    }
    buf.write('</d:multistatus>');
    await _send(req, 207, body: buf.toString(), contentType: 'application/xml');
  }

  // ── GET / PUT / DELETE on individual events ──────────────────────────

  Future<void> _handleGet(
      HttpRequest req, String path, String authedShort) async {
    final identity = _byShortId[authedShort]!;
    final calPrefix = '/dav/calendars/$authedShort/$_calendarPathSegment';
    if (!path.startsWith('$calPrefix/') || !path.endsWith('.ics')) {
      await _send(req, 404, body: 'Not Found');
      return;
    }
    final eventId = _eventIdFromPath(path, calPrefix);
    final event = identity.calendar.events[eventId];
    if (event == null) {
      await _send(req, 404, body: 'Not Found');
      return;
    }
    final etag = _etagOf(event);
    final ical = ICalEngine.exportEventToIcs(event);
    req.response.statusCode = 200;
    req.response.headers
        .set('Content-Type', 'text/calendar; charset=utf-8');
    req.response.headers.set('ETag', '"$etag"');
    req.response.write(ical);
    await req.response.close();
  }

  Future<void> _handlePut(
      HttpRequest req, String path, String authedShort) async {
    final identity = _byShortId[authedShort]!;
    final calPrefix = '/dav/calendars/$authedShort/$_calendarPathSegment';
    if (!path.startsWith('$calPrefix/') || !path.endsWith('.ics')) {
      await _send(req, 404, body: 'Not Found');
      return;
    }
    final eventId = _eventIdFromPath(path, calPrefix);
    final existing = identity.calendar.events[eventId];
    final ifNoneMatch = req.headers.value('If-None-Match');
    final ifMatch = req.headers.value('If-Match');

    if (ifNoneMatch == '*' && existing != null) {
      await _send(req, 412, body: 'Precondition Failed (exists)');
      return;
    }
    if (ifMatch != null && existing != null) {
      final clean = _stripQuotes(ifMatch);
      if (clean != _etagOf(existing)) {
        await _send(req, 412, body: 'Precondition Failed (etag mismatch)');
        return;
      }
    }

    final body = await _readBody(req);
    final parsed = ICalEngine.importFromIcs(
      body,
      identityId: identity.fullNodeId,
      createdBy: identity.fullNodeId,
    );
    if (parsed.isEmpty) {
      await _send(req, 400, body: 'Bad Request: no VEVENT/VTODO found');
      return;
    }
    // Force the event's UID to match the URL basename. Most desktop
    // clients keep the two in sync, but servers are authoritative about
    // the on-disk layout — if we stored the event under its self-declared
    // UID instead of the URL, a subsequent GET on the URL would 404 and
    // confuse Thunderbird's ETag cache.
    final imported = parsed.first;
    final json = imported.toJson();
    json['eventId'] = eventId;
    final stored = CalendarEvent.fromJson(json);
    identity.calendar.events[eventId] = stored;
    identity.calendar.save();

    req.response.statusCode = existing == null ? 201 : 204;
    req.response.headers.set('ETag', '"${_etagOf(stored)}"');
    await req.response.close();
  }

  Future<void> _handleDelete(
      HttpRequest req, String path, String authedShort) async {
    final identity = _byShortId[authedShort]!;
    final calPrefix = '/dav/calendars/$authedShort/$_calendarPathSegment';
    if (!path.startsWith('$calPrefix/') || !path.endsWith('.ics')) {
      await _send(req, 404, body: 'Not Found');
      return;
    }
    final eventId = _eventIdFromPath(path, calPrefix);
    final existing = identity.calendar.events[eventId];
    if (existing == null) {
      // Per RFC 7231 this could be 404 or 204 (idempotent delete). Clients
      // typically accept both; return 404 so they update their ETag cache.
      await _send(req, 404, body: 'Not Found');
      return;
    }
    final ifMatch = req.headers.value('If-Match');
    if (ifMatch != null) {
      final clean = _stripQuotes(ifMatch);
      if (clean != _etagOf(existing)) {
        await _send(req, 412, body: 'Precondition Failed');
        return;
      }
    }
    identity.calendar.deleteEvent(eventId);
    await _send(req, 204);
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Maximum request body we'll accept. A single iCal event is typically
  /// a few kilobytes; 5 MB leaves headroom for VALARMs, attendees, and
  /// pathological but legitimate PROPFIND bodies. Beyond this, a client
  /// (or a browser tricked via DNS rebinding, see _isLoopbackHost) could
  /// OOM the daemon by trickling bytes.
  static const int _maxBodyBytes = 5 * 1024 * 1024;

  /// Reads the request body with a size cap. Throws [_BodyTooLarge] when
  /// the cap is exceeded so the caller can answer 413 without the server
  /// already having buffered gigabytes.
  Future<String> _readBody(HttpRequest req) async {
    final bytes = <int>[];
    await for (final chunk in req) {
      if (bytes.length + chunk.length > _maxBodyBytes) {
        throw const _BodyTooLarge();
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> _send(HttpRequest req, int status,
      {String? body, String? contentType}) async {
    req.response.statusCode = status;
    if (contentType != null) {
      req.response.headers.set('Content-Type', contentType);
    }
    if (body != null) {
      req.response.write(body);
    }
    await req.response.close();
  }

  String _etagOf(CalendarEvent event) {
    // Per-event monotonic: the wall clock of the last edit. Two edits in
    // the same millisecond get the same ETag — acceptable because the
    // server also stores the event body, so a stale If-Match mismatch
    // falls back to a fresh GET which clients handle.
    return '${event.eventId}-${event.updatedAt}';
  }

  String _computeCtag(CalDAVServerIdentity identity) {
    // Collection tag = (max updatedAt) . (event count). Any add, edit, or
    // delete will change one of these.
    var maxMs = 0;
    for (final e in identity.calendar.events.values) {
      if (e.updatedAt > maxMs) maxMs = e.updatedAt;
    }
    return '"$maxMs.${identity.calendar.events.length}"';
  }

  String _eventIdFromPath(String path, String calPrefix) {
    final withoutPrefix = path.startsWith('$calPrefix/')
        ? path.substring(calPrefix.length + 1)
        : path;
    final stripped = withoutPrefix.endsWith('.ics')
        ? withoutPrefix.substring(0, withoutPrefix.length - 4)
        : withoutPrefix;
    return Uri.decodeComponent(stripped);
  }

  String _stripQuotes(String etag) {
    var e = etag.trim();
    if (e.startsWith('W/')) e = e.substring(2).trim();
    if (e.startsWith('"') && e.endsWith('"') && e.length >= 2) {
      e = e.substring(1, e.length - 1);
    }
    return e;
  }

  String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

class _BodyTooLarge implements Exception {
  const _BodyTooLarge();
}
