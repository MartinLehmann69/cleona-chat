import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// 24-word recovery phrase using phonetic pattern words.
///
/// 256 bits entropy + 8-bit checksum = 264 bits = 24 × 11-bit indices.
/// Word list: 2048 phonetically distinct words (CV/CVC/CVCV patterns).
class SeedPhrase {
  static const int _entropyBytes = 32; // 256 bits
  static const int _wordCount = 24;
  static const int _bitsPerWord = 11;

  /// Generate a new random seed phrase.
  static List<String> generate() {
    final sodium = SodiumFFI();
    final entropy = sodium.randomBytes(_entropyBytes);
    return entropyToWords(entropy);
  }

  /// Convert 32-byte entropy to 24 words.
  static List<String> entropyToWords(Uint8List entropy) {
    if (entropy.length != _entropyBytes) {
      throw ArgumentError('Entropy must be $_entropyBytes bytes');
    }

    // Compute checksum: first byte of SHA-256(entropy)
    final sodium = SodiumFFI();
    final hash = sodium.sha256(entropy);
    final checksumByte = hash[0];

    // Combine entropy (256 bits) + checksum (8 bits) = 264 bits
    final allBits = Uint8List(_entropyBytes + 1);
    allBits.setRange(0, _entropyBytes, entropy);
    allBits[_entropyBytes] = checksumByte;

    // Extract 24 × 11-bit indices
    final words = <String>[];
    for (var i = 0; i < _wordCount; i++) {
      final bitOffset = i * _bitsPerWord;
      final index = _extractBits(allBits, bitOffset, _bitsPerWord);
      words.add(_wordList[index]);
    }
    return words;
  }

  /// Convert 24 words back to 32-byte entropy.
  /// Throws if checksum doesn't match or words are invalid.
  static Uint8List wordsToEntropy(List<String> words) {
    if (words.length != _wordCount) {
      throw ArgumentError('Expected $_wordCount words, got ${words.length}');
    }

    // Look up word indices
    final indices = <int>[];
    for (final word in words) {
      final lower = word.toLowerCase().trim();
      final idx = _wordList.indexOf(lower);
      if (idx < 0) throw ArgumentError('Unknown word: "$word"');
      indices.add(idx);
    }

    // Reconstruct 264 bits from 24 × 11-bit indices
    final allBits = Uint8List(_entropyBytes + 1);
    for (var i = 0; i < _wordCount; i++) {
      _insertBits(allBits, i * _bitsPerWord, _bitsPerWord, indices[i]);
    }

    // Split into entropy (32 bytes) + checksum (1 byte)
    final entropy = Uint8List.fromList(allBits.sublist(0, _entropyBytes));
    final givenChecksum = allBits[_entropyBytes];

    // Verify checksum
    final sodium = SodiumFFI();
    final hash = sodium.sha256(entropy);
    if (hash[0] != givenChecksum) {
      throw ArgumentError('Checksum mismatch — invalid recovery phrase');
    }

    return entropy;
  }

  /// Derive master seed from entropy (32 bytes → 32 bytes).
  static Uint8List entropyToSeed(Uint8List entropy) {
    final sodium = SodiumFFI();
    // Domain-separated derivation
    final input = Uint8List.fromList([
      ...'cleona-master-seed-v1'.codeUnits,
      ...entropy,
    ]);
    return sodium.sha256(input);
  }

