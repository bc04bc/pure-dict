class WordEntry {
  const WordEntry({
    required this.word,
    this.phonetic,
    this.definition,
    this.translation,
    this.pos,
    this.tag,
    this.bnc,
    this.frq,
    this.exchange,
    this.detail,
  });

  final String word;
  final String? phonetic;
  final String? definition;
  final String? translation;
  final String? pos;
  final String? tag;
  final int? bnc;
  final int? frq;
  final String? exchange;
  final String? detail;

  factory WordEntry.fromRow(Map<String, Object?> row) => WordEntry(
        word: row['word'] as String,
        phonetic: row['phonetic'] as String?,
        definition: row['definition'] as String?,
        translation: row['translation'] as String?,
        pos: row['pos'] as String?,
        tag: row['tag'] as String?,
        bnc: row['bnc'] as int?,
        frq: row['frq'] as int?,
        exchange: row['exchange'] as String?,
        detail: row['detail'] as String?,
      );
}
