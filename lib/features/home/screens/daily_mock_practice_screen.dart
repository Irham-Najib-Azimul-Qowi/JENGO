import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_helper.dart';

class DailyMockPracticeScreen extends StatefulWidget {
  final String language;
  final int stage;
  final int day;

  const DailyMockPracticeScreen({
    super.key,
    required this.language,
    this.stage = 1,
    this.day = 1,
  });

  @override
  State<DailyMockPracticeScreen> createState() =>
      _DailyMockPracticeScreenState();
}

class _DailyMockPracticeScreenState extends State<DailyMockPracticeScreen> {
  final FlutterTts _flutterTts = FlutterTts();

  int _currentStep = 0; // 0: Tips, 1-4: Day N, 5-8: Day N-1 review
  final int _totalSteps = 9;
  bool _isLoading = true;
  bool _isSpeakingPlaying = false;
  bool _isRecording = false;
  bool _hasSpoken = false;
  String _spokenText = "";

  // Input fields
  final TextEditingController _writingController = TextEditingController();
  int _wordCount = 0;
  int _selectedReadAnswerIndex = -1;
  int _selectedListenAnswerIndex = -1;
  bool _hasCheckedRead = false;
  bool _hasCheckedListen = false;

  // Data
  final List<Map<String, dynamic>> _readingItems = [];
  final List<Map<String, dynamic>> _listeningItems = [];
  final List<Map<String, dynamic>> _writingItems = [];
  final List<Map<String, dynamic>> _speakingItems = [];
  Map<String, dynamic>? _readingData;
  Map<String, dynamic>? _listeningData;
  Map<String, dynamic>? _writingData;
  Map<String, dynamic>? _speakingData;

  @override
  void initState() {
    super.initState();
    _loadExamContent();
    _writingController.addListener(_updateWordCount);
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _writingController.dispose();
    super.dispose();
  }

