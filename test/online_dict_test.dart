import 'package:flutter_test/flutter_test.dart';

import 'package:dict/core/network/online_dict.dart';

void main() {
  group('parseYoudaoZh', () {
    test('parses ec section with phonetics', () {
      const body = '''
      {
        "ec": {
          "word": [{
            "ukphone": "ˈænɪmeɪ",
            "usphone": "ˈænəmeɪ",
            "trs": [
              {"tr": [{"l": {"i": ["n. 日本动画片（常以科幻为主题）；芳香树脂"]}}]}
            ]
          }]
        }
      }''';
      final result = parseYoudaoZh(body);
      expect(result, isNotNull);
      expect(result!.phonetics, {'uk': 'ˈænɪmeɪ', 'us': 'ˈænəmeɪ'});
      expect(result.senses, hasLength(1));
      expect(result.senses.first.pos, 'n.');
      expect(result.senses.first.definitions, [
        '日本动画片（常以科幻为主题）',
        '芳香树脂',
      ]);
    });

    test('splits multiple senses and keeps multiple pos groups', () {
      const body = '''
      {
        "ec": {
          "word": [{
            "trs": [
              {"tr": [{"l": {"i": ["n. 盒子, 箱", "vt. 装箱"]}}]},
              {"tr": [{"l": {"i": ["adj. 盒装的"]}}]}
            ]
          }]
        }
      }''';
      final result = parseYoudaoZh(body)!;
      expect(result.senses, hasLength(3));
      expect(result.senses[0].pos, 'n.');
      expect(result.senses[0].definitions, ['盒子, 箱']);
      expect(result.senses[1].pos, 'vt.');
      expect(result.senses[1].definitions, ['装箱']);
      expect(result.senses[2].pos, 'adj.');
      expect(result.senses[2].definitions, ['盒装的']);
    });

    test('strips html tags and dedupes senses', () {
      const body = '''
      {
        "ec": {
          "word": [{
            "trs": [
              {"tr": [{"l": {"i": ["n. <b>动漫</b>作品"]}}]},
              {"tr": [{"l": {"i": ["n. 动漫作品"]}}]}
            ]
          }]
        }
      }''';
      final result = parseYoudaoZh(body)!;
      expect(result.senses.first.definitions, ['动漫作品']);
      expect(result.senses.first.definitions, hasLength(1));
    });

    test('falls back to simple section when ec is missing', () {
      const body = '''
      {
        "simple": {
          "word": [{
            "trs": [
              {"tr": [{"l": {"i": ["n. 表情符号，绘文字"]}}]}
            ]
          }]
        }
      }''';
      final result = parseYoudaoZh(body);
      expect(result, isNotNull);
      expect(result!.phonetics, isEmpty);
      expect(result.senses.first.definitions, ['表情符号，绘文字']);
    });

    test('returns null for invalid json', () {
      expect(parseYoudaoZh('not json'), isNull);
    });

    test('returns null when no senses found', () {
      expect(parseYoudaoZh('{"web_trans": {}}'), isNull);
    });
  });
}
