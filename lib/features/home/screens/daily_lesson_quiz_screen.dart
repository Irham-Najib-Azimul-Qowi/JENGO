import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/utils/custom_top_notification.dart';

enum QuestionType {
  multipleChoice,
  sentenceUnscramble,
  fillInBlank,
  matchingPairs,
  listening,
  typing,
  connectPairs
}

class QuizQuestion {
  final QuestionType type;
  final String questionText;
  final String wordPrompt;
  final String? readingPrompt; // Hiragana reading if applicable
  final String correctAnswer;
  final List<String> options;
  final List<String> wordPool;
  final Map<String, String> pairs; // For connecting pairs

  QuizQuestion({
    required this.type,
    required this.questionText,
    required this.wordPrompt,
    this.readingPrompt,
    required this.correctAnswer,
    this.options = const [],
    this.wordPool = const [],
    this.pairs = const {},
  });
}

class DailyLessonQuizScreen extends StatefulWidget {
  final String language;
  final List<dynamic>? vocabList;
  final int stage;
  final int day;

  const DailyLessonQuizScreen({
    super.key,
    required this.language,
    this.vocabList,
    this.stage = 1,
    this.day = 1,
  });

  @override
  State<DailyLessonQuizScreen> createState() => _DailyLessonQuizScreenState();
}

