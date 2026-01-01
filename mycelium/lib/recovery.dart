import 'dart:typed_data';

import 'package:cleona/core/crypto/seed_phrase.dart';
import 'package:mycelium/envelope.dart';

/// The word sequence — the only thing a human has to write down.
///
/// It is the root key in readable form. Every identity of this person
/// arises from it, and deterministically: the same words
/// always yield the same keys.
///
/// **Without it a lost device is a lost identity.** There
/// is nobody who could reset it — no server, no
/// recovery mail, no hotline. That is the price for there
/// also being nobody who could take over the identity.
///
/// **It NEVER goes over the network.** No message, no packet, no
/// backup carries it. It stands on paper or nowhere.
class WordSequence {
  final List<String> words;

  const WordSequence._(this.words);

  /// How many words a word sequence has.
  static const int countWords = 24;

  /// Rolls a new word sequence.
  static WordSequence fresh() => WordSequence._(SeedPhrase.generate());

  /// Reads an entered word sequence. Throws if it is not correct —
  /// the checksum in the sequence itself catches typos before
  /// anything is derived.
  static WordSequence read(List<String> input) {
    final cleaned = [
      for (final w in input)
        if (w.trim().isNotEmpty) w.trim().toLowerCase()
    ];
    if (cleaned.length != countWords) {
      throw RecoveryError(
          'The word sequence has $countWords words, entered were '
          '${cleaned.length}');
    }
    if (!SeedPhrase.isValid(cleaned)) {
      throw RecoveryError(
          'The word sequence does not match — mistyped or swapped');
    }
    return WordSequence._(cleaned);
  }

  /// From text as someone types or pastes it.
  static WordSequence outText(String text) =>
      read(text.split(RegExp(r'[\s,]+')));

  /// The root key. Everything else arises from it.
  Uint8List get rootKey =>
      SeedPhrase.entropyToSeed(SeedPhrase.wordsToEntropy(words));

  /// The identity number [index] of this word sequence.
  ///
  /// Index 0 is the first. Further identities cannot be linked
  /// to it: between them stands only a derivation that nobody
  /// can compute backwards.
  PostBox postBox(int index) =>
      PostBox.outRoot(rootKey, index);

  /// The first [howMany] identities — what is restored after a
  /// device loss.
  ///
  /// How many there were the word sequence does NOT know: any number can be
  /// derived from it. The caller must know it or ask.
  List<PostBox> postBoxes(int howMany) =>
      [for (var i = 0; i < howMany; i++) postBox(i)];

  /// For the display when writing down: numbered, four per line.
  String toRecord() {
    final z = <String>[];
    for (var i = 0; i < words.length; i += 4) {
      z.add([
        for (var j = i; j < i + 4 && j < words.length; j++)
          '${(j + 1).toString().padLeft(2)}. ${words[j]}'
      ].join('   '));
    }
    return z.join('\n');
  }

  @override
  String toString() => words.join(' ');
}

class RecoveryError implements Exception {
  final String reason;
  RecoveryError(this.reason);
  @override
  String toString() => 'WiederherstellungFehler: $reason';
}
