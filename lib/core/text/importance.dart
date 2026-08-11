/// Importance level derived from ECDICT frequency ranking.
enum WordImportance {
  core('核心', '当代语料库前 3000'),
  high('高频', '当代语料库 3001–6000'),
  medium('中频', '当代语料库 6001–15000'),
  low('低频', '当代语料库 15001+'),
  unknown('生僻', '未收录于常用词频表');

  const WordImportance(this.label, this.description);

  final String label;
  final String description;
}

/// Maps ECDICT `frq` (1-based frequency rank, lower = more common) to a
/// coarse importance bucket. Null/zero means the word is not in the
/// contemporary corpus ranking.
WordImportance importanceFromFrq(int? frq) {
  if (frq == null || frq <= 0) return WordImportance.unknown;
  if (frq <= 3000) return WordImportance.core;
  if (frq <= 6000) return WordImportance.high;
  if (frq <= 15000) return WordImportance.medium;
  return WordImportance.low;
}
