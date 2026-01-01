class ChannelUri {
  final String channelIdHex;
  final String name;

  const ChannelUri({required this.channelIdHex, required this.name});

  static const prefix = 'cleona://channel/';

  String toUri() {
    return '$prefix$channelIdHex?n=${Uri.encodeComponent(name)}';
  }

  String toShareText() => 'Cleona Channel: $name\n${toUri()}';

  static ChannelUri? parse(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith(prefix)) return null;

    final rest = trimmed.substring(prefix.length);
    final qIdx = rest.indexOf('?');

    final channelIdHex = qIdx >= 0 ? rest.substring(0, qIdx) : rest;
    if (channelIdHex.length != 64) return null;
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(channelIdHex)) return null;

    var name = '';
    if (qIdx >= 0) {
      final params = Uri.splitQueryString(rest.substring(qIdx + 1));
      name = params['n'] ?? '';
    }

    return ChannelUri(channelIdHex: channelIdHex.toLowerCase(), name: name);
  }

  static final _channelUriRegex = RegExp(
    r'cleona://channel/[0-9a-fA-F]{64}(?:\?[^\s]*)?',
  );

  static ChannelUri? findInText(String text) {
    final match = _channelUriRegex.firstMatch(text);
    if (match == null) return null;
    return parse(match.group(0)!);
  }
}
