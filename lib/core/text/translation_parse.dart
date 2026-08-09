/// Parses ECDICT `translation` text (newline-separated "pos. senses" lines)
/// into (partOfSpeech, text) pairs.
List<(String, String)> parseTranslation(String raw) {
  return raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) {
        final m = RegExp(r'^([a-z]{1,4}\.)\s*(.*)$').firstMatch(line);
        if (m != null) return (m.group(1)!, m.group(2)!.trim());
        final n = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(line);
        if (n != null) return (n.group(1)!, n.group(2)!.trim());
        return ('', line);
      })
      .toList();
}

/// Parses ECDICT `exchange` text ("d:abandoned/p:abandoned/...") into
/// (label, form) pairs with human-readable Chinese labels.
List<(String, String)> parseExchange(String raw) {
  const tags = {
    'p': '过去式',
    'd': '过去分词',
    'i': '现在分词',
    '3': '第三人称单数',
    'r': '比较级',
    't': '最高级',
    's': '复数',
    '0': '原型',
    '1': '原型变换',
  };
  return raw
      .split('/')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .map((part) {
        final m = RegExp(r'^([a-z0-9]):(.*)$').firstMatch(part);
        if (m != null) {
          return (tags[m.group(1)!] ?? m.group(1)!, m.group(2)!);
        }
        return ('', part);
      })
      .toList();
}
