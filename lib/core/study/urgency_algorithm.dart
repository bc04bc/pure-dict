import 'dart:math' as math;

import '../models/study_entry.dart';
import '../text/importance.dart';

enum ReviewFeedback {
  again('忘记了', '重新记忆，缩短复习间隔'),
  hard('模糊', '有些勉强，保持或微增间隔'),
  good('记住了', '顺利回忆，延长复习周期');

  const ReviewFeedback(this.label, this.description);
  final String label;
  final String description;
}

class UrgencyCalculator {
  UrgencyCalculator._();

  /// Standard SRS progression intervals (in days) indexed by stage (1..7).
  static const List<double> standardIntervals = [
    0.5, // Stage 0/1: 12 hours (first review)
    1.0, // Stage 2: 1 day
    2.0, // Stage 3: 2 days
    4.0, // Stage 4: 4 days
    7.0, // Stage 5: 1 week
    15.0, // Stage 6: ~2 weeks
    30.0, // Stage 7: 1 month
    60.0, // Stage 8+: Mastered
  ];

  /// Calculates the urgency score for a study word.
  ///
  /// Higher scores indicate the word should be reviewed sooner.
  /// Formula: Score = S_overdue * W_query * W_importance
  static double calculateScore({
    required UserWordEntry entry,
    required WordImportance importance,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();

    // 1. Personal lookup query weight (logarithmic scaling)
    final wQuery = 1.0 + math.log(1 + math.max(1, entry.queryCount)) * 0.6;

    // 2. Objective corpus importance weight
    final double wImportance = switch (importance) {
      WordImportance.core => 1.5,
      WordImportance.high => 1.3,
      WordImportance.medium => 1.0,
      WordImportance.low => 0.85,
      WordImportance.unknown => 0.8,
    };

    // 3. Spaced-repetition overdue urgency
    double sOverdue;
    if (entry.srsStage == 0 || entry.nextReviewAt == null) {
      // New word, not yet reviewed: high initial baseline
      final ageHours = currentTime
          .difference(entry.createdAt)
          .inHours
          .clamp(0, 72);
      sOverdue = 1.5 + (ageHours / 48.0);
    } else {
      final dueTime = entry.nextReviewAt!;
      final intervalDays = math.max(0.5, entry.intervalDays);
      final intervalMillis = intervalDays * 24 * 3600 * 1000;

      if (currentTime.isAfter(dueTime)) {
        // Overdue: score grows proportionally with overdue delay
        final overdueMillis =
            currentTime.difference(dueTime).inMilliseconds;
        final overdueRatio = overdueMillis / intervalMillis;
        sOverdue = 1.0 + overdueRatio * 1.8;
      } else {
        // Not due yet: discounted based on remaining time until due
        final remainingMillis =
            dueTime.difference(currentTime).inMilliseconds;
        final remainingRatio = (remainingMillis / intervalMillis).clamp(0.0, 1.0);
        sOverdue = math.max(0.05, 1.0 - remainingRatio * 0.9);
      }
    }

    return sOverdue * wQuery * wImportance;
  }

  /// Calculates the updated [UserWordEntry] state after user feedback.
  static UserWordEntry processReview({
    required UserWordEntry entry,
    required ReviewFeedback feedback,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    int newStage;
    double newInterval;
    double newEase = entry.easeFactor;
    int newLapse = entry.lapseCount;

    switch (feedback) {
      case ReviewFeedback.again:
        // Reset to initial stage
        newStage = 1;
        newInterval = 0.5; // 12 hours
        newLapse += 1;
        newEase = math.max(1.3, entry.easeFactor - 0.2);
      case ReviewFeedback.hard:
        // Hold current interval or small bump
        newStage = math.max(1, entry.srsStage);
        newInterval = math.max(1.0, entry.intervalDays * 1.15);
        newEase = math.max(1.3, entry.easeFactor - 0.1);
      case ReviewFeedback.good:
        // Advance stage
        newStage = entry.srsStage + 1;
        if (newStage < standardIntervals.length) {
          newInterval = standardIntervals[newStage];
        } else {
          newInterval = entry.intervalDays * entry.easeFactor;
        }
        newEase = math.min(3.0, entry.easeFactor + 0.1);
    }

    final nextReview = currentTime.add(
      Duration(minutes: (newInterval * 24 * 60).round()),
    );

    return entry.copyWith(
      srsStage: newStage,
      intervalDays: newInterval,
      easeFactor: newEase,
      lapseCount: newLapse,
      nextReviewAt: nextReview,
      updatedAt: currentTime,
    );
  }
}
