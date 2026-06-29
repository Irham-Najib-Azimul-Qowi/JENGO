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
    String additionalWhere = "";
    if (widget.language == 'JAPANESE') {
      if (targetStage == 1) {
        diffLevels = ['HIRAGANA'];
        additionalWhere = " AND id <= 100025";
      } else if (targetStage == 2) {
        diffLevels = ['HIRAGANA'];
        additionalWhere = " AND id > 100025";
      } else if (targetStage == 3) {
        diffLevels = ['HIRAGANA'];
      } else if (targetStage == 4) {
        diffLevels = ['KATAKANA'];
        additionalWhere = " AND id <= 100100";
      } else if (targetStage == 5) {
        diffLevels = ['KATAKANA'];
        additionalWhere = " AND id > 100100";
      } else if (targetStage == 6) {
        diffLevels = ['HIRAGANA', 'KATAKANA'];
      } else if (targetStage >= 7 && targetStage <= 13) {
        diffLevels = ['N5'];
      } else if (targetStage >= 14 && targetStage <= 15) {
        diffLevels = ['N4'];
      } else if (targetStage >= 16 && targetStage <= 18) {
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
        'SELECT COUNT(*) as total FROM vocabulary WHERE language = ? AND difficulty_level IN ($placeholders)$additionalWhere',
        [widget.language, ...diffLevels],
      );
      int totalCount = Sqflite.firstIntValue(countResults) ?? 0;
      
      int wordsPerDay = 10;
      int lessonIndex = (targetStage - 1) * 30 + (targetDay - 1);
      
      // Muat kata Hari ini
      int offsetToday = 0;
      if (totalCount > 0) {
        offsetToday = (lessonIndex * wordsPerDay) % totalCount;
      }
      final resultsToday = await db.query(
        'vocabulary',
        where: 'language = ? AND difficulty_level IN ($placeholders)$additionalWhere',
        whereArgs: [widget.language, ...diffLevels],
        orderBy: 'id ASC',
        limit: wordsPerDay,
        offset: offsetToday,
      );
      
      List<Map<String, dynamic>> combined = List<Map<String, dynamic>>.from(resultsToday);
      
      // Muat kata ulasan Hari Kemarin (jika lessonIndex > 0)
      if (lessonIndex > 0) {
        int offsetYesterday = 0;
        if (totalCount > 0) {
          offsetYesterday = ((lessonIndex - 1) * wordsPerDay) % totalCount;
        }
        final resultsYesterday = await db.query(
          'vocabulary',
          where: 'language = ? AND difficulty_level IN ($placeholders)$additionalWhere',
          whereArgs: [widget.language, ...diffLevels],
          orderBy: 'id ASC',
          limit: wordsPerDay,
          offset: offsetYesterday,
        );
        combined.addAll(resultsYesterday);
      }
      
      dueWords = combined;
    }

    // Fallback jika kosong
    if (dueWords.isEmpty) {
      int wordsPerDay = 10;
      int lessonIndex = (targetStage - 1) * 30 + (targetDay - 1);
      final resultsToday = await db.query(
        'vocabulary',
        where: 'language = ?',
        whereArgs: [widget.language],
        limit: wordsPerDay,
        offset: lessonIndex * wordsPerDay,
      );
      List<Map<String, dynamic>> combined = List<Map<String, dynamic>>.from(resultsToday);
      
      if (lessonIndex > 0) {
        final resultsYesterday = await db.query(
          'vocabulary',
          where: 'language = ?',
          whereArgs: [widget.language],
          limit: wordsPerDay,
          offset: (lessonIndex - 1) * wordsPerDay,
        );
        combined.addAll(resultsYesterday);
      }
      dueWords = combined;
    }

    // Filter out empty entries
    dueWords = dueWords.where((v) {
      final w = (v['word'] ?? '').toString().trim();
      final t = (v['translation'] ?? '').toString().trim();
      return w.isNotEmpty && t.isNotEmpty;
    }).toList();

    if (mounted) {
      setState(() {
        _flashcards = dueWords;
        _isLoading = false;
      });
      // Auto-speak the first card word when loaded
      if (dueWords.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _speak(dueWords.first['word']!);
        });
      }
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
                          // Romaji policy badge
                          if (isJapanese) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: widget.stage <= 6
                                    ? AppTheme.neonBlue.withOpacity(0.15)
                                    : widget.stage <= 12
                                        ? Colors.orange.withOpacity(0.15)
                                        : Colors.red.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                widget.stage <= 6
                                    ? '🔤 Romaji Aktif'
                                    : widget.stage <= 12
                                        ? '🔤 Romaji di Balik Kartu'
                                        : '🎯 Mode Tanpa Romaji',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: widget.stage <= 6
                                      ? AppTheme.neonBlue
                                      : widget.stage <= 12
                                          ? Colors.orange
                                          : Colors.redAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (!_isFlipped) ...[
                            Text(
                              currentCard['word']!,
                              style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              textAlign: TextAlign.center,
                            ),
                            if (isJapanese) ...[
                              // Show reading/furigana for stages 1-12 only
                              if (widget.stage <= 12) ...[
                                if (!isHiraganaKatakana) ...[
                                  if (currentCard['reading'] != null && currentCard['reading'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      '[ ${currentCard['reading']} ]',
                                      style: const TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ],
                              // Show Romaji on FRONT only for stages 1-6
                              if (widget.stage <= 6) ...[
                                const SizedBox(height: 6),
                                Text(
                                  isHiraganaKatakana
                                      ? 'Cara baca: ${KanaHelper.toRomaji(currentCard['word']!)}'
                                      : currentCard['reading'] != null && currentCard['reading'].toString().isNotEmpty
                                          ? 'Cara baca: ${KanaHelper.toRomaji(currentCard['reading']!)}'
                                          : 'Cara baca: ${KanaHelper.toRomaji(currentCard['word']!)}',
                                  style: const TextStyle(fontSize: 16, color: AppTheme.neonBlue, fontWeight: FontWeight.w500),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              // Hint for stages 7-12 (flip to see romaji)
                              if (widget.stage >= 7 && widget.stage <= 12) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  '👆 Balik kartu untuk melihat cara baca',
                                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ] else ...[
                            Text(
                              currentCard['translation']!,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              textAlign: TextAlign.center,
                            ),
                            // Show Romaji on BACK for stages 1-12
                            if (isJapanese && widget.stage <= 12) ...[
                              const SizedBox(height: 12),
                              Text(
                                isHiraganaKatakana
                                    ? 'Cara baca: ${KanaHelper.toRomaji(currentCard['word']!)}'
                                    : currentCard['reading'] != null && currentCard['reading'].toString().isNotEmpty
                                        ? 'Cara baca: ${KanaHelper.toRomaji(currentCard['reading']!)}'
                                        : 'Cara baca: ${KanaHelper.toRomaji(currentCard['word']!)}',
                                style: const TextStyle(fontSize: 18, color: AppTheme.neonBlue, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 16),
                            Text(
                              'Level: ${currentCard['difficulty_level']}',
                              style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            // Show example sentence if available
                            if ((currentCard['example_sentence'] ?? '').toString().trim().isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '📝 Contoh Kalimat',
                                      style: TextStyle(fontSize: 11, color: accentColor, fontWeight: FontWeight.bold, letterSpacing: 1),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      currentCard['example_sentence'].toString(),
                                      style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontStyle: FontStyle.italic),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
