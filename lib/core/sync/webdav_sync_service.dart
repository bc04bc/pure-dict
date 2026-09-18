import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/user_database.dart';
import '../models/study_entry.dart';

final webDavSyncServiceProvider =
    FutureProvider<WebDavSyncService>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return WebDavSyncService(prefs);
});

class SyncResult {
  const SyncResult({
    required this.success,
    required this.message,
    this.uploadedCount = 0,
    this.downloadedCount = 0,
  });

  final bool success;
  final String message;
  final int uploadedCount;
  final int downloadedCount;
}

class WebDavConfig {
  const WebDavConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.autoSyncOnLaunch = false,
    this.lastSyncTime = 0,
  });

  final String serverUrl;
  final String username;
  final String password;
  final bool autoSyncOnLaunch;
  final int lastSyncTime;

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.trim().isNotEmpty;
}

class WebDavSyncService {
  WebDavSyncService(this._prefs);

  final SharedPreferences _prefs;

  static const _serverUrlKey = 'webdav_server_url';
  static const _usernameKey = 'webdav_username';
  static const _passwordKey = 'webdav_password';
  static const _autoSyncKey = 'webdav_auto_sync';
  static const _lastSyncKey = 'webdav_last_sync_timestamp';

  static const _remoteSyncFilename = 'user_sync.json';

