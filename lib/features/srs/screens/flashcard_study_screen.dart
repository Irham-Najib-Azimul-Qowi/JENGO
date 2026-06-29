import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/srs_engine.dart';
import '../../../core/utils/kana_helper.dart';
import '../../../core/utils/custom_top_notification.dart';
import 'package:sqflite/sqflite.dart';

class FlashcardStudyScreen extends StatefulWidget {
  final String language;
  final int stage;
  final int day;

  const FlashcardStudyScreen({
    super.key,
    required this.language,
    this.stage = 1,
    this.day = 1,
  });

  @override
  State<FlashcardStudyScreen> createState() => _FlashcardStudyScreenState();
}

class _HealthStatusHelper {
  static Map<String, dynamic> getHealthData(Map<String, dynamic>? userData, int activeStage) {
    if (userData == null) return {'hearts': 5, 'lagDays': 0};

    final int startTimeMs = userData['start_time'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final DateTime startTime = DateTime.fromMillisecondsSinceEpoch(startTimeMs);
    final DateTime now = DateTime.now();

    final int daysElapsed = now.difference(startTime).inDays;
    final int progressDays = (activeStage - 1) * 30 + 12; // Simulasi hari ke-12
    final int lagDays = daysElapsed - progressDays;

    if (lagDays <= 0) return {'hearts': 5, 'lagDays': 0};

    int lostHearts = (lagDays / 6).floor();
    int currentHearts = 5 - lostHearts;
    if (currentHearts < 0) currentHearts = 0;

    return {'hearts': currentHearts, 'lagDays': lagDays};
  }
}

class _FlashcardStudyScreenState extends State<FlashcardStudyScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  List<Map<String, dynamic>> _flashcards = [];
  int _currentIndex = 0;
  bool _isFlipped = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVocabulary();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _loadVocabulary() async {
    final db = await DatabaseHelper.instance.database;

    final targetStage = widget.stage;
    final targetDay = widget.day;

    // 1. Tentukan difficulty level berdasarkan stage dan bahasa
    List<String> diffLevels = [];
    if (widget.language == 'JAPANESE') {
      if (targetStage == 1) {
        diffLevels = ['HIRAGANA'];
      } else if (targetStage == 2) {
        diffLevels = ['KATAKANA'];
      } else if (targetStage >= 3 && targetStage <= 4) {
        diffLevels = ['N5'];
      } else if (targetStage >= 5 && targetStage <= 6) {
        diffLevels = ['N4'];
      } else if (targetStage >= 7 && targetStage <= 12) {
        diffLevels = ['N3'];
      } else {
        diffLevels = ['N2', 'N1'];
      }
    } else {
      // ENGLISH
      if (targetStage >= 1 && targetStage <= 2) {
        diffLevels = ['A1'];
      } else if (targetStage >= 3 && targetStage <= 4) {
        diffLevels = ['A2'];
      } else if (targetStage >= 5 && targetStage <= 6) {
        diffLevels = ['B1'];
      } else if (targetStage >= 7 && targetStage <= 12) {
        diffLevels = ['B2'];
      } else {
        diffLevels = ['C1'];
      }
    }

    List<Map<String, dynamic>> dueWords = [];
    
    // 2. Muat kata secara deterministik dengan paginasi per Hari (LIMIT 10, OFFSET)
    if (diffLevels.isNotEmpty) {
      String placeholders = List.filled(diffLevels.length, '?').join(', ');
      
      // Hitung total kata yang tersedia untuk level ini
      final countResults = await db.rawQuery(
        'SELECT COUNT(*) as total FROM vocabulary WHERE language = ? AND difficulty_level IN ($placeholders)',
        [widget.language, ...diffLevels],
      );
      int totalCount = Sqflite.firstIntValue(countResults) ?? 0;
      
      int wordsPerDay = 10;
      int lessonIndex = (targetStage - 1) * 30 + (targetDay - 1);
      int offset = 0;
      if (totalCount > 0) {
        offset = (lessonIndex * wordsPerDay) % totalCount;
      }

      final results = await db.query(
        'vocabulary',
        where: 'language = ? AND difficulty_level IN ($placeholders)',
        whereArgs: [widget.language, ...diffLevels],
        orderBy: 'id ASC',
        limit: wordsPerDay,
        offset: offset,
      );
      dueWords = List<Map<String, dynamic>>.from(results);
    }

    // Fallback jika kosong
    if (dueWords.isEmpty) {
      final results = await db.query(
        'vocabulary',
        where: 'language = ?',
        whereArgs: [widget.language],
        limit: 10,
      );
      dueWords = List<Map<String, dynamic>>.from(results);
    }

    if (mounted) {
      setState(() {
        _flashcards = dueWords;
        _isLoading = false;
      });
    }
  }

  Future<void> _speak(String text) async {
    if (widget.language == 'JAPANESE') {
      await _flutterTts.setLanguage("ja-JP");
    } else {
      await _flutterTts.setLanguage("en-US");
    }
    await _flutterTts.speak(text);
  }

