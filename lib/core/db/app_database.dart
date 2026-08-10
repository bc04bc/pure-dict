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
  static const _assetGzPath = 'assets/dict.sqlite.gz';
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dir = await getApplicationSupportDirectory();
    final target = p.join(dir.path, 'dict.sqlite');

    if (!File(target).existsSync()) {
      final gz = await rootBundle.load(_assetGzPath);
      final compressed = gz.buffer.asUint8List(
        gz.offsetInBytes,
        gz.lengthInBytes,
      );
      final decompressed = gzip.decode(compressed);
      await File(target).writeAsBytes(decompressed, flush: true);
    }
    _db = await openDatabase(target, readOnly: true);
    return _db!;
  }

  static Future<void> reset() async {
    await _db?.close();
    _db = null;
  }
}
