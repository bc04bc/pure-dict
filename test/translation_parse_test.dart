import 'package:flutter_test/flutter_test.dart';

import 'package:dict/core/text/translation_parse.dart';

void main() {
  group('parseTranslation', () {
    test('real newlines', () {
      final items = parseTranslation(
        'n. 男人, 人类, 人\nvt. 为...配备人手\n[计] 城域网',
      );
      expect(items, hasLength(3));
      expect(items[0].$1, 'n.');
      expect(items[0].$2, '男人, 人类, 人');
      expect(items[1].$1, 'vt.');
      expect(items[2].$1, '[计]');
    });

    test('literal backslash-n from ECDICT csv', () {
      final items = parseTranslation(
        r'n. 男人, 人类, 人\nvt. 为...配备人手, 操纵, 使振奋\n[计] 城域网, 手册',
      );
      expect(items, hasLength(3));
      expect(items[0].$1, 'n.');
      expect(items[0].$2, '男人, 人类, 人');
      expect(items[1].$1, 'vt.');
      expect(items[1].$2, '为...配备人手, 操纵, 使振奋');
      expect(items[2].$1, '[计]');
      expect(items[2].$2, '城域网, 手册');
    });

    test('mixed newline kinds', () {
      final items = parseTranslation(r'n. 苹果\nv. 种植\n[网络] 苹果');
      expect(items.map((e) => e.$1).toList(), ['n.', 'v.', '[网络]']);
    });
  });

  group('parseExchange', () {
    test('forms', () {
      final items = parseExchange('d:abandoned/p:abandoned/i:abandoning');
      expect(items, hasLength(3));
      expect(items[0].$1, '过去分词');
      expect(items[0].$2, 'abandoned');
    });
  });
}