  void _updateWordCount() {
    final text = _writingController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _wordCount = 0;
      });
      return;
    }
    setState(() {
      _wordCount = text.split(RegExp(r'\s+')).length;
    });
  }

  Future<void> _loadExamContent() async {
    final db = await DatabaseHelper.instance.database;

    // Tentukan level berdasarkan stage
    String level = 'N3';
    if (widget.language == 'JAPANESE') {
      if (widget.stage <= 2)
        level = 'N5';
      else if (widget.stage <= 4)
        level = 'N5';
      else if (widget.stage <= 6)
        level = 'N4';
      else if (widget.stage <= 12)
        level = 'N3';
      else
        level = 'N2';
    } else {
      level = 'C1';
    }

    // Hitung total data
    final readCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM reading WHERE language = ? AND level = ?',
            [widget.language, level])) ??
        1;
    final listenCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM listening WHERE language = ? AND level = ?',
            [widget.language, level])) ??
        1;
    final writingCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM writing_prompts')) ??
        1;
    final speakingCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM speaking_prompts')) ??
        1;

    int lessonIndex = (widget.stage - 1) * 30 + (widget.day - 1);

    final reviewIndex = lessonIndex > 0 ? lessonIndex - 1 : lessonIndex;
    final readToday = await _queryReading(db, level, lessonIndex, readCount);
    final readReview = await _queryReading(db, level, reviewIndex, readCount);
    final listenToday =
        await _queryListening(db, level, lessonIndex, listenCount);
    final listenReview =
        await _queryListening(db, level, reviewIndex, listenCount);
    final writingToday =
        await _queryPrompt(db, 'writing_prompts', lessonIndex, writingCount);
    final writingReview =
        await _queryPrompt(db, 'writing_prompts', reviewIndex, writingCount);
    final speakingToday =
        await _queryPrompt(db, 'speaking_prompts', lessonIndex, speakingCount);
    final speakingReview =
        await _queryPrompt(db, 'speaking_prompts', reviewIndex, speakingCount);

    if (mounted) {
      setState(() {
        final fallbackReading = _getFallbackReading(widget.language, level);
        final fallbackListening = _getFallbackListening(widget.language, level);
        final fallbackWriting = {
          'prompt':
              'Write an essay about the advantages and disadvantages of technology in education.',
          'tips':
              'Focus on dynamic structures, linking words, and state reasons clearly.'
        };
        final fallbackSpeaking = {
          'topic': 'Describe a place you visited that you liked.',
          'tips': 'Speak about what, when, where, and why you liked it.'
        };

        _readingItems
          ..clear()
          ..add(readToday ?? fallbackReading)
          ..add(readReview ?? readToday ?? fallbackReading);
        _listeningItems
          ..clear()
          ..add(listenToday ?? fallbackListening)
          ..add(listenReview ?? listenToday ?? fallbackListening);
        _writingItems
          ..clear()
          ..add(writingToday ?? fallbackWriting)
          ..add(writingReview ?? writingToday ?? fallbackWriting);
        _speakingItems
          ..clear()
          ..add(speakingToday ?? fallbackSpeaking)
          ..add(speakingReview ?? speakingToday ?? fallbackSpeaking);

        _selectContentSlot(0);

        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _queryReading(
      Database db, String level, int lessonIndex, int count) async {
    final rows = await db.query(
      'reading',
      where: 'language = ? AND level = ?',
      whereArgs: [widget.language, level],
      limit: 1,
      offset: count > 0 ? lessonIndex % count : 0,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, dynamic>?> _queryListening(
      Database db, String level, int lessonIndex, int count) async {
    final rows = await db.query(
      'listening',
      where: 'language = ? AND level = ?',
      whereArgs: [widget.language, level],
      limit: 1,
      offset: count > 0 ? lessonIndex % count : 0,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, dynamic>?> _queryPrompt(
      Database db, String table, int lessonIndex, int count) async {
    final rows = await db.query(
      table,
      limit: 1,
      offset: count > 0 ? lessonIndex % count : 0,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  void _selectContentSlot(int slot) {
    if (_readingItems.isNotEmpty)
      _readingData = _readingItems[slot.clamp(0, _readingItems.length - 1)];
    if (_listeningItems.isNotEmpty)
      _listeningData =
          _listeningItems[slot.clamp(0, _listeningItems.length - 1)];
    if (_writingItems.isNotEmpty)
      _writingData = _writingItems[slot.clamp(0, _writingItems.length - 1)];
    if (_speakingItems.isNotEmpty)
      _speakingData = _speakingItems[slot.clamp(0, _speakingItems.length - 1)];
  }

  Map<String, dynamic> _getFallbackReading(String lang, String level) {
    if (lang == 'JAPANESE') {
      return {
        'title': 'JLPT $level Reading: 毎日勉強',
        'passage': 'わたしは毎日日本語を勉強します。日本語はとてもおもしろいです。でも、漢字は難しいです。毎日書いて練習します。',
        'translation':
            'Saya belajar bahasa Jepang setiap hari. Bahasa Jepang sangat menarik. Tetapi, Kanji sulit. Saya berlatih menulisnya setiap hari.',
        'questions': jsonEncode([
          {
            'question': '日本語の漢字はどうですか？ (Bagaimana kanji bahasa Jepang?)',
            'options': [
              'おもしろくて、簡単です (Menarik dan mudah)',
              'おもしろいですが、難しいです (Menarik tapi sulit)',
              'あまりおもしろくないです (Kurang menarik)'
            ],
            'correct_answer_index': 1
          }
        ])
      };
    } else {
      return {
        'title': 'IELTS Reading: Academic Study Techniques',
        'passage':
            'Effective time management is a critical success factor for academic performance. Research suggests that dividing study sessions into short, focused blocks of 25 minutes, separated by 5-minute intervals, maximizes cognitive retention. This method is widely known as the Pomodoro Technique.',
        'translation':
            'Manajemen waktu yang efektif adalah faktor kunci kesuksesan untuk kinerja akademis. Penelitian menunjukkan bahwa membagi sesi belajar menjadi blok-blok terfokus berdurasi 25 menit, yang dipisahkan oleh interval 5 menit, memaksimalkan retensi kognitif.',
        'questions': jsonEncode([
          {
            'question':
                'What is the main benefit of the Pomodoro Technique according to the text?',
            'options': [
              'It minimizes study time completely',
              'It maximizes cognitive retention',
              'It reduces student anxiety levels'
            ],
            'correct_answer_index': 1
          }
        ])
      };
    }
  }

  Map<String, dynamic> _getFallbackListening(String lang, String level) {
    if (lang == 'JAPANESE') {
      return {
        'title': 'JLPT $level Listening: Percakapan Singkat',
        'transcript':
            '男の人と女の人が話しています。男の人は明日、何時に来ますか？\n男：明日、9時に行きます。\n女：すみません、明日は10時にお願いします。\n男：分かりました。じゃあ、10時に行きます。',
        'translation':
            'Pria dan wanita sedang berbicara. Jam berapa pria itu akan datang besok?\nPria: Besok saya datang jam 9.\nWanita: Maaf, besok tolong jam 10 ya.\nPria: Baik, kalau begitu saya datang jam 10.',
        'questions': jsonEncode([
          {
            'question': '男の人は明日、何時に来ますか？ (Jam berapa pria itu datang besok?)',
            'options': ['9時 (Jam 9)', '10時 (Jam 10)', '11時 (Jam 11)'],
            'correct_answer_index': 1
          }
        ])
      };
    } else {
      return {
        'title': 'IELTS Listening: Student Accommodation',
        'transcript':
            'Hello, I would like to inquire about the rental price for a single room in the university hall of residence.\nStaff: Sure, single rooms are currently 120 pounds per week, which includes water and electricity utilities.',
        'translation':
            'Halo, saya ingin menanyakan tentang harga sewa untuk kamar single di asrama universitas.\nStaf: Tentu saja, kamar single saat ini seharga 120 pound per minggu, sudah termasuk utilitas air dan listrik.',
        'questions': jsonEncode([
          {
            'question': 'How much is the weekly rent for a single room?',
            'options': ['100 pounds', '120 pounds', '150 pounds'],
            'correct_answer_index': 1
          }
        ])
      };
    }
  }

  Future<void> _speak(String text) async {
    setState(() {
      _isSpeakingPlaying = true;
    });
    if (widget.language == 'JAPANESE') {
      await _flutterTts.setLanguage("ja-JP");
    } else {
      await _flutterTts.setLanguage("en-US");
    }
    await _flutterTts.speak(text);
    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeakingPlaying = false;
        });
      }
    });
  }

  void _simulateSpeakingRecord(String sentence) async {
    setState(() {
      _isRecording = true;
    });
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _isRecording = false;
        _hasSpoken = true;
        _spokenText = sentence;
      });
    }
  }

  void _goToStep(int nextStep) {
    setState(() {
      _currentStep = nextStep;
      if (nextStep == 1 || nextStep == 5) {
        _selectedReadAnswerIndex = -1;
        _hasCheckedRead = false;
      }
      if (nextStep == 2 || nextStep == 6) {
        _writingController.clear();
        _wordCount = 0;
      }
      if (nextStep == 3 || nextStep == 7) {
        _isRecording = false;
        _hasSpoken = false;
        _spokenText = "";
      }
      if (nextStep == 4 || nextStep == 8) {
        _selectedListenAnswerIndex = -1;
        _hasCheckedListen = false;
      }
    });
  }

  void _finishExamSession() async {
    final db = await DatabaseHelper.instance.database;
    final userList = await db.query('gamification', limit: 1);
    if (userList.isNotEmpty) {
      final user = userList.first;
      final currentXp = user['total_xp'] as int? ?? 0;
      final currentGems = user['gems'] as int? ?? 0;
      await DatabaseHelper.instance.advanceLanguageProgressIfCurrent(
        language: widget.language,
        completedStage: widget.stage,
        completedDay: widget.day,
      );

      await db.update(
        'gamification',
        {
          'total_xp': currentXp + 80,
          'gems': currentGems + 15,
        },
        where: 'id = ?',
        whereArgs: [user['id']],
      );
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.neonGreen),
        ),
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.amber),
            SizedBox(width: 10),
            Text('Sesi Ujian Selesai! 🎓'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Luar biasa! Sesi harian ${widget.language == 'JAPANESE' ? 'JLPT' : 'IELTS'} Anda selesai hari ini.'),
            const SizedBox(height: 12),
            const Text('🏆 Hadiah XP: +80 XP',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.neonGreen)),
            const Text('💎 Hadiah Permata: +15 Gems',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.neonBlue)),
          ],
        ),
        actions: [
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.neonGreen),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to Dashboard
            },
            child: const Text('Selesai & Keluar',
                style: TextStyle(
                    color: AppTheme.darkBackground,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: AppTheme.neonBlue)),
      );
    }

    final isJapanese = widget.language == 'JAPANESE';
    final accentColor = isJapanese ? AppTheme.neonBlue : AppTheme.neonGreen;
    final progressPercent = (_currentStep + 1) / _totalSteps;

    return Scaffold(
      appBar: AppBar(
        title: Text('Sesi Harian ${isJapanese ? 'JLPT' : 'IELTS'}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressPercent,
                minHeight: 8,
                backgroundColor: AppTheme.darkSurface,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: _buildStepContent(isJapanese, accentColor),
              ),
            ),
            const SizedBox(height: 16),
            _buildNavigationBottomBar(accentColor),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(bool isJapanese, Color accentColor) {
    _selectContentSlot(_currentStep >= 5 ? 1 : 0);
    switch (_currentStep) {
      case 0:
        return _buildTipsAndTricks(isJapanese, accentColor);
      case 1:
      case 5:
        return _buildReadingSection(isJapanese, accentColor);
      case 2:
      case 6:
        return _buildWritingSection(isJapanese, accentColor);
      case 3:
      case 7:
        return _buildSpeakingSection(isJapanese, accentColor);
      default:
        return _buildListeningSection(isJapanese, accentColor);
    }
  }

  // ================= STEP 0: TIPS & TRICKS =================
  Widget _buildTipsAndTricks(bool isJapanese, Color accentColor) {
    final title = isJapanese ? 'Strategi Sukses JLPT' : 'Strategi Sukses IELTS';
    final tipsList = isJapanese
        ? [
            'Fokus pada Radikal Kanji: Membantu memahami makna kata baru secara intuitif.',
            'Perhatikan Partikel (は, が, に): Kunci penting memahami subjek & hubungan kalimat.',
            'Skimming saat Reading: Jangan membaca kata per kata, temukan kata kunci utama.',
            'Catat Informasi Penting Listening: Perhatikan kata tanya (siapa, di mana, kapan).'
          ]
        : [
            'Pomodoro Study Strategy: Latih fokus 25 menit per sesi untuk meningkatkan retensi.',
            'Read Instructions Carefully: Pastikan jumlah kata (e.g. NO MORE THAN TWO WORDS).',
            'Paraphrase in Writing: Gunakan sinonim untuk menunjukkan penguasaan kosakata luas.',
            'Fluency in Speaking: Bicara terus tanpa sering berhenti meski ada kesalahan kecil.'
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lightbulb, color: accentColor, size: 28),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Sebelum memulai latihan harian, baca tips & trik berikut untuk membantu efisiensi belajar Anda:',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        ...tipsList.map((tip) => Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppTheme.textSecondary.withOpacity(0.1)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💡',
                      style: TextStyle(fontSize: 20, color: accentColor)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tip,
                      style: const TextStyle(
                          fontSize: 15,
                          color: AppTheme.textPrimary,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  // ================= STEP 1: READING MODULE =================
  Widget _buildReadingSection(bool isJapanese, Color accentColor) {
    if (_readingData == null) return const SizedBox();

    final questions = jsonDecode(_readingData!['questions']) as List<dynamic>;
    if (questions.isEmpty) return const SizedBox();

    final questionObj = questions[0];
    final options = questionObj['options'] as List<dynamic>;
    final int correctAnswerIndex = questionObj['correct_answer_index'] as int;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            _currentStep >= 5
                ? 'REVIEW HARI SEBELUMNYA: MEMBACA'
                : 'MODUL 1: MEMBACA (READING)',
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        Text(_readingData!['title'],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.textSecondary.withOpacity(0.1)),
          ),
          child: Text(
            _readingData!['passage'],
            style: const TextStyle(
                fontSize: 16, height: 1.6, color: AppTheme.textPrimary),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Terjemahan: ${_readingData!['translation']}',
          style: const TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 24),
        Text(
          questionObj['question'],
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...List.generate(options.length, (index) {
          final isSelected = _selectedReadAnswerIndex == index;
          Color borderCol = isSelected
              ? accentColor
              : AppTheme.textSecondary.withOpacity(0.2);
          if (_hasCheckedRead) {
            if (index == correctAnswerIndex)
              borderCol = AppTheme.neonGreen;
            else if (isSelected) borderCol = AppTheme.neonPink;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                side: BorderSide(color: borderCol, width: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                backgroundColor: isSelected
                    ? accentColor.withOpacity(0.05)
                    : Colors.transparent,
              ),
              onPressed: _hasCheckedRead
                  ? null
                  : () {
                      setState(() {
                        _selectedReadAnswerIndex = index;
                      });
                    },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  options[index].toString(),
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ================= STEP 2: WRITING MODULE =================
  Widget _buildWritingSection(bool isJapanese, Color accentColor) {
    if (_writingData == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            _currentStep >= 5
                ? 'REVIEW HARI SEBELUMNYA: MENULIS'
                : 'MODUL 2: MENULIS (WRITING)',
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        const Text('Latihan Menulis Esai Pendek',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accentColor.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Topik: ${_writingData!['prompt']}',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 10),
              Text(
                'Tips: ${_writingData!['tips']}',
                style: const TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _writingController,
          maxLines: 8,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Tulis esai Anda di sini (Mulai dari 30-50 kata)...',
            hintStyle:
                TextStyle(color: AppTheme.textSecondary.withOpacity(0.5)),
            filled: true,
            fillColor: AppTheme.darkSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  BorderSide(color: AppTheme.textSecondary.withOpacity(0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: accentColor),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Jumlah Kata: $_wordCount kata',
              style: TextStyle(
                  color: _wordCount >= 20
                      ? AppTheme.neonGreen
                      : AppTheme.textSecondary,
                  fontWeight: FontWeight.bold),
            ),
            const Text('Saran minimum: 20 kata',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  // ================= STEP 3: SPEAKING MODULE =================
  Widget _buildSpeakingSection(bool isJapanese, Color accentColor) {
    if (_speakingData == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            _currentStep >= 5
                ? 'REVIEW HARI SEBELUMNYA: BERBICARA'
                : 'MODUL 3: BERBICARA (SPEAKING)',
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        const Text('Latihan Shadowing & Pelafalan',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.textSecondary.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Topik: ${_speakingData!['topic']}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Tips: ${_speakingData!['tips']}',
                style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _isRecording
                    ? null
                    : () => _simulateSpeakingRecord(_speakingData!['topic']),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? AppTheme.neonPink.withOpacity(0.2)
                        : accentColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isRecording ? AppTheme.neonPink : accentColor,
                      width: 3,
                    ),
                  ),
                  child: Icon(
                    _isRecording ? Icons.mic : Icons.mic_none,
                    color: _isRecording ? AppTheme.neonPink : accentColor,
                    size: 42,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isRecording
                    ? '🎙️ Sedang Merekam...'
                    : 'Ketuk mikrofon untuk melatih berbicara',
                style: TextStyle(
                  color:
                      _isRecording ? AppTheme.neonPink : AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_hasSpoken) ...[
                const SizedBox(height: 24),
                const Text('✅ Pelafalan Anda Terdeteksi Baik (Akurasi: 96.4%)',
                    style: TextStyle(
                        color: AppTheme.neonGreen,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('"${_spokenText}"',
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontStyle: FontStyle.italic)),
              ]
            ],
          ),
        ),
      ],
    );
  }

  // ================= STEP 4: LISTENING MODULE =================
  Widget _buildListeningSection(bool isJapanese, Color accentColor) {
    if (_listeningData == null) return const SizedBox();

    final questions = jsonDecode(_listeningData!['questions']) as List<dynamic>;
    if (questions.isEmpty) return const SizedBox();

    final questionObj = questions[0];
    final options = questionObj['options'] as List<dynamic>;
    final int correctAnswerIndex = questionObj['correct_answer_index'] as int;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            _currentStep >= 5
                ? 'REVIEW HARI SEBELUMNYA: MENDENGARKAN'
                : 'MODUL 4: MENDENGARKAN (LISTENING)',
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        Text(_listeningData!['title'],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        const Text(
          'Tekan tombol speaker untuk mendengarkan audio transkrip ujian resmi, kemudian jawab pertanyaan berikut:',
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: _isSpeakingPlaying
                ? null
                : () => _speak(_listeningData!['transcript']),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _isSpeakingPlaying
                    ? accentColor.withOpacity(0.3)
                    : accentColor.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: accentColor, width: 2),
              ),
              child: Icon(
                _isSpeakingPlaying ? Icons.volume_up : Icons.volume_mute,
                color: accentColor,
                size: 36,
              ),
            ),
          ),
        ),
        const SizedBox(height: 36),
        Text(
          questionObj['question'],
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...List.generate(options.length, (index) {
          final isSelected = _selectedListenAnswerIndex == index;
          Color borderCol = isSelected
              ? accentColor
              : AppTheme.textSecondary.withOpacity(0.2);
          if (_hasCheckedListen) {
            if (index == correctAnswerIndex)
              borderCol = AppTheme.neonGreen;
            else if (isSelected) borderCol = AppTheme.neonPink;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                side: BorderSide(color: borderCol, width: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                backgroundColor: isSelected
                    ? accentColor.withOpacity(0.05)
                    : Colors.transparent,
              ),
              onPressed: _hasCheckedListen
                  ? null
                  : () {
                      setState(() {
                        _selectedListenAnswerIndex = index;
                      });
                    },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  options[index].toString(),
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ================= NAVIGATION BOTTOM BAR =================
  Widget _buildNavigationBottomBar(Color accentColor) {
    if (_currentStep == 0) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: AppTheme.darkBackground,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            ),
            onPressed: () {
              _goToStep(1);
            },
            child: const Text('Mulai Latihan Ujian',
                style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      );
    } else if (_currentStep == 1 || _currentStep == 5) {
      final bool canCheck = _selectedReadAnswerIndex != -1;
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: canCheck ? accentColor : AppTheme.darkSurface,
              foregroundColor: AppTheme.darkBackground,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            onPressed: !canCheck
                ? null
                : () {
                    if (!_hasCheckedRead) {
                      setState(() {
                        _hasCheckedRead = true;
                      });
                    } else {
                      _goToStep(_currentStep + 1);
                    }
                  },
            child: Text(
              _hasCheckedRead ? 'Lanjut' : 'Periksa',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          )
        ],
      );
    } else if (_currentStep == 2 || _currentStep == 6) {
      final bool canCheck = _wordCount >= 10;
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: canCheck ? accentColor : AppTheme.darkSurface,
              foregroundColor: AppTheme.darkBackground,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            onPressed: !canCheck
                ? null
                : () {
                    _goToStep(_currentStep + 1);
                  },
            child: const Text('Lanjut',
                style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      );
    } else if (_currentStep == 3 || _currentStep == 7) {
      final bool canCheck = _hasSpoken;
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: canCheck ? accentColor : AppTheme.darkSurface,
              foregroundColor: AppTheme.darkBackground,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            onPressed: !canCheck
                ? null
                : () {
                    _goToStep(_currentStep + 1);
                  },
            child: const Text('Lanjut',
                style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      );
    } else {
      final bool canCheck = _selectedListenAnswerIndex != -1;
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: canCheck ? accentColor : AppTheme.darkSurface,
              foregroundColor: AppTheme.darkBackground,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            onPressed: !canCheck
                ? null
                : () {
                    if (!_hasCheckedListen) {
                      setState(() {
                        _hasCheckedListen = true;
                      });
                    } else {
                      if (_currentStep < _totalSteps - 1) {
                        _goToStep(_currentStep + 1);
                      } else {
                        _finishExamSession();
                      }
                    }
                  },
            child: Text(
              _hasCheckedListen
                  ? (_currentStep < _totalSteps - 1
                      ? 'Lanjut Review'
                      : 'Selesai')
                  : 'Periksa',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          )
        ],
      );
    }
  }
}
