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
        where: 'language = ? AND id != ?',
        whereArgs: [record['language'], widget.historyId],
        orderBy: 'timestamp DESC',
        limit: 5,
      );

      if (mounted) {
        setState(() {
          _historyRecord = record;
          _pastAttempts = pastQuery;
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
            _buildOverallScoreCard(isJp, level, overallScore, correctAnswers, totalQuestions, accentColor),
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

            // 4. Progress Comparison vs Past Tests
            Text(
              'Perbandingan Progress',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildProgressComparisonList(isJp),
            const SizedBox(height: 32),

            // 5. Exit button
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
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
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
              color: score >= (isJp ? 120 : 7.0) ? AppTheme.neonGreen.withOpacity(0.15) : AppTheme.neonPink.withOpacity(0.15),
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
              _buildBriefStat('Benar', '$correct', AppTheme.neonGreen),
              _buildBriefStat('Salah', '${total - correct}', AppTheme.neonPink),
              _buildBriefStat('Total Soal', '$total', AppTheme.textSecondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBriefStat(String label, String val, Color labelColor) {
    return Column(
      children: [
        Text(val, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
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
          final String scoreLabel = isJp ? '${scoreVal.toInt()} / 90 Poin' : 'Band $scoreVal';

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
        border: Border.all(color: AppTheme.textSecondary.withOpacity(0.1)),
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

  Widget _buildProgressComparisonList(bool isJp) {
    if (_pastAttempts.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'Ini merupakan simulasi tes pertama Anda. Data perbandingan akan muncul pada ujian berikutnya.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: _pastAttempts.map((attempt) {
        final double score = attempt['overall_score'] as double;
        final String scoreText = isJp ? '${score.toInt()} Poin' : 'Band $score';
        final DateTime date = DateTime.fromMillisecondsSinceEpoch(attempt['timestamp'] as int);
        final dateString = '${date.day}/${date.month}/${date.year}';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tingkat ${attempt['level']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(dateString, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
              Text(
                scoreText,
                style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
