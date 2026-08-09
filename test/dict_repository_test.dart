import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dict/core/db/dict_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final dbFactory = databaseFactoryFfi;
  final dbPath =
      p.join(Directory.current.path, 'assets', 'dict.sqlite');

  group('DictRepository (offline dict asset)', () {
    late Database db;
    late DictRepository repo;

    setUpAll(() async {
      db = await dbFactory.openDatabase(dbPath,
          options: OpenDatabaseOptions(readOnly: true));
      repo = DictRepository(db);
    });

    tearDownAll(() => db.close());

    test('exact lookup', () async {
      final w = await repo.lookup('hello');
      expect(w, isNotNull);
      expect(w!.word, 'hello');
      expect(w.translation, contains('喂'));
      expect(w.phonetic, isNotEmpty);
    });

    test('exact lookup miss', () async {
      expect(await repo.lookup('zzzznotaword'), isNull);
    });

    test('case-insensitive fallback', () async {
      final w = await repo.lookup('god');
      expect(w, isNotNull);
      expect(w!.word, 'God');
      expect(await repo.lookup('HELLO'), isNotNull);
    });

    test('english prefix suggestions', () async {
      final s = await repo.suggestions('wor');
      expect(s, isNotEmpty);
      expect(s.first.word.startsWith('wor'), isTrue);
      final words = s.map((e) => e.word).toList();
      expect(words, isNot(contains('wor')));
      expect(words, contains('word'));
    });

    test('chinese suggestions', () async {
      final s = await repo.suggestions('苹果');
      expect(s, isNotEmpty);
    });

    test('empty suggestions', () async {
      expect(await repo.suggestions(''), isEmpty);
    });
  });
}
