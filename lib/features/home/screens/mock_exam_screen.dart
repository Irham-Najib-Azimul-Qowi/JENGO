import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/custom_top_notification.dart';

enum MockQuestionKind { multipleChoice, writing, speaking }

class MockExamQuestion {
  final String id;
  final String category;
  final String type;
  final MockQuestionKind kind;
  final String prompt;
  final String? passage;
  final String? transcript;
  final List<String> options;
  final int? correctAnswerIndex;
  final String explanation;
  final int targetWords;
  final int speakingSeconds;

  const MockExamQuestion({
    required this.id,
    required this.category,
    required this.type,
    required this.kind,
    required this.prompt,
    this.passage,
    this.transcript,
    this.options = const [],
    this.correctAnswerIndex,
    required this.explanation,
    this.targetWords = 0,
    this.speakingSeconds = 0,
  });
}

class MockExamSection {
  final String id;
  final String title;
  final String officialLabel;
  final int minutes;
  final List<MockExamQuestion> questions;

  const MockExamSection({
    required this.id,
    required this.title,
    required this.officialLabel,
    required this.minutes,
    required this.questions,
  });
}

class MockExamScreen extends StatefulWidget {
  final String language;
  final String level;

  const MockExamScreen({
    super.key,
    required this.language,
    this.level = 'N3',
  });

  @override
  State<MockExamScreen> createState() => _MockExamScreenState();
}

