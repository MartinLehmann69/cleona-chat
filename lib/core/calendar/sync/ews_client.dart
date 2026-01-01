import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/calendar/sync/sync_types.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Exchange Web Services (EWS) client for calendar sync.
///
/// Supports:
/// - EWS Autodiscover (v1 XML + v2 JSON) for endpoint resolution
/// - OAuth2 for Microsoft 365 (loopback redirect + PKCE)
/// - Basic auth for on-premise Exchange
/// - Calendar CRUD: FindItem, GetItem, CreateItem, UpdateItem, DeleteItem
///
/// Pure Dart — no native dependencies beyond [SodiumFFI] (for PKCE SHA-256).
class EWSClient {
  // ── Microsoft Identity Platform ──────────────────────────────────────
  static const String _msOAuthAuthorizeUrl =
      'https://login.microsoftonline.com/common/oauth2/v2.0/authorize';
  static const String _msOAuthTokenUrl =
      'https://login.microsoftonline.com/common/oauth2/v2.0/token';
  static const String _ewsScope =
      'https://outlook.office365.com/EWS.AccessAsUser.All offline_access';

  // ── Autodiscover ─────────────────────────────────────────────────────
  static const String _autodiscoverV2Url =
      'https://autodiscover-s.outlook.com/autodiscover/autodiscover.json';

  // ── SOAP XML namespaces ──────────────────────────────────────────────
  static const String _soapNs =
      'http://schemas.xmlsoap.org/soap/envelope/';
  static const String _typesNs =
      'http://schemas.microsoft.com/exchange/services/2006/types';
  static const String _messagesNs =
      'http://schemas.microsoft.com/exchange/services/2006/messages';

  static const String _exchangeVersion = 'Exchange2013_SP1';

  final HttpClient _http;
  EWSConfig config;

  EWSClient(this.config)
      : _http = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  void close() => _http.close(force: true);

  // ────────────────────────────────────────────────────────────────────
  // §1  OAuth2 Flow (Microsoft 365)
  // ────────────────────────────────────────────────────────────────────

