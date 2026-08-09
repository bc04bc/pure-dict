import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static const _assetPath = 'assets/dict.sqlite';
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dir = await getApplicationSupportDirectory();
    final target = p.join(dir.path, 'dict.sqlite');

    if (!File(target).existsSync()) {
      final data = await rootBundle.load(_assetPath);
      await File(target).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    _db = await openDatabase(target, readOnly: true);
    return _db!;
  }

  static Future<void> reset() async {
    await _db?.close();
    _db = null;
  }
}
