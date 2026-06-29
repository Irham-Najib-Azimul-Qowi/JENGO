import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_helper.dart';

class ExamReviewScreen extends StatefulWidget {
  final int historyId;

  const ExamReviewScreen({
    super.key,
    required this.historyId,
  });

  @override
  State<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

class _ExamReviewScreenState extends State<ExamReviewScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _historyRecord;
  List<Map<String, dynamic>> _pastAttempts = [];
  List<dynamic> _reviewData = [];

  @override
  void initState() {
    super.initState();
    _loadReviewData();
  }

  Future<void> _loadReviewData() async {
    final db = await DatabaseHelper.instance.database;

    // Load current test history record
    final recordQuery = await db.query(
      'simulations_history',
      where: 'id = ?',
      whereArgs: [widget.historyId],
      limit: 1,
    );

    if (recordQuery.isNotEmpty) {
      final record = recordQuery.first;
      
      // Load all previous tests of the same language to do progress comparison
      final pastQuery = await db.query(
        'simulations_history',
        where: 'language = ?',
        whereArgs: [record['language']],
        orderBy: 'timestamp ASC',
        limit: 6,
      );

      List<dynamic> decodedReview = [];
      try {
        if (record['review_data'] != null) {
          decodedReview = jsonDecode(record['review_data'] as String) as List<dynamic>;
        }
      } catch (e) {
        debugPrint("Error decoding review_data: $e");
      }

      if (mounted) {
        setState(() {
          _historyRecord = record;
          _pastAttempts = pastQuery;
          _reviewData = decodedReview;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatTimeSpent(int totalSeconds) {
    if (totalSeconds <= 0) return "0 detik";
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes > 0) {
      return "$minutes menit $seconds detik";
    }
    return "$seconds detik";
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.neonBlue)),
      );
    }

    if (_historyRecord == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tinjauan Ujian')),
        body: const Center(child: Text('Data riwayat ujian tidak ditemukan.')),
      );
    }

    final isJp = _historyRecord!['language'] == 'JAPANESE';
    final Color accentColor = isJp ? AppTheme.neonBlue : AppTheme.neonGreen;
    final level = _historyRecord!['level'] as String;
    final double overallScore = _historyRecord!['overall_score'] as double;
    final Map<String, dynamic> sectionalScores = jsonDecode(_historyRecord!['sectional_scores']);
    
    final int correctAnswers = _historyRecord!['correct_answers'] as int;
    final int totalQuestions = _historyRecord!['total_questions'] as int;
    final String weaknesses = _historyRecord!['weaknesses'] as String;
    final String recommendations = _historyRecord!['recommendations'] as String;
    final int timeSpent = _historyRecord!['time_spent'] as int? ?? 0;

    final double percentage = totalQuestions > 0 ? (correctAnswers / totalQuestions) * 100 : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analisis Hasil Ujian'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Overall Score Card
            _buildOverallScoreCard(isJp, level, overallScore, correctAnswers, totalQuestions, percentage, timeSpent, accentColor),
            const SizedBox(height: 24),

            // 2. Sectional Breakdown
            Text(
              'Rincian Nilai Komponen',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildSectionScoresList(sectionalScores, isJp, accentColor),
            const SizedBox(height: 24),

            // 3. Weakness Analysis (Analisis Kelemahan)
            _buildWeaknessAnalysisCard(weaknesses, recommendations, accentColor),
            const SizedBox(height: 24),

            // 4. Progress Chart / Grafik Perkembangan
            Text(
              'Grafik Perkembangan Hasil Ujian',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildProgressChart(isJp, accentColor),
            const SizedBox(height: 24),

            // 5. Detailed Question Review (Jawaban benar/salah & Pembahasan)
            if (_reviewData.isNotEmpty) ...[
              Text(
                'Pembahasan Detail Soal',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              _buildDetailedQuestionList(accentColor),
              const SizedBox(height: 24),
            ],

            // 6. Exit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: AppTheme.darkBackground,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(context); // Back to dashboard
                },
                child: const Text('SELESAI & KEMBALI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallScoreCard(
    bool isJp,
    String level,
    double score,
    int correct,
    int total,
    double percentage,
    int timeSpent,
    Color color,
  ) {
    String scoreText = isJp ? '${score.toInt()} / 180 Poin' : 'Band $score / 9.0';
    String passLabel = isJp ? (score >= 120 ? 'LULUS KOMPETENSI' : 'BELUM LULUS') : (score >= 7.0 ? 'KOMPETENSI TINGGI (Band 7+)' : 'BUTUH PERBAIKAN');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            isJp ? 'JLPT $level SIMULASI' : 'IELTS ACADEMIC SIMULASI',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color, letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),
          Text(
            scoreText,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: score >= (isJp ? 120 : 7.0) ? AppTheme.neonGreen.withValues(alpha: 0.15) : AppTheme.neonPink.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              passLabel,
              style: TextStyle(
                fontSize: 12, 
                fontWeight: FontWeight.bold, 
                color: score >= (isJp ? 120 : 7.0) ? AppTheme.neonGreen : AppTheme.neonPink,
              ),
            ),
          ),
          const Divider(height: 32, color: AppTheme.darkBackground),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBriefStat('Akurasi', '${percentage.toStringAsFixed(1)}%', AppTheme.neonBlue),
              _buildBriefStat('Durasi', _formatTimeSpent(timeSpent), AppTheme.neonGreen),
              _buildBriefStat('Benar', '$correct / $total', AppTheme.textSecondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBriefStat(String label, String val, Color labelColor) {
    return Column(
      children: [
        Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: labelColor)),
      ],
    );
  }

