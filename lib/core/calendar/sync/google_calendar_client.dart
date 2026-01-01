import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/calendar/sync/sync_types.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Google Calendar API v3 client with OAuth2 (Installed Application flow).
///
/// Uses the "Loopback IP" redirect method per RFC 8252, so no client secret
/// is required on desktop: the app starts a one-shot HTTP server on
/// `127.0.0.1:<randomPort>`, opens the system browser to Google's consent
/// screen, and receives the authorization code on the loopback redirect.
/// PKCE (RFC 7636) is used to protect the exchange.
///
/// The refresh_token is long-lived and stored encrypted (see [GoogleCalendarConfig]).
/// Access tokens are refreshed automatically when they expire.
class GoogleCalendarClient {
  static const String _oauthAuthUrl = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const String _oauthTokenUrl = 'https://oauth2.googleapis.com/token';
  static const String _calendarApiBase = 'https://www.googleapis.com/calendar/v3';
  static const String _scope = 'https://www.googleapis.com/auth/calendar';
  static const String _userInfoUrl =
      'https://openidconnect.googleapis.com/v1/userinfo';

  final HttpClient _http;
  GoogleCalendarConfig config;

  GoogleCalendarClient(this.config)
      : _http = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  void close() => _http.close(force: true);

  // ── OAuth Flow ─────────────────────────────────────────────────────