  static String normalizeUrl(String rawUrl) {
    var url = rawUrl.trim();
    if (url.isEmpty) return url;
    if (!url.endsWith('/')) {
      url = '$url/';
    }
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final isJianguo = uri.host.toLowerCase().contains('jianguoyun.com');
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      // If user inputs Jianguoyun root /dav/ or /dav, automatically target /dav/PureDict/
      if (isJianguo &&
          (segments.isEmpty || (segments.length == 1 && segments.first == 'dav'))) {
        return '${url}PureDict/';
      }
    }
    return url;
  }

  WebDavConfig getConfig() {
    final rawUrl = _prefs.getString(_serverUrlKey) ?? '';
    return WebDavConfig(
      serverUrl: normalizeUrl(rawUrl),
      username: _prefs.getString(_usernameKey) ?? '',
      password: _prefs.getString(_passwordKey) ?? '',
      autoSyncOnLaunch: _prefs.getBool(_autoSyncKey) ?? false,
      lastSyncTime: _prefs.getInt(_lastSyncKey) ?? 0,
    );
  }

  Future<void> saveConfig({
    required String serverUrl,
    required String username,
    required String password,
    bool? autoSyncOnLaunch,
  }) async {
    final url = normalizeUrl(serverUrl);
    await _prefs.setString(_serverUrlKey, url);
    await _prefs.setString(_usernameKey, username.trim());
    await _prefs.setString(_passwordKey, password.trim());
    if (autoSyncOnLaunch != null) {
      await _prefs.setBool(_autoSyncKey, autoSyncOnLaunch);
    }
  }

  static Uri safeParseUri(String url) {
    final trimmed = url.trim();
    try {
      final parsed = Uri.parse(trimmed);
      if (parsed.path.runes.any((r) => r > 127)) {
        return Uri.parse(Uri.encodeFull(trimmed));
      }
      return parsed;
    } catch (_) {
      return Uri.parse(Uri.encodeFull(trimmed));
    }
  }

  Map<String, String> _headers(String username, String password) {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    return {
      'Authorization': 'Basic $credentials',
      'User-Agent': 'PureDict/1.1.0 (Android)',
    };
  }

  /// Tests WebDAV connection via PROPFIND request.
  Future<SyncResult> testConnection([http.Client? client]) async {
    final config = getConfig();
    if (!config.isConfigured) {
      return const SyncResult(
        success: false,
        message: '请先填写完整的 WebDAV 服务器地址、用户名和密码',
      );
    }

    final httpClient = client ?? http.Client();
    try {
      final uri = safeParseUri(config.serverUrl);
      final isJianguo = uri.host.toLowerCase().contains('jianguoyun.com');
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

      if (isJianguo &&
          (segments.isEmpty || (segments.length == 1 && segments.first == 'dav'))) {
        return const SyncResult(
          success: false,
          message: '坚果云限制：不可直接使用 /dav/ 根目录。请在地址后加上具体的同步文件夹名称，例如：\nhttps://dav.jianguoyun.com/dav/我的坚果云/\n（或在坚果云新建文件夹 PureDict 后填写）',
        );
      }

      final req = http.Request('PROPFIND', uri)
        ..headers.addAll(_headers(config.username, config.password))
        ..headers['Depth'] = '0';

      final streamedResponse =
          await httpClient.send(req).timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300 ||
          response.statusCode == 207) {
        return const SyncResult(success: true, message: '连接成功');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return SyncResult(
          success: false,
          message: '认证失败 (${response.statusCode})，请检查用户名或应用密码',
        );
      } else if (response.statusCode == 404) {
        // Try creating remote directory if missing
        final mkcolReq = http.Request('MKCOL', uri)
          ..headers.addAll(_headers(config.username, config.password));
        final mkcolStreamed =
            await httpClient.send(mkcolReq).timeout(const Duration(seconds: 8));
        if (mkcolStreamed.statusCode == 201 ||
            mkcolStreamed.statusCode == 405) {
          return const SyncResult(
            success: true,
            message: '连接成功（已自动创建远端目录）',
          );
        }
        final hint = isJianguo
            ? '坚果云提示：无法自动创建 PureDict 文件夹 (${mkcolStreamed.statusCode})，请在坚果云网页端新建“PureDict”文件夹后再试'
            : '远端目录不存在 (${response.statusCode})';
        return SyncResult(
          success: false,
          message: hint,
        );
      } else {
        return SyncResult(
          success: false,
          message: '服务器返回错误码: ${response.statusCode}',
        );
      }
    } catch (e) {
      return SyncResult(success: false, message: '连接超时或网络异常: $e');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Performs two-way incremental sync using Last-Write-Wins and tombstones.
  Future<SyncResult> sync({
    Database? customDb,
    http.Client? customClient,
  }) async {
    final config = getConfig();
    if (!config.isConfigured) {
      return const SyncResult(
        success: false,
        message: 'WebDAV 尚未配置，无法同步',
      );
    }

    final db = customDb ?? await UserDatabase.instance;
    final client = customClient ?? http.Client();

    try {
      final baseUrl = config.serverUrl;
      final baseUri = safeParseUri(baseUrl);
      final isJianguo = baseUri.host.toLowerCase().contains('jianguoyun.com');

      final fileUri = safeParseUri('$baseUrl$_remoteSyncFilename');
      final headers = _headers(config.username, config.password);

      // Proactively ensure remote directory (e.g. PureDict) exists via MKCOL
      try {
        final mkcolReq = http.Request('MKCOL', baseUri)
          ..headers.addAll(headers);
        await client.send(mkcolReq).timeout(const Duration(seconds: 8));
      } catch (_) {}

      // 1. Fetch remote sync file (if exists)
      List<UserWordEntry> remoteEntries = [];
      final getResp = await client
          .get(fileUri, headers: headers)
          .timeout(const Duration(seconds: 12));

      if (getResp.statusCode == 200 && getResp.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(getResp.body) as Map<String, dynamic>;
          final wordsJson = decoded['words'] as List<dynamic>? ?? [];
          remoteEntries = wordsJson
              .map((w) => UserWordEntry.fromRow(w as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }

      // 2. Load all local records (including active and tombstones)
      final localRows = await db.query('user_words');
      final localMap = {
        for (final row in localRows)
          (row['word'] as String).toLowerCase(): UserWordEntry.fromRow(row)
      };

      final remoteMap = {
        for (final entry in remoteEntries) entry.word.toLowerCase(): entry
      };

      final allKeys = {...localMap.keys, ...remoteMap.keys};
      final mergedEntries = <UserWordEntry>[];
      int downloaded = 0;
      int uploaded = 0;

      final now = DateTime.now().millisecondsSinceEpoch;
      // 30 days tombstone retention
      final tombstoneCutoff = now - 30 * 24 * 3600 * 1000;

      for (final key in allKeys) {
        final local = localMap[key];
        final remote = remoteMap[key];

        if (local == null && remote != null) {
          // Remote new entity -> apply locally
          if (!remote.isDeleted ||
              remote.updatedAt.millisecondsSinceEpoch > tombstoneCutoff) {
            mergedEntries.add(remote);
            downloaded++;
          }
        } else if (local != null && remote == null) {
          // Local new entity -> will upload
          mergedEntries.add(local);
          uploaded++;
        } else if (local != null && remote != null) {
          // Both present: merge frequency + LWW state
          final fusedQueryCount =
              math.max(local.queryCount, remote.queryCount);
          final fusedLastQueriedAt = local.lastQueriedAt
                  .isAfter(remote.lastQueriedAt)
              ? local.lastQueriedAt
              : remote.lastQueriedAt;

          final UserWordEntry winner;
          if (remote.updatedAt.isAfter(local.updatedAt)) {
            winner = remote.copyWith(
              queryCount: fusedQueryCount,
              lastQueriedAt: fusedLastQueriedAt,
            );
            downloaded++;
          } else {
            winner = local.copyWith(
              queryCount: fusedQueryCount,
              lastQueriedAt: fusedLastQueriedAt,
            );
            uploaded++;
          }

          if (!winner.isDeleted ||
              winner.updatedAt.millisecondsSinceEpoch > tombstoneCutoff) {
            mergedEntries.add(winner);
          }
        }
      }

      // 3. Save merged records to local database
      final batch = db.batch();
      for (final item in mergedEntries) {
        batch.insert(
          'user_words',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);

      // 4. Upload unified dataset back to remote WebDAV
      final payload = jsonEncode({
        'version': 1,
        'synced_at': now,
        'client': 'PureDict v1.1.0',
        'words': mergedEntries.map((e) => e.toMap()).toList(),
      });

      var putResp = await client
          .put(
            fileUri,
            headers: {
              ...headers,
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: utf8.encode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (putResp.statusCode == 404) {
        // Parent folder might not exist yet, attempt MKCOL
        try {
          final mkcolReq = http.Request('MKCOL', baseUri)
            ..headers.addAll(headers);
          final mkcolStreamed =
              await client.send(mkcolReq).timeout(const Duration(seconds: 8));
          if (mkcolStreamed.statusCode == 201 ||
              mkcolStreamed.statusCode == 405) {
            putResp = await client
                .put(
                  fileUri,
                  headers: {
                    ...headers,
                    'Content-Type': 'application/json; charset=utf-8',
                  },
                  body: utf8.encode(payload),
                )
                .timeout(const Duration(seconds: 15));
          }
        } catch (_) {}
      }

      if (putResp.statusCode >= 200 && putResp.statusCode < 300) {
        await _prefs.setInt(_lastSyncKey, now);
        return SyncResult(
          success: true,
          message: '同步完成',
          uploadedCount: uploaded,
          downloadedCount: downloaded,
        );
      } else {
        String detailHint = '';
        if (putResp.statusCode == 404) {
          detailHint = isJianguo
              ? '（坚果云提示：无法自动创建“PureDict”目录，请在坚果云网页端/App中新建“PureDict”文件夹后重试）'
              : '（请检查服务器上该路径的父文件夹是否存在）';
        }
        return SyncResult(
          success: false,
          message: '远端数据写入失败 (${putResp.statusCode})$detailHint',
        );
      }
    } catch (e) {
      return SyncResult(success: false, message: '同步发生异常: $e');
    } finally {
      if (customClient == null) client.close();
    }
  }

  /// Exports all user data as a standalone JSON string for offline cold backup.
  Future<String> exportBackupJson([Database? customDb]) async {
    final db = customDb ?? await UserDatabase.instance;
    final wordRows = await db.query('user_words');
    final historyRows = await db.query(
      'search_history',
      orderBy: 'queried_at DESC',
      limit: 200,
    );

    final data = {
      'app': 'PureDict',
      'version': '1.1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'words': wordRows,
      'history': historyRows,
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Restores user data from a JSON string using merge logic.
  Future<int> restoreBackupJson(String jsonStr, [Database? customDb]) async {
    final db = customDb ?? await UserDatabase.instance;
    final Map<String, dynamic> data = jsonDecode(jsonStr);
    final wordList = data['words'] as List<dynamic>? ?? [];

    final batch = db.batch();
    var restored = 0;
    for (final item in wordList) {
      if (item is Map<String, dynamic>) {
        final entry = UserWordEntry.fromRow(item);
        batch.insert(
          'user_words',
          entry.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        restored++;
      }
    }
    await batch.commit(noResult: true);
    return restored;
  }
}