  void _handleReview(bool isCorrect) async {
    if (_flashcards.isEmpty) return;

    final currentCard = _flashcards[_currentIndex];
    final int vocabId = currentCard['id'] as int;

    // Panggil SRS Engine untuk memperbarui box level dan waktu ulasan berikutnya
    await SrsEngine.instance.updateReviewResult(vocabId, isCorrect);

    CustomTopNotification.show(
      context,
      message: isCorrect ? 'Ulasan Berhasil! (+10 XP)' : 'Diulang Nanti (Box 1)',
      isError: !isCorrect,
      duration: const Duration(milliseconds: 1000),
    );

    if (_currentIndex < _flashcards.length - 1) {
      setState(() {
        _currentIndex++;
        _isFlipped = false;
      });
    } else {
      _showCompletionDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.neonBlue)),
      );
    }

    if (_flashcards.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Flashcard: ${widget.language}')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'Belum ada kosakata untuk diulas hari ini. Silakan tambahkan pelajaran baru di Dashboard!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    final currentCard = _flashcards[_currentIndex];
    final progressPercent = (_currentIndex + 1) / _flashcards.length;
    final isJapanese = widget.language == 'JAPANESE';
    final Color accentColor = isJapanese ? AppTheme.neonBlue : AppTheme.neonGreen;
    final isHiraganaKatakana = currentCard['difficulty_level'] == 'HIRAGANA' || currentCard['difficulty_level'] == 'KATAKANA';

    return Scaffold(
      appBar: AppBar(
        title: Text('Flashcard: ${isJapanese ? 'Jepang' : 'Inggris'}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 1. Progress Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Kartu ${_currentIndex + 1} / ${_flashcards.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${((_currentIndex + 1) / _flashcards.length * 100).toInt()}%',
                  style: TextStyle(color: accentColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressPercent,
                minHeight: 8,
                backgroundColor: AppTheme.darkSurface,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 48),

            // 2. Flashcard Flip Card
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isFlipped = !_isFlipped;
                  });
                  if (_isFlipped) {
                    _speak(currentCard['word']!);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isFlipped ? accentColor : AppTheme.textSecondary.withOpacity(0.2),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _isFlipped ? accentColor.withOpacity(0.1) : Colors.transparent,
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isFlipped ? 'TERJEMAHAN / ARTI' : 'KOSAKATA / KANA',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 1.5),
                          ),
                          const SizedBox(height: 20),
                          if (!_isFlipped) ...[
                            Text(
                              currentCard['word']!,
                              style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              textAlign: TextAlign.center,
                            ),
                            if (isJapanese) ...[
                              if (!isHiraganaKatakana) ...[
                                if (currentCard['reading'] != null && currentCard['reading'].toString().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '[ ${currentCard['reading']} ]',
                                    style: const TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Cara baca: ${KanaHelper.toRomaji(currentCard['reading']!)}',
                                    style: const TextStyle(fontSize: 16, color: AppTheme.neonBlue, fontWeight: FontWeight.w500),
                                    textAlign: TextAlign.center,
                                  ),
                                ] else ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Cara baca: ${KanaHelper.toRomaji(currentCard['word']!)}',
                                    style: const TextStyle(fontSize: 16, color: AppTheme.neonBlue, fontWeight: FontWeight.w500),
                                    textAlign: TextAlign.center,
                                  ),
                                ]
                              ]
                            ],
                          ] else ...[
                            Text(
                              currentCard['translation']!,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              textAlign: TextAlign.center,
                            ),
                            if (isJapanese && (currentCard['difficulty_level'] == 'HIRAGANA' || currentCard['difficulty_level'] == 'KATAKANA')) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Cara baca: ${KanaHelper.toRomaji(currentCard['word']!)}',
                                style: const TextStyle(fontSize: 18, color: AppTheme.neonBlue, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 24),
                            Text(
                              'Level: ${currentCard['difficulty_level']}',
                              style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                          const SizedBox(height: 32),
                          Icon(
                            _isFlipped ? Icons.volume_up : Icons.touch_app,
                            color: _isFlipped ? accentColor : AppTheme.textSecondary.withOpacity(0.5),
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),

            // 3. Leitner Box Buttons (Muncul saat kartu dibalik)
            if (_isFlipped) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neonPink,
                      foregroundColor: AppTheme.darkBackground,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    onPressed: () => _handleReview(false),
                    child: const Text('Lupa (Salah)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neonGreen,
                      foregroundColor: AppTheme.darkBackground,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    onPressed: () => _handleReview(true),
                    child: const Text('Ingat (Benar)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ] else ...[
              // Navigasi Dua Arah sederhana jika belum dibalik
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.darkSurface,
                      foregroundColor: AppTheme.textPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    onPressed: _currentIndex == 0 ? null : () {
                      setState(() {
                        _currentIndex--;
                        _isFlipped = false;
                      });
                    },
                    child: const Text('Sebelumnya'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: AppTheme.darkBackground,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    onPressed: () {
                      setState(() {
                        _isFlipped = true;
                      });
                      _speak(currentCard['word']!);
                    },
                    child: const Text('Buka Kartu'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppTheme.neonGreen),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.neonGreen),
            SizedBox(width: 10),
            Text('Flashcard Selesai!'),
          ],
        ),
        content: const Text(
          'Hebat! Anda telah mengulas kosakata ulasan hari ini. '
          'Langkah berikutnya adalah langsung mengikuti latihan kuis interaktif (Duolingo-style) untuk menguji ingatan Anda.',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonGreen),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(
                context,
                '/daily_lesson_quiz',
                arguments: {
                  'language': widget.language,
                  'vocabList': _flashcards,
                  'stage': widget.stage,
                  'day': widget.day,
                },
              );
            },
            child: const Text('Mulai Kuis Latihan', style: TextStyle(color: AppTheme.darkBackground)),
          ),
        ],
      ),
    );
  }
}