  /// Begin the OAuth2 flow. Returns an [EWSOAuthHandle] with:
  /// - [authUrl] — the URL to open in the system browser.
  /// - [waitForCompletion] — future that resolves to an [EWSConfig] once the
  ///   user completes consent (or times out after 5 minutes).
  ///
  /// Uses loopback redirect + PKCE, same pattern as GoogleCalendarClient.
  static Future<EWSOAuthHandle> startOAuthFlow({
    required String clientId,
    required String email,
    CalendarSyncDirection direction = CalendarSyncDirection.bidirectional,
    bool askOnConflict = false,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final verifier = _randomUrlSafe(48);
    final challenge = _pkceChallenge(verifier);
    final state = _randomUrlSafe(24);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/oauth2/callback';

    final authUri = Uri.parse(_msOAuthAuthorizeUrl).replace(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _ewsScope,
      'login_hint': email,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
    });

    final completer = Completer<EWSConfig>();

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
            'Cleona connected to Exchange',
            'You can close this window and return to Cleona.'));
      }
      await req.response.close();
      await sub.cancel();
      await server.close();

      if (completer.isCompleted) return;
      if (error != null) {
        completer.completeError(
            EWSException('Microsoft OAuth error: $error'));
        return;
      }
      if (code == null || returnedState != state) {
        completer.completeError(
            EWSException('OAuth callback missing code or state mismatch.'));
        return;
      }

      try {
        final cfg = await _exchangeCodeForTokens(
          clientId: clientId,
          email: email,
          code: code,
          redirectUri: redirectUri,
          verifier: verifier,
          direction: direction,
          askOnConflict: askOnConflict,
        );
        completer.complete(cfg);
      } catch (e) {
        completer.completeError(e);
      }
    });

    Timer(timeout, () async {
      if (!completer.isCompleted) {
        await sub.cancel();
        await server.close();
        completer.completeError(EWSException(
            'OAuth timed out after ${timeout.inMinutes} minutes'));
      }
    });

    return EWSOAuthHandle(
      authUrl: authUri.toString(),
      waitForCompletion: completer.future,
      port: server.port,
    );
  }

  static Future<EWSConfig> _exchangeCodeForTokens({
    required String clientId,
    required String email,
    required String code,
    required String redirectUri,
    required String verifier,
    required CalendarSyncDirection direction,
    required bool askOnConflict,
  }) async {
    final body = {
      'client_id': clientId,
      'code': code,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
      'code_verifier': verifier,
    };

    final resp = await _postForm(Uri.parse(_msOAuthTokenUrl), body);
    if (resp.statusCode != 200) {
      throw EWSException(
          'Token exchange failed: HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String?;
    final refreshToken = json['refresh_token'] as String?;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    if (accessToken == null || refreshToken == null) {
      throw EWSException(
          'Token response missing access_token or refresh_token');
    }

    // Discover the EWS endpoint for this user.
    String? ewsUrl;
    try {
      ewsUrl = await _autodiscoverEwsUrl(email, accessToken);
    } catch (_) {
      // Fallback to standard Office 365 EWS endpoint.
    }
    ewsUrl ??= 'https://outlook.office365.com/EWS/Exchange.asmx';

    return EWSConfig(
      serverUrl: ewsUrl,
      email: email,
      clientId: clientId,
      refreshToken: refreshToken,
      accessToken: accessToken,
      accessTokenExpiresAt:
          DateTime.now().millisecondsSinceEpoch + (expiresIn - 60) * 1000,
      direction: direction,
      askOnConflict: askOnConflict,
    );
  }

  /// Refresh the access token if it has expired (or is about to).
  Future<void> ensureAccessToken({int graceMs = 60000}) async {
    if (config.clientId == null) return; // Basic auth — no token refresh.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (config.accessToken.isNotEmpty &&
        config.accessTokenExpiresAt > now + graceMs) {
      return;
    }
    await _refreshAccessToken();
  }

  Future<void> _refreshAccessToken() async {
    if (config.clientId == null || config.refreshToken == null) {
      throw EWSException('Cannot refresh token: no OAuth2 credentials');
    }
    final body = {
      'client_id': config.clientId!,
      'refresh_token': config.refreshToken!,
      'grant_type': 'refresh_token',
      'scope': _ewsScope,
    };
    final resp = await _postForm(Uri.parse(_msOAuthTokenUrl), body);
    if (resp.statusCode != 200) {
      throw EWSException(
          'Token refresh failed: HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String?;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    if (accessToken == null) {
      throw EWSException('Token refresh response missing access_token');
    }
    config.accessToken = accessToken;
    config.accessTokenExpiresAt =
        DateTime.now().millisecondsSinceEpoch + (expiresIn - 60) * 1000;
    // Update refresh token if rotated.
    final newRefresh = json['refresh_token'] as String?;
    if (newRefresh != null && newRefresh.isNotEmpty) {
      config = EWSConfig(
        serverUrl: config.serverUrl,
        email: config.email,
        clientId: config.clientId,
        refreshToken: newRefresh,
        accessToken: config.accessToken,
        accessTokenExpiresAt: config.accessTokenExpiresAt,
        username: config.username,
        password: config.password,
        direction: config.direction,
        askOnConflict: config.askOnConflict,
      );
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // §2  Autodiscover
  // ────────────────────────────────────────────────────────────────────

  /// Autodiscover the EWS endpoint URL for [email].
  ///
  /// Tries v2 JSON first (Microsoft 365), then falls back to v1 XML
  /// (on-premise Exchange). Returns the EWS URL or throws [EWSException].
  static Future<String> autodiscover(String email,
      {String? accessToken}) async {
    final url = await _autodiscoverEwsUrl(email, accessToken);
    if (url == null) {
      throw EWSException('Autodiscover failed for $email');
    }
    return url;
  }

  static Future<String?> _autodiscoverEwsUrl(
      String email, String? accessToken) async {
    // Try v2 JSON (Microsoft 365).
    try {
      final url = await _autodiscoverV2(email, accessToken);
      if (url != null) return url;
    } catch (_) {
      // Fall through to v1.
    }

    // Try v1 XML (on-premise).
    try {
      final url = await _autodiscoverV1(email);
      if (url != null) return url;
    } catch (_) {
      // Fall through.
    }

    return null;
  }

  /// Autodiscover v2 (JSON) — works for Microsoft 365 / Exchange Online.
  static Future<String?> _autodiscoverV2(
      String email, String? accessToken) async {
    final uri = Uri.parse(
        '$_autodiscoverV2Url/v1.0/${Uri.encodeComponent(email)}?Protocol=EWS');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri);
      if (accessToken != null) {
        req.headers.set('Authorization', 'Bearer $accessToken');
      }
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(body) as Map<String, dynamic>;
      final ewsUrl = json['Url'] as String?;
      if (ewsUrl != null && ewsUrl.startsWith('https://')) return ewsUrl;
    } finally {
      client.close(force: true);
    }
    return null;
  }

  /// Autodiscover v1 (XML) — works for on-premise Exchange 2007+.
  ///
  /// Tries the standard autodiscover endpoints for the email domain.
  static Future<String?> _autodiscoverV1(String email) async {
    final atIdx = email.indexOf('@');
    if (atIdx < 0) return null;
    final domain = email.substring(atIdx + 1);

    final candidates = [
      'https://autodiscover.$domain/autodiscover/autodiscover.xml',
      'https://$domain/autodiscover/autodiscover.xml',
    ];

    final requestBody = '<?xml version="1.0" encoding="utf-8"?>'
        '<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/outlook/requestschema/2006">'
        '<Request>'
        '<EMailAddress>${_xmlEscape(email)}</EMailAddress>'
        '<AcceptableResponseSchema>'
        'http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a'
        '</AcceptableResponseSchema>'
        '</Request>'
        '</Autodiscover>';

    for (final url in candidates) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..badCertificateCallback = (_, _, _) => false;
      try {
        final req = await client.postUrl(Uri.parse(url));
        req.headers.contentType =
            ContentType('text', 'xml', charset: 'utf-8');
        final bytes = utf8.encode(requestBody);
        req.contentLength = bytes.length;
        req.add(bytes);
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();
        if (resp.statusCode == 200 || resp.statusCode == 302) {
          // Extract EwsUrl from XML response.
          final ewsUrl = _extractInnerText(body, 'EwsUrl');
          if (ewsUrl != null && ewsUrl.startsWith('https://')) return ewsUrl;
        }
      } catch (_) {
        // Try next candidate.
        continue;
      } finally {
        client.close(force: true);
      }
    }
    return null;
  }

  // ────────────────────────────────────────────────────────────────────
  // §3  SOAP Transport
  // ────────────────────────────────────────────────────────────────────

  /// Build a SOAP envelope wrapping [bodyContent].
  static String _soapEnvelope(String bodyContent) {
    return '<?xml version="1.0" encoding="utf-8"?>'
        '<soap:Envelope xmlns:soap="$_soapNs" '
        'xmlns:t="$_typesNs" '
        'xmlns:m="$_messagesNs">'
        '<soap:Header>'
        '<t:RequestServerVersion Version="$_exchangeVersion"/>'
        '</soap:Header>'
        '<soap:Body>'
        '$bodyContent'
        '</soap:Body>'
        '</soap:Envelope>';
  }

  /// Send a SOAP request to the EWS endpoint and return the response body XML.
  Future<_EWSResponse> _soapRequest(String bodyContent) async {
    await ensureAccessToken();

    final envelope = _soapEnvelope(bodyContent);
    final uri = Uri.parse(config.serverUrl);
    final req = await _http.postUrl(uri);

    // Authentication.
    if (config.clientId != null && config.accessToken.isNotEmpty) {
      req.headers.set('Authorization', 'Bearer ${config.accessToken}');
    } else if (config.username != null && config.password != null) {
      final token =
          base64.encode(utf8.encode('${config.username}:${config.password}'));
      req.headers.set('Authorization', 'Basic $token');
    }

    req.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
    final bytes = utf8.encode(envelope);
    req.contentLength = bytes.length;
    req.add(bytes);

    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();

    // If token expired mid-flight, refresh + retry once.
    if (resp.statusCode == 401 && config.clientId != null) {
      await _refreshAccessToken();
      return _soapRequest(bodyContent);
    }

    if (resp.statusCode != 200) {
      throw EWSException(
          'EWS SOAP request failed: HTTP ${resp.statusCode}: '
          '${body.length > 500 ? body.substring(0, 500) : body}');
    }

    // Check for SOAP fault.
    final fault = _extractInnerText(body, 'faultstring');
    if (fault != null) {
      throw EWSException('EWS SOAP fault: $fault');
    }

    // Check EWS response class.
    final responseClass = _extractAttribute(body, 'ResponseClass');
    if (responseClass == 'Error') {
      final code = _extractInnerText(body, 'MessageText') ??
          _extractInnerText(body, 'ResponseCode') ??
          'Unknown error';
      throw EWSException('EWS error: $code');
    }

    return _EWSResponse(status: resp.statusCode, body: body);
  }

  // ────────────────────────────────────────────────────────────────────
  // §4  Calendar Operations
  // ────────────────────────────────────────────────────────────────────

  /// Find calendar items in a date range. Returns lightweight references
  /// (ItemId, ChangeKey, Subject, Start, End, LastModifiedTime).
  Future<List<EWSCalendarItem>> findItems({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String folderId = 'calendar',
  }) async {
    final body = '<m:FindItem Traversal="Shallow">'
        '<m:ItemShape>'
        '<t:BaseShape>IdOnly</t:BaseShape>'
        '<t:AdditionalProperties>'
        '<t:FieldURI FieldURI="item:Subject"/>'
        '<t:FieldURI FieldURI="item:LastModifiedTime"/>'
        '<t:FieldURI FieldURI="calendar:Start"/>'
        '<t:FieldURI FieldURI="calendar:End"/>'
        '</t:AdditionalProperties>'
        '</m:ItemShape>'
        '<m:CalendarView StartDate="${_formatIso8601(rangeStart)}" '
        'EndDate="${_formatIso8601(rangeEnd)}"/>'
        '<m:ParentFolderIds>'
        '<t:DistinguishedFolderId Id="$folderId"/>'
        '</m:ParentFolderIds>'
        '</m:FindItem>';

    final resp = await _soapRequest(body);
    return _parseCalendarItems(resp.body);
  }

  /// Get full details of calendar items by their ItemIds.
  Future<List<EWSCalendarItem>> getItems(List<String> itemIds) async {
    if (itemIds.isEmpty) return [];

    final ids = StringBuffer();
    for (final id in itemIds) {
      ids.write('<t:ItemId Id="${_xmlEscape(id)}"/>');
    }

    final body = '<m:GetItem>'
        '<m:ItemShape>'
        '<t:BaseShape>AllProperties</t:BaseShape>'
        '<t:BodyType>Text</t:BodyType>'
        '</m:ItemShape>'
        '<m:ItemIds>$ids</m:ItemIds>'
        '</m:GetItem>';

    final resp = await _soapRequest(body);
    return _parseFullCalendarItems(resp.body);
  }

  /// Get a single calendar item by its ItemId.
  Future<EWSCalendarItem> getItem(String itemId) async {
    final items = await getItems([itemId]);
    if (items.isEmpty) {
      throw EWSException('Item not found: $itemId');
    }
    return items.first;
  }

  /// Create a new calendar event. Returns the created item with its
  /// server-assigned ItemId and ChangeKey.
  Future<EWSCalendarItem> createItem(EWSCalendarItem item) async {
    final body = '<m:CreateItem SendMeetingInvitations="SendToNone">'
        '<m:Items>'
        '${_calendarItemToXml(item)}'
        '</m:Items>'
        '</m:CreateItem>';

    final resp = await _soapRequest(body);

    // Extract the created item's ItemId from the response.
    final idMatch = RegExp(
      r'<t:ItemId\s+Id="([^"]+)"\s+ChangeKey="([^"]+)"',
    ).firstMatch(resp.body);
    if (idMatch == null) {
      throw EWSException('CreateItem succeeded but no ItemId in response');
    }

    return item.copyWith(
      itemId: _decodeXmlEntities(idMatch.group(1)!),
      changeKey: _decodeXmlEntities(idMatch.group(2)!),
    );
  }

  /// Update an existing calendar event. Requires a valid ChangeKey.
  /// Returns the updated item with the new ChangeKey.
  Future<EWSCalendarItem> updateItem(EWSCalendarItem item) async {
    if (item.itemId == null || item.changeKey == null) {
      throw EWSException('updateItem requires itemId and changeKey');
    }

    // Build update fields using the SetItemField pattern.
    final updates = StringBuffer();

    if (item.subject != null) {
      updates.write(_setItemField('item:Subject', 'Subject', item.subject!));
    }
    if (item.start != null) {
      updates.write(_setItemField(
          'calendar:Start', 'Start', _formatIso8601(item.start!)));
    }
    if (item.end != null) {
      updates.write(
          _setItemField('calendar:End', 'End', _formatIso8601(item.end!)));
    }
    if (item.location != null) {
      updates.write(
          _setItemField('calendar:Location', 'Location', item.location!));
    }
    if (item.body != null) {
      updates.write('<t:SetItemField>'
          '<t:FieldURI FieldURI="item:Body"/>'
          '<t:CalendarItem>'
          '<t:Body BodyType="Text">${_xmlEscape(item.body!)}</t:Body>'
          '</t:CalendarItem>'
          '</t:SetItemField>');
    }
    if (item.isAllDay != null) {
      updates.write(_setItemField('calendar:IsAllDayEvent', 'IsAllDayEvent',
          item.isAllDay! ? 'true' : 'false'));
    }
    if (item.reminderMinutes != null) {
      updates.write(_setItemField('item:ReminderMinutesBeforeStart',
          'ReminderMinutesBeforeStart', '${item.reminderMinutes}'));
      updates.write(_setItemField('item:ReminderIsSet', 'ReminderIsSet',
          item.reminderMinutes! > 0 ? 'true' : 'false'));
    }
    if (item.sensitivity != null) {
      updates.write(_setItemField(
          'item:Sensitivity', 'Sensitivity', item.sensitivity!));
    }
    if (item.showAs != null) {
      updates.write(_setItemField('calendar:LegacyFreeBusyStatus',
          'LegacyFreeBusyStatus', item.showAs!));
    }

    if (updates.isEmpty) {
      // Nothing to update — return the item as-is.
      return item;
    }

    final body = '<m:UpdateItem '
        'ConflictResolution="AutoResolve" '
        'SendMeetingInvitationsOrCancellations="SendToNone">'
        '<m:ItemChanges>'
        '<t:ItemChange>'
        '<t:ItemId Id="${_xmlEscape(item.itemId!)}" '
        'ChangeKey="${_xmlEscape(item.changeKey!)}"/>'
        '<t:Updates>$updates</t:Updates>'
        '</t:ItemChange>'
        '</m:ItemChanges>'
        '</m:UpdateItem>';

    final resp = await _soapRequest(body);

    // Extract new ChangeKey.
    final idMatch = RegExp(
      r'<t:ItemId\s+Id="([^"]+)"\s+ChangeKey="([^"]+)"',
    ).firstMatch(resp.body);
    if (idMatch == null) {
      throw EWSException('UpdateItem succeeded but no ItemId in response');
    }

    return item.copyWith(
      changeKey: _decodeXmlEntities(idMatch.group(2)!),
    );
  }

  /// Delete a calendar event by ItemId. Ignores "item not found" errors.
  Future<void> deleteItem(
    String itemId, {
    String deleteType = 'MoveToDeletedItems',
  }) async {
    final body = '<m:DeleteItem DeleteType="$deleteType" '
        'SendMeetingCancellations="SendToNone">'
        '<m:ItemIds>'
        '<t:ItemId Id="${_xmlEscape(itemId)}"/>'
        '</m:ItemIds>'
        '</m:DeleteItem>';

    try {
      await _soapRequest(body);
    } on EWSException catch (e) {
      // Treat "item not found" as success (already deleted).
      if (e.message.contains('ErrorItemNotFound')) return;
      rethrow;
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // §5  Conversion Helpers
  // ────────────────────────────────────────────────────────────────────

  /// Convert an [EWSCalendarItem] to a simple map representation
  /// suitable for mapping to Cleona calendar events.
  static Map<String, dynamic> itemToMap(EWSCalendarItem item) {
    return <String, dynamic>{
      if (item.itemId != null) 'itemId': item.itemId,
      if (item.changeKey != null) 'changeKey': item.changeKey,
      if (item.subject != null) 'subject': item.subject,
      if (item.start != null) 'start': item.start!.toIso8601String(),
      if (item.end != null) 'end': item.end!.toIso8601String(),
      if (item.location != null) 'location': item.location,
      if (item.body != null) 'body': item.body,
      if (item.isAllDay != null) 'isAllDay': item.isAllDay,
      if (item.sensitivity != null) 'sensitivity': item.sensitivity,
      if (item.showAs != null) 'showAs': item.showAs,
      if (item.organizer != null) 'organizer': item.organizer,
      if (item.reminderMinutes != null)
        'reminderMinutes': item.reminderMinutes,
      if (item.lastModifiedTime != null)
        'lastModifiedTime': item.lastModifiedTime!.toIso8601String(),
      if (item.categories.isNotEmpty) 'categories': item.categories,
      if (item.recurrence != null) 'recurrence': item.recurrence,
      if (item.iCalUid != null) 'iCalUid': item.iCalUid,
    };
  }

  /// Convert a simple map back to an [EWSCalendarItem].
  static EWSCalendarItem mapToItem(Map<String, dynamic> map) {
    return EWSCalendarItem(
      itemId: map['itemId'] as String?,
      changeKey: map['changeKey'] as String?,
      subject: map['subject'] as String?,
      start: map['start'] != null
          ? DateTime.parse(map['start'] as String)
          : null,
      end: map['end'] != null
          ? DateTime.parse(map['end'] as String)
          : null,
      location: map['location'] as String?,
      body: map['body'] as String?,
      isAllDay: map['isAllDay'] as bool?,
      sensitivity: map['sensitivity'] as String?,
      showAs: map['showAs'] as String?,
      organizer: map['organizer'] as String?,
      reminderMinutes: map['reminderMinutes'] as int?,
      lastModifiedTime: map['lastModifiedTime'] != null
          ? DateTime.parse(map['lastModifiedTime'] as String)
          : null,
      categories: (map['categories'] as List?)?.cast<String>() ?? [],
      recurrence: map['recurrence'] as String?,
      iCalUid: map['iCalUid'] as String?,
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // §6  XML Parsing Helpers
  // ────────────────────────────────────────────────────────────────────
  //
  // Regex-based extraction — same approach as CalDAVClient.
  // Safe for EWS SOAP responses which have a well-defined structure.

  /// Parse FindItem response into lightweight calendar item references.
  List<EWSCalendarItem> _parseCalendarItems(String xml) {
    final items = <EWSCalendarItem>[];
    final itemBlocks = RegExp(
      r'<t:CalendarItem[\s>][\s\S]*?</t:CalendarItem>',
      caseSensitive: false,
    ).allMatches(xml);

    for (final block in itemBlocks) {
      final fragment = block.group(0)!;
      items.add(_parseCalendarItemFragment(fragment));
    }
    return items;
  }

  /// Parse GetItem response into full calendar items.
  List<EWSCalendarItem> _parseFullCalendarItems(String xml) {
    // GetItem wraps items in <m:Items> inside <m:GetItemResponseMessage>.
    // The CalendarItem elements have the same structure.
    return _parseCalendarItems(xml);
  }

  EWSCalendarItem _parseCalendarItemFragment(String xml) {
    // Extract ItemId and ChangeKey from attributes.
    String? itemId;
    String? changeKey;
    final idMatch = RegExp(
      r'<t:ItemId\s+Id="([^"]+)"\s+ChangeKey="([^"]+)"',
    ).firstMatch(xml);
    if (idMatch != null) {
      itemId = _decodeXmlEntities(idMatch.group(1)!);
      changeKey = _decodeXmlEntities(idMatch.group(2)!);
    }

    return EWSCalendarItem(
      itemId: itemId,
      changeKey: changeKey,
      subject: _extractInnerText(xml, 'Subject'),
      start: _parseDateTime(_extractInnerText(xml, 'Start')),
      end: _parseDateTime(_extractInnerText(xml, 'End')),
      location: _extractInnerText(xml, 'Location'),
      body: _extractBodyText(xml),
      isAllDay: _parseBool(_extractInnerText(xml, 'IsAllDayEvent')),
      sensitivity: _extractInnerText(xml, 'Sensitivity'),
      showAs: _extractInnerText(xml, 'LegacyFreeBusyStatus'),
      organizer: _extractOrganizerEmail(xml),
      reminderMinutes:
          _parseInt(_extractInnerText(xml, 'ReminderMinutesBeforeStart')),
      lastModifiedTime:
          _parseDateTime(_extractInnerText(xml, 'LastModifiedTime')),
      categories: _extractCategories(xml),
      recurrence: _extractRecurrence(xml),
      iCalUid: _extractInnerText(xml, 'UID'),
    );
  }

  // ── XML construction helpers ──────────────────────────────────────

  /// Build a CalendarItem XML element for CreateItem.
  String _calendarItemToXml(EWSCalendarItem item) {
    final buf = StringBuffer('<t:CalendarItem>');

    if (item.subject != null) {
      buf.write('<t:Subject>${_xmlEscape(item.subject!)}</t:Subject>');
    }
    if (item.body != null) {
      buf.write(
          '<t:Body BodyType="Text">${_xmlEscape(item.body!)}</t:Body>');
    }
    if (item.reminderMinutes != null) {
      buf.write(
          '<t:ReminderIsSet>${item.reminderMinutes! > 0 ? 'true' : 'false'}'
          '</t:ReminderIsSet>');
      buf.write('<t:ReminderMinutesBeforeStart>${item.reminderMinutes}'
          '</t:ReminderMinutesBeforeStart>');
    }
    if (item.sensitivity != null) {
      buf.write(
          '<t:Sensitivity>${_xmlEscape(item.sensitivity!)}</t:Sensitivity>');
    }
    if (item.start != null) {
      buf.write('<t:Start>${_formatIso8601(item.start!)}</t:Start>');
    }
    if (item.end != null) {
      buf.write('<t:End>${_formatIso8601(item.end!)}</t:End>');
    }
    if (item.isAllDay != null) {
      buf.write('<t:IsAllDayEvent>${item.isAllDay! ? 'true' : 'false'}'
          '</t:IsAllDayEvent>');
    }
    if (item.showAs != null) {
      buf.write('<t:LegacyFreeBusyStatus>${_xmlEscape(item.showAs!)}'
          '</t:LegacyFreeBusyStatus>');
    }
    if (item.location != null) {
      buf.write('<t:Location>${_xmlEscape(item.location!)}</t:Location>');
    }
    if (item.categories.isNotEmpty) {
      buf.write('<t:Categories>');
      for (final cat in item.categories) {
        buf.write('<t:String>${_xmlEscape(cat)}</t:String>');
      }
      buf.write('</t:Categories>');
    }

    buf.write('</t:CalendarItem>');
    return buf.toString();
  }

  /// Build a SetItemField element for UpdateItem.
  static String _setItemField(
      String fieldUri, String elementName, String value) {
    return '<t:SetItemField>'
        '<t:FieldURI FieldURI="$fieldUri"/>'
        '<t:CalendarItem>'
        '<t:$elementName>${_xmlEscape(value)}</t:$elementName>'
        '</t:CalendarItem>'
        '</t:SetItemField>';
  }

  // ── Generic XML extraction ────────────────────────────────────────

  /// Extract inner text of an element by its local name (ignoring namespace
  /// prefixes). Returns null if not found.
  static String? _extractInnerText(String xml, String localName) {
    final re = RegExp(
      '<(?:\\w+:)?$localName(?:\\s[^>]*)?>([\\s\\S]*?)</(?:\\w+:)?$localName>',
      caseSensitive: false,
    );
    final match = re.firstMatch(xml);
    if (match == null) return null;
    return _decodeXmlEntities(match.group(1)!.trim());
  }

  /// Extract the value of the first attribute named [attr] from the XML.
  static String? _extractAttribute(String xml, String attr) {
    final re = RegExp('$attr="([^"]*)"');
    final match = re.firstMatch(xml);
    return match?.group(1);
  }

  /// Extract Body text, handling the BodyType attribute.
  static String? _extractBodyText(String xml) {
    final re = RegExp(
      r'<(?:\w+:)?Body[^>]*>([\s\S]*?)</(?:\w+:)?Body>',
      caseSensitive: false,
    );
    final match = re.firstMatch(xml);
    if (match == null) return null;
    return _decodeXmlEntities(match.group(1)!.trim());
  }

  /// Extract the organizer's email from the Mailbox element.
  static String? _extractOrganizerEmail(String xml) {
    final orgRe = RegExp(
      r'<(?:\w+:)?Organizer[\s>][\s\S]*?</(?:\w+:)?Organizer>',
      caseSensitive: false,
    );
    final orgMatch = orgRe.firstMatch(xml);
    if (orgMatch == null) return null;
    return _extractInnerText(orgMatch.group(0)!, 'EmailAddress');
  }

  /// Extract categories as a list of strings.
  static List<String> _extractCategories(String xml) {
    final catBlockRe = RegExp(
      r'<(?:\w+:)?Categories[\s>][\s\S]*?</(?:\w+:)?Categories>',
      caseSensitive: false,
    );
    final catBlock = catBlockRe.firstMatch(xml);
    if (catBlock == null) return [];

    final result = <String>[];
    final stringRe = RegExp(
      r'<(?:\w+:)?String(?:\s[^>]*)?>([^<]+)</(?:\w+:)?String>',
      caseSensitive: false,
    );
    for (final m in stringRe.allMatches(catBlock.group(0)!)) {
      final val = m.group(1)?.trim();
      if (val != null && val.isNotEmpty) {
        result.add(_decodeXmlEntities(val));
      }
    }
    return result;
  }

  /// Extract raw recurrence XML if present (for round-tripping).
  static String? _extractRecurrence(String xml) {
    final re = RegExp(
      r'<(?:\w+:)?Recurrence[\s>][\s\S]*?</(?:\w+:)?Recurrence>',
      caseSensitive: false,
    );
    final match = re.firstMatch(xml);
    return match?.group(0);
  }

  // ── Value parsers ─────────────────────────────────────────────────

  static DateTime? _parseDateTime(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  static bool? _parseBool(String? s) {
    if (s == null) return null;
    return s.toLowerCase() == 'true';
  }

  static int? _parseInt(String? s) {
    if (s == null) return null;
    return int.tryParse(s);
  }

  // ── XML encoding ──────────────────────────────────────────────────

  static String _xmlEscape(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _decodeXmlEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  static String _formatIso8601(DateTime dt) {
    return dt.toUtc().toIso8601String();
  }

  // ── HTTP helpers ──────────────────────────────────────────────────

  static Future<_HttpResponse> _postForm(
      Uri uri, Map<String, String> formData) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType(
          'application', 'x-www-form-urlencoded',
          charset: 'utf-8');
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

  /// Convenience helper: list calendar items for a config in a date range.
  static Future<List<EWSCalendarItem>> discoverAndListItems({
    required EWSConfig config,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final client = EWSClient(config);
    try {
      return await client.findItems(
          rangeStart: rangeStart, rangeEnd: rangeEnd);
    } finally {
      client.close();
    }
  }
}

// ──────────────────────────────────────────────────────────────────────
// Types
// ──────────────────────────────────────────────────────────────────────

/// Configuration for an Exchange Web Services account.
///
/// Supports two authentication modes:
/// - **OAuth2 (Microsoft 365):** [clientId] + [refreshToken] + [accessToken].
///   [username] and [password] are null.
/// - **Basic auth (on-premise):** [username] + [password].
///   [clientId] and [refreshToken] are null.
///
/// Tokens are persisted encrypted on disk.
// EWSConfig is defined in sync_types.dart (canonical location for all
// provider config types: CalDAVConfig, GoogleCalendarConfig, EWSConfig, etc.)

/// Represents an Exchange calendar item.
class EWSCalendarItem {
  final String? itemId;
  final String? changeKey;
  final String? subject;
  final DateTime? start;
  final DateTime? end;
  final String? location;
  final String? body;
  final bool? isAllDay;
  final String? sensitivity; // Normal, Personal, Private, Confidential
  final String? showAs; // Free, Tentative, Busy, OOF, WorkingElsewhere, NoData
  final String? organizer; // email address
  final int? reminderMinutes;
  final DateTime? lastModifiedTime;
  final List<String> categories;
  final String? recurrence; // Raw recurrence XML for round-tripping
  final String? iCalUid; // iCalendar UID for cross-system correlation

  EWSCalendarItem({
    this.itemId,
    this.changeKey,
    this.subject,
    this.start,
    this.end,
    this.location,
    this.body,
    this.isAllDay,
    this.sensitivity,
    this.showAs,
    this.organizer,
    this.reminderMinutes,
    this.lastModifiedTime,
    this.categories = const [],
    this.recurrence,
    this.iCalUid,
  });

  EWSCalendarItem copyWith({
    String? itemId,
    String? changeKey,
    String? subject,
    DateTime? start,
    DateTime? end,
    String? location,
    String? body,
    bool? isAllDay,
    String? sensitivity,
    String? showAs,
    String? organizer,
    int? reminderMinutes,
    DateTime? lastModifiedTime,
    List<String>? categories,
    String? recurrence,
    String? iCalUid,
  }) {
    return EWSCalendarItem(
      itemId: itemId ?? this.itemId,
      changeKey: changeKey ?? this.changeKey,
      subject: subject ?? this.subject,
      start: start ?? this.start,
      end: end ?? this.end,
      location: location ?? this.location,
      body: body ?? this.body,
      isAllDay: isAllDay ?? this.isAllDay,
      sensitivity: sensitivity ?? this.sensitivity,
      showAs: showAs ?? this.showAs,
      organizer: organizer ?? this.organizer,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      lastModifiedTime: lastModifiedTime ?? this.lastModifiedTime,
      categories: categories ?? this.categories,
      recurrence: recurrence ?? this.recurrence,
      iCalUid: iCalUid ?? this.iCalUid,
    );
  }

  Map<String, dynamic> toJson() => EWSClient.itemToMap(this);

  @override
  String toString() => 'EWSCalendarItem(id: $itemId, subject: $subject, '
      'start: $start, end: $end)';
}

/// Handle returned by [EWSClient.startOAuthFlow].
class EWSOAuthHandle {
  /// URL to open in the system browser.
  final String authUrl;

  /// Completes with an [EWSConfig] once the user finishes consent,
  /// or errors on timeout / failure.
  final Future<EWSConfig> waitForCompletion;

  /// Local port the loopback server is listening on.
  final int port;

  EWSOAuthHandle({
    required this.authUrl,
    required this.waitForCompletion,
    required this.port,
  });
}

class EWSException implements Exception {
  final String message;
  EWSException(this.message);
  @override
  String toString() => 'EWSException: $message';
}

class _EWSResponse {
  final int status;
  final String body;
  _EWSResponse({required this.status, required this.body});
}

class _HttpResponse {
  final int statusCode;
  final String body;
  _HttpResponse(this.statusCode, this.body);
}
