import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/utils/kana_helper.dart';
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
  final bool isSkippingQuiz;

  const DailyLessonQuizScreen({
    super.key,
    required this.language,
    this.vocabList,
    this.stage = 1,
    this.day = 1,
    this.isSkippingQuiz = false,
  });

  @override
  State<DailyLessonQuizScreen> createState() => _DailyLessonQuizScreenState();
}

class _DailyLessonQuizScreenState extends State<DailyLessonQuizScreen> {
  final FlutterTts _flutterTts = FlutterTts();

  bool _isLoading = true;
  List<QuizQuestion> _questions = [];
  int _currentStep = 0;
  int _correctCount = 0; // Tracks the user's score

  // State for user answers
  int _selectedChoiceIndex = -1; // Multiple Choice & Listening
  List<String> _unscrambleSelection = []; // Sentence Unscramble
  List<String> _unscramblePool = [];
  final TextEditingController _typingController =
      TextEditingController(); // Typing & Fill-in-blanks
  String _typedAnswer = "";
  String _connectSelectedLeft = ""; // Connect Pairs State
  String _connectSelectedRight = "";
  Map<String, String> _connectPairsAnswers = {}; // Connected pairs so far

  // Evaluation States
  bool _hasAnswered = false;
  bool _isCorrect = false;

  // Stable Connect Pairs items to prevent rearranging on builds
  List<String> _connectLeftItems = [];
  List<String> _connectRightItems = [];

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _typingController.dispose();
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

    if (widget.isSkippingQuiz) {
      final targetStage = widget.stage;
      List<String> diffLevels = [];
      if (widget.language == 'JAPANESE') {
        if (targetStage > 1) diffLevels.add('HIRAGANA');
        if (targetStage > 4) diffLevels.add('KATAKANA');
        if (targetStage > 7) diffLevels.add('N5');
        if (targetStage > 17) diffLevels.add('N4');
        if (targetStage > 18) diffLevels.add('N3');
        if (targetStage > 18) {
          diffLevels.add('N2');
        }
      } else {
        if (targetStage > 1) diffLevels.add('A1');
        if (targetStage > 2) diffLevels.add('A2');
        if (targetStage > 4) diffLevels.add('B1');
        if (targetStage > 6) diffLevels.add('B2');
        if (targetStage > 12) diffLevels.add('C1');
      }

      if (diffLevels.isEmpty) {
        diffLevels = widget.language == 'JAPANESE' ? ['HIRAGANA'] : ['A1'];
      }

      String placeholders = List.filled(diffLevels.length, '?').join(', ');
      final listQuery = await db.query(
        'vocabulary',
        where: 'language = ? AND difficulty_level IN ($placeholders)',
        whereArgs: [widget.language, ...diffLevels],
        orderBy: 'RANDOM()',
        limit: 15,
      );
      vocabItems = List<Map<String, dynamic>>.from(listQuery);
    } else if (widget.vocabList != null && widget.vocabList!.isNotEmpty) {
      vocabItems = List<Map<String, dynamic>>.from(widget.vocabList!);
    } else {
      // Fallback query from vocabulary table, scoped to this stage curriculum.
      final stageLevels =
          _difficultyLevelsForStage(widget.language, widget.stage);
      final placeholders = List.filled(stageLevels.length, '?').join(', ');
      final listQuery = await db.query(
        'vocabulary',
        where: 'language = ? AND difficulty_level IN ($placeholders)',
        whereArgs: [widget.language, ...stageLevels],
        orderBy: 'RANDOM()',
        limit: 15,
      );
      vocabItems = List<Map<String, dynamic>>.from(listQuery);
    }

    // CRITICAL: Filter out vocab items with empty word or translation
    vocabItems = vocabItems.where((v) {
      final w = (v['word'] ?? '').toString().trim();
      final t = (v['translation'] ?? v['meaning'] ?? '').toString().trim();
      return w.isNotEmpty && t.isNotEmpty;
    }).toList();

