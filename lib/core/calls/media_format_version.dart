// Medienformat-Versionierung fuer den Audio/Video-Kanal (V1.18).
//
// Architektur §10.3.1 (Live-Media-Transport), §10.4 (Voice-Stack), §10.6
// (Video). Wire-Felder: `CallInvite.caller_{audio,video}_format_{min,max}`
// und `CallAnswer.selected_{audio,video}_format` in `proto/cleona.proto`.
//
// WOZU. Zu 3.1 gibt es keine Rueckwaertskompatibilitaet, das bleibt so
// (§10.4 "Compatibility: none, by decision"). Dieses Modul stellt sie nicht
// her. Es existiert fuer den umgekehrten Fall: damit eine KUENFTIGE Version
// (3.3, 4.0, ...) mit 3.2 noch sprechen kann, statt einen zweiten harten
// Schnitt zu erzwingen.
//
// ABGRENZUNG ZUM VERSIONSGATE AUF CALL_INVITE (Feld 8, V1.12/V2.1). Die
// beiden ueberschneiden sich nicht und keines ist ueberfluessig:
//
//   * `caller_app_major_minor` ist ein einseitiger BODEN auf der APP-Version.
//     Er wird nicht ausgehandelt, und er kann nicht ausdruecken, was die
//     Gegenseite spricht. Ein heute ausgelieferter 3.2-Client traegt
//     `>= 3002` einbetoniert und nimmt damit jede kuenftige Version
//     bedingungslos an — er kann nie lernen, dass 3.4-Medien fuer ihn
//     undekodierbar sind.
//   * Das Medienformat hier wird AUSGEHANDELT und ist BEIDSEITIG. Es
//     beschreibt das Format, nicht die App.
//
// Feld 8 beantwortet "koennen wir ueberhaupt reden" und weist 3.1.x ab, das
// weder das eine noch das andere Feld traegt. Dieses Modul beantwortet "in
// welchem Dialekt" und wirkt ausschliesslich oberhalb jenes Bodens.
//
// VORBILD IM HAUS. `PerMessageKem.acceptKemVersions` (per_message_kem.dart:65)
// fuehrt denselben protokolleigenen Zaehler, unabhaengig von der App-Version,
// und weist unbekannte Versionen ab statt sie durchzuwinken. Dass die
// Akzeptanzmenge dort von {1} auf {2} gewechselt ist (v1 entfernt in V3.1.72),
// ist zugleich der Beleg, dass alte Formate fallen gelassen werden — deshalb
// traegt die Aushandlung hier ein Minimum und nicht nur ein Maximum.
//
// Reine Logik: keine Sockets, keine Proto-Abhaengigkeit, kein Zustand. Die
// Verdrahtung in `call_service.dart` samt fuer den Nutzer sichtbarem
// Ablehnungsgrund gehoert V2.1 (BUILD_REQUEST_V1.18.md).

/// Ausgang einer Formataushandlung.
enum MediaFormatOutcome {
  /// Beide Seiten haben ein gemeinsames Format. [MediaFormatDecision.selected]
  /// traegt es.
  agreed,

  /// Die Spannen ueberschneiden sich nicht. Der Call wird abgelehnt — mit
  /// einem fuer den Nutzer sichtbaren Grund. §10.4: "never allowed to fail
  /// silently, which would reproduce exactly the field symptoms this rewrite
  /// removes".
  incompatible,
}

/// Ergebnis einer Aushandlung oder einer Pruefung der Gegenwahl.
class MediaFormatDecision {
  final MediaFormatOutcome outcome;

  /// Das gewaehlte Format. Nur bei [MediaFormatOutcome.agreed] aussagekraeftig.
  final int selected;

  /// Klartext-Begruendung fuer Log und Fehlerreport. NICHT der uebersetzte
  /// Text fuer den Nutzer — die i18n-Keys in allen 34 Locales legt V2.1 an
  /// (Arbeitsregel 7), zusammen mit der Anzeige.
  final String detail;

  const MediaFormatDecision._(this.outcome, this.selected, this.detail);

  bool get isAgreed => outcome == MediaFormatOutcome.agreed;

  @override
  String toString() =>
      'MediaFormatDecision(${outcome.name}, selected=$selected, $detail)';
}

/// Eine zusammenhaengende Spanne unterstuetzter Formatversionen.
///
/// Zusammenhaengend und nicht als Menge, weil die Akzeptanzmenge dieses
/// Projekts immer zusammenhaengend war (siehe `acceptKemVersions`) und eine
/// Menge auf dem Draht teurer waere als der Gegenwert.
class MediaFormatRange {
  final int min;
  final int max;

  const MediaFormatRange(this.min, this.max);

  bool contains(int v) => v >= min && v <= max;

  @override
  String toString() => '[$min,$max]';
}

/// Politik und Konstanten der Medienformat-Versionierung.
class MediaFormatVersion {
  MediaFormatVersion._();

  /// Das Basisformat: der Medienstapel, wie ihn 3.2.0 ausliefert.
  ///
  /// Zaehlt unabhaengig von der App-Version hoch, genau wie
  /// `PerMessageKem.currentKemVersion`. Ein Patch-Release aendert das Format
  /// nicht; ein Format-Wechsel kann in jeder kuenftigen Version liegen.
  static const int kBaselineFormat = 1;

