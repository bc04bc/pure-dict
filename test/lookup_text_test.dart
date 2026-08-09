import 'package:flutter_test/flutter_test.dart';

import 'package:dict/core/text/lookup_text.dart';

void main() {
  group('extractLookupWord', () {
    test('plain latin word', () {
      expect(extractLookupWord('apple'), 'apple');
      expect(extractLookupWord('God'), 'God');
    });

    test('word with surrounding punctuation', () {
      expect(extractLookupWord('"hello"'), 'hello');
      expect(extractLookupWord("don't"), "don't");
      expect(extractLookupWord('word, '), 'word');
    });

    test('sentence picks first word', () {
      expect(extractLookupWord('The quick brown fox'), 'The');
      expect(extractLookupWord('Hello, world!'), 'Hello');
    });

    test('cjk input preferred', () {
      expect(extractLookupWord('苹果'), '苹果');
      expect(extractLookupWord('我喜欢苹果'), '我喜欢苹果'.substring(0, 4));
      expect(extractLookupWord('I love 苹果'), '苹果');
    });

    test('empty and unusable', () {
      expect(extractLookupWord(''), isNull);
      expect(extractLookupWord('   '), isNull);
      expect(extractLookupWord('123456'), isNull);
      expect(extractLookupWord('!!'), isNull);
    });
  });
}