    if (vocabItems.isEmpty) {
      // Return fallback dummy questions if no vocabulary database rows
      _generateFallbackQuestions();
      return;
    }

    vocabItems.shuffle();
    final List<QuizQuestion> generatedQuestions = [];
    final rand = Random();

    final int totalQuestionsLimit = widget.isSkippingQuiz ? 15 : 6;

    for (int i = 0; i < min(vocabItems.length, totalQuestionsLimit); i++) {
      final item = vocabItems[i];
      final String word = item['word']?.toString() ?? '';
      if (word.trim().isEmpty) continue;
      final String reading = item['reading'] ?? '';
      final String translation = item['translation'] ?? item['meaning'] ?? '';
      final isJp = widget.language == 'JAPANESE';
      final isKanaFoundation = isJp && widget.stage <= 6;
      final readingForPrompt = isJp
          ? (reading.isNotEmpty
              ? reading
              : (isKanaFoundation ? KanaHelper.toRomaji(word) : ''))
          : null;

      // Pick a type dynamically. Kana foundation stays choice-based and simple.
      QuestionType qType;
      if (isKanaFoundation) {
        final kanaTypes = [
          QuestionType.multipleChoice,
          QuestionType.listening,
          QuestionType.connectPairs,
        ];
        qType = kanaTypes[i % kanaTypes.length];
      } else if (widget.stage <= 12) {
        final begTypes = [
          QuestionType.multipleChoice,
          QuestionType.listening,
          QuestionType.connectPairs,
          QuestionType.fillInBlank
        ];
        qType = begTypes[i % begTypes.length];
      } else {
        qType = QuestionType.values[i % QuestionType.values.length];
      }

      switch (qType) {
        case QuestionType.multipleChoice:
          // MC Option generation
          List<String> opts = [translation];
          for (var other in vocabItems) {
            final ot = (other['translation'] ?? other['meaning'] ?? '')
                .toString()
                .trim();
            if (ot != translation && ot.isNotEmpty && opts.length < 4) {
              opts.add(ot);
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
            readingPrompt: readingForPrompt,
            correctAnswer: translation,
            options: opts,
          ));
          break;

        case QuestionType.sentenceUnscramble:
          // Dapatkan kalimat acak dengan sangat cepat menggunakan pencarian ID acak
          String targetSentence = translation;
          String unscramblePrompt = word;

          try {
            final maxIdResult =
                await db.rawQuery('SELECT MAX(id) as max_id FROM sentences');
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
            questionText:
                'Susun kata-kata berikut menjadi terjemahan kalimat yang tepat:',
            wordPrompt: unscramblePrompt,
            correctAnswer: targetSentence,
            wordPool: pool,
          ));
          break;

        case QuestionType.fillInBlank:
          // For fill-in-blank, build 4 choices including the correct answer
          String wordWithBlank = '___';
          String charToFill = word;

          // Cari contoh kalimat yang mengandung kata ini dari database
          try {
            final sentRows = await db.query(
              'sentences',
              where: isJp ? 'japanese LIKE ?' : 'english LIKE ?',
              whereArgs: ['%$word%'],
              limit: 1,
            );
            if (sentRows.isNotEmpty) {
              final contextSentence = isJp
                  ? sentRows.first['japanese'] as String
                  : sentRows.first['english'] as String;
              wordWithBlank = contextSentence.replaceFirst(word, '___');
              charToFill = word;
            }
          } catch (_) {}

          // Build 4 choice options (distractor words from same vocab set)
          List<String> fillOpts = [charToFill];
          for (var other in vocabItems) {
            final ow = (other['word'] ?? '').toString().trim();
            if (ow != charToFill && ow.isNotEmpty && fillOpts.length < 4) {
              fillOpts.add(ow);
            }
          }
          while (fillOpts.length < 4) fillOpts.add('？？？');
          fillOpts.shuffle();

          generatedQuestions.add(QuizQuestion(
            type: QuestionType.fillInBlank,
            questionText:
                'Pilih kata yang tepat untuk melengkapi kalimat berikut (Petunjuk: "$translation"):',
            wordPrompt: wordWithBlank,
            // NOTE: readingPrompt intentionally omitted to avoid leaking the answer
            correctAnswer: charToFill,
            options:
                fillOpts, // Always include options for choice-based rendering
          ));
          break;

        case QuestionType.matchingPairs:
        case QuestionType.connectPairs:
          // Connecting pairs using 4 random items — need at least 4 items
          if (vocabItems.length >= 4) {
            final Map<String, String> pairMap = {};
            final pairItems = List<Map<String, dynamic>>.from(vocabItems)
              ..shuffle();
            for (int j = 0; j < 4; j++) {
              final pWord = (pairItems[j]['word'] ?? '').toString().trim();
              final pTrans =
                  (pairItems[j]['translation'] ?? pairItems[j]['meaning'] ?? '')
                      .toString()
                      .trim();
              if (pWord.isNotEmpty && pTrans.isNotEmpty)
                pairMap[pWord] = pTrans;
            }
            if (pairMap.length >= 2) {
              generatedQuestions.add(QuizQuestion(
                type: QuestionType.connectPairs,
                questionText: 'Hubungkan pasangan kata yang tepat berikut ini:',
                wordPrompt: '',
                correctAnswer: '',
                pairs: pairMap,
              ));
            }
          } else {
            // Fallback to multiple choice if not enough vocab
            List<String> opts = [translation];
            for (var other in vocabItems) {
              final t2 = (other['translation'] ?? other['meaning'] ?? '')
                  .toString()
                  .trim();
              if (t2 != translation && t2.isNotEmpty && opts.length < 4)
                opts.add(t2);
            }
            while (opts.length < 4) opts.add('Pilihan ${opts.length}');
            opts.shuffle();
            generatedQuestions.add(QuizQuestion(
              type: QuestionType.multipleChoice,
              questionText: 'Pilihlah arti kata yang tepat untuk kata berikut:',
              wordPrompt: word,
              readingPrompt: readingForPrompt,
              correctAnswer: translation,
              options: opts,
            ));
          }
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
          String? readingLabel = readingForPrompt;
          if (isJp && widget.stage > 6) {
            // Hide Romaji and translations for high levels
            readingLabel = null;
          }

          generatedQuestions.add(QuizQuestion(
            type: QuestionType.listening,
            questionText:
                'Dengarkan suara audio dan pilih arti kata yang tepat:',
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
            readingPrompt: readingForPrompt,
            correctAnswer: translation,
          ));
          break;
      }
    }

    if (mounted) {
      setState(() {
        _questions = generatedQuestions.isNotEmpty
            ? generatedQuestions
            : _getFallbackQuestionsList();
        _isLoading = false;
      });
      // Initialize state for the first question
      if (_questions.isNotEmpty) {
        _initQuestionStateForStep(0);
      }
      // Auto speak first listening question if active
      _triggerAutoSpeak();
    }
  }

  List<String> _difficultyLevelsForStage(String language, int stage) {
    if (language == 'JAPANESE') {
      if (stage <= 3) return ['HIRAGANA'];
      if (stage <= 5) return ['KATAKANA'];
      if (stage == 6) return ['HIRAGANA', 'KATAKANA'];
      if (stage <= 16) return ['N5'];
      if (stage == 17) return ['N4'];
      if (stage == 18) return ['N3'];
      return ['N2'];
    }

    if (stage <= 2) return ['A1'];
    if (stage <= 4) return ['A2'];
    if (stage <= 6) return ['B1'];
    if (stage <= 12) return ['B2'];
    return ['C1'];
  }

  void _generateFallbackQuestions() {
    setState(() {
      _questions = _getFallbackQuestionsList();
      _isLoading = false;
    });
    if (_questions.isNotEmpty) {
      _initQuestionStateForStep(0);
    }
  }

  void _initQuestionStateForStep(int stepIndex) {
    if (stepIndex >= _questions.length) return;
    final q = _questions[stepIndex];
    if (q.type == QuestionType.sentenceUnscramble) {
      _unscramblePool = List<String>.from(q.wordPool);
      _unscrambleSelection = [];
    } else if (q.type == QuestionType.connectPairs) {
      _connectLeftItems = q.pairs.keys.toList()..shuffle();
      _connectRightItems = q.pairs.values.toList()..shuffle();
      _connectPairsAnswers = {};
      _connectSelectedLeft = "";
      _connectSelectedRight = "";
    }
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
          CustomTopNotification.show(context,
              message: 'Pasangan tidak cocok, silakan coba lagi.',
              isError: true);
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
          correct =
              currentQ.options[_selectedChoiceIndex] == currentQ.correctAnswer;
        }
        break;

      case QuestionType.sentenceUnscramble:
        final userString = _unscrambleSelection.join(' ').trim().toLowerCase();
        final correctString = currentQ.correctAnswer.trim().toLowerCase();
        correct = userString == correctString;
        break;

      case QuestionType.fillInBlank:
        // Choice-based (stages <= 12) uses selectedChoiceIndex; advanced uses typed answer
        if (widget.stage <= 12 && currentQ.options.isNotEmpty) {
          if (_selectedChoiceIndex != -1) {
            correct = currentQ.options[_selectedChoiceIndex] ==
                currentQ.correctAnswer;
          }
        } else {
          correct = _typedAnswer.trim().toLowerCase() ==
              currentQ.correctAnswer.trim().toLowerCase();
        }
        break;

      case QuestionType.typing:
        correct = _typedAnswer.trim().toLowerCase() ==
            currentQ.correctAnswer.trim().toLowerCase();
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
      _correctCount++;
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
        _typingController.clear();
        _unscrambleSelection = [];
        _connectPairsAnswers = {};
        _connectSelectedLeft = "";
        _connectSelectedRight = "";
      });

      // Prepare state for the new step
      _initQuestionStateForStep(_currentStep);

      _triggerAutoSpeak();
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final db = await DatabaseHelper.instance.database;
    final userList = await db.query('gamification', limit: 1);

    if (userList.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final user = userList.first;
    final currentXp = user['total_xp'] as int? ?? 0;
    final currentGems = user['gems'] as int? ?? 50;

    // 1. SKIPPING QUIZ FLOW
    if (widget.isSkippingQuiz) {
      final totalQ = _questions.length;
      final requiredCorrect = (totalQ * 0.8).ceil();
      final isPassed = _correctCount >= requiredCorrect;
      final target = widget.stage;

      if (isPassed) {
        await DatabaseHelper.instance.skipLanguageToStage(
          language: widget.language,
          stage: target,
        );

        await db.update(
          'gamification',
          {
            'total_xp': currentXp + 200,
            'gems': currentGems + 30,
          },
          where: 'id = ?',
          whereArgs: [user['id']],
        );

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
                Icon(Icons.stars, color: AppTheme.neonGreen),
                SizedBox(width: 10),
                Text('LULUS! 🎉'),
              ],
            ),
            content: Text(
              'Selamat! Anda lulus Kuis Evaluasi Lompat Stage dengan menjawab $_correctCount dari $totalQ pertanyaan dengan benar.\n\nStage $target sekarang TERBUKA!',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.neonGreen),
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Return to LearningPathScreen
                },
                child: const Text('Lanjutkan',
                    style: TextStyle(
                        color: AppTheme.darkBackground,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: AppTheme.darkSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppTheme.neonPink),
            ),
            title: const Row(
              children: [
                Icon(Icons.gpp_bad, color: AppTheme.neonPink),
                SizedBox(width: 10),
                Text('BELUM LULUS ❌'),
              ],
            ),
            content: Text(
              'Maaf, Anda hanya menjawab $_correctCount dari $totalQ pertanyaan dengan benar.\n\nAnda membutuhkan minimal $requiredCorrect jawaban benar (80%) untuk melompati ke Stage $target. Silakan coba lagi!',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.neonPink),
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Return to LearningPathScreen
                },
                child: const Text('Kembali',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
      return;
    }

    // 2. NORMAL LESSON PROGRESSION FLOW
    final isBasicStage = widget.stage <= 6;

    if (isBasicStage) {
      await DatabaseHelper.instance.advanceLanguageProgressIfCurrent(
        language: widget.language,
        completedStage: widget.stage,
        completedDay: widget.day,
      );

      await db.update(
        'gamification',
        {
          'total_xp': currentXp + 50,
          'gems': currentGems + 10,
        },
        where: 'id = ?',
        whereArgs: [user['id']],
      );
    } else {
      // stages > 6: progress is driven by mock exam session after daily lesson quiz
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
            const Text(
                'Hebat! Seluruh kuis latihan harian interaktif Duolingo-style telah selesai.'),
            const SizedBox(height: 12),
            const Text('🏆 XP Belajar: +50 XP',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.neonGreen)),
            const Text('💎 Hadiah Permata: +10 Gems',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.neonBlue)),
            const SizedBox(height: 16),
            if (!isBasicStage)
              Text(
                'Langkah berikutnya: Selesaikan Sesi Latihan Rutin ${widget.language == 'JAPANESE' ? 'JLPT' : 'IELTS'} Anda!',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              )
            else
              const Text(
                'Anda telah menyelesaikan materi hari ini. Silakan lanjutkan belajar hari berikutnya secara langsung!',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
          ],
        ),
        actions: [
          if (!isBasicStage)
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.neonGreen),
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
              child: const Text('Mulai Sesi Ujian Harian',
                  style: TextStyle(
                      color: AppTheme.darkBackground,
                      fontWeight: FontWeight.bold)),
            )
          else
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.neonBlue),
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Return to LessonListScreen
              },
              child: const Text('Kembali ke Menu',
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

    final currentQ = _questions[_currentStep];
    final progress = (_connectLeftItems.isNotEmpty ||
            _connectRightItems.isNotEmpty ||
            currentQ.type == QuestionType.connectPairs)
        ? (_currentStep + (_hasAnswered ? 1 : 0)) / _questions.length
        : _currentStep / _questions.length;
    final isJp = widget.language == 'JAPANESE';
    final accentColor = isJp ? AppTheme.neonBlue : AppTheme.neonGreen;

    // Initialize unscramble pool or connect items if not done
    if (currentQ.type == QuestionType.sentenceUnscramble &&
        _unscramblePool.isEmpty &&
        _unscrambleSelection.isEmpty) {
      _unscramblePool = List<String>.from(currentQ.wordPool);
    }
    if (currentQ.type == QuestionType.connectPairs &&
        _connectLeftItems.isEmpty &&
        _connectRightItems.isEmpty) {
      _connectLeftItems = currentQ.pairs.keys.toList()..shuffle();
      _connectRightItems = currentQ.pairs.values.toList()..shuffle();
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
                  value: progress.clamp(0.0, 1.0),
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
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
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
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary),
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
    final isJp = widget.language == 'JAPANESE';

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
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                // Show reading (furigana) for stages <= 12
                if (showReading && widget.stage <= 12) ...[
                  const SizedBox(height: 8),
                  Text(
                    '(${q.readingPrompt})',
                    style: const TextStyle(
                        fontSize: 16, color: AppTheme.textSecondary),
                  ),
                ],
                // Romaji hint for stages 1-6 only
                if (isJp && widget.stage <= 6 && showReading) ...[
                  const SizedBox(height: 4),
                  Text(
                    '🔤 Hint romaji di balik jawaban',
                    style: TextStyle(
                        fontSize: 11,
                        color: color.withOpacity(0.7),
                        fontStyle: FontStyle.italic),
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
          Color? bgColor;
          Color borderColor;
          if (_hasAnswered) {
            if (optText == q.correctAnswer) {
              bgColor = AppTheme.neonGreen.withOpacity(0.15);
              borderColor = AppTheme.neonGreen;
            } else if (isSelected && optText != q.correctAnswer) {
              bgColor = Colors.red.withOpacity(0.10);
              borderColor = Colors.redAccent;
            } else {
              bgColor = Colors.transparent;
              borderColor = AppTheme.textSecondary.withOpacity(0.1);
            }
          } else {
            bgColor = isSelected ? color.withOpacity(0.08) : Colors.transparent;
            borderColor =
                isSelected ? color : AppTheme.textSecondary.withOpacity(0.1);
          }
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: borderColor, width: 2),
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                backgroundColor: bgColor,
              ),
              onPressed: _hasAnswered
                  ? null
                  : () => setState(() => _selectedChoiceIndex = idx),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        optText,
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 15),
                      ),
                    ),
                    if (_hasAnswered && optText == q.correctAnswer)
                      const Icon(Icons.check_circle,
                          color: AppTheme.neonGreen, size: 20),
                    if (_hasAnswered &&
                        isSelected &&
                        optText != q.correctAnswer)
                      const Icon(Icons.cancel,
                          color: Colors.redAccent, size: 20),
                  ],
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
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
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
        const Text('Pilih kata-kata untuk menyusun kalimat:',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _unscramblePool.map((w) {
            return ActionChip(
              backgroundColor: AppTheme.darkSurface,
              label:
                  Text(w, style: const TextStyle(color: AppTheme.textPrimary)),
              onPressed: _hasAnswered ? null : () => _unscrambleTapWord(w),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFillInBlankView(QuizQuestion q, Color color) {
    // Stages 1-12: choice buttons (Duolingo style). Stages 13+: free text input
    final useChoiceMode = widget.stage <= 12 && q.options.isNotEmpty;

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
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2),
                  textAlign: TextAlign.center,
                ),
                if (q.readingPrompt != null &&
                    q.readingPrompt!.isNotEmpty &&
                    widget.stage <= 6) ...[
                  const SizedBox(height: 6),
                  Text(
                    '(${q.readingPrompt})',
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (useChoiceMode) ...[
          // Duolingo-style 4-choice buttons
          const Text('Pilih kata yang tepat:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          ...List.generate(q.options.length, (idx) {
            final isSelected = _selectedChoiceIndex == idx;
            final optText = q.options[idx];
            Color? bgColor;
            Color borderColor;
            if (_hasAnswered) {
              if (optText == q.correctAnswer) {
                bgColor = AppTheme.neonGreen.withOpacity(0.15);
                borderColor = AppTheme.neonGreen;
              } else if (isSelected && optText != q.correctAnswer) {
                bgColor = Colors.red.withOpacity(0.10);
                borderColor = Colors.redAccent;
              } else {
                bgColor = Colors.transparent;
                borderColor = AppTheme.textSecondary.withOpacity(0.1);
              }
            } else {
              bgColor =
                  isSelected ? color.withOpacity(0.08) : Colors.transparent;
              borderColor =
                  isSelected ? color : AppTheme.textSecondary.withOpacity(0.1);
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: borderColor, width: 2),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  backgroundColor: bgColor,
                ),
                onPressed: _hasAnswered
                    ? null
                    : () => setState(() => _selectedChoiceIndex = idx),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(optText,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 16)),
                    ),
                    if (_hasAnswered && optText == q.correctAnswer)
                      const Icon(Icons.check_circle,
                          color: AppTheme.neonGreen, size: 20),
                    if (_hasAnswered &&
                        isSelected &&
                        optText != q.correctAnswer)
                      const Icon(Icons.cancel,
                          color: Colors.redAccent, size: 20),
                  ],
                ),
              ),
            );
          }),
        ] else ...[
          // Advanced: free text input (stages 13+)
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Ketik kata yang hilang...',
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: color, width: 2)),
            ),
            style: const TextStyle(fontSize: 18, color: AppTheme.textPrimary),
            onChanged: (val) {
              _typedAnswer = val;
            },
            enabled: !_hasAnswered,
          ),
        ],
      ],
    );
  }

  Widget _buildConnectPairsView(QuizQuestion q, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column
        Expanded(
          child: Column(
            children: _connectLeftItems.map((term) {
              final isMatched = _connectPairsAnswers.containsKey(term);
              final isSelected = _connectSelectedLeft == term;
              Color border = isMatched
                  ? AppTheme.neonGreen
                  : (isSelected
                      ? color
                      : AppTheme.textSecondary.withOpacity(0.1));

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: border, width: 2),
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isMatched || _hasAnswered
                      ? null
                      : () => _connectTapItem(term, true),
                  child: Text(term,
                      style: const TextStyle(color: AppTheme.textPrimary)),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 16),
        // Right Column
        Expanded(
          child: Column(
            children: _connectRightItems.map((trans) {
              final isMatched = _connectPairsAnswers.containsValue(trans);
              final isSelected = _connectSelectedRight == trans;
              Color border = isMatched
                  ? AppTheme.neonGreen
                  : (isSelected
                      ? color
                      : AppTheme.textSecondary.withOpacity(0.1));

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: border, width: 2),
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isMatched || _hasAnswered
                      ? null
                      : () => _connectTapItem(trans, false),
                  child: Text(trans,
                      style: const TextStyle(color: AppTheme.textPrimary)),
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
                side: BorderSide(
                    color: isSelected
                        ? color
                        : AppTheme.textSecondary.withOpacity(0.1),
                    width: 2),
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                backgroundColor:
                    isSelected ? color.withOpacity(0.08) : Colors.transparent,
              ),
              onPressed: _hasAnswered
                  ? null
                  : () => setState(() => _selectedChoiceIndex = idx),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  optText,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 15),
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
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _typingController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Ketik arti kata di sini...',
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: color, width: 2)),
          ),
          style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
          onChanged: (val) {
            setState(() {
              _typedAnswer = val;
            });
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
      if (q.type == QuestionType.multipleChoice ||
          q.type == QuestionType.listening) {
        canCheck = _selectedChoiceIndex != -1;
      } else if (q.type == QuestionType.fillInBlank) {
        // Choice mode (stages <= 12): use selectedChoiceIndex; text mode (stages 13+): use typed answer
        if (widget.stage <= 12 && q.options.isNotEmpty) {
          canCheck = _selectedChoiceIndex != -1;
        } else {
          canCheck = _typedAnswer.isNotEmpty;
        }
      } else if (q.type == QuestionType.typing) {
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
          border: Border(
              top: BorderSide(color: AppTheme.textSecondary.withOpacity(0.1))),
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                canCheck ? color : AppTheme.textSecondary.withOpacity(0.2),
            foregroundColor: AppTheme.darkBackground,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: canCheck ? _checkAnswer : null,
          child: const Text('PERIKSA JAWABAN',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
              Icon(_isCorrect ? Icons.check_circle : Icons.error,
                  color: feedColor, size: 28),
              const SizedBox(width: 12),
              Text(
                _isCorrect ? 'Jawaban Anda Benar!' : 'Jawaban Kurang Tepat',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: feedColor,
                    fontSize: 16),
              ),
            ],
          ),
          if (!_isCorrect) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Kunci jawaban tepat: ${q.correctAnswer}',
                style:
                    const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _nextStep,
              child: const Text('LANJUTKAN',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
