import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dict/app/app.dart';
import 'package:dict/core/db/user_data.dart';
import 'package:dict/core/models/word_entry.dart';
import 'package:dict/features/home/home_page.dart';

void main() {
  testWidgets('App renders and navigates', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wordOfDayProvider.overrideWith((ref) async => const WordEntry(
                word: 'apple',
                phonetic: "ˈæpl",
                translation: 'n. 苹果',
              )),
          historyProvider.overrideWith((ref) async => const ['hello']),
        ],
        child: const DictApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('词典'), findsOneWidget);
    expect(find.text('背单词'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('今日一词'), findsOneWidget);
  });
}
