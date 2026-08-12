import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  /// The dictionary ships gzip-compressed (assets/dict.sqlite.gz) to keep the
  /// repository under GitHub's 100 MB per-file limit. On first launch the
  /// bundle is decompressed into the app support directory.
  ///
  /// Bump this whenever the bundled schema/data changes (e.g. new columns),
  /// so installed apps re-extract the newer dictionary instead of reusing a
  /// stale local copy.
  static const _dictVersion = 4;
  static const _assetGzPath = 'assets/dict.sqlite.gz';
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dir = await getApplicationSupportDirectory();
    final target = p.join(dir.path, 'dict.sqlite');
    final versionFile = File(p.join(dir.path, 'dict.version'));

    if (_versionOutdated(versionFile)) {
      await _extractFromAssets(target);
      await versionFile.writeAsString('$_dictVersion', flush: true);
    }
    _db = await openDatabase(target, readOnly: true);
    return _db!;
  }

  static bool _versionOutdated(File versionFile) {
    if (!versionFile.existsSync()) return true;
    try {
      return versionFile.readAsStringSync().trim() != '$_dictVersion';
    } catch (_) {
      return true;
    }
  }

  static Future<void> _extractFromAssets(String target) async {
    final gz = await rootBundle.load(_assetGzPath);
    final compressed = gz.buffer.asUint8List(
      gz.offsetInBytes,
      gz.lengthInBytes,
    );
    final decompressed = gzip.decode(compressed);
    await File(target).writeAsBytes(decompressed, flush: true);
  }

  static Future<void> reset() async {
    await _db?.close();
    _db = null;
  }

  /// Closes the database, deletes the local copy and version marker so the
  /// bundled dictionary is re-extracted on the next [instance] access.
  static Future<void> rebuild() async {
    await _db?.close();
    _db = null;
    try {
      final dir = await getApplicationSupportDirectory();
      final target = File(p.join(dir.path, 'dict.sqlite'));
      final versionFile = File(p.join(dir.path, 'dict.version'));
      if (target.existsSync()) await target.delete();
      if (versionFile.existsSync()) await versionFile.delete();
    } catch (_) {}
  }
}
