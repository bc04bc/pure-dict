/// Data model for a word tracked in the user study database (`user.db`).
class UserWordEntry {
  const UserWordEntry({
    required this.word,
    this.inStudy = true,
    this.queryCount = 1,
    required this.lastQueriedAt,
    this.srsStage = 0,
    this.nextReviewAt,
    this.intervalDays = 0,
    this.easeFactor = 2.5,
    this.lapseCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  final String word;

  /// Whether this word is actively in the study/flashcard queue.
  final bool inStudy;

  /// How many times the user has queried this word in the app.
  final int queryCount;

  /// Timestamp when this word was most recently queried.
  final DateTime lastQueriedAt;

  /// Current spaced-repetition stage (0 = new/unreviewed, 1..7 = progression).
  final int srsStage;

  /// When this word is next due for review.
  final DateTime? nextReviewAt;

  /// Current repetition interval in days.
  final double intervalDays;

  /// Ease factor for SM-2 interval calculations (default 2.5).
  final double easeFactor;

  /// Number of times the user forgot this word during review.
  final int lapseCount;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Tombstone flag for incremental sync (1 = deleted by user).
  final bool isDeleted;

  factory UserWordEntry.fromRow(Map<String, Object?> row) {
    return UserWordEntry(
      word: row['word'] as String,
      inStudy: (row['in_study'] as int? ?? 1) == 1,
      queryCount: row['query_count'] as int? ?? 1,
      lastQueriedAt: DateTime.fromMillisecondsSinceEpoch(
        row['last_queried_at'] as int? ?? 0,
      ),
      srsStage: row['srs_stage'] as int? ?? 0,
      nextReviewAt: row['next_review_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['next_review_at'] as int),
      intervalDays: (row['interval_days'] as num? ?? 0).toDouble(),
      easeFactor: (row['ease_factor'] as num? ?? 2.5).toDouble(),
      lapseCount: row['lapse_count'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int? ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int? ?? 0,
      ),
      isDeleted: (row['is_deleted'] as int? ?? 0) == 1,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'word': word,
      'in_study': inStudy ? 1 : 0,
      'query_count': queryCount,
      'last_queried_at': lastQueriedAt.millisecondsSinceEpoch,
      'srs_stage': srsStage,
      'next_review_at': nextReviewAt?.millisecondsSinceEpoch,
      'interval_days': intervalDays,
      'ease_factor': easeFactor,
      'lapse_count': lapseCount,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  UserWordEntry copyWith({
    String? word,
    bool? inStudy,
    int? queryCount,
    DateTime? lastQueriedAt,
    int? srsStage,
    DateTime? nextReviewAt,
    double? intervalDays,
    double? easeFactor,
    int? lapseCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return UserWordEntry(
      word: word ?? this.word,
      inStudy: inStudy ?? this.inStudy,
      queryCount: queryCount ?? this.queryCount,
      lastQueriedAt: lastQueriedAt ?? this.lastQueriedAt,
      srsStage: srsStage ?? this.srsStage,
      nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      intervalDays: intervalDays ?? this.intervalDays,
      easeFactor: easeFactor ?? this.easeFactor,
      lapseCount: lapseCount ?? this.lapseCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
