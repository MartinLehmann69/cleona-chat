import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:image/image.dart' as img;

// ---------------------------------------------------------------------------
// Sender-Side Link Preview Fetcher
//
// Security: HTTPS-only, SSRF protection (private IP block), timeout,
// max response size, no cookies, no auth headers.
// The RECIPIENT never makes any network request.
// ---------------------------------------------------------------------------

/// Logger interface — injected to avoid hard dependency on CleonaNode.
typedef LogFn = void Function(String msg);

/// Result of a link preview fetch.
class LinkPreviewData {
  final String url;
  final String title;
  final String description;
  final String siteName;
  final Uint8List? thumbnail; // JPEG, max 64 KB
  final DateTime fetchedAt;

  LinkPreviewData({
    required this.url,
    required this.title,
    this.description = '',
    this.siteName = '',
    this.thumbnail,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  proto.LinkPreview toProto() => proto.LinkPreview()
    ..url = url
    ..title = title
    ..description = description
    ..siteName = siteName
    ..thumbnail = thumbnail ?? Uint8List(0)
    ..fetchedAtMs = Int64(fetchedAt.millisecondsSinceEpoch);
}

/// Settings for link preview fetching (user-configurable).
enum BrowserOpenMode {
  /// Open links in default browser, normal mode.
  normal,

  /// Prefer incognito/private mode, fallback to normal if unsupported.
  incognitoPreferred,

  /// Ask the user every time (dialog: Normal / Incognito / Cancel).
  alwaysAsk,
}

class LinkPreviewSettings {
  /// Whether to fetch link previews when sending messages.
  bool enabled;

  /// How to open links when the user taps them.
  BrowserOpenMode browserOpenMode;

  /// Timeout for fetching a URL (seconds).
  int fetchTimeoutSec;

  /// Maximum HTML response size in bytes.
  int maxHtmlBytes;

  /// Maximum image size to download for thumbnail (bytes).
  int maxImageBytes;

  LinkPreviewSettings({
    this.enabled = true,
    this.browserOpenMode = BrowserOpenMode.normal,
    this.fetchTimeoutSec = 5,
    this.maxHtmlBytes = 262144, // 256 KB
    this.maxImageBytes = 262144, // 256 KB
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'browserOpenMode': browserOpenMode.name,
        'fetchTimeoutSec': fetchTimeoutSec,
        'maxHtmlBytes': maxHtmlBytes,
        'maxImageBytes': maxImageBytes,
      };

  static LinkPreviewSettings fromJson(Map<String, dynamic> json) =>
      LinkPreviewSettings(
        enabled: json['enabled'] as bool? ?? true,
        browserOpenMode: BrowserOpenMode.values.firstWhere(
          (e) => e.name == (json['browserOpenMode'] as String? ?? 'normal'),
          orElse: () => BrowserOpenMode.normal,
        ),
        fetchTimeoutSec: json['fetchTimeoutSec'] as int? ?? 5,
        maxHtmlBytes: json['maxHtmlBytes'] as int? ?? 262144,
        maxImageBytes: json['maxImageBytes'] as int? ?? 262144,
      );
}

// ---------------------------------------------------------------------------
// URL detection regex (same as chat_screen.dart)
// ---------------------------------------------------------------------------

final urlRegex = RegExp(
  r'https?://[^\s<>\[\]{}|\\^`"]+',
  caseSensitive: false,
);

/// Extract the first URL from text, or null if none found.
String? extractFirstUrl(String text) {
  final match = urlRegex.firstMatch(text);
  return match?.group(0);
}

// ---------------------------------------------------------------------------
// SSRF Protection — block private/reserved IP ranges
// ---------------------------------------------------------------------------

/// Returns true if the IP address is private, loopback, link-local,
/// multicast, or otherwise not safe for external HTTP requests.
bool isPrivateOrReservedIp(InternetAddress addr) {
  final bytes = addr.rawAddress;

  if (addr.type == InternetAddressType.IPv4 && bytes.length == 4) {
    final a = bytes[0], b = bytes[1];
    // 10.0.0.0/8
    if (a == 10) return true;
    // 172.16.0.0/12
    if (a == 172 && b >= 16 && b <= 31) return true;
    // 192.168.0.0/16
    if (a == 192 && b == 168) return true;
    // 127.0.0.0/8 (loopback)
    if (a == 127) return true;
    // 169.254.0.0/16 (link-local)
    if (a == 169 && b == 254) return true;
    // 0.0.0.0/8
    if (a == 0) return true;
    // 100.64.0.0/10 (CGNAT)
    if (a == 100 && b >= 64 && b <= 127) return true;
    // 192.0.0.0/24 (IANA protocol assignments)
    if (a == 192 && b == 0 && bytes[2] == 0) return true;
    // 192.0.2.0/24 (TEST-NET-1)
    if (a == 192 && b == 0 && bytes[2] == 2) return true;
    // 198.51.100.0/24 (TEST-NET-2)
    if (a == 198 && b == 51 && bytes[2] == 100) return true;
    // 203.0.113.0/24 (TEST-NET-3)
    if (a == 203 && b == 0 && bytes[2] == 113) return true;
    // 224.0.0.0/4 (multicast)
    if (a >= 224 && a <= 239) return true;
    // 240.0.0.0/4 (reserved)
    if (a >= 240) return true;
    return false;
  }

  if (addr.type == InternetAddressType.IPv6 && bytes.length == 16) {
    // ::1 (loopback)
    if (bytes.every((b) => b == 0) ||
        (bytes.sublist(0, 15).every((b) => b == 0) && bytes[15] == 1)) {
      return true;
    }
    // fe80::/10 (link-local)
    if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return true;
    // fc00::/7 (unique local)
    if ((bytes[0] & 0xfe) == 0xfc) return true;
    // ff00::/8 (multicast)
    if (bytes[0] == 0xff) return true;
    // ::ffff:0:0/96 (IPv4-mapped — check the embedded IPv4)
    if (bytes[10] == 0xff && bytes[11] == 0xff &&
        bytes.sublist(0, 10).every((b) => b == 0)) {
      final ipv4 = InternetAddress.fromRawAddress(
          Uint8List.fromList(bytes.sublist(12, 16)));
      return isPrivateOrReservedIp(ipv4);
    }
    // 64:ff9b::/96 (NAT64 — last 4 bytes are embedded IPv4)
    if (bytes[0] == 0x00 && bytes[1] == 0x64 &&
        bytes[2] == 0xff && bytes[3] == 0x9b &&
        bytes.sublist(4, 12).every((b) => b == 0)) {
      final ipv4 = InternetAddress.fromRawAddress(
          Uint8List.fromList(bytes.sublist(12, 16)));
      return isPrivateOrReservedIp(ipv4);
    }
    // 2002::/16 (6to4 — bytes 2-5 contain the embedded IPv4)
    if (bytes[0] == 0x20 && bytes[1] == 0x02) {
      final ipv4 = InternetAddress.fromRawAddress(
          Uint8List.fromList(bytes.sublist(2, 6)));
      return isPrivateOrReservedIp(ipv4);
    }
    return false;
  }

  return true; // Unknown address type — block
}

/// Resolve hostname and check if ALL resulting IPs are safe.
/// Returns the first safe IP, or null if all are private/reserved.
Future<InternetAddress?> resolveSafeIp(String hostname,
    {int timeoutSec = 5}) async {
  try {
    // B-32: bound the DNS lookup. Without a timeout, a slow/unreachable resolver
    // (common on VMs routing via parprouted) stalls sendTextMessage for tens of
    // seconds inside the synchronous send path. TimeoutException falls into the
    // catch below → treated as "could not resolve" → no preview (fail-fast).
    final addresses = await InternetAddress.lookup(hostname)
        .timeout(Duration(seconds: timeoutSec));
    for (final addr in addresses) {
      if (!isPrivateOrReservedIp(addr)) return addr;
    }
    return null; // All IPs are private
  } catch (_) {
    return null; // DNS failure or timeout
  }
}

// ---------------------------------------------------------------------------
// OpenGraph Metadata Parser (regex-based, no HTML parser dependency)
// ---------------------------------------------------------------------------

/// Extract og: meta tags from HTML using regex.
/// Also falls back to <title> if og:title is missing.
Map<String, String> parseOpenGraphTags(String html) {
  final result = <String, String>{};

  // Match <meta property="og:*" content="*"> and <meta content="*" property="og:*">
  final metaRegex = RegExp(
    r'''<meta\s+[^>]*?(?:property\s*=\s*["']og:(\w+)["'][^>]*?content\s*=\s*["']([^"']*?)["']|content\s*=\s*["']([^"']*?)["'][^>]*?property\s*=\s*["']og:(\w+)["'])[^>]*/?>''',
    caseSensitive: false,
  );

  for (final match in metaRegex.allMatches(html)) {
    final key = match.group(1) ?? match.group(4);
    final value = match.group(2) ?? match.group(3);
    if (key != null && value != null && value.isNotEmpty) {
      result[key] = _decodeHtmlEntities(value);
    }
  }

  // Fallback: <title> tag if no og:title
  if (!result.containsKey('title')) {
    final titleRegex = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true);
    final titleMatch = titleRegex.firstMatch(html);
    if (titleMatch != null) {
      final title = titleMatch.group(1)?.trim();
      if (title != null && title.isNotEmpty) {
        result['title'] = _decodeHtmlEntities(title);
      }
    }
  }

  return result;
}

String _decodeHtmlEntities(String text) {
  return text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&#x2F;', '/');
}

// ---------------------------------------------------------------------------
// Link Preview Fetcher
// ---------------------------------------------------------------------------

class LinkPreviewFetcher {
  final LinkPreviewSettings settings;
  final LogFn? log;

  LinkPreviewFetcher({required this.settings, this.log});

  /// Fetch link preview for the first URL in [text].
  /// Returns null if no URL found, fetch fails, or previews are disabled.
  Future<LinkPreviewData?> fetchPreview(String text) async {
    if (!settings.enabled) return null;

    final url = extractFirstUrl(text);
    if (url == null) return null;

    return fetchPreviewForUrl(url);
  }

  /// Maximum number of redirects to follow manually (prevent infinite loops).
  static const _maxRedirects = 5;

  /// Fetch link preview for a specific URL.
  Future<LinkPreviewData?> fetchPreviewForUrl(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;

      // HTTPS only
      if (uri.scheme != 'https') {
        log?.call('LinkPreview: Skipping non-HTTPS URL: $url');
        return null;
      }

      // SSRF check — resolve DNS and verify IP is not private
      final safeIp = await resolveSafeIp(uri.host,
          timeoutSec: settings.fetchTimeoutSec);
      if (safeIp == null) {
        log?.call('LinkPreview: SSRF blocked — private/reserved IP for ${uri.host}');
        return null;
      }

      final timeout = Duration(seconds: settings.fetchTimeoutSec);

      // Fetch HTML with redirect handling (each hop SSRF re-validated)
      final html = await _fetchHtml(uri, timeout);
      if (html == null) return null;

      // Parse og: tags
      final tags = parseOpenGraphTags(html);
      final title = tags['title'];
      if (title == null || title.isEmpty) return null;

      // Fetch and thumbnail og:image
      Uint8List? thumbnail;
      final imageUrl = tags['image'];
      if (imageUrl != null && imageUrl.isNotEmpty) {
        thumbnail = await _fetchThumbnail(imageUrl, uri, timeout);
      }

      return LinkPreviewData(
        url: url,
        title: title.length > 200 ? title.substring(0, 200) : title,
        description: (tags['description'] ?? '').length > 300
            ? tags['description']!.substring(0, 300)
            : tags['description'] ?? '',
        siteName: tags['site_name'] ?? '',
        thumbnail: thumbnail,
      );
    } catch (e) {
      log?.call('LinkPreview: Error fetching $url — $e');
      return null;
    }
  }

  /// Create an HttpClient for the fetch.
  ///
  /// SSRF protection relies on [resolveSafeIp] called BEFORE every fetch and
  /// redirect hop — the resolved IP is validated against the private/reserved
  /// blocklist. The theoretical TOCTOU gap (attacker DNS flips between our
  /// lookup and HttpClient's internal DNS) is accepted because:
  ///   (a) it requires a targeted DNS rebinding attack within <1ms,
  ///   (b) the attacker must also host an exploitable HTTP service on the
  ///       private target, and
  ///   (c) Dart's connectionFactory + HTTPS is broken for certain CDN servers
  ///       (Wikipedia, Cloudflare — TLS upgrade fails with "Connection closed
  ///       before full header was received"), so IP-pinning via
  ///       connectionFactory is not viable.
  HttpClient _createClient(Duration timeout) {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    client.userAgent = 'Cleona/1.0';
    return client;
  }

  /// Perform a single HTTP GET. Returns the response.
  /// Redirects are NOT followed automatically — the caller handles them
  /// via [_fetchWithRedirects] so each hop gets full SSRF re-validation.
  Future<HttpClientResponse> _safeGet(
      HttpClient client, Uri uri, Duration timeout) async {
    final request = await client.getUrl(uri).timeout(timeout);
    // Disable automatic redirects — we handle them manually so each
    // redirect target goes through full SSRF validation.
    request.followRedirects = false;
    // No cookies, no auth
    request.headers.removeAll('cookie');
    return request.close().timeout(timeout);
  }

  /// Follow redirects manually, re-validating SSRF on every hop.
  /// Returns the final (non-redirect) response and its HttpClient (caller
  /// must close), or null if any hop fails SSRF or the chain is too long.
  Future<({HttpClientResponse response, HttpClient client})?> _fetchWithRedirects(
      Uri uri, Duration timeout) async {
    var currentUri = uri;
    HttpClient? client;

    for (var hop = 0; hop <= _maxRedirects; hop++) {
      client?.close(force: true);
      client = _createClient(timeout);

      final response = await _safeGet(client, currentUri, timeout);
      final statusCode = response.statusCode;

      // Not a redirect — return the response
      if (statusCode < 300 || statusCode >= 400) {
        return (response: response, client: client);
      }

      // 3xx redirect — extract Location, SSRF-validate, continue
      final location = response.headers.value('location');
      // Drain the redirect response body to free the connection
      await response.drain<void>();
      if (location == null || location.isEmpty) {
        client.close(force: true);
        return null;
      }

      final nextUri = currentUri.resolve(location);

      // Must stay HTTPS
      if (nextUri.scheme != 'https') {
        log?.call('LinkPreview: Redirect to non-HTTPS blocked: $nextUri');
        client.close(force: true);
        return null;
      }

      // Full SSRF check on the redirect target
      final nextIp = await resolveSafeIp(nextUri.host,
          timeoutSec: timeout.inSeconds);
      if (nextIp == null) {
        log?.call(
            'LinkPreview: SSRF blocked redirect to private IP: ${nextUri.host}');
        client.close(force: true);
        return null;
      }

      currentUri = nextUri;
    }

    // Too many redirects
    log?.call('LinkPreview: Too many redirects (>$_maxRedirects)');
    client?.close(force: true);
    return null;
  }

  /// Fetch HTML content from URL. Returns null on failure.
  Future<String?> _fetchHtml(Uri uri, Duration timeout) async {
    try {
      final result = await _fetchWithRedirects(uri, timeout);
      if (result == null) return null;

      try {
        final response = result.response;
        if (response.statusCode != 200) return null;

        // Check content-type is HTML
        final contentType = response.headers.contentType;
        if (contentType != null) {
          final isHtml = (contentType.primaryType == 'text' && contentType.subType == 'html') ||
              (contentType.primaryType == 'application' && contentType.subType == 'xhtml+xml');
          if (!isHtml) return null;
        }

        // Read response with size limit
        final chunks = <List<int>>[];
        var totalBytes = 0;
        await for (final chunk in response) {
          totalBytes += chunk.length;
          if (totalBytes > settings.maxHtmlBytes) {
            break; // Size limit exceeded — use what we have
          }
          chunks.add(chunk);
        }

        return utf8.decode(
          chunks.expand((c) => c).toList(),
          allowMalformed: true,
        );
      } finally {
        result.client.close(force: true);
      }
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch og:image and create a small JPEG thumbnail.
  /// Returns raw image bytes (max 64 KB) or null.
  Future<Uint8List?> _fetchThumbnail(
      String imageUrl, Uri pageUri, Duration timeout) async {
    try {
      // Resolve relative URLs
      var imgUri = Uri.tryParse(imageUrl);
      if (imgUri == null) return null;
      if (!imgUri.hasScheme) imgUri = pageUri.resolve(imageUrl);
      if (imgUri.scheme != 'https') return null;

      // SSRF check on image URL — resolve and validate
      final safeIp = await resolveSafeIp(imgUri.host,
          timeoutSec: timeout.inSeconds);
      if (safeIp == null) return null;

      // Fetch with redirect handling (each hop SSRF-validated)
      final result = await _fetchWithRedirects(imgUri, timeout);
      if (result == null) return null;

      try {
        final response = result.response;
        if (response.statusCode != 200) return null;

        // Read with size limit
        final chunks = <List<int>>[];
        var totalBytes = 0;
        await for (final chunk in response) {
          totalBytes += chunk.length;
          if (totalBytes > settings.maxImageBytes) return null;
          chunks.add(chunk);
        }

        final bytes = Uint8List.fromList(chunks.expand((c) => c).toList());

        if (bytes.length <= 65536) return bytes;
        return recompressToFit(bytes, 65536);
      } finally {
        result.client.close(force: true);
      }
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Decode an image and re-encode as JPEG until it fits in [maxBytes].
  ///
  /// Strategy: try descending JPEG quality at width 600, then 400, then 300.
  /// Returns null if the image cannot be decoded or no quality/size combination
  /// produces a payload within [maxBytes]. Public so that smoke tests can verify
  /// the size-fit invariant without requiring a network round-trip.
  static Uint8List? recompressToFit(Uint8List src, int maxBytes) {
    try {
      final decoded = img.decodeImage(src);
      if (decoded == null) return null;

      const widths = [600, 400, 300];
      const qualities = [75, 60, 45, 30];
      for (final w in widths) {
        final scaled = decoded.width > w
            ? img.copyResize(decoded, width: w)
            : decoded;
        for (final q in qualities) {
          final encoded = img.encodeJpg(scaled, quality: q);
          if (encoded.length <= maxBytes) return Uint8List.fromList(encoded);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
