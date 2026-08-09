import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:edge_tts/edge_tts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Accent { us, uk }

enum TtsMode {
  edge('Edge 神经网络'),
  local('本地离线 TTS'),
  youdao('有道词典'),
  baidu('百度翻译');

  const TtsMode(this.label);

  final String label;
}

class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _localTts = FlutterTts();
  Directory? _dir;
  TtsMode _mode = TtsMode.edge;
  bool _cacheEnabled = true;
  Future<void>? _modeReady;

  static const _modeKey = 'tts_mode';
  static const _cacheKey = 'tts_cache_enabled';
  static const _voiceUs = 'en-US-JennyMultilingualNeural';
  static const _voiceUk = 'en-GB-SoniaNeural';

  TtsMode get mode => _mode;
  bool get cacheEnabled => _cacheEnabled;

  /// Waits until the persisted mode is loaded from storage.
  Future<void> get ready => _modeReady ??= _initMode();

  Future<void> _initMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_modeKey);
    _mode = TtsMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => TtsMode.edge,
    );
    _cacheEnabled = prefs.getBool(_cacheKey) ?? true;
  }

  Future<void> setMode(TtsMode mode) async {
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  Future<void> setCacheEnabled(bool enabled) async {
    _cacheEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cacheKey, enabled);
  }

  /// Total size of the cached audio directory in bytes.
  Future<int> cacheSize() async {
    try {
      final dir = await _cache();
      var total = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearCache() async {
    try {
      final dir = await _cache();
      await for (final entity in dir.list()) {
        await entity.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<Directory> _cache() async {
    if (_dir == null) {
      final base = await getApplicationSupportDirectory();
      _dir = Directory(p.join(base.path, 'audio'));
      await _dir!.create(recursive: true);
    }
    return _dir!;
  }

  Future<void> speak(String text, {Accent accent = Accent.us}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final isCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(trimmed);
    switch (_mode) {
      case TtsMode.edge:
        await _speakEdge(trimmed, accent);
      case TtsMode.local:
        await _speakLocal(trimmed, accent);
      case TtsMode.youdao:
        if (isCjk) {
          await _speakLocal(trimmed, accent);
        } else {
          final ok = await _speakUrl(
            trimmed,
            accent,
            'https://dict.youdao.com/dictvoice?audio='
                '${Uri.encodeComponent(trimmed)}&type='
                '${accent == Accent.us ? 1 : 2}',
          );
          if (!ok) await _speakLocal(trimmed, accent);
        }
      case TtsMode.baidu:
        if (isCjk) {
          await _speakLocal(trimmed, accent);
        } else {
          final ok = await _speakUrl(
            trimmed,
            accent,
            'https://fanyi.baidu.com/gettts?lan='
                '${accent == Accent.us ? 'en' : 'uk'}&text='
                '${Uri.encodeComponent(trimmed)}&spd=3&source=dict',
          );
          if (!ok) await _speakLocal(trimmed, accent);
        }
    }
  }

  Future<void> _speakEdge(String text, Accent accent) async {
    try {
      if (_cacheEnabled) {
        final cache = await _cache();
        final key = 'edge_${accent.name}_${text.toLowerCase()}'
            .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '_');
        final file = File(p.join(cache.path, '$key.mp3'));

        if (!file.existsSync()) {
          final bytes = await Communicate(
            text: text,
            voice: accent == Accent.us ? _voiceUs : _voiceUk,
            rate: '-10%',
          ).toBytes();
          if (bytes.isEmpty) throw Exception('empty audio');
          await file.writeAsBytes(bytes, flush: true);
        }
        await _playFile(file);
      } else {
        final bytes = await Communicate(
          text: text,
          voice: accent == Accent.us ? _voiceUs : _voiceUk,
          rate: '-10%',
        ).toBytes();
        if (bytes.isEmpty) throw Exception('empty audio');
        await _player.stop();
        await _player.play(BytesSource(bytes));
      }
    } catch (_) {
      await _speakLocal(text, accent);
    }
  }

  Future<bool> _speakUrl(String text, Accent accent, String url) async {
    try {
      if (_cacheEnabled) {
        final cache = await _cache();
        final key = '${_mode.name}_${accent.name}_${text.toLowerCase()}'
            .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '_');
        final file = File(p.join(cache.path, '$key.mp3'));

        if (!file.existsSync()) {
          final resp = await http.get(Uri.parse(url)).timeout(
                const Duration(seconds: 8),
              );
          if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return false;
          await file.writeAsBytes(resp.bodyBytes, flush: true);
        }
        await _playFile(file);
      } else {
        await _player.stop();
        await _player.play(UrlSource(url));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _speakLocal(String text, Accent accent) async {
    try {
      await _localTts.stop();
      await _localTts.setLanguage(accent == Accent.us ? 'en-US' : 'en-GB');
      await _localTts.setSpeechRate(0.45);
      await _localTts.speak(text);
    } catch (_) {}
  }

  Future<void> _playFile(File file) async {
    await _player.stop();
    await _player.play(DeviceFileSource(file.path));
  }

  Future<void> stop() async {
    await _player.stop();
    await _localTts.stop();
  }
}