class _MockExamScreenState extends State<MockExamScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final Random _random = Random();
  final Map<String, dynamic> _answers = {};
  final Set<String> _playedListeningIds = {};
  final Set<String> _recordedSpeakingIds = {};
  final Map<String, int> _elapsedBySection = {};

  List<MockExamSection> _sections = [];
  Timer? _sectionTimer;
  Timer? _speakingTimer;
  int _sectionIndex = 0;
  int _secondsRemaining = 0;
  int _activeSpeakingSeconds = 0;
  String? _activeSpeakingId;
  bool _isLoading = true;
  bool _isAudioPlaying = false;
  bool _speechAvailable = false;

  bool get _isJapanese => widget.language == 'JAPANESE';

  Color get _accentColor =>
      _isJapanese ? AppTheme.neonBlue : AppTheme.neonGreen;

  MockExamSection get _currentSection => _sections[_sectionIndex];

  @override
  void initState() {
    super.initState();
    _prepareExam();
  }

  @override
  void dispose() {
    _sectionTimer?.cancel();
    _speakingTimer?.cancel();
    _flutterTts.stop();
    _speechToText.stop();
    super.dispose();
  }

  Future<void> _prepareExam() async {
    _speechAvailable = await _speechToText.initialize();
    final db = await DatabaseHelper.instance.database;
    final sections = _isJapanese
        ? await _buildJlptSections(db)
        : await _buildIeltsSections(db);

    if (!mounted) return;
    setState(() {
      _sections = sections;
      _isLoading = false;
    });
    _startSectionTimer();
  }

  Future<List<MockExamSection>> _buildJlptSections(Database db) async {
    final level = widget.level;
    final vocab = await _buildJlptVocabularyQuestions(db, level, 12);
    final kanji = await _buildJlptKanjiQuestions(db, level, 8);
    final grammar = await _buildJlptGrammarQuestions(db, level, 8);
    final reading = await _buildPassageQuestions(
      db: db,
      table: 'reading',
      language: 'JAPANESE',
      level: level,
      category: 'Reading',
      type: 'Reading Comprehension',
      limit: 6,
    );
    final listening = await _buildPassageQuestions(
      db: db,
      table: 'listening',
      language: 'JAPANESE',
      level: level,
      category: 'Listening',
      type: 'Conversation / Monologue',
      limit: 6,
      listening: true,
    );

    if (level == 'N2') {
      return [
        MockExamSection(
          id: 'jp_lk_reading',
          title: 'Language Knowledge and Reading',
          officialLabel: 'Vocabulary / Grammar / Reading',
          minutes: 105,
          questions: [...vocab, ...kanji, ...grammar, ...reading]
            ..shuffle(_random),
        ),
        MockExamSection(
          id: 'jp_listening',
          title: 'Listening',
          officialLabel: 'Listening',
          minutes: 50,
          questions: listening,
        ),
      ];
    }

    final timings = {
      'N3': [30, 70, 40],
      'N4': [25, 55, 35],
      'N5': [20, 40, 30],
    }[level]!;

    return [
      MockExamSection(
        id: 'jp_vocab',
        title: 'Language Knowledge',
        officialLabel: 'Vocabulary / Kanji',
        minutes: timings[0],
        questions: [...vocab, ...kanji]..shuffle(_random),
      ),
      MockExamSection(
        id: 'jp_grammar_reading',
        title: 'Grammar and Reading',
        officialLabel: 'Grammar / Reading',
        minutes: timings[1],
        questions: [...grammar, ...reading]..shuffle(_random),
      ),
      MockExamSection(
        id: 'jp_listening',
        title: 'Listening',
        officialLabel: 'Listening',
        minutes: timings[2],
        questions: listening,
      ),
    ];
  }

  Future<List<MockExamSection>> _buildIeltsSections(Database db) async {
    final listening = await _buildPassageQuestions(
      db: db,
      table: 'listening',
      language: 'ENGLISH',
      level: 'C1',
      category: 'Listening',
      type: 'Multiple Choice / Completion',
      limit: 10,
      listening: true,
    );
    final reading = await _buildPassageQuestions(
      db: db,
      table: 'reading',
      language: 'ENGLISH',
      level: 'C1',
      category: 'Reading',
      type: 'Multiple Choice / Matching / Completion',
      limit: 12,
    );
    final writing = await _buildIeltsWritingQuestions(db);
    final speaking = await _buildIeltsSpeakingQuestions(db);

    return [
      MockExamSection(
        id: 'ielts_listening',
        title: 'Listening',
        officialLabel: '4 parts, one audio play per item',
        minutes: 30,
        questions: listening,
      ),
      MockExamSection(
        id: 'ielts_reading',
        title: 'Reading',
        officialLabel: 'Academic Reading passages',
        minutes: 60,
        questions: reading,
      ),
      MockExamSection(
        id: 'ielts_writing',
        title: 'Writing',
        officialLabel: 'Task 1 and Task 2',
        minutes: 60,
        questions: writing,
      ),
      MockExamSection(
        id: 'ielts_speaking',
        title: 'Speaking',
        officialLabel: 'Part 1, Part 2, Part 3',
        minutes: 14,
        questions: speaking,
      ),
    ];
  }

  Future<List<MockExamQuestion>> _buildJlptVocabularyQuestions(
      Database db, String level, int limit) async {
    final rows = await _randomRows(
      db,
      'vocabulary',
      where: 'language = ? AND difficulty_level = ?',
      whereArgs: ['JAPANESE', level],
      limit: limit,
    );

    return rows.map((row) {
      final word = row['word']?.toString() ?? '';
      final reading = row['reading']?.toString() ?? '';
      final meaning = row['translation']?.toString() ?? '';
      final options = _makeOptions(meaning, _fallbackMeanings);

      return MockExamQuestion(
        id: 'vocab_${row['id']}_$word',
        category: 'Vocabulary',
        type: 'Word Meaning',
        kind: MockQuestionKind.multipleChoice,
        prompt:
            'Pilih arti yang paling tepat untuk "$word"${reading.isEmpty ? '' : ' ($reading)'}.',
        options: options,
        correctAnswerIndex: options.indexOf(meaning),
        explanation: 'Kosakata "$word" berarti "$meaning".',
      );
    }).toList();
  }

  Future<List<MockExamQuestion>> _buildJlptKanjiQuestions(
      Database db, String level, int limit) async {
    final rows = await _randomRows(
      db,
      'kanji',
      where: 'level = ?',
      whereArgs: [level],
      limit: limit,
    );

    return rows.map((row) {
      final kanji = row['kanji']?.toString() ?? '';
      final meaning = row['meaning']?.toString() ?? '';
      final options = _makeOptions(meaning, _fallbackMeanings);

      return MockExamQuestion(
        id: 'kanji_${row['id']}_$kanji',
        category: 'Kanji',
        type: 'Kanji Meaning',
        kind: MockQuestionKind.multipleChoice,
        prompt: 'Apa makna kanji "$kanji"?',
        options: options,
        correctAnswerIndex: options.indexOf(meaning),
        explanation: 'Kanji "$kanji" bermakna "$meaning".',
      );
    }).toList();
  }

  Future<List<MockExamQuestion>> _buildJlptGrammarQuestions(
      Database db, String level, int limit) async {
    final rows = await _randomRows(
      db,
      'grammar',
      where: 'language = ? AND level = ?',
      whereArgs: ['JAPANESE', level],
      limit: limit,
    );

    return rows.map((row) {
      final rule = row['rule_name']?.toString() ?? '';
      final explanation = row['explanation']?.toString() ?? '';
      final example = row['example_sentence']?.toString() ?? '';
      final options = _makeOptions(rule, _fallbackGrammarOptions);

      return MockExamQuestion(
        id: 'grammar_${row['id']}_$rule',
        category: 'Grammar',
        type: 'Grammar Pattern',
        kind: MockQuestionKind.multipleChoice,
        prompt:
            'Pola tata bahasa mana yang paling sesuai dengan contoh berikut?\n$example',
        options: options,
        correctAnswerIndex: options.indexOf(rule),
        explanation:
            explanation.isEmpty ? 'Pola yang tepat adalah $rule.' : explanation,
      );
    }).toList();
  }

  Future<List<MockExamQuestion>> _buildPassageQuestions({
    required Database db,
    required String table,
    required String language,
    required String level,
    required String category,
    required String type,
    required int limit,
    bool listening = false,
  }) async {
    var rows = await _randomRows(
      db,
      table,
      where: 'language = ? AND level = ?',
      whereArgs: [language, level],
      limit: limit,
    );

    if (rows.isEmpty && language == 'ENGLISH') {
      rows = await _randomRows(
        db,
        table,
        where: 'language = ?',
        whereArgs: [language],
        limit: limit,
      );
    }

    final questions = <MockExamQuestion>[];
    for (final row in rows) {
      final rawQuestions = _decodeQuestions(row['questions']);
      for (var i = 0; i < rawQuestions.length; i++) {
        final q = rawQuestions[i];
        final options = (q['options'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();
        questions.add(
          MockExamQuestion(
            id: '${table}_${row['id']}_$i',
            category: category,
            type: type,
            kind: MockQuestionKind.multipleChoice,
            prompt: q['question']?.toString() ?? 'Pilih jawaban yang benar.',
            passage: listening ? null : row['passage']?.toString(),
            transcript: listening ? row['transcript']?.toString() : null,
            options: options,
            correctAnswerIndex: q['correct_answer_index'] as int? ?? 0,
            explanation: row['translation']?.toString() ??
                'Pembahasan mengikuti materi pada teks/audio.',
          ),
        );
      }
    }

    if (questions.isEmpty) {
      return listening
          ? _fallbackListeningQuestions(language, limit)
          : _fallbackReadingQuestions(language, limit);
    }

    questions.shuffle(_random);
    return questions.take(limit).toList();
  }

  Future<List<MockExamQuestion>> _buildIeltsWritingQuestions(
      Database db) async {
    final rows = await _randomRows(db, 'writing_prompts', limit: 2);
    final task1 = rows.isNotEmpty
        ? rows.first
        : {
            'prompt':
                'The chart shows changes in the number of international students at a university from 2015 to 2025. Summarise the main features and make comparisons where relevant.',
            'type': 'Line Chart',
          };
    final task2 = rows.length > 1
        ? rows[1]
        : {
            'prompt':
                'Some people believe governments should invest more in public transport than roads. To what extent do you agree or disagree?',
            'type': 'Transportation',
          };

    return [
      MockExamQuestion(
        id: 'ielts_writing_task_1',
        category: 'Writing',
        type: 'Task 1 - ${task1['type'] ?? 'Chart'}',
        kind: MockQuestionKind.writing,
        prompt: task1['prompt']?.toString() ?? '',
        explanation:
            'Task 1 dinilai dari task achievement, coherence, lexical resource, dan grammar.',
        targetWords: 150,
      ),
      MockExamQuestion(
        id: 'ielts_writing_task_2',
        category: 'Writing',
        type: 'Task 2 - ${task2['type'] ?? 'Essay'}',
        kind: MockQuestionKind.writing,
        prompt: task2['prompt']?.toString() ?? '',
        explanation: 'Task 2 membutuhkan argumen formal minimal 250 kata.',
        targetWords: 250,
      ),
    ];
  }

  Future<List<MockExamQuestion>> _buildIeltsSpeakingQuestions(
      Database db) async {
    final rows = await _randomRows(db, 'speaking_prompts', limit: 3);
    final topic = rows.isNotEmpty
        ? rows.first['topic']?.toString() ?? 'education'
        : 'education';
    final cueCard = rows.isNotEmpty
        ? rows.first['prompt_card']?.toString() ??
            'Describe an important learning experience you had.'
        : 'Describe an important learning experience you had.';

    return [
      const MockExamQuestion(
        id: 'ielts_speaking_part_1',
        category: 'Speaking',
        type: 'Part 1',
        kind: MockQuestionKind.speaking,
        prompt:
            'Answer general questions about your home, studies, work, interests, and daily routine.',
        explanation: 'Part 1 menguji respons spontan pada topik familiar.',
        speakingSeconds: 240,
      ),
      MockExamQuestion(
        id: 'ielts_speaking_part_2',
        category: 'Speaking',
        type: 'Part 2 Cue Card',
        kind: MockQuestionKind.speaking,
        prompt: cueCard,
        explanation:
            'Part 2 memberi waktu persiapan singkat lalu berbicara panjang.',
        speakingSeconds: 120,
      ),
      MockExamQuestion(
        id: 'ielts_speaking_part_3',
        category: 'Speaking',
        type: 'Part 3 Discussion',
        kind: MockQuestionKind.speaking,
        prompt:
            'Discuss broader issues related to "$topic". Give reasons, examples, and comparisons.',
        explanation: 'Part 3 menguji diskusi abstrak dan argumentasi lanjutan.',
        speakingSeconds: 300,
      ),
    ];
  }

  Future<List<Map<String, dynamic>>> _randomRows(
    Database db,
    String table, {
    String? where,
    List<Object?>? whereArgs,
    required int limit,
  }) async {
    return db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: 'RANDOM()',
      limit: limit,
    );
  }

  List<Map<String, dynamic>> _decodeQuestions(dynamic value) {
    if (value is List) return value.cast<Map<String, dynamic>>();
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded.cast<Map<String, dynamic>>();
    }
    return const [];
  }

  List<String> _makeOptions(String correct, List<String> fallbackPool) {
    final options = <String>{correct};
    final pool = [...fallbackPool]..shuffle(_random);
    for (final item in pool) {
      if (options.length >= 4) break;
      if (item.trim().isNotEmpty && item != correct) options.add(item);
    }
    final result = options.toList()..shuffle(_random);
    return result;
  }

  void _startSectionTimer() {
    _sectionTimer?.cancel();
    _secondsRemaining = _currentSection.minutes * 60;
    _sectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        _elapsedBySection[_currentSection.id] = _currentSection.minutes * 60;
        _moveToNextSection(auto: true);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  void _moveToNextSection({bool auto = false}) {
    _sectionTimer?.cancel();
    _flutterTts.stop();
    _elapsedBySection[_currentSection.id] =
        (_currentSection.minutes * 60) - _secondsRemaining;

    if (_sectionIndex >= _sections.length - 1) {
      _submitExam();
      return;
    }

    setState(() {
      _sectionIndex++;
      _isAudioPlaying = false;
      _activeSpeakingId = null;
      _activeSpeakingSeconds = 0;
    });
    _startSectionTimer();

    if (auto && mounted) {
      CustomTopNotification.show(context,
          message: 'Waktu section habis. Lanjut ke section berikutnya.');
    }
  }

  Future<void> _playListeningOnce(MockExamQuestion question) async {
    if (_playedListeningIds.contains(question.id) || _isAudioPlaying) return;

    setState(() {
      _isAudioPlaying = true;
      _playedListeningIds.add(question.id);
    });

    await _flutterTts.setLanguage(_isJapanese ? 'ja-JP' : 'en-US');
    await _flutterTts.speak(question.transcript ?? question.prompt);
    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _isAudioPlaying = false);
    });
  }

  Future<void> _toggleSpeaking(MockExamQuestion question) async {
    if (_activeSpeakingId == question.id) {
      await _speechToText.stop();
      _finishSpeaking(question.id);
      return;
    }

    if (!_speechAvailable) {
      _speechAvailable = await _speechToText.initialize();
    }
    if (!_speechAvailable) {
      if (mounted) {
        CustomTopNotification.show(
          context,
          message: 'Mikrofon belum tersedia. Periksa izin audio perangkat.',
        );
      }
      return;
    }

    _speakingTimer?.cancel();
    setState(() {
      _activeSpeakingId = question.id;
      _activeSpeakingSeconds = question.speakingSeconds;
      _answers[question.id] = '';
    });

    await _speechToText.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: 'en_US',
        listenFor: Duration(seconds: question.speakingSeconds),
        pauseFor: const Duration(seconds: 4),
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _answers[question.id] = result.recognizedWords;
          if (result.recognizedWords.trim().isNotEmpty) {
            _recordedSpeakingIds.add(question.id);
          }
        });
      },
    );

    _speakingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_activeSpeakingSeconds <= 1) {
        _finishSpeaking(question.id);
      } else {
        setState(() => _activeSpeakingSeconds--);
      }
    });
  }

  void _finishSpeaking(String questionId) {
    _speakingTimer?.cancel();
    _speechToText.stop();
    setState(() {
      _recordedSpeakingIds.add(questionId);
      _answers[questionId] =
          (_answers[questionId]?.toString().trim().isNotEmpty ?? false)
              ? _answers[questionId]
              : 'recorded audio response';
      _activeSpeakingId = null;
      _activeSpeakingSeconds = 0;
    });
  }

  Future<void> _submitExam() async {
    _sectionTimer?.cancel();
    _speakingTimer?.cancel();
    _flutterTts.stop();
    _speechToText.stop();

    // Pastikan durasi section terakhir juga tercatat
    _elapsedBySection[_currentSection.id] =
        (_currentSection.minutes * 60) - _secondsRemaining;

    final db = await DatabaseHelper.instance.database;
    final result = _isJapanese ? _gradeJlpt() : _gradeIelts();

    final totalSecondsSpent =
        _elapsedBySection.values.fold<int>(0, (sum, val) => sum + val);

    final List<Map<String, dynamic>> reviewDataList = [];
    for (final section in _sections) {
      for (final q in section.questions) {
        final userAnswer = _answers[q.id];
        bool isCorrect = false;
        if (q.kind == MockQuestionKind.multipleChoice) {
          isCorrect = userAnswer == q.correctAnswerIndex;
        } else if (q.kind == MockQuestionKind.writing) {
          isCorrect = (userAnswer?.toString().trim().isNotEmpty ?? false);
        } else if (q.kind == MockQuestionKind.speaking) {
          isCorrect = _recordedSpeakingIds.contains(q.id);
        }

        reviewDataList.add({
          'id': q.id,
          'category': q.category,
          'type': q.type,
          'kind': q.kind.name,
          'prompt': q.prompt,
          'passage': q.passage,
          'transcript': q.transcript,
          'options': q.options,
          'correctAnswerIndex': q.correctAnswerIndex,
          'userAnswer': userAnswer,
          'isCorrect': isCorrect,
          'explanation': q.explanation,
        });
      }
    }

    final historyId = await db.insert('simulations_history', {
      'language': widget.language,
      'level': _isJapanese ? widget.level : 'IELTS',
      'overall_score': result.overallScore,
      'sectional_scores': jsonEncode(result.sectionalScores),
      'correct_answers': result.correctAnswers,
      'total_questions': result.totalQuestions,
      'weaknesses': result.weaknesses,
      'recommendations': result.recommendations,
      'time_spent': totalSecondsSpent,
      'review_data': jsonEncode(reviewDataList),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    final userList = await db.query('gamification', limit: 1);
    if (userList.isNotEmpty) {
      final user = userList.first;
      await db.update(
        'gamification',
        {
          'total_xp': (user['total_xp'] as int? ?? 0) + 200,
          'gems': (user['gems'] as int? ?? 50) + 30,
        },
        where: 'id = ?',
        whereArgs: [user['id']],
      );
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      '/exam_review',
      arguments: {'historyId': historyId, 'language': widget.language},
    );
  }

  _ExamGrade _gradeJlpt() {
    final categoryTotals = <String, int>{};
    final categoryCorrect = <String, int>{};

    for (final section in _sections) {
      for (final question in section.questions) {
        if (question.kind != MockQuestionKind.multipleChoice) continue;
        categoryTotals[question.category] =
            (categoryTotals[question.category] ?? 0) + 1;
        if (_answers[question.id] == question.correctAnswerIndex) {
          categoryCorrect[question.category] =
              (categoryCorrect[question.category] ?? 0) + 1;
        }
      }
    }

    double pointsFor(List<String> categories, int max) {
      final total =
          categories.fold<int>(0, (sum, c) => sum + (categoryTotals[c] ?? 0));
      final correct =
          categories.fold<int>(0, (sum, c) => sum + (categoryCorrect[c] ?? 0));
      return total == 0 ? 0 : (correct / total * max);
    }

    final languageKnowledge = pointsFor(['Vocabulary', 'Kanji', 'Grammar'], 60);
    final reading = pointsFor(
        ['Reading'], widget.level == 'N4' || widget.level == 'N5' ? 60 : 60);
    final listening = pointsFor(['Listening'], 60);
    final total = languageKnowledge + reading + listening;
    final passMarks = {'N2': 90, 'N3': 95, 'N4': 90, 'N5': 80};
    final passMark = passMarks[widget.level] ?? 90;

    final weak = categoryTotals.keys.where((category) {
      final total = categoryTotals[category] ?? 0;
      if (total == 0) return false;
      return ((categoryCorrect[category] ?? 0) / total) < 0.65;
    }).toList();

    return _ExamGrade(
      overallScore: total,
      sectionalScores: {
        'Language Knowledge': languageKnowledge.round(),
        'Reading': reading.round(),
        'Listening': listening.round(),
        'Estimated Pass Mark': passMark,
      },
      correctAnswers: categoryCorrect.values.fold(0, (a, b) => a + b),
      totalQuestions: categoryTotals.values.fold(0, (a, b) => a + b),
      weaknesses: weak.isEmpty
          ? 'Tidak ada kelemahan dominan pada simulasi ini.'
          : 'Kategori yang perlu diperkuat: ${weak.join(', ')}.',
      recommendations: weak.isEmpty
          ? 'Pertahankan latihan full-test dan ulangi simulasi dengan bank soal berbeda.'
          : 'Prioritaskan review materi ${weak.join(', ')} lalu ulangi simulasi level ${widget.level}.',
    );
  }

  _ExamGrade _gradeIelts() {
    final listening = _scoreMultipleChoiceCategory('Listening');
    final reading = _scoreMultipleChoiceCategory('Reading');
    final writing = _scoreWritingBand();
    final speaking = _scoreSpeakingBand();
    final overall = _roundHalf((listening + reading + writing + speaking) / 4);
    final weaknesses = <String>[];

    if (listening < 7) weaknesses.add('Listening');
    if (reading < 7) weaknesses.add('Reading');
    if (writing < 7) weaknesses.add('Writing');
    if (speaking < 7) weaknesses.add('Speaking');

    final mcTotal = _sections
        .expand((s) => s.questions)
        .where((q) => q.kind == MockQuestionKind.multipleChoice)
        .length;
    final mcCorrect = _sections
        .expand((s) => s.questions)
        .where((q) =>
            q.kind == MockQuestionKind.multipleChoice &&
            _answers[q.id] == q.correctAnswerIndex)
        .length;

    return _ExamGrade(
      overallScore: overall,
      sectionalScores: {
        'Listening': listening,
        'Reading': reading,
        'Writing': writing,
        'Speaking': speaking,
      },
      correctAnswers: mcCorrect,
      totalQuestions: mcTotal,
      weaknesses: weaknesses.isEmpty
          ? 'Tidak ada kelemahan dominan pada simulasi ini.'
          : 'Section yang perlu diperkuat: ${weaknesses.join(', ')}.',
      recommendations: weaknesses.isEmpty
          ? 'Lanjutkan simulasi penuh berkala untuk menjaga konsistensi band.'
          : 'Fokus latihan pada ${weaknesses.join(', ')} dengan format soal resmi dan batas waktu ketat.',
    );
  }

  double _scoreMultipleChoiceCategory(String category) {
    final questions = _sections
        .expand((s) => s.questions)
        .where((q) => q.category == category)
        .toList();
    if (questions.isEmpty) return 0;
    final correct =
        questions.where((q) => _answers[q.id] == q.correctAnswerIndex).length;
    final ratio = correct / questions.length;
    if (ratio >= 0.9) return 8.5;
    if (ratio >= 0.8) return 8.0;
    if (ratio >= 0.7) return 7.0;
    if (ratio >= 0.6) return 6.5;
    if (ratio >= 0.5) return 6.0;
    if (ratio >= 0.4) return 5.5;
    return 5.0;
  }

  double _scoreWritingBand() {
    final writingQuestions = _sections
        .expand((s) => s.questions)
        .where((q) => q.kind == MockQuestionKind.writing);
    var score = 0.0;
    var count = 0;
    for (final question in writingQuestions) {
      final text = _answers[question.id]?.toString() ?? '';
      final words = _wordCount(text);
      count++;
      if (words >= question.targetWords) {
        score += 7.5;
      } else if (words >= question.targetWords * 0.75) {
        score += 6.5;
      } else if (words >= question.targetWords * 0.5) {
        score += 5.5;
      } else {
        score += 4.5;
      }
    }
    return count == 0 ? 0 : _roundHalf(score / count);
  }

  double _scoreSpeakingBand() {
    final speakingQuestions = _sections
        .expand((s) => s.questions)
        .where((q) => q.kind == MockQuestionKind.speaking)
        .toList();
    if (speakingQuestions.isEmpty) return 0;
    final recorded = speakingQuestions
        .where((q) => _recordedSpeakingIds.contains(q.id))
        .length;
    final ratio = recorded / speakingQuestions.length;
    if (ratio >= 1) return 7.5;
    if (ratio >= 0.66) return 6.5;
    if (ratio >= 0.33) return 5.5;
    return 4.0;
  }

  double _roundHalf(double value) => (value * 2).round() / 2;

  int _wordCount(String text) =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: AppTheme.neonBlue)),
      );
    }

    final timerString =
        '${(_secondsRemaining ~/ 60).toString().padLeft(2, '0')}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isJapanese
            ? 'JLPT ${widget.level} Full Simulation'
            : 'IELTS Academic Full Simulation'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(Icons.timer, color: AppTheme.neonPink, size: 18),
                const SizedBox(width: 6),
                Text(
                  timerString,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppTheme.neonPink,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSectionHeader(),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemBuilder: (context, index) =>
                  _buildQuestionCard(_currentSection.questions[index], index),
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemCount: _currentSection.questions.length,
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader() {
    final progress = (_sectionIndex + 1) / _sections.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        border: Border(
            bottom: BorderSide(color: _accentColor.withValues(alpha: 0.25))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Section ${_sectionIndex + 1}/${_sections.length}',
                style: TextStyle(
                    color: _accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
              const Spacer(),
              Text(
                '${_currentSection.minutes} menit',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _currentSection.title,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            _currentSection.officialLabel,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppTheme.darkBackground,
              color: _accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(MockExamQuestion question, int index) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${index + 1}. ${question.category}',
                style: TextStyle(
                    color: _accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  question.type,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (question.passage != null) _buildPassage(question.passage!),
          if (question.transcript != null) _buildListeningControl(question),
          Text(
            question.prompt,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          if (question.kind == MockQuestionKind.multipleChoice)
            _buildOptions(question),
          if (question.kind == MockQuestionKind.writing)
            _buildWritingAnswer(question),
          if (question.kind == MockQuestionKind.speaking)
            _buildSpeakingAnswer(question),
        ],
      ),
    );
  }

  Widget _buildPassage(String passage) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        passage,
        style: const TextStyle(
            color: AppTheme.textPrimary, height: 1.55, fontSize: 14),
      ),
    );
  }

  Widget _buildListeningControl(MockExamQuestion question) {
    final hasPlayed = _playedListeningIds.contains(question.id);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: hasPlayed
                ? AppTheme.textSecondary.withValues(alpha: 0.2)
                : _accentColor.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(hasPlayed ? Icons.lock : Icons.play_arrow,
              color: hasPlayed ? AppTheme.textSecondary : _accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasPlayed
                  ? 'Audio sudah diputar satu kali.'
                  : 'Putar audio satu kali.',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: hasPlayed || _isAudioPlaying
                ? null
                : () => _playListeningOnce(question),
            child: Text(hasPlayed ? 'Terkunci' : 'Play'),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions(MockExamQuestion question) {
    return Column(
      children: List.generate(question.options.length, (index) {
        final selected = _answers[question.id] == index;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.all(14),
              backgroundColor: selected
                  ? _accentColor.withValues(alpha: 0.08)
                  : Colors.transparent,
              side: BorderSide(
                  color: selected
                      ? _accentColor
                      : AppTheme.textSecondary.withValues(alpha: 0.18),
                  width: selected ? 2 : 1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => setState(() => _answers[question.id] = index),
            child: Text(
              question.options[index],
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildWritingAnswer(MockExamQuestion question) {
    final text = _answers[question.id]?.toString() ?? '';
    final words = _wordCount(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          maxLines: 10,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Tulis jawaban formal Anda di sini.',
            hintStyle:
                TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6)),
            filled: true,
            fillColor: AppTheme.darkBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (value) => setState(() => _answers[question.id] = value),
        ),
        const SizedBox(height: 8),
        Text(
          'Jumlah kata: $words / target ${question.targetWords}',
          style: TextStyle(
              color: words >= question.targetWords
                  ? AppTheme.neonGreen
                  : AppTheme.textSecondary,
              fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildSpeakingAnswer(MockExamQuestion question) {
    final isActive = _activeSpeakingId == question.id;
    final isDone = _recordedSpeakingIds.contains(question.id);
    final transcript = _answers[question.id]?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isActive ? Icons.stop_circle : Icons.mic,
                  color: isActive ? AppTheme.neonPink : _accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isActive
                      ? 'Recording... $_activeSpeakingSeconds detik tersisa'
                      : isDone
                          ? 'Respons speaking tercatat.'
                          : 'Mulai rekam respons speaking.',
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: () => _toggleSpeaking(question),
                child: Text(isActive ? 'Stop' : 'Record'),
              ),
            ],
          ),
          if (transcript.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              transcript,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final isLast = _sectionIndex == _sections.length - 1;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        border: Border(
            top: BorderSide(
                color: AppTheme.textSecondary.withValues(alpha: 0.12))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_answeredCount(_currentSection)} dari ${_currentSection.questions.length} respons terisi',
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: AppTheme.darkBackground,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _moveToNextSection(),
            child: Text(isLast ? 'Submit Test' : 'Next Section',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  int _answeredCount(MockExamSection section) {
    return section.questions.where((q) {
      if (q.kind == MockQuestionKind.speaking) {
        return _recordedSpeakingIds.contains(q.id);
      }
      final answer = _answers[q.id];
      if (answer == null) return false;
      if (answer is String) return answer.trim().isNotEmpty;
      return true;
    }).length;
  }

  List<MockExamQuestion> _fallbackReadingQuestions(String language, int limit) {
    return List.generate(limit, (index) {
      final isJp = language == 'JAPANESE';
      return MockExamQuestion(
        id: 'fallback_reading_${language}_$index',
        category: 'Reading',
        type: isJp ? 'Reading Comprehension' : 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: isJp
            ? 'A short notice explains a schedule change and asks readers to confirm the new time.'
            : 'A university notice explains changes to the library opening hours during examination week.',
        prompt: isJp
            ? 'Apa informasi utama dari teks tersebut?'
            : 'What is the main purpose of the notice?',
        options: const [
          'To announce a schedule change',
          'To sell a product',
          'To describe a person',
          'To invite a complaint'
        ],
        correctAnswerIndex: 0,
        explanation: 'Jawaban benar diambil dari ide utama teks.',
      );
    });
  }

  List<MockExamQuestion> _fallbackListeningQuestions(
      String language, int limit) {
    return List.generate(limit, (index) {
      final isJp = language == 'JAPANESE';
      return MockExamQuestion(
        id: 'fallback_listening_${language}_$index',
        category: 'Listening',
        type: isJp
            ? 'Short Conversation'
            : 'IELTS Listening Part ${(index % 4) + 1}',
        kind: MockQuestionKind.multipleChoice,
        transcript: isJp
            ? 'The speaker says the meeting will start at three o clock in room two.'
            : 'The student asks about accommodation. The officer says the single room costs one hundred and twenty pounds per week.',
        prompt: isJp ? 'Kapan rapat dimulai?' : 'How much is the weekly rent?',
        options: const ['120 pounds', '3 o clock', 'Room four', 'Next Monday'],
        correctAnswerIndex: isJp ? 1 : 0,
        explanation: 'Informasi kunci disebutkan langsung dalam audio.',
      );
    });
  }

  static const List<String> _fallbackMeanings = [
    'study',
    'work',
    'society',
    'change',
    'important',
    'method',
    'problem',
    'decision',
    'environment',
    'communication',
  ];

  static const List<String> _fallbackGrammarOptions = [
    'because',
    'although',
    'must',
    'seems',
    'while',
    'before',
    'after',
    'if',
  ];
}

class _ExamGrade {
  final double overallScore;
  final Map<String, dynamic> sectionalScores;
  final int correctAnswers;
  final int totalQuestions;
  final String weaknesses;
  final String recommendations;

  const _ExamGrade({
    required this.overallScore,
    required this.sectionalScores,
    required this.correctAnswers,
    required this.totalQuestions,
    required this.weaknesses,
    required this.recommendations,
  });
}