  /// Begin the OAuth2 flow. Returns a record with:
  /// - [authUrl] — the URL to open in the system browser.
  /// - [waitForCompletion] — future that resolves to a [GoogleCalendarConfig]
  ///   once the user completes consent (or times out after 5 minutes).
  ///
  /// Caller opens [authUrl] in the user's browser (e.g., via `url_launcher`).
  static Future<GoogleOAuthHandle> startOAuthFlow({
    required String clientId,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final verifier = _randomUrlSafe(48);
    final challenge = _pkceChallenge(verifier);
    final state = _randomUrlSafe(24);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/oauth2/callback';

    final authUri = Uri.parse(_oauthAuthUrl).replace(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scope,
      'access_type': 'offline',
      'prompt': 'consent',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
    });

    final completer = Completer<GoogleCalendarConfig>();

    // Listen for the redirect. Single response, then close server.
    late StreamSubscription<HttpRequest> sub;
    sub = server.listen((req) async {
      final uri = req.uri;
      if (uri.path != '/oauth2/callback') {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final returnedState = uri.queryParameters['state'];
      final code = uri.queryParameters['code'];
      final error = uri.queryParameters['error'];

      // Respond to browser first so the user sees a friendly page.
      req.response.headers.contentType =
          ContentType('text', 'html', charset: 'utf-8');
      if (error != null || code == null || returnedState != state) {
        req.response.statusCode = 400;
        req.response.write(_htmlMessage(
            'Authorization failed',
            'You may close this window. Error: '
                '${error ?? (code == null ? 'no code' : 'state mismatch')}'));
      } else {
        req.response.write(_htmlMessage(
            'Cleona connected to Google Calendar',
            'You can close this window and return to Cleona.'));
      }
      await req.response.close();
      await sub.cancel();
      await server.close();

      if (completer.isCompleted) return;
      if (error != null) {
        completer.completeError(
            GoogleCalendarException('Google OAuth error: $error'));
        return;
      }
      if (code == null || returnedState != state) {
        completer.completeError(GoogleCalendarException(
            'OAuth callback missing code or state mismatch.'));
        return;
      }

      try {
        final cfg = await _exchangeCodeForTokens(
          clientId: clientId,
          code: code,
          redirectUri: redirectUri,
          verifier: verifier,
        );
        completer.complete(cfg);
      } catch (e) {
        completer.completeError(e);
      }
    });

    // Safety timeout — user never returns.
    Timer(timeout, () async {
      if (!completer.isCompleted) {
        await sub.cancel();
        await server.close();
        completer.completeError(
            GoogleCalendarException('OAuth timed out after ${timeout.inMinutes} minutes'));
      }
    });

    return GoogleOAuthHandle(
      authUrl: authUri.toString(),
      waitForCompletion: completer.future,
      port: server.port,
    );
  }

  static Future<GoogleCalendarConfig> _exchangeCodeForTokens({
    required String clientId,
    required String code,
    required String redirectUri,
    required String verifier,
  }) async {
    final body = {
      'code': code,
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
      'code_verifier': verifier,
    };

    final resp = await _postForm(Uri.parse(_oauthTokenUrl), body);
    if (resp.statusCode != 200) {
      throw GoogleCalendarException(
          'Token exchange failed: HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String?;
    final refreshToken = json['refresh_token'] as String?;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    if (accessToken == null || refreshToken == null) {
      throw GoogleCalendarException(
          'Token response missing access_token or refresh_token');
    }

    final email = await _fetchAccountEmail(accessToken);

    return GoogleCalendarConfig(
      clientId: clientId,
      accountEmail: email,
      refreshToken: refreshToken,
      accessToken: accessToken,
      accessTokenExpiresAt:
          DateTime.now().millisecondsSinceEpoch + (expiresIn - 60) * 1000,
    );
  }

  static Future<String> _fetchAccountEmail(String accessToken) async {
    try {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse(_userInfoUrl));
        req.headers.set('Authorization', 'Bearer $accessToken');
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();
        if (resp.statusCode == 200) {
          final j = jsonDecode(body) as Map<String, dynamic>;
          return (j['email'] as String?) ?? '';
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      // Non-critical — missing email is fine.
    }
    return '';
  }

  /// Refresh the access token if it has expired (or is about to).
  Future<void> ensureAccessToken({int graceMs = 60000}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (config.accessToken.isNotEmpty &&
        config.accessTokenExpiresAt > now + graceMs) {
      return;
    }
    await _refreshAccessToken();
  }

  Future<void> _refreshAccessToken() async {
    final body = {
      'client_id': config.clientId,
      'refresh_token': config.refreshToken,
      'grant_type': 'refresh_token',
    };
    final resp = await _postForm(Uri.parse(_oauthTokenUrl), body);
    if (resp.statusCode != 200) {
      throw GoogleCalendarException(
          'Token refresh failed: HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String?;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    if (accessToken == null) {
      throw GoogleCalendarException('Token refresh response missing access_token');
    }
    config.accessToken = accessToken;
    config.accessTokenExpiresAt =
        DateTime.now().millisecondsSinceEpoch + (expiresIn - 60) * 1000;
  }

  // ── Calendar API ───────────────────────────────────────────────────

  Future<_HttpResponse> _apiRequest(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? jsonBody,
  }) async {
    await ensureAccessToken();

    final uri = Uri.parse('$_calendarApiBase$path')
        .replace(queryParameters: query?.isEmpty == true ? null : query);
    final req = await _http.openUrl(method, uri);
    req.headers.set('Authorization', 'Bearer ${config.accessToken}');
    if (jsonBody != null) {
      req.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode(jsonBody));
      req.contentLength = bytes.length;
      req.add(bytes);
    }
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();

    // If token expired mid-flight, refresh + retry once.
    if (resp.statusCode == 401 && jsonBody == null) {
      await _refreshAccessToken();
      return _apiRequest(method, path, query: query, jsonBody: jsonBody);
    }

    return _HttpResponse(resp.statusCode, body);
  }

  /// List calendars the user has access to.
  Future<List<GoogleCalendarListEntry>> listCalendars() async {
    final resp = await _apiRequest('GET', '/users/me/calendarList');
    if (resp.statusCode != 200) {
      throw GoogleCalendarException(
          'listCalendars failed: HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (json['items'] as List?) ?? [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(GoogleCalendarListEntry.fromJson)
        .toList();
  }

  /// Incremental event list. Use [syncToken] for delta queries (null on first
  /// call or after a 410 Gone). Returns the page plus the next sync/page token.
  Future<GoogleEventPage> listEvents({
    String? syncToken,
    String? pageToken,
    DateTime? timeMin,
    DateTime? timeMax,
    int maxResults = 250,
  }) async {
    final q = <String, String>{
      'maxResults': '$maxResults',
      'showDeleted': 'true',
      'singleEvents': 'false',
    };
    if (syncToken != null) {
      q['syncToken'] = syncToken;
    } else {
      if (timeMin != null) q['timeMin'] = timeMin.toUtc().toIso8601String();
      if (timeMax != null) q['timeMax'] = timeMax.toUtc().toIso8601String();
    }
    if (pageToken != null) q['pageToken'] = pageToken;

    final resp = await _apiRequest(
      'GET',
      '/calendars/${Uri.encodeComponent(config.calendarId)}/events',
      query: q,
    );

    if (resp.statusCode == 410) {
      // Sync token invalid — caller must full-resync.
      throw GoogleSyncTokenExpired();
    }
    if (resp.statusCode != 200) {
      throw GoogleCalendarException(
          'listEvents failed: HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (json['items'] as List?) ?? [];
    return GoogleEventPage(
      events: items.whereType<Map<String, dynamic>>().toList(),
      nextPageToken: json['nextPageToken'] as String?,
      nextSyncToken: json['nextSyncToken'] as String?,
    );
  }

  Future<Map<String, dynamic>> insertEvent(Map<String, dynamic> eventJson) async {
    final resp = await _apiRequest(
      'POST',
      '/calendars/${Uri.encodeComponent(config.calendarId)}/events',
      jsonBody: eventJson,
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw GoogleCalendarException(
          'insertEvent failed: HTTP ${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateEvent(
      String eventId, Map<String, dynamic> eventJson) async {
    final resp = await _apiRequest(
      'PUT',
      '/calendars/${Uri.encodeComponent(config.calendarId)}/events/${Uri.encodeComponent(eventId)}',
      jsonBody: eventJson,
    );
    if (resp.statusCode != 200) {
      throw GoogleCalendarException(
          'updateEvent failed: HTTP ${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> deleteEvent(String eventId) async {
    final resp = await _apiRequest(
      'DELETE',
      '/calendars/${Uri.encodeComponent(config.calendarId)}/events/${Uri.encodeComponent(eventId)}',
    );
    if (resp.statusCode != 204 && resp.statusCode != 200 &&
        resp.statusCode != 410) {
      throw GoogleCalendarException(
          'deleteEvent failed: HTTP ${resp.statusCode}: ${resp.body}');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  static Future<_HttpResponse> _postForm(
      Uri uri, Map<String, String> formData) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      final body = formData.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final bytes = utf8.encode(body);
      req.contentLength = bytes.length;
      req.add(bytes);
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      return _HttpResponse(resp.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  static String _randomUrlSafe(int byteCount) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _pkceChallenge(String verifier) {
    final sodium = SodiumFFI();
    final hash = sodium.sha256(Uint8List.fromList(utf8.encode(verifier)));
    return base64Url.encode(hash).replaceAll('=', '');
  }

  static String _htmlMessage(String title, String body) {
    return '<html><head><meta charset="utf-8"><title>Cleona</title>'
        '<style>body{font-family:system-ui,sans-serif;max-width:480px;'
        'margin:80px auto;padding:32px;border-radius:12px;background:#f7f7f9;'
        'color:#222}</style></head><body>'
        '<h2>$title</h2><p>$body</p></body></html>';
  }
}

class GoogleOAuthHandle {
  final String authUrl;
  final Future<GoogleCalendarConfig> waitForCompletion;
  final int port;
  GoogleOAuthHandle({
    required this.authUrl,
    required this.waitForCompletion,
    required this.port,
  });
}

class GoogleCalendarListEntry {
  final String id;
  final String summary;
  final bool primary;
  final String accessRole;
  GoogleCalendarListEntry({
    required this.id,
    required this.summary,
    required this.primary,
    required this.accessRole,
  });

  factory GoogleCalendarListEntry.fromJson(Map<String, dynamic> json) =>
      GoogleCalendarListEntry(
        id: json['id'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        primary: json['primary'] as bool? ?? false,
        accessRole: json['accessRole'] as String? ?? 'reader',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'summary': summary,
        'primary': primary,
        'accessRole': accessRole,
      };
}

class GoogleEventPage {
  final List<Map<String, dynamic>> events;
  final String? nextPageToken;
  final String? nextSyncToken;
  GoogleEventPage({
    required this.events,
    this.nextPageToken,
    this.nextSyncToken,
  });
}

class _HttpResponse {
  final int statusCode;
  final String body;
  _HttpResponse(this.statusCode, this.body);
}

class GoogleCalendarException implements Exception {
  final String message;
  GoogleCalendarException(this.message);
  @override
  String toString() => 'GoogleCalendarException: $message';
}

class GoogleSyncTokenExpired implements Exception {
  @override
  String toString() => 'GoogleSyncTokenExpired: sync token invalid, full re-sync required';
}
