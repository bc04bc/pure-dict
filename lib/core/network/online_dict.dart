import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class OnlineSense {
  const OnlineSense({required this.pos, required this.definitions});

  final String pos;
  final List<String> definitions;
}

class OnlineExamples {
  const OnlineExamples({required this.senses, required this.examples});

  final List<OnlineSense> senses;
  final List<String> examples;
}

final onlineLookupProvider = FutureProvider.family<OnlineExamples?, String>(
  (ref, word) async {
    try {
      final resp = await http
          .get(Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as List<dynamic>;
      final senses = <OnlineSense>[];
      final examples = <String>[];

      for (final entry in data) {
        final meanings = entry['meanings'] as List<dynamic>? ?? const [];
        for (final meaning in meanings) {
          final pos = meaning['partOfSpeech'] as String? ?? '';
          final defs = <String>[];
          for (final def in meaning['definitions'] as List<dynamic>? ?? const []) {
            final d = def as Map<String, dynamic>;
            final text = d['definition'] as String? ?? '';
            if (text.isNotEmpty) defs.add(text);
            final example = d['example'] as String?;
            if (example != null && example.isNotEmpty) examples.add(example);
          }
          if (defs.isNotEmpty) senses.add(OnlineSense(pos: pos, definitions: defs));
        }
      }
      if (senses.isEmpty && examples.isEmpty) return null;
      return OnlineExamples(senses: senses, examples: examples);
    } catch (_) {
      return null;
    }
  },
);

/// Chinese senses fetched from Youdao's public dict endpoint.
class OnlineZhResult {
  const OnlineZhResult({this.phonetics = const {}, this.senses = const []});

  /// Phonetics keyed by accent: 'uk' / 'us'.
  final Map<String, String> phonetics;
  final List<OnlineSense> senses;
}

final onlineZhLookupProvider = FutureProvider.family<OnlineZhResult?, String>(
  (ref, word) async {
    try {
      final resp = await http
          .get(Uri.parse('https://dict.youdao.com/jsonapi?q=$word'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      return parseYoudaoZh(resp.body);
    } catch (_) {
      return null;
    }
  },
);

/// Parses the Youdao `jsonapi` response into Chinese senses.
///
/// Uses the `ec` (英汉) section for phonetics and POS-tagged senses, falling
/// back to the `simple` section when `ec` is absent. Returns null when no
/// usable sense is found.
OnlineZhResult? parseYoudaoZh(String body) {
  final Map<String, dynamic> data;
  try {
    data = jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }

  final phonetics = <String, String>{};
  var senses = <OnlineSense>[];

  final ec = data['ec'];
  if (ec is Map<String, dynamic>) {
    final wordList = ec['word'];
    if (wordList is List && wordList.isNotEmpty && wordList[0] is Map) {
      final word = wordList[0] as Map<String, dynamic>;
      final uk = word['ukphone'] as String?;
      final us = word['usphone'] as String?;
      if (uk != null && uk.isNotEmpty) phonetics['uk'] = uk;
      if (us != null && us.isNotEmpty) phonetics['us'] = us;
      senses = _parseYoudaoTrs(word['trs']);
    }
  }

  if (senses.isEmpty) {
    final simple = data['simple'];
    if (simple is Map<String, dynamic>) {
      final wordList = simple['word'];
      if (wordList is List && wordList.isNotEmpty && wordList[0] is Map) {
        final word = wordList[0] as Map<String, dynamic>;
        senses = _parseYoudaoTrs(word['trs']);
      }
    }
  }

  if (senses.isEmpty) return null;
  return OnlineZhResult(phonetics: phonetics, senses: senses);
}

List<OnlineSense> _parseYoudaoTrs(Object? trsRaw) {
  final groups = <String, List<String>>{};
  final seen = <String>{};
  final trs = trsRaw is List ? trsRaw : const <dynamic>[];
  final posRe = RegExp(r'^([a-z]{1,8}\.)\s*(.*)$');

  for (final trItem in trs) {
    if (trItem is! Map<String, dynamic>) continue;
    final tr = trItem['tr'];
    if (tr is! List) continue;
    for (final t in tr) {
      if (t is! Map<String, dynamic>) continue;
      final l = t['l'];
      if (l is! Map<String, dynamic>) continue;
      final items = l['i'];
      if (items is! List) continue;
      for (final raw in items) {
        if (raw is! String) continue;
        final text = raw
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll('\n', '')
            .trim();
        if (text.isEmpty || seen.contains(text)) continue;
        seen.add(text);

        final m = posRe.firstMatch(text);
        final pos = m != null ? m.group(1)! : '';
        final rest = m != null ? m.group(2)!.trim() : text;
        for (final part in rest.split('；')) {
          final sense = part.trim();
          if (sense.isEmpty) continue;
          groups.putIfAbsent(pos, () => []).add(sense);
        }
      }
    }
  }

  return [
    for (final entry in groups.entries)
      OnlineSense(pos: entry.key, definitions: entry.value),
  ];
}
