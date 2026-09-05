import 'package:audioplayers/audioplayers.dart';
import 'package:dict/core/tts/tts_service.dart';
import 'package:dict/features/settings/settings_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const globalChannel = MethodChannel('xyz.luan/audioplayers.global');
    const playerChannel = MethodChannel('xyz.luan/audioplayers');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(globalChannel, (call) async => 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(playerChannel, (call) async => 1);
  });

  group('Audio Ducking Configuration & State', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to audio ducking enabled', () async {
      final tts = TtsService.instance;
      await tts.ready;
      expect(tts.audioDucking, isTrue);
    });

    test('can toggle audio ducking and persist preference', () async {
      final tts = TtsService.instance;
      await tts.setAudioDucking(false);
      expect(tts.audioDucking, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tts_audio_ducking'), isFalse);

      await tts.setAudioDucking(true);
      expect(tts.audioDucking, isTrue);
      expect(prefs.getBool('tts_audio_ducking'), isTrue);
    });

    test('audioDuckingProvider syncs with TtsService', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(audioDuckingProvider.notifier);
      await notifier.init();

      expect(container.read(audioDuckingProvider), isTrue);

      await notifier.set(false);
      expect(container.read(audioDuckingProvider), isFalse);
      expect(TtsService.instance.audioDucking, isFalse);

      await notifier.set(true);
      expect(container.read(audioDuckingProvider), isTrue);
      expect(TtsService.instance.audioDucking, isTrue);
    });

    test('AudioContextAndroid reflects gainTransientMayDuck when ducking enabled', () {
      final ctxWithDuck = AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: false,
        contentType: AndroidContentType.speech,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      );

      expect(ctxWithDuck.audioFocus, AndroidAudioFocus.gainTransientMayDuck);
      expect(ctxWithDuck.contentType, AndroidContentType.speech);
      expect(ctxWithDuck.usageType, AndroidUsageType.media);

      final ctxWithoutDuck = AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: false,
        contentType: AndroidContentType.speech,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gainTransient,
      );

      expect(ctxWithoutDuck.audioFocus, AndroidAudioFocus.gainTransient);
    });
  });
}
