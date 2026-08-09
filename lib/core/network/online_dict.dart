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