class _DailyLessonQuizScreenState extends State<DailyLessonQuizScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  
  bool _isLoading = true;
  List<QuizQuestion> _questions = [];
  int _currentStep = 0;

  // State for user answers
  int _selectedChoiceIndex = -1; // Multiple Choice & Listening
  List<String> _unscrambleSelection = []; // Sentence Unscramble
  List<String> _unscramblePool = [];
  String _typedAnswer = ""; // Typing & Fill-in-blanks
  String _connectSelectedLeft = ""; // Connect Pairs State
  String _connectSelectedRight = "";
  Map<String, String> _connectPairsAnswers = {}; // Connected pairs so far

  // Evaluation States
  bool _hasAnswered = false;
  bool _isCorrect = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    if (widget.language == 'JAPANESE') {
      await _flutterTts.setLanguage("ja-JP");
    } else {
      await _flutterTts.setLanguage("en-US");
    }
    await _flutterTts.speak(text);
  }

  Future<void> _loadQuestions() async {
    final db = await DatabaseHelper.instance.database;
    List<Map<String, dynamic>> vocabItems = [];

    if (widget.vocabList != null && widget.vocabList!.isNotEmpty) {
      vocabItems = List<Map<String, dynamic>>.from(widget.vocabList!);
    } else {
      // Fallback query from vocabulary table
      final listQuery = await db.query(
        'vocabulary',
        where: 'language = ?',
        whereArgs: [widget.language],
        limit: 15,
      );
      vocabItems = List<Map<String, dynamic>>.from(listQuery);
    }

    if (vocabItems.isEmpty) {
      // Return fallback dummy questions if no vocabulary database rows
      _generateFallbackQuestions();
      return;
    }

    vocabItems.shuffle();
    final List<QuizQuestion> generatedQuestions = [];
    final rand = Random();

    for (int i = 0; i < min(vocabItems.length, 6); i++) {
      final item = vocabItems[i];
      final String word = item['word']?.toString() ?? '';
      if (word.trim().isEmpty) continue;
      final String reading = item['reading'] ?? '';
      final String translation = item['translation'] ?? item['meaning'] ?? '';
      final isJp = widget.language == 'JAPANESE';

      // Pick a type dynamically
      final qType = QuestionType.values[i % QuestionType.values.length];

      switch (qType) {
        case QuestionType.multipleChoice:
          // MC Option generation
          List<String> opts = [translation];
          for (var other in vocabItems) {
            if (other['translation'] != translation && opts.length < 4) {
              opts.add(other['translation']);
            }
          }
          while (opts.length < 4) {
            opts.add("Pilihan Palsu ${opts.length}");
          }
          opts.shuffle();

          generatedQuestions.add(QuizQuestion(
            type: QuestionType.multipleChoice,
            questionText: 'Pilihlah arti kata yang tepat untuk kata berikut:',
            wordPrompt: word,
            readingPrompt: isJp ? reading : null,
            correctAnswer: translation,
            options: opts,
          ));
          break;

        case QuestionType.sentenceUnscramble:
          // Dapatkan kalimat acak dengan sangat cepat menggunakan pencarian ID acak
          String targetSentence = translation;
          String unscramblePrompt = word;

          try {
            final maxIdResult = await db.rawQuery('SELECT MAX(id) as max_id FROM sentences');
            final maxId = (maxIdResult.first['max_id'] as int?) ?? 0;
            if (maxId > 0) {
              final randomId = rand.nextInt(maxId) + 1;
              final sentences = await db.query(
                'sentences',
                where: 'id = ?',
                whereArgs: [randomId],
                limit: 1,
              );
              if (sentences.isNotEmpty) {
                targetSentence = sentences.first['indonesian'] as String;
                unscramblePrompt = isJp 
                    ? sentences.first['japanese'] as String 
                    : sentences.first['english'] as String;
              }
            }
          } catch (e) {
            debugPrint("Error loading random sentence: $e");
          }

          List<String> pool = targetSentence.split(' ')..shuffle();

          generatedQuestions.add(QuizQuestion(
            type: QuestionType.sentenceUnscramble,
            questionText: 'Susun kata-kata berikut menjadi terjemahan kalimat yang tepat:',
            wordPrompt: unscramblePrompt,
            correctAnswer: targetSentence,
            wordPool: pool,
          ));
          break;

        case QuestionType.fillInBlank:
          // Blank character replacement
          String wordWithBlank = word;
          String charToFill = "";
          if (word.length > 2) {
            int blankIndex = rand.nextInt(word.length);
            charToFill = word[blankIndex];
            wordWithBlank = word.replaceRange(blankIndex, blankIndex + 1, " __ ");
          } else {
            charToFill = word;
            wordWithBlank = " __ ";
          }

          generatedQuestions.add(QuizQuestion(
            type: QuestionType.fillInBlank,
            questionText: 'Lengkapi karakter huruf yang hilang dari kata berikut (Petunjuk: "$translation"):',
            wordPrompt: wordWithBlank,
            correctAnswer: charToFill,
          ));
          break;

        case QuestionType.matchingPairs:
        case QuestionType.connectPairs:
          // Connecting pairs using 4 random items
          final Map<String, String> pairMap = {};
          for (int j = 0; j < min(vocabItems.length, 4); j++) {
            pairMap[vocabItems[j]['word']] = vocabItems[j]['translation'];
          }

          generatedQuestions.add(QuizQuestion(
            type: QuestionType.connectPairs,
            questionText: 'Hubungkan pasangan kata yang tepat berikut ini:',
            wordPrompt: '',
            correctAnswer: '',
            pairs: pairMap,
          ));
          break;

        case QuestionType.listening:
          // Listening MCQ
          List<String> opts = [translation];
          for (var other in vocabItems) {
            if (other['translation'] != translation && opts.length < 4) {
              opts.add(other['translation']);
            }
          }
          while (opts.length < 4) {
            opts.add("Pilihan Palsu ${opts.length}");
          }
          opts.shuffle();

          // Stage based Japanese Rules
          String listenPrompt = word;
          String? readingLabel = isJp ? reading : null;
          if (isJp && widget.stage > 2) {
            // Hide Romaji and translations for high levels
            readingLabel = null;
          }

          generatedQuestions.add(QuizQuestion(
            type: QuestionType.listening,
            questionText: 'Dengarkan suara audio dan pilih arti kata yang tepat:',
            wordPrompt: listenPrompt,
            readingPrompt: readingLabel,
            correctAnswer: translation,
            options: opts,
          ));
          break;

        case QuestionType.typing:
          generatedQuestions.add(QuizQuestion(
            type: QuestionType.typing,
            questionText: 'Ketiklah arti terjemahan dari kata berikut:',
            wordPrompt: word,
            readingPrompt: isJp ? reading : null,
            correctAnswer: translation,
          ));
          break;
      }
    }

    if (mounted) {
      setState(() {
        _questions = generatedQuestions.isNotEmpty ? generatedQuestions : _getFallbackQuestionsList();
        _isLoading = false;
      });
      // Auto speak first listening question if active
      _triggerAutoSpeak();
    }
  }

  void _generateFallbackQuestions() {
    setState(() {
      _questions = _getFallbackQuestionsList();
      _isLoading = false;
    });
  }

  List<QuizQuestion> _getFallbackQuestionsList() {
    final isJp = widget.language == 'JAPANESE';
    return [
      QuizQuestion(
        type: QuestionType.multipleChoice,
        questionText: 'Pilihlah arti kata yang tepat untuk kata berikut:',
        wordPrompt: isJp ? '先生' : 'Apple',
        readingPrompt: isJp ? 'せんせい' : null,
        correctAnswer: 'Guru/Apel',
        options: ['Guru/Apel', 'Buku', 'Meja', 'Rumah'],
      ),
      QuizQuestion(
        type: QuestionType.typing,
        questionText: 'Ketiklah arti terjemahan dari kata berikut:',
        wordPrompt: isJp ? '車' : 'Car',
        readingPrompt: isJp ? 'くるま' : null,
        correctAnswer: 'Mobil',
      )
    ];
  }

  void _triggerAutoSpeak() {
    if (_questions.isEmpty || _currentStep >= _questions.length) return;
    final currentQ = _questions[_currentStep];
    if (currentQ.type == QuestionType.listening) {
      _speak(currentQ.wordPrompt);
    }
  }

  void _unscrambleTapWord(String word) {
    if (_hasAnswered) return;
    setState(() {
      if (_unscrambleSelection.contains(word)) {
        _unscrambleSelection.remove(word);
        _unscramblePool.add(word);
      } else {
        _unscrambleSelection.add(word);
        _unscramblePool.remove(word);
      }
    });
  }

  void _connectTapItem(String term, bool isLeft) {
    if (_hasAnswered) return;
    setState(() {
      if (isLeft) {
        _connectSelectedLeft = term;
      } else {
        _connectSelectedRight = term;
      }

      // Check pair match
      if (_connectSelectedLeft.isNotEmpty && _connectSelectedRight.isNotEmpty) {
        final currentQ = _questions[_currentStep];
        final expectedRight = currentQ.pairs[_connectSelectedLeft];

        if (expectedRight == _connectSelectedRight) {
          _connectPairsAnswers[_connectSelectedLeft] = _connectSelectedRight;
        } else {
          CustomTopNotification.show(context, message: 'Pasangan tidak cocok, silakan coba lagi.', isError: true);
        }

        _connectSelectedLeft = "";
        _connectSelectedRight = "";
      }
    });
  }

  void _checkAnswer() {
    if (_questions.isEmpty || _currentStep >= _questions.length) return;
    final currentQ = _questions[_currentStep];
    bool correct = false;

    switch (currentQ.type) {
      case QuestionType.multipleChoice:
      case QuestionType.listening:
        if (_selectedChoiceIndex != -1) {
          correct = currentQ.options[_selectedChoiceIndex] == currentQ.correctAnswer;
        }
        break;

      case QuestionType.sentenceUnscramble:
        final userString = _unscrambleSelection.join(' ').trim().toLowerCase();
        final correctString = currentQ.correctAnswer.trim().toLowerCase();
        correct = userString == correctString;
        break;

      case QuestionType.fillInBlank:
        correct = _typedAnswer.trim().toLowerCase() == currentQ.correctAnswer.trim().toLowerCase();
        break;

      case QuestionType.typing:
        correct = _typedAnswer.trim().toLowerCase() == currentQ.correctAnswer.trim().toLowerCase();
        break;

      case QuestionType.connectPairs:
        correct = _connectPairsAnswers.length == currentQ.pairs.length;
        break;

      default:
        correct = false;
    }

    setState(() {
      _hasAnswered = true;
      _isCorrect = correct;
    });

    if (correct) {
      _speak(currentQ.wordPrompt);
    }
  }

  void _nextStep() {
    if (_currentStep < _questions.length - 1) {
      setState(() {
        _currentStep++;
        _hasAnswered = false;
        _isCorrect = false;
        _selectedChoiceIndex = -1;
        _typedAnswer = "";
        _unscrambleSelection = [];
        _connectPairsAnswers = {};
        _connectSelectedLeft = "";
        _connectSelectedRight = "";
      });

      // Prepare unscramble pools
      final currentQ = _questions[_currentStep];
      if (currentQ.type == QuestionType.sentenceUnscramble) {
        _unscramblePool = List<String>.from(currentQ.wordPool);
      }

      _triggerAutoSpeak();
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final db = await DatabaseHelper.instance.database;
    final userList = await db.query('gamification', limit: 1);
    if (userList.isNotEmpty) {
      final user = userList.first;
      final currentXp = user['total_xp'] as int? ?? 0;
      final currentGems = user['gems'] as int? ?? 50;

      await db.update(
        'gamification',
        {
          'total_xp': currentXp + 50,
          'gems': currentGems + 10,
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
            Icon(Icons.emoji_events, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text('Latihan Tuntas!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hebat! Seluruh kuis latihan harian interaktif Duolingo-style telah selesai.'),
            const SizedBox(height: 12),
            const Text('🏆 XP Belajar: +50 XP', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.neonGreen)),
            const Text('💎 Hadiah Permata: +10 Gems', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.neonBlue)),
            const SizedBox(height: 16),
            Text(
              'Langkah berikutnya: Selesaikan Sesi Latihan Rutin ${widget.language == 'JAPANESE' ? 'JLPT' : 'IELTS'} Anda!',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonGreen),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(
                context,
                '/daily_mock_practice',
                arguments: {
                  'language': widget.language,
                  'stage': widget.stage,
                  'day': widget.day,
                },
              );
            },
            child: const Text('Mulai Sesi Ujian Harian', style: TextStyle(color: AppTheme.darkBackground, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.neonBlue)),
      );
    }

    final currentQ = _questions[_currentStep];
    final progress = _currentStep / _questions.length;
    final isJp = widget.language == 'JAPANESE';
    final accentColor = isJp ? AppTheme.neonBlue : AppTheme.neonGreen;

    // Initialize unscramble pool if not done
    if (currentQ.type == QuestionType.sentenceUnscramble && _unscramblePool.isEmpty && _unscrambleSelection.isEmpty) {
      _unscramblePool = List<String>.from(currentQ.wordPool);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Latihan Harian: ${isJp ? 'Jepang' : 'Inggris'}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: AppTheme.darkSurface,
                  color: accentColor,
                ),
              ),
            ),
            
            // Question Counter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Soal ${_currentStep + 1} dari ${_questions.length}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentQ.questionText,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 16),
                    _buildQuestionInterface(currentQ, accentColor),
                  ],
                ),
              ),
            ),

            // Bottom Feedback Overlay or Verify Button
            _buildActionBottomPanel(currentQ, accentColor),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionInterface(QuizQuestion q, Color color) {
    switch (q.type) {
      case QuestionType.multipleChoice:
        return _buildMultipleChoiceView(q, color);
      case QuestionType.sentenceUnscramble:
        return _buildSentenceUnscrambleView(q, color);
      case QuestionType.fillInBlank:
        return _buildFillInBlankView(q, color);
      case QuestionType.connectPairs:
        return _buildConnectPairsView(q, color);
      case QuestionType.listening:
        return _buildListeningView(q, color);
      case QuestionType.typing:
        return _buildTypingView(q, color);
      default:
        return const SizedBox();
    }
  }

  Widget _buildMultipleChoiceView(QuizQuestion q, Color color) {
    final showReading = q.readingPrompt != null && q.readingPrompt!.isNotEmpty;

    return Column(
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Text(
                  q.wordPrompt,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                if (showReading) ...[
                  const SizedBox(height: 8),
                  Text(
                    '(${q.readingPrompt})',
                    style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        ...List.generate(q.options.length, (idx) {
          final isSelected = _selectedChoiceIndex == idx;
          final optText = q.options[idx];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: isSelected ? color : AppTheme.textSecondary.withOpacity(0.1), width: 2),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: isSelected ? color.withOpacity(0.08) : Colors.transparent,
              ),
              onPressed: _hasAnswered ? null : () => setState(() => _selectedChoiceIndex = idx),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  optText,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSentenceUnscrambleView(QuizQuestion q, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              q.wordPrompt,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Selection Area
        Container(
          constraints: const BoxConstraints(minHeight: 80),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.darkBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _unscrambleSelection.map((w) {
              return ActionChip(
                backgroundColor: color.withOpacity(0.2),
                label: Text(w, style: const TextStyle(color: Colors.white)),
                onPressed: _hasAnswered ? null : () => _unscrambleTapWord(w),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),
        // Pool Area
        const Text('Pilih kata-kata untuk menyusun kalimat:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _unscramblePool.map((w) {
            return ActionChip(
              backgroundColor: AppTheme.darkSurface,
              label: Text(w, style: const TextStyle(color: AppTheme.textPrimary)),
              onPressed: _hasAnswered ? null : () => _unscrambleTapWord(w),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFillInBlankView(QuizQuestion q, Color color) {
    return Column(
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              q.wordPrompt,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2),
            ),
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Ketik karakter yang hilang...',
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: color, width: 2)),
          ),
          style: const TextStyle(fontSize: 18, color: AppTheme.textPrimary),
          onChanged: (val) {
            _typedAnswer = val;
          },
          enabled: !_hasAnswered,
        ),
      ],
    );
  }

  Widget _buildConnectPairsView(QuizQuestion q, Color color) {
    final leftList = q.pairs.keys.toList()..sort();
    final rightList = q.pairs.values.toList()..shuffle();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column
        Expanded(
          child: Column(
            children: leftList.map((term) {
              final isMatched = _connectPairsAnswers.containsKey(term);
              final isSelected = _connectSelectedLeft == term;
              Color border = isMatched ? AppTheme.neonGreen : (isSelected ? color : AppTheme.textSecondary.withOpacity(0.1));

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: border, width: 2),
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isMatched || _hasAnswered ? null : () => _connectTapItem(term, true),
                  child: Text(term, style: const TextStyle(color: AppTheme.textPrimary)),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 16),
        // Right Column
        Expanded(
          child: Column(
            children: rightList.map((trans) {
              final isMatched = _connectPairsAnswers.containsValue(trans);
              final isSelected = _connectSelectedRight == trans;
              Color border = isMatched ? AppTheme.neonGreen : (isSelected ? color : AppTheme.textSecondary.withOpacity(0.1));

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: border, width: 2),
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isMatched || _hasAnswered ? null : () => _connectTapItem(trans, false),
                  child: Text(trans, style: const TextStyle(color: AppTheme.textPrimary)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildListeningView(QuizQuestion q, Color color) {
    return Column(
      children: [
        Center(
          child: InkWell(
            onTap: () => _speak(q.wordPrompt),
            borderRadius: BorderRadius.circular(50),
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2.5),
              ),
              child: Icon(Icons.volume_up, color: color, size: 40),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Ketuk tombol suara untuk memutar ulang audio',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 32),
        // Choices
        ...List.generate(q.options.length, (idx) {
          final isSelected = _selectedChoiceIndex == idx;
          final optText = q.options[idx];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: isSelected ? color : AppTheme.textSecondary.withOpacity(0.1), width: 2),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: isSelected ? color.withOpacity(0.08) : Colors.transparent,
              ),
              onPressed: _hasAnswered ? null : () => setState(() => _selectedChoiceIndex = idx),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  optText,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTypingView(QuizQuestion q, Color color) {
    return Column(
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              q.wordPrompt,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Ketik arti kata di sini...',
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: color, width: 2)),
          ),
          style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
          onChanged: (val) {
            _typedAnswer = val;
          },
          enabled: !_hasAnswered,
        ),
      ],
    );
  }

  Widget _buildActionBottomPanel(QuizQuestion q, Color color) {
    if (!_hasAnswered) {
      // Show check button
      bool canCheck = false;
      if (q.type == QuestionType.multipleChoice || q.type == QuestionType.listening) {
        canCheck = _selectedChoiceIndex != -1;
      } else if (q.type == QuestionType.typing || q.type == QuestionType.fillInBlank) {
        canCheck = _typedAnswer.isNotEmpty;
      } else if (q.type == QuestionType.sentenceUnscramble) {
        canCheck = _unscrambleSelection.isNotEmpty;
      } else if (q.type == QuestionType.connectPairs) {
        canCheck = true; // Always allow check match progress
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          border: Border(top: BorderSide(color: AppTheme.textSecondary.withOpacity(0.1))),
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: canCheck ? color : AppTheme.textSecondary.withOpacity(0.2),
            foregroundColor: AppTheme.darkBackground,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: canCheck ? _checkAnswer : null,
          child: const Text('PERIKSA JAWABAN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      );
    }

    // Evaluation panel visible
    final feedColor = _isCorrect ? AppTheme.neonGreen : AppTheme.neonPink;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: feedColor.withOpacity(0.12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(_isCorrect ? Icons.check_circle : Icons.error, color: feedColor, size: 28),
              const SizedBox(width: 12),
              Text(
                _isCorrect ? 'Jawaban Anda Benar!' : 'Jawaban Kurang Tepat',
                style: TextStyle(fontWeight: FontWeight.bold, color: feedColor, fontSize: 16),
              ),
            ],
          ),
          if (!_isCorrect) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Kunci jawaban tepat: ${q.correctAnswer}',
                style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: feedColor,
                foregroundColor: AppTheme.darkBackground,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _nextStep,
              child: const Text('LANJUTKAN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