  /// Was dieser Build an Audio spricht. Heute nur das Basisformat.
  /// Steigt, sobald §10.4 Stufe 5 (Opus) das Frame-Format aendert.
  static const MediaFormatRange audio =
      MediaFormatRange(kBaselineFormat, kBaselineFormat);

  /// Was dieser Build an Video spricht. Heute nur das Basisformat.
  /// Steigt, sobald §10.6 Stufe 4/5 (Plattform-Hardware-Codec) das
  /// Frame-Format aendert.
  static const MediaFormatRange video =
      MediaFormatRange(kBaselineFormat, kBaselineFormat);

  /// Deutet einen vom Draht gelesenen Formatwert.
  ///
  /// EIN FEHLENDES FELD IST EINE AUSSAGE, KEINE LUECKE. proto3 liefert 0.
  /// Weglassen kann das Feld nur ein Build ab 3.2.0, der vor V1.18 entstanden
  /// ist — und der spricht genau das Basisformat. 0 heisst hier deshalb
  /// definiert [kBaselineFormat], nicht "unbekannt, also wohl in Ordnung".
  ///
  /// Das ist bewusst die andere Folgerung als bei `caller_app_major_minor`,
  /// wo 0 zur Ablehnung fuehrt: dort stammt die 0 von einem 3.1.x-Client, der
  /// ueberhaupt keinen Call halten kann, hier von einem 3.2.0-Client, der es
  /// kann. Gleiche Regel, verschiedene Sachlage.
  static int normalize(int wireValue) =>
      wireValue == 0 ? kBaselineFormat : wireValue;

  /// Liest eine Spanne vom Draht. Beide Felder werden einzeln normalisiert.
  ///
  /// Eine vom Peer verdrehte Spanne (min > max) wird nicht stillschweigend
  /// geradegebogen — sie bleibt verdreht und fuehrt in [negotiate] zur
  /// Ablehnung. Ein Peer, der Unsinn sendet, bekommt keinen Call, keine
  /// Reparatur.
  static MediaFormatRange rangeFromWire(int wireMin, int wireMax) =>
      MediaFormatRange(normalize(wireMin), normalize(wireMax));

  /// Angerufenen-Seite: waehlt das hoechste Format, das BEIDE sprechen.
  ///
  /// Das hoechste gemeinsame und nicht das eigene hoechste — genau hier
  /// entsteht die kuenftige Abwaertskompatibilitaet. Spricht der Peer mehr
  /// als wir, schalten wir herunter, statt ihn abzuweisen.
  ///
  /// Beide Richtungen sind abgedeckt:
  ///  * Peer-Maximum HOEHER als das eigene -> das eigene Maximum wird gewaehlt
  ///    (Herunterschalten). Der eigentliche Zweck dieses Moduls.
  ///  * Peer-Maximum NIEDRIGER als das eigene -> das Peer-Maximum wird
  ///    gewaehlt, sofern es nicht unter das eigene Minimum faellt. Faellt es
  ///    darunter, haben wir dieses Format fallen gelassen -> Ablehnung.
  static MediaFormatDecision negotiate({
    required MediaFormatRange peer,
    required MediaFormatRange own,
    String kind = 'media',
  }) {
    if (peer.min > peer.max) {
      return MediaFormatDecision._(
        MediaFormatOutcome.incompatible,
        0,
        '$kind: Peer-Spanne ist verdreht ($peer) — kein gueltiges Angebot',
      );
    }
    final lo = peer.min > own.min ? peer.min : own.min;
    final hi = peer.max < own.max ? peer.max : own.max;
    if (hi < lo) {
      return MediaFormatDecision._(
        MediaFormatOutcome.incompatible,
        0,
        '$kind: keine Ueberschneidung — Peer $peer, eigen $own',
      );
    }
    return MediaFormatDecision._(
      MediaFormatOutcome.agreed,
      hi,
      '$kind: $hi gewaehlt aus Peer $peer und eigen $own',
    );
  }

  /// Anrufer-Seite: prueft die Wahl des Angerufenen aus `CallAnswer`.
  ///
  /// Geprueft wird gegen die eigene Spanne UND gegen das tatsaechlich
  /// angebotene [offered]. Ein defekter oder boeswilliger Peer kann so kein
  /// Format erzwingen, das wir nie angeboten haben — auch dann nicht, wenn
  /// wir es grundsaetzlich sprechen koennten.
  static MediaFormatDecision verifySelection({
    required int wireSelected,
    required MediaFormatRange own,
    required MediaFormatRange offered,
    String kind = 'media',
  }) {
    final selected = normalize(wireSelected);
    if (!own.contains(selected)) {
      return MediaFormatDecision._(
        MediaFormatOutcome.incompatible,
        0,
        '$kind: Peer waehlte $selected, das dieser Build nicht spricht '
        '(eigen $own)',
      );
    }
    if (!offered.contains(selected)) {
      return MediaFormatDecision._(
        MediaFormatOutcome.incompatible,
        0,
        '$kind: Peer waehlte $selected, das nicht angeboten war '
        '(angeboten $offered)',
      );
    }
    return MediaFormatDecision._(
      MediaFormatOutcome.agreed,
      selected,
      '$kind: Wahl $selected bestaetigt',
    );
  }
}
