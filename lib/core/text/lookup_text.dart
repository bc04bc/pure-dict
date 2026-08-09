final _latinWord = RegExp(r"[a-zA-Z]+(?:['’-][a-zA-Z]+)*");
final _cjkRun = RegExp(r'[\u4e00-\u9fff]+');

/// Extracts the searchable query from raw selected text.
///
/// Prefers a CJK run (truncated to 4 chars so the bigram index can match),
/// otherwise the first Latin word. Returns null when nothing usable exists.
String? extractLookupWord(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final cjk = _cjkRun.firstMatch(text);
  if (cjk != null) {
    final word = cjk.group(0)!;
    return word.length > 4 ? word.substring(0, 4) : word;
  }

  final latin = _latinWord.firstMatch(text);
  return latin?.group(0);
}
