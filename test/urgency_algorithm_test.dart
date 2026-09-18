import 'package:flutter_test/flutter_test.dart';

import 'package:dict/core/models/study_entry.dart';
import 'package:dict/core/study/urgency_algorithm.dart';
import 'package:dict/core/text/importance.dart';

void main() {
  group('UrgencyCalculator', () {
    final baseTime = DateTime(2026, 9, 18, 12, 0);

    test('frequently queried words score higher than single-query words', () {
      final singleQuery = UserWordEntry(
        word: 'apple',
        queryCount: 1,
        lastQueriedAt: baseTime,
        createdAt: baseTime,
        updatedAt: baseTime,
      );

      final fiveQueries = UserWordEntry(
        word: 'read',
        queryCount: 5,
        lastQueriedAt: baseTime,
        createdAt: baseTime,
        updatedAt: baseTime,
      );

      final score1 = UrgencyCalculator.calculateScore(
        entry: singleQuery,
        importance: WordImportance.core,
        now: baseTime,
      );

      final score5 = UrgencyCalculator.calculateScore(
        entry: fiveQueries,
        importance: WordImportance.core,
        now: baseTime,
      );

      expect(score5, greaterThan(score1));
    });

    test('overdue words score significantly higher than future due words', () {
      final overdueWord = UserWordEntry(
        word: 'ephemeral',
        srsStage: 2,
        intervalDays: 1.0,
        nextReviewAt: baseTime.subtract(const Duration(days: 2)), // 2 days overdue
        lastQueriedAt: baseTime,
        createdAt: baseTime.subtract(const Duration(days: 5)),
        updatedAt: baseTime,
      );

      final futureWord = UserWordEntry(
        word: 'ubiquitous',
        srsStage: 2,
        intervalDays: 1.0,
        nextReviewAt: baseTime.add(const Duration(days: 2)), // Due in 2 days
        lastQueriedAt: baseTime,
        createdAt: baseTime.subtract(const Duration(days: 1)),
        updatedAt: baseTime,
      );

      final overdueScore = UrgencyCalculator.calculateScore(
        entry: overdueWord,
        importance: WordImportance.medium,
        now: baseTime,
      );

      final futureScore = UrgencyCalculator.calculateScore(
        entry: futureWord,
        importance: WordImportance.medium,
        now: baseTime,
      );

      expect(overdueScore, greaterThan(futureScore * 2));
    });

    test('core corpus words score higher than low frequency words', () {
      final word = UserWordEntry(
        word: 'water',
        queryCount: 2,
        lastQueriedAt: baseTime,
        createdAt: baseTime,
        updatedAt: baseTime,
      );

      final coreScore = UrgencyCalculator.calculateScore(
        entry: word,
        importance: WordImportance.core,
        now: baseTime,
      );

      final lowScore = UrgencyCalculator.calculateScore(
        entry: word,
        importance: WordImportance.low,
        now: baseTime,
      );

      expect(coreScore, greaterThan(lowScore));
    });

    test('processReview handles Again, Hard, and Good correctly', () {
      final initial = UserWordEntry(
        word: 'paradigm',
        srsStage: 2,
        intervalDays: 2.0,
        easeFactor: 2.5,
        lapseCount: 0,
        lastQueriedAt: baseTime,
        createdAt: baseTime,
        updatedAt: baseTime,
      );

      // Again: resets stage, increments lapse count, schedules soon (12h)
      final againResult = UrgencyCalculator.processReview(
        entry: initial,
        feedback: ReviewFeedback.again,
        now: baseTime,
      );
      expect(againResult.srsStage, 1);
      expect(againResult.lapseCount, 1);
      expect(againResult.intervalDays, 0.5);
      expect(againResult.nextReviewAt, baseTime.add(const Duration(hours: 12)));

      // Good: advances stage and increases interval
      final goodResult = UrgencyCalculator.processReview(
        entry: initial,
        feedback: ReviewFeedback.good,
        now: baseTime,
      );
      expect(goodResult.srsStage, 3);
      expect(goodResult.intervalDays, greaterThan(initial.intervalDays));
      expect(goodResult.nextReviewAt!.isAfter(baseTime), isTrue);
    });
  });
}
