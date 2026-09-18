import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dict/core/sync/webdav_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final dbFactory = databaseFactoryFfi;

  group('WebDavSyncService & Incremental Sync', () {
    late Database db;
    late SharedPreferences prefs;

    setUp(() async {
      db = await dbFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS user_words (
                word TEXT PRIMARY KEY,
                in_study INTEGER NOT NULL DEFAULT 1,
                query_count INTEGER NOT NULL DEFAULT 1,
                last_queried_at INTEGER NOT NULL,
                srs_stage INTEGER NOT NULL DEFAULT 0,
                next_review_at INTEGER,
                interval_days REAL NOT NULL DEFAULT 0,
                ease_factor REAL NOT NULL DEFAULT 2.5,
                lapse_count INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                is_deleted INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS search_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word TEXT NOT NULL,
                queried_at INTEGER NOT NULL
              )
            ''');
          },
        ),
      );

      SharedPreferences.setMockInitialValues({
        'webdav_server_url': 'https://example.com/dav/PureDict/',
        'webdav_username': 'test_user',
        'webdav_password': 'secret_password',
      });
      prefs = await SharedPreferences.getInstance();
    });

    tearDown(() async {
      await db.close();
    });

    test('performs two-way LWW merge and frequency fusion', () async {
      final now = DateTime(2026, 9, 18, 12, 0);

      // 1. Prepare local dataset: 'alpha' (local only), 'gamma' (local query_count 3, older srs)
      await db.insert('user_words', {
        'word': 'alpha',
        'in_study': 1,
        'query_count': 2,
        'last_queried_at': now.millisecondsSinceEpoch,
        'srs_stage': 1,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'is_deleted': 0,
      });

      await db.insert('user_words', {
        'word': 'gamma',
        'in_study': 1,
        'query_count': 3,
        'last_queried_at': now.millisecondsSinceEpoch,
        'srs_stage': 1,
        'created_at': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        'updated_at': now.subtract(const Duration(hours: 5)).millisecondsSinceEpoch,
        'is_deleted': 0,
      });

      // 2. Prepare remote payload: 'beta' (remote only), 'gamma' (query_count 6, newer srs stage 3)
      final remoteJson = jsonEncode({
        'version': 1,
        'words': [
          {
            'word': 'beta',
            'in_study': 1,
            'query_count': 1,
            'last_queried_at': now.millisecondsSinceEpoch,
            'srs_stage': 2,
            'created_at': now.millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
            'is_deleted': 0,
          },
          {
            'word': 'gamma',
            'in_study': 1,
            'query_count': 6,
            'last_queried_at': now.millisecondsSinceEpoch,
            'srs_stage': 3,
            'created_at': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
            'updated_at': now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch, // newer!
            'is_deleted': 0,
          }
        ]
      });

      String? uploadedBody;
      final mockClient = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('user_sync.json')) {
          return http.Response(remoteJson, 200);
        }
        if (request.method == 'PUT' &&
            request.url.path.endsWith('user_sync.json')) {
          uploadedBody = request.body;
          return http.Response('', 200);
        }
        return http.Response('Not Found', 404);
      });

      final syncService = WebDavSyncService(prefs);
      final result = await syncService.sync(
        customDb: db,
        customClient: mockClient,
      );

      expect(result.success, isTrue);

      // Verify local database state after merge
      final rows = await db.query('user_words', orderBy: 'word ASC');
      expect(rows.length, 3);

      final gammaRow = rows.firstWhere((r) => r['word'] == 'gamma');
      expect(gammaRow['query_count'], 6); // Max frequency fused
      expect(gammaRow['srs_stage'], 3); // Remote won LWW

      // Verify uploaded body contains all 3 words
      expect(uploadedBody, isNotNull);
      final uploadedJson = jsonDecode(uploadedBody!) as Map<String, dynamic>;
      final uploadedWords = uploadedJson['words'] as List<dynamic>;
      expect(uploadedWords.length, 3);
    });

    test('cold backup exports and restores valid JSON', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('user_words', {
        'word': 'zenith',
        'in_study': 1,
        'query_count': 4,
        'last_queried_at': now,
        'srs_stage': 2,
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      });

      final syncService = WebDavSyncService(prefs);
      final jsonStr = await syncService.exportBackupJson(db);

      expect(jsonStr, contains('zenith'));
      expect(jsonStr, contains('PureDict'));

      // Clear table
      await db.delete('user_words');
      expect(await db.query('user_words'), isEmpty);

      // Restore
      final count = await syncService.restoreBackupJson(jsonStr, db);
      expect(count, 1);

      final rows = await db.query('user_words');
      expect(rows.length, 1);
      expect(rows.first['word'], 'zenith');
    });

    test('safeParseUri encodes non-ASCII characters in URI path', () {
      final uri = WebDavSyncService.safeParseUri(
          'https://dav.jianguoyun.com/dav/我的坚果云/user_sync.json');
      expect(uri.path, contains('%E6%88%91%E7%9A%84%E5%9D%9A%E6%9E%9C%E4%BA%91'));
    });

    test('normalizeUrl automatically appends PureDict/ for Jianguoyun root', () {
      expect(
        WebDavSyncService.normalizeUrl('https://dav.jianguoyun.com/dav/'),
        'https://dav.jianguoyun.com/dav/PureDict/',
      );
      expect(
        WebDavSyncService.normalizeUrl('https://dav.jianguoyun.com/dav'),
        'https://dav.jianguoyun.com/dav/PureDict/',
      );
      expect(
        WebDavSyncService.normalizeUrl(
            'https://dav.jianguoyun.com/dav/MyFolder/'),
        'https://dav.jianguoyun.com/dav/MyFolder/',
      );
    });

    test('automatically creates PureDict folder on Jianguoyun via MKCOL when missing',
        () async {
      await prefs.setString(
          'webdav_server_url', 'https://dav.jianguoyun.com/dav/');
      final syncService = WebDavSyncService(prefs);

      expect(syncService.getConfig().serverUrl,
          'https://dav.jianguoyun.com/dav/PureDict/');

      var mkcolCalled = false;
      final client = MockClient((req) async {
        if (req.method == 'PROPFIND') {
          return http.Response('Not Found', 404);
        }
        if (req.method == 'MKCOL') {
          mkcolCalled = true;
          return http.Response('Created', 201);
        }
        return http.Response('OK', 200);
      });

      final testResult = await syncService.testConnection(client);
      expect(mkcolCalled, isTrue);
      expect(testResult.success, isTrue);
      expect(testResult.message, contains('已自动创建'));
    });
  });
}