  /// Validate a phrase without returning the entropy.
  static bool isValid(List<String> words) {
    try {
      wordsToEntropy(words);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Bit manipulation helpers ──────────────────────────────────────

  static int _extractBits(Uint8List data, int bitOffset, int bitCount) {
    var value = 0;
    for (var i = 0; i < bitCount; i++) {
      final byteIdx = (bitOffset + i) ~/ 8;
      final bitIdx = 7 - ((bitOffset + i) % 8);
      if (data[byteIdx] & (1 << bitIdx) != 0) {
        value |= (1 << (bitCount - 1 - i));
      }
    }
    return value;
  }

  static void _insertBits(Uint8List data, int bitOffset, int bitCount, int value) {
    for (var i = 0; i < bitCount; i++) {
      final byteIdx = (bitOffset + i) ~/ 8;
      final bitIdx = 7 - ((bitOffset + i) % 8);
      if (value & (1 << (bitCount - 1 - i)) != 0) {
        data[byteIdx] |= (1 << bitIdx);
      }
    }
  }

  // ── Phonetic word list (2048 words, CV/CVC/CVCV patterns) ────────
  // Generated for maximum phonetic distinctiveness.
  // Patterns: consonant+vowel combinations, easy to pronounce in any language.

  static const List<String> _wordList = [
    // Row 0-63: ba-bu, ca-cu, da-du, fa-fu, ga-gu, ha-hu, ja-ju, ka-ku
    'bado', 'bafe', 'bago', 'bahi', 'bajo', 'baku', 'bale', 'bamo',
    'bane', 'bapo', 'bare', 'baso', 'bate', 'bavo', 'bawe', 'baxo',
    'beda', 'befo', 'bega', 'behi', 'bejo', 'beku', 'bela', 'bemo',
    'bena', 'bepo', 'bera', 'beso', 'beta', 'bevo', 'bewa', 'bexo',
    'bida', 'bife', 'bigo', 'bihe', 'bijo', 'biku', 'bile', 'bimo',
    'bina', 'bipo', 'bire', 'biso', 'bite', 'bivo', 'biwe', 'bixo',
    'boda', 'bofe', 'boga', 'bohi', 'bojo', 'boku', 'bole', 'bomo',
    'bona', 'bopo', 'bore', 'boso', 'bote', 'bovo', 'bowe', 'boxo',
    // Row 64-127: ca-cu
    'cado', 'cafe', 'cago', 'cahi', 'cajo', 'caku', 'cale', 'camo',
    'cane', 'capo', 'care', 'caso', 'cate', 'cavo', 'cawe', 'caxo',
    'ceda', 'cefo', 'cega', 'cehi', 'cejo', 'ceku', 'cela', 'cemo',
    'cena', 'cepo', 'cera', 'ceso', 'ceta', 'cevo', 'cewa', 'cexo',
    'cida', 'cife', 'cigo', 'cihe', 'cijo', 'ciku', 'cile', 'cimo',
    'cina', 'cipo', 'cire', 'ciso', 'cite', 'civo', 'ciwe', 'cixo',
    'coda', 'cofe', 'coga', 'cohi', 'cojo', 'coku', 'cole', 'como',
    'cona', 'copo', 'core', 'coso', 'cote', 'covo', 'cowe', 'coxo',
    // Row 128-191: da-du
    'dabo', 'dafe', 'dago', 'dahi', 'dajo', 'daku', 'dale', 'damo',
    'dane', 'dapo', 'dare', 'daso', 'date', 'davo', 'dawe', 'daxo',
    'deba', 'defo', 'dega', 'dehi', 'dejo', 'deku', 'dela', 'demo',
    'dena', 'depo', 'dera', 'deso', 'deta', 'devo', 'dewa', 'dexo',
    'diba', 'dife', 'digo', 'dihe', 'dijo', 'diku', 'dile', 'dimo',
    'dina', 'dipo', 'dire', 'diso', 'dite', 'divo', 'diwe', 'dixo',
    'doba', 'dofe', 'doga', 'dohi', 'dojo', 'doku', 'dole', 'domo',
    'dona', 'dopo', 'dore', 'doso', 'dote', 'dovo', 'dowe', 'doxo',
    // Row 192-255: fa-fu
    'fabo', 'face', 'fago', 'fahi', 'fajo', 'faku', 'fale', 'famo',
    'fane', 'fapo', 'fare', 'faso', 'fate', 'favo', 'fawe', 'faxo',
    'feba', 'feco', 'fega', 'fehi', 'fejo', 'feku', 'fela', 'femo',
    'fena', 'fepo', 'fera', 'feso', 'feta', 'fevo', 'fewa', 'fexo',
    'fiba', 'fice', 'figo', 'fihe', 'fijo', 'fiku', 'file', 'fimo',
    'fina', 'fipo', 'fire', 'fiso', 'fite', 'fivo', 'fiwe', 'fixo',
    'foba', 'foce', 'foga', 'fohi', 'fojo', 'foku', 'fole', 'fomo',
    'fona', 'fopo', 'fore', 'foso', 'fote', 'fovo', 'fowe', 'foxo',
    // Row 256-319: ga-gu
    'gabo', 'gace', 'gado', 'gahi', 'gajo', 'gaku', 'gale', 'gamo',
    'gane', 'gapo', 'gare', 'gaso', 'gate', 'gavo', 'gawe', 'gaxo',
    'geba', 'geco', 'geda', 'gehi', 'gejo', 'geku', 'gela', 'gemo',
    'gena', 'gepo', 'gera', 'geso', 'geta', 'gevo', 'gewa', 'gexo',
    'giba', 'gice', 'gida', 'gihe', 'gijo', 'giku', 'gile', 'gimo',
    'gina', 'gipo', 'gire', 'giso', 'gite', 'givo', 'giwe', 'gixo',
    'goba', 'goce', 'goda', 'gohi', 'gojo', 'goku', 'gole', 'gomo',
    'gona', 'gopo', 'gore', 'goso', 'gote', 'govo', 'gowe', 'goxo',
    // Row 320-383: ha-hu
    'habo', 'hace', 'hado', 'hafi', 'hajo', 'haku', 'hale', 'hamo',
    'hane', 'hapo', 'hare', 'haso', 'hate', 'havo', 'hawe', 'haxo',
    'heba', 'heco', 'heda', 'hefi', 'hejo', 'heku', 'hela', 'hemo',
    'hena', 'hepo', 'hera', 'heso', 'heta', 'hevo', 'hewa', 'hexo',
    'hiba', 'hice', 'hida', 'hife', 'hijo', 'hiku', 'hile', 'himo',
    'hina', 'hipo', 'hire', 'hiso', 'hite', 'hivo', 'hiwe', 'hixo',
    'hoba', 'hoce', 'hoda', 'hofe', 'hojo', 'hoku', 'hole', 'homo',
    'hona', 'hopo', 'hore', 'hoso', 'hote', 'hovo', 'howe', 'hoxo',
    // Row 384-447: ja-ju
    'jabo', 'jace', 'jado', 'jafe', 'jago', 'jaku', 'jale', 'jamo',
    'jane', 'japo', 'jare', 'jaso', 'jate', 'javo', 'jawe', 'jaxo',
    'jeba', 'jeco', 'jeda', 'jefe', 'jego', 'jeku', 'jela', 'jemo',
    'jena', 'jepo', 'jera', 'jeso', 'jeta', 'jevo', 'jewa', 'jexo',
    'jiba', 'jice', 'jida', 'jife', 'jigo', 'jiku', 'jile', 'jimo',
    'jina', 'jipo', 'jire', 'jiso', 'jite', 'jivo', 'jiwe', 'jixo',
    'joba', 'joce', 'joda', 'jofe', 'jogo', 'joku', 'jole', 'jomo',
    'jona', 'jopo', 'jore', 'joso', 'jote', 'jovo', 'jowe', 'joxo',
    // Row 448-511: ka-ku
    'kabo', 'kace', 'kado', 'kafe', 'kago', 'kahi', 'kale', 'kamo',
    'kane', 'kapo', 'kare', 'kaso', 'kate', 'kavo', 'kawe', 'kaxo',
    'keba', 'keco', 'keda', 'kefe', 'kega', 'kehi', 'kela', 'kemo',
    'kena', 'kepo', 'kera', 'keso', 'keta', 'kevo', 'kewa', 'kexo',
    'kiba', 'kice', 'kida', 'kife', 'kiga', 'kihe', 'kile', 'kimo',
    'kina', 'kipo', 'kire', 'kiso', 'kite', 'kivo', 'kiwe', 'kixo',
    'koba', 'koce', 'koda', 'kofe', 'koga', 'kohi', 'kole', 'komo',
    'kona', 'kopo', 'kore', 'koso', 'kote', 'kovo', 'kowe', 'koxo',
    // Row 512-575: la-lu
    'labo', 'lace', 'lado', 'lafe', 'lago', 'lahi', 'laje', 'lamo',
    'lane', 'lapo', 'lare', 'laso', 'late', 'lavo', 'lawe', 'laxo',
    'leba', 'leco', 'leda', 'lefe', 'lega', 'lehi', 'leja', 'lemo',
    'lena', 'lepo', 'lera', 'leso', 'leta', 'levo', 'lewa', 'lexo',
    'liba', 'lice', 'lida', 'life', 'liga', 'lihe', 'lija', 'limo',
    'lina', 'lipo', 'lire', 'liso', 'lite', 'livo', 'liwe', 'lixo',
    'loba', 'loce', 'loda', 'lofe', 'loga', 'lohi', 'loja', 'lomo',
    'lona', 'lopo', 'lore', 'loso', 'lote', 'lovo', 'lowe', 'loxo',
    // Row 576-639: ma-mu
    'mabo', 'mace', 'mado', 'mafe', 'mago', 'mahi', 'maje', 'mako',
    'mane', 'mapo', 'mare', 'maso', 'mate', 'mavo', 'mawe', 'maxo',
    'meba', 'meco', 'meda', 'mefe', 'mega', 'mehi', 'meja', 'meko',
    'mena', 'mepo', 'mera', 'meso', 'meta', 'mevo', 'mewa', 'mexo',
    'miba', 'mice', 'mida', 'mife', 'miga', 'mihe', 'mija', 'miko',
    'mina', 'mipo', 'mire', 'miso', 'mite', 'mivo', 'miwe', 'mixo',
    'moba', 'moce', 'moda', 'mofe', 'moga', 'mohe', 'moja', 'moko',
    'mona', 'mopo', 'more', 'moso', 'mote', 'movo', 'mowe', 'moxo',
    // Row 640-703: na-nu
    'nabo', 'nace', 'nado', 'nafe', 'nago', 'nahi', 'naje', 'nako',
    'name', 'napo', 'nare', 'naso', 'nate', 'navo', 'nawe', 'naxo',
    'neba', 'neco', 'neda', 'nefe', 'nega', 'nehi', 'neja', 'neko',
    'nema', 'nepo', 'nera', 'neso', 'neta', 'nevo', 'newa', 'nexo',
    'niba', 'nice', 'nida', 'nife', 'niga', 'nihe', 'nija', 'niko',
    'nima', 'nipo', 'nire', 'niso', 'nite', 'nivo', 'niwe', 'nixo',
    'noba', 'noce', 'noda', 'nofe', 'noga', 'nohe', 'noja', 'noko',
    'noma', 'nopo', 'nore', 'noso', 'note', 'novo', 'nowe', 'noxo',
    // Row 704-767: pa-pu
    'pabo', 'pace', 'pado', 'pafe', 'pago', 'pahi', 'paje', 'pako',
    'pame', 'papo', 'pare', 'paso', 'pate', 'pavo', 'pawe', 'paxo',
    'peba', 'peco', 'peda', 'pefe', 'pega', 'pehi', 'peja', 'peko',
    'pema', 'pepo', 'pera', 'peso', 'peta', 'pevo', 'pewa', 'pexo',
    'piba', 'pice', 'pida', 'pife', 'piga', 'pihe', 'pija', 'piko',
    'pima', 'pipo', 'pire', 'piso', 'pite', 'pivo', 'piwe', 'pixo',
    'poba', 'poce', 'poda', 'pofe', 'poga', 'pohe', 'poja', 'poko',
    'poma', 'popo', 'pore', 'poso', 'pote', 'povo', 'powe', 'poxo',
    // Row 768-831: ra-ru
    'rabo', 'race', 'rado', 'rafe', 'rago', 'rahi', 'raje', 'rako',
    'rame', 'rapo', 'rare', 'raso', 'rate', 'ravo', 'rawe', 'raxo',
    'reba', 'reco', 'reda', 'refe', 'rega', 'rehi', 'reja', 'reko',
    'rema', 'repo', 'rera', 'reso', 'reta', 'revo', 'rewa', 'rexo',
    'riba', 'rice', 'rida', 'rife', 'riga', 'rihe', 'rija', 'riko',
    'rima', 'ripo', 'rira', 'riso', 'rite', 'rivo', 'riwe', 'rixo',
    'roba', 'roce', 'roda', 'rofe', 'roga', 'rohe', 'roja', 'roko',
    'roma', 'ropo', 'rora', 'roso', 'rote', 'rovo', 'rowe', 'roxo',
    // Row 832-895: sa-su
    'sabo', 'sace', 'sado', 'safe', 'sago', 'sahi', 'saje', 'sako',
    'same', 'sapo', 'sare', 'saro', 'sate', 'savo', 'sawe', 'saxo',
    'seba', 'seco', 'seda', 'sefe', 'sega', 'sehi', 'seja', 'seko',
    'sema', 'sepo', 'sera', 'sero', 'seta', 'sevo', 'sewa', 'sexo',
    'siba', 'sice', 'sida', 'sife', 'siga', 'sihe', 'sija', 'siko',
    'sima', 'sipo', 'sira', 'siro', 'site', 'sivo', 'siwe', 'sixo',
    'soba', 'soce', 'soda', 'sofe', 'soga', 'sohe', 'soja', 'soko',
    'soma', 'sopo', 'sora', 'soro', 'sote', 'sovo', 'sowe', 'soxo',
    // Row 896-959: ta-tu
    'tabo', 'tace', 'tado', 'tafe', 'tago', 'tahi', 'taje', 'tako',
    'tame', 'tapo', 'tare', 'taro', 'tase', 'tavo', 'tawe', 'taxo',
    'teba', 'teco', 'teda', 'tefe', 'tega', 'tehi', 'teja', 'teko',
    'tema', 'tepo', 'tera', 'tero', 'tesa', 'tevo', 'tewa', 'texo',
    'tiba', 'tice', 'tida', 'tife', 'tiga', 'tihe', 'tija', 'tiko',
    'tima', 'tipo', 'tira', 'tiro', 'tisa', 'tivo', 'tiwe', 'tixo',
    'toba', 'toce', 'toda', 'tofe', 'toga', 'tohe', 'toja', 'toko',
    'toma', 'topo', 'tora', 'toro', 'tosa', 'tovo', 'towe', 'toxo',
    // Row 960-1023: va-vu
    'vabo', 'vace', 'vado', 'vafe', 'vago', 'vahi', 'vaje', 'vako',
    'vame', 'vapo', 'vare', 'varo', 'vase', 'vato', 'vawe', 'vaxo',
    'veba', 'veco', 'veda', 'vefe', 'vega', 'vehi', 'veja', 'veko',
    'vema', 'vepo', 'vera', 'vero', 'vesa', 'veto', 'vewa', 'vexo',
    'viba', 'vice', 'vida', 'vife', 'viga', 'vihe', 'vija', 'viko',
    'vima', 'vipo', 'vira', 'viro', 'visa', 'vito', 'viwe', 'vixo',
    'voba', 'voce', 'voda', 'vofe', 'voga', 'vohe', 'voja', 'voko',
    'voma', 'vopo', 'vora', 'voro', 'vosa', 'voto', 'vowe', 'voxo',
    // Row 1024-1087: wa-wu
    'wabo', 'wace', 'wado', 'wafe', 'wago', 'wahi', 'waje', 'wako',
    'wame', 'wapo', 'ware', 'waro', 'wase', 'wato', 'wave', 'waxo',
    'weba', 'weco', 'weda', 'wefe', 'wega', 'wehi', 'weja', 'weko',
    'wema', 'wepo', 'wera', 'wero', 'wesa', 'weto', 'weva', 'wexo',
    'wiba', 'wice', 'wida', 'wife', 'wiga', 'wihe', 'wija', 'wiko',
    'wima', 'wipo', 'wira', 'wiro', 'wisa', 'wito', 'wiva', 'wixo',
    'woba', 'woce', 'woda', 'wofe', 'woga', 'wohe', 'woja', 'woko',
    'woma', 'wopo', 'wora', 'woro', 'wosa', 'woto', 'wova', 'woxo',
    // Row 1088-1151: xa-xu (rare, distinctive)
    'xabo', 'xace', 'xado', 'xafe', 'xago', 'xahi', 'xaje', 'xako',
    'xame', 'xapo', 'xare', 'xaro', 'xase', 'xato', 'xave', 'xawo',
    'xeba', 'xeco', 'xeda', 'xefe', 'xega', 'xehi', 'xeja', 'xeko',
    'xema', 'xepo', 'xera', 'xero', 'xesa', 'xeto', 'xeva', 'xewo',
    'xiba', 'xice', 'xida', 'xife', 'xiga', 'xihe', 'xija', 'xiko',
    'xima', 'xipo', 'xira', 'xiro', 'xisa', 'xito', 'xiva', 'xiwo',
    'xoba', 'xoce', 'xoda', 'xofe', 'xoga', 'xohe', 'xoja', 'xoko',
    'xoma', 'xopo', 'xora', 'xoro', 'xosa', 'xoto', 'xova', 'xowo',
    // Row 1152-1215: za-zu
    'zabo', 'zace', 'zado', 'zafe', 'zago', 'zahi', 'zaje', 'zako',
    'zame', 'zapo', 'zare', 'zaro', 'zase', 'zato', 'zave', 'zawo',
    'zeba', 'zeco', 'zeda', 'zefe', 'zega', 'zehi', 'zeja', 'zeko',
    'zema', 'zepo', 'zera', 'zero', 'zesa', 'zeto', 'zeva', 'zewo',
    'ziba', 'zice', 'zida', 'zife', 'ziga', 'zihe', 'zija', 'ziko',
    'zima', 'zipo', 'zira', 'ziro', 'zisa', 'zito', 'ziva', 'ziwo',
    'zoba', 'zoce', 'zoda', 'zofe', 'zoga', 'zohe', 'zoja', 'zoko',
    'zoma', 'zopo', 'zora', 'zoro', 'zosa', 'zoto', 'zova', 'zowo',
    // Row 1216-2047: Unique CVCVC patterns (auto-generated)
    'babab', 'babad', 'babaf', 'babak', 'baban', 'babap', 'babar', 'babas',
    'babat', 'babeb', 'babed', 'babef', 'babek', 'baben', 'babep', 'baber',
    'babes', 'babet', 'babib', 'babid', 'babif', 'babik', 'babin', 'babip',
    'babir', 'babis', 'babit', 'babob', 'babod', 'babof', 'babok', 'babon',
    'babop', 'babor', 'babos', 'babot', 'babub', 'babud', 'babuf', 'babuk',
    'babun', 'babup', 'babur', 'babus', 'babut', 'badab', 'badad', 'badaf',
    'badak', 'badan', 'badap', 'badar', 'badas', 'badat', 'badeb', 'baded',
    'badef', 'badek', 'baden', 'badep', 'bader', 'bades', 'badet', 'badib',
    'badid', 'badif', 'badik', 'badin', 'badip', 'badir', 'badis', 'badit',
    'badob', 'badod', 'badof', 'badok', 'badon', 'badop', 'bador', 'bados',
    'badot', 'badub', 'badud', 'baduf', 'baduk', 'badun', 'badup', 'badur',
    'badus', 'badut', 'bafab', 'bafad', 'bafaf', 'bafak', 'bafan', 'bafap',
    'bafar', 'bafas', 'bafat', 'bafeb', 'bafed', 'bafef', 'bafek', 'bafen',
    'bafep', 'bafer', 'bafes', 'bafet', 'bafib', 'bafid', 'bafif', 'bafik',
    'bafin', 'bafip', 'bafir', 'bafis', 'bafit', 'bafob', 'bafod', 'bafof',
    'bafok', 'bafon', 'bafop', 'bafor', 'bafos', 'bafot', 'bafub', 'bafud',
    'bafuf', 'bafuk', 'bafun', 'bafup', 'bafur', 'bafus', 'bafut', 'bagab',
    'bagad', 'bagaf', 'bagak', 'bagan', 'bagap', 'bagar', 'bagas', 'bagat',
    'bageb', 'baged', 'bagef', 'bagek', 'bagen', 'bagep', 'bager', 'bages',
    'baget', 'bagib', 'bagid', 'bagif', 'bagik', 'bagin', 'bagip', 'bagir',
    'bagis', 'bagit', 'bagob', 'bagod', 'bagof', 'bagok', 'bagon', 'bagop',
    'bagor', 'bagos', 'bagot', 'bagub', 'bagud', 'baguf', 'baguk', 'bagun',
    'bagup', 'bagur', 'bagus', 'bagut', 'bakab', 'bakad', 'bakaf', 'bakak',
    'bakan', 'bakap', 'bakar', 'bakas', 'bakat', 'bakeb', 'baked', 'bakef',
    'bakek', 'baken', 'bakep', 'baker', 'bakes', 'baket', 'bakib', 'bakid',
    'bakif', 'bakik', 'bakin', 'bakip', 'bakir', 'bakis', 'bakit', 'bakob',
    'bakod', 'bakof', 'bakok', 'bakon', 'bakop', 'bakor', 'bakos', 'bakot',
    'bakub', 'bakud', 'bakuf', 'bakuk', 'bakun', 'bakup', 'bakur', 'bakus',
    'bakut', 'balab', 'balad', 'balaf', 'balak', 'balan', 'balap', 'balar',
    'balas', 'balat', 'baleb', 'baled', 'balef', 'balek', 'balen', 'balep',
    'baler', 'bales', 'balet', 'balib', 'balid', 'balif', 'balik', 'balin',
    'balip', 'balir', 'balis', 'balit', 'balob', 'balod', 'balof', 'balok',
    'balon', 'balop', 'balor', 'balos', 'balot', 'balub', 'balud', 'baluf',
    'baluk', 'balun', 'balup', 'balur', 'balus', 'balut', 'bamab', 'bamad',
    'bamaf', 'bamak', 'baman', 'bamap', 'bamar', 'bamas', 'bamat', 'bameb',
    'bamed', 'bamef', 'bamek', 'bamen', 'bamep', 'bamer', 'bames', 'bamet',
    'bamib', 'bamid', 'bamif', 'bamik', 'bamin', 'bamip', 'bamir', 'bamis',
    'bamit', 'bamob', 'bamod', 'bamof', 'bamok', 'bamon', 'bamop', 'bamor',
    'bamos', 'bamot', 'bamub', 'bamud', 'bamuf', 'bamuk', 'bamun', 'bamup',
    'bamur', 'bamus', 'bamut', 'banab', 'banad', 'banaf', 'banak', 'banan',
    'banap', 'banar', 'banas', 'banat', 'baneb', 'baned', 'banef', 'banek',
    'banen', 'banep', 'baner', 'banes', 'banet', 'banib', 'banid', 'banif',
    'banik', 'banin', 'banip', 'banir', 'banis', 'banit', 'banob', 'banod',
    'banof', 'banok', 'banon', 'banop', 'banor', 'banos', 'banot', 'banub',
    'banud', 'banuf', 'banuk', 'banun', 'banup', 'banur', 'banus', 'banut',
    'bapab', 'bapad', 'bapaf', 'bapak', 'bapan', 'bapap', 'bapar', 'bapas',
    'bapat', 'bapeb', 'baped', 'bapef', 'bapek', 'bapen', 'bapep', 'baper',
    'bapes', 'bapet', 'bapib', 'bapid', 'bapif', 'bapik', 'bapin', 'bapip',
    'bapir', 'bapis', 'bapit', 'bapob', 'bapod', 'bapof', 'bapok', 'bapon',
    'bapop', 'bapor', 'bapos', 'bapot', 'bapub', 'bapud', 'bapuf', 'bapuk',
    'bapun', 'bapup', 'bapur', 'bapus', 'baput', 'barab', 'barad', 'baraf',
    'barak', 'baran', 'barap', 'barar', 'baras', 'barat', 'bareb', 'bared',
    'baref', 'barek', 'baren', 'barep', 'barer', 'bares', 'baret', 'barib',
    'barid', 'barif', 'barik', 'barin', 'barip', 'barir', 'baris', 'barit',
    'barob', 'barod', 'barof', 'barok', 'baron', 'barop', 'baror', 'baros',
    'barot', 'barub', 'barud', 'baruf', 'baruk', 'barun', 'barup', 'barur',
    'barus', 'barut', 'basab', 'basad', 'basaf', 'basak', 'basan', 'basap',
    'basar', 'basas', 'basat', 'baseb', 'based', 'basef', 'basek', 'basen',
    'basep', 'baser', 'bases', 'baset', 'basib', 'basid', 'basif', 'basik',
    'basin', 'basip', 'basir', 'basis', 'basit', 'basob', 'basod', 'basof',
    'basok', 'bason', 'basop', 'basor', 'basos', 'basot', 'basub', 'basud',
    'basuf', 'basuk', 'basun', 'basup', 'basur', 'basus', 'basut', 'batab',
    'batad', 'bataf', 'batak', 'batan', 'batap', 'batar', 'batas', 'batat',
    'bateb', 'bated', 'batef', 'batek', 'baten', 'batep', 'bater', 'bates',
    'batet', 'batib', 'batid', 'batif', 'batik', 'batin', 'batip', 'batir',
    'batis', 'batit', 'batob', 'batod', 'batof', 'batok', 'baton', 'batop',
    'bator', 'batos', 'batot', 'batub', 'batud', 'batuf', 'batuk', 'batun',
    'batup', 'batur', 'batus', 'batut', 'bavab', 'bavad', 'bavaf', 'bavak',
    'bavan', 'bavap', 'bavar', 'bavas', 'bavat', 'baveb', 'baved', 'bavef',
    'bavek', 'baven', 'bavep', 'baver', 'baves', 'bavet', 'bavib', 'bavid',
    'bavif', 'bavik', 'bavin', 'bavip', 'bavir', 'bavis', 'bavit', 'bavob',
    'bavod', 'bavof', 'bavok', 'bavon', 'bavop', 'bavor', 'bavos', 'bavot',
    'bavub', 'bavud', 'bavuf', 'bavuk', 'bavun', 'bavup', 'bavur', 'bavus',
    'bavut', 'bebab', 'bebad', 'bebaf', 'bebak', 'beban', 'bebap', 'bebar',
    'bebas', 'bebat', 'bebeb', 'bebed', 'bebef', 'bebek', 'beben', 'bebep',
    'beber', 'bebes', 'bebet', 'bebib', 'bebid', 'bebif', 'bebik', 'bebin',
    'bebip', 'bebir', 'bebis', 'bebit', 'bebob', 'bebod', 'bebof', 'bebok',
    'bebon', 'bebop', 'bebor', 'bebos', 'bebot', 'bebub', 'bebud', 'bebuf',
    'bebuk', 'bebun', 'bebup', 'bebur', 'bebus', 'bebut', 'bedab', 'bedad',
    'bedaf', 'bedak', 'bedan', 'bedap', 'bedar', 'bedas', 'bedat', 'bedeb',
    'beded', 'bedef', 'bedek', 'beden', 'bedep', 'beder', 'bedes', 'bedet',
    'bedib', 'bedid', 'bedif', 'bedik', 'bedin', 'bedip', 'bedir', 'bedis',
    'bedit', 'bedob', 'bedod', 'bedof', 'bedok', 'bedon', 'bedop', 'bedor',
    'bedos', 'bedot', 'bedub', 'bedud', 'beduf', 'beduk', 'bedun', 'bedup',
    'bedur', 'bedus', 'bedut', 'befab', 'befad', 'befaf', 'befak', 'befan',
    'befap', 'befar', 'befas', 'befat', 'befeb', 'befed', 'befef', 'befek',
    'befen', 'befep', 'befer', 'befes', 'befet', 'befib', 'befid', 'befif',
    'befik', 'befin', 'befip', 'befir', 'befis', 'befit', 'befob', 'befod',
    'befof', 'befok', 'befon', 'befop', 'befor', 'befos', 'befot', 'befub',
    'befud', 'befuf', 'befuk', 'befun', 'befup', 'befur', 'befus', 'befut',
    'begab', 'begad', 'begaf', 'begak', 'began', 'begap', 'begar', 'begas',
    'begat', 'begeb', 'beged', 'begef', 'begek', 'begen', 'begep', 'beger',
    'beges', 'beget', 'begib', 'begid', 'begif', 'begik', 'begin', 'begip',
    'begir', 'begis', 'begit', 'begob', 'begod', 'begof', 'begok', 'begon',
    'begop', 'begor', 'begos', 'begot', 'begub', 'begud', 'beguf', 'beguk',
    'begun', 'begup', 'begur', 'begus', 'begut', 'bekab', 'bekad', 'bekaf',
    'bekak', 'bekan', 'bekap', 'bekar', 'bekas', 'bekat', 'bekeb', 'beked',
    'bekef', 'bekek', 'beken', 'bekep', 'beker', 'bekes', 'beket', 'bekib',
    'bekid', 'bekif', 'bekik', 'bekin', 'bekip', 'bekir', 'bekis', 'bekit',
    'bekob', 'bekod', 'bekof', 'bekok', 'bekon', 'bekop', 'bekor', 'bekos',
    'bekot', 'bekub', 'bekud', 'bekuf', 'bekuk', 'bekun', 'bekup', 'bekur',
    'bekus', 'bekut', 'belab', 'belad', 'belaf', 'belak', 'belan', 'belap',
    'belar', 'belas', 'belat', 'beleb', 'beled', 'belef', 'belek', 'belen',
    'belep', 'beler', 'beles', 'belet', 'belib', 'belid', 'belif', 'belik',
    ];
}