  Widget _buildSectionScoresList(Map<String, dynamic> sections, bool isJp, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: sections.entries.map((entry) {
          final double scoreVal = entry.value is int ? (entry.value as int).toDouble() : (entry.value as double);
          final String scoreLabel = isJp 
              ? (entry.key.contains('Estimated') ? '${scoreVal.toInt()}' : '${scoreVal.toInt()} / 60 Poin') 
              : 'Band $scoreVal';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(entry.key, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                Text(scoreLabel, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWeaknessAnalysisCard(String weaknesses, String recommendations, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics, color: AppTheme.neonPink, size: 22),
              SizedBox(width: 8),
              Text(
                'ANALISIS KELEMAHAN',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.neonPink, letterSpacing: 1.1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            weaknesses,
            style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.45),
          ),
          const Divider(height: 24, color: AppTheme.darkBackground),
          const Row(
            children: [
              Icon(Icons.lightbulb, color: AppTheme.neonGreen, size: 22),
              SizedBox(width: 8),
              Text(
                'REKOMENDASI MATERI & TIPS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.neonGreen, letterSpacing: 1.1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            recommendations,
            style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressChart(bool isJp, Color color) {
    if (_pastAttempts.isEmpty) return const SizedBox();

    final maxScore = isJp ? 180.0 : 9.0;
    return Container(
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _pastAttempts.map((attempt) {
          final double score = attempt['overall_score'] as double;
          final double ratio = score / maxScore;
          final scoreText = isJp ? '${score.toInt()}' : '$score';
          final DateTime date = DateTime.fromMillisecondsSinceEpoch(attempt['timestamp'] as int);
          final dateStr = '${date.day}/${date.month}';

          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  scoreText,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 6),
                Container(
                  height: (100 * ratio).clamp(10.0, 100.0),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.3)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, -2),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  dateStr,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDetailedQuestionList(Color accentColor) {
    return Column(
      children: List.generate(_reviewData.length, (index) {
        final q = _reviewData[index];
        final bool isCorrect = q['isCorrect'] as bool? ?? false;
        final String category = q['category']?.toString() ?? '';
        final String prompt = q['prompt']?.toString() ?? '';
        final String? passage = q['passage']?.toString();
        final String? transcript = q['transcript']?.toString();
        final List<dynamic> options = q['options'] as List<dynamic>? ?? [];
        final dynamic userAnswer = q['userAnswer'];
        final dynamic correctAnswerIndex = q['correctAnswerIndex'];
        final String explanation = q['explanation']?.toString() ?? '';

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCorrect ? AppTheme.neonGreen.withValues(alpha: 0.15) : AppTheme.neonPink.withValues(alpha: 0.15),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isCorrect ? AppTheme.neonGreen.withValues(alpha: 0.15) : AppTheme.neonPink.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isCorrect ? 'BENAR' : 'SALAH',
                      style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.bold, 
                        color: isCorrect ? AppTheme.neonGreen : AppTheme.neonPink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Soal ${index + 1} • $category',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (passage != null && passage.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.darkBackground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    passage,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.45),
                  ),
                ),
              ],
              if (transcript != null && transcript.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.darkBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.neonBlue.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    'Audio Transcript:\n$transcript',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontStyle: FontStyle.italic, height: 1.45),
                  ),
                ),
              ],
              Text(
                prompt,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 14),
              if (options.isNotEmpty) ...[
                ...List.generate(options.length, (optIdx) {
                  final optionText = options[optIdx].toString();
                  final isUserSelected = userAnswer == optIdx;
                  final isCorrectOpt = correctAnswerIndex == optIdx;

                  Color optionBorder = AppTheme.textSecondary.withValues(alpha: 0.08);
                  Color optionBackground = Colors.transparent;
                  Widget? trailingIcon;

                  if (isCorrectOpt) {
                    optionBorder = AppTheme.neonGreen;
                    optionBackground = AppTheme.neonGreen.withValues(alpha: 0.05);
                    trailingIcon = const Icon(Icons.check_circle, color: AppTheme.neonGreen, size: 16);
                  } else if (isUserSelected) {
                    optionBorder = AppTheme.neonPink;
                    optionBackground = AppTheme.neonPink.withValues(alpha: 0.05);
                    trailingIcon = const Icon(Icons.cancel, color: AppTheme.neonPink, size: 16);
                  }

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: optionBackground,
                      border: Border.all(color: optionBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            optionText,
                            style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                          ),
                        ),
                        if (trailingIcon != null) trailingIcon,
                      ],
                    ),
                  );
                }),
              ] else ...[
                // For writing/speaking answers
                Text(
                  'Respons Anda:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accentColor),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.darkBackground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    userAnswer?.toString() ?? '(Tidak ada respon)',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.4),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(color: AppTheme.darkBackground),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.menu_book, color: AppTheme.neonBlue, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Pembahasan:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.neonBlue),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                explanation,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.45),
              ),
            ],
          ),
        );
      }),
    );
  }
}
