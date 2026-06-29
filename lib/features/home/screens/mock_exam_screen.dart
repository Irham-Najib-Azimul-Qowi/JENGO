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

    final questions = rows.map((row) {
      final word = row['word']?.toString() ?? '';
      final reading = row['reading']?.toString() ?? '';
      final meaning = row['translation']?.toString() ?? '';
      final options = _makeOptions(meaning, _fallbackJpMeanings);

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

    // Pad with high quality N5-N1 Japanese vocabulary fallbacks if database lacks entries
    if (questions.length < limit) {
      final needed = limit - questions.length;
      final extra = List.generate(needed, (idx) {
        final sampleWords = [
          {'w': '先生', 'r': 'せんせい', 'm': 'Guru'},
          {'w': '学生', 'r': 'がくせい', 'm': 'Siswa'},
          {'w': '本', 'r': 'ほん', 'm': 'Buku'},
          {'w': '車', 'r': 'くるま', 'm': 'Mobil'},
          {'w': '水', 'r': 'みず', 'm': 'Air'},
          {'w': '机', 'r': 'つくえ', 'm': 'Meja'},
        ];
        final item = sampleWords[idx % sampleWords.length];
        final options = _makeOptions(item['m']!, _fallbackJpMeanings);
        return MockExamQuestion(
          id: 'fallback_vocab_jp_${level}_${idx}',
          category: 'Vocabulary',
          type: 'Word Meaning',
          kind: MockQuestionKind.multipleChoice,
          prompt: 'Pilih arti yang paling tepat untuk "${item['w']}" (${item['r']}).',
          options: options,
          correctAnswerIndex: options.indexOf(item['m']!),
          explanation: 'Kosakata "${item['w']}" berarti "${item['m']}".',
        );
      });
      questions.addAll(extra);
    }
    return questions;
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

    final questions = rows.map((row) {
      final kanji = row['kanji']?.toString() ?? '';
      final meaning = row['meaning']?.toString() ?? '';
      final options = _makeOptions(meaning, _fallbackJpMeanings);

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

    // Pad with high quality N5-N1 Japanese kanji fallbacks if database lacks entries
    if (questions.length < limit) {
      final needed = limit - questions.length;
      final extra = List.generate(needed, (idx) {
        final sampleKanji = [
          {'k': '一', 'm': 'Satu'},
          {'k': '二', 'm': 'Dua'},
          {'k': '三', 'm': 'Tiga'},
          {'k': '山', 'm': 'Gunung'},
          {'k': '川', 'm': 'Sungai'},
          {'k': '木', 'm': 'Pohon'},
        ];
        final item = sampleKanji[idx % sampleKanji.length];
        final options = _makeOptions(item['m']!, _fallbackJpMeanings);
        return MockExamQuestion(
          id: 'fallback_kanji_jp_${level}_${idx}',
          category: 'Kanji',
          type: 'Kanji Meaning',
          kind: MockQuestionKind.multipleChoice,
          prompt: 'Apa makna kanji "${item['k']}"?',
          options: options,
          correctAnswerIndex: options.indexOf(item['m']!),
          explanation: 'Kanji "${item['k']}" bermakna "${item['m']}".',
        );
      });
      questions.addAll(extra);
    }
    return questions;
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

    final questions = rows.map((row) {
      final rule = row['rule_name']?.toString() ?? '';
      final explanation = row['explanation']?.toString() ?? '';
      final example = row['example_sentence']?.toString() ?? '';
      final options = _makeOptions(rule, _fallbackJpGrammarOptions);

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

    // Pad with high quality N5-N1 Japanese grammar fallbacks if database lacks entries
    if (questions.length < limit) {
      final needed = limit - questions.length;
      final extra = List.generate(needed, (idx) {
        final sampleGrammar = [
          {'g': 'から', 'ex': '日本が好きだから、日本語を勉強します。', 'exp': 'Mengindikasikan alasan/sebab.'},
          {'g': 'ので', 'ex': '雨が降っているので、傘を持って行きます。', 'exp': 'Mengindikasikan alasan secara sopan.'},
          {'g': 'ながら', 'ex': '音楽を聞きながら勉強します。', 'exp': 'Melakukan dua aktivitas bersamaan.'},
        ];
        final item = sampleGrammar[idx % sampleGrammar.length];
        final options = _makeOptions(item['g']!, _fallbackJpGrammarOptions);
        return MockExamQuestion(
          id: 'fallback_grammar_jp_${level}_${idx}',
          category: 'Grammar',
          type: 'Grammar Pattern',
          kind: MockQuestionKind.multipleChoice,
          prompt: 'Pola tata bahasa mana yang sesuai dengan contoh berikut?\n${item['ex']}',
          options: options,
          correctAnswerIndex: options.indexOf(item['g']!),
          explanation: item['exp']!,
        );
      });
      questions.addAll(extra);
    }
    return questions;
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
    // Task 1 and Task 2 local fallback banks for variety
    const task1Bank = [
      {
        'prompt': 'The bar chart below shows the percentage of households with internet access in three countries between 2015 and 2025. Summarise the information by selecting and reporting the main features, and make comparisons where relevant.',
        'type': 'Bar Chart',
      },
      {
        'prompt': 'The line graph illustrates the average monthly temperature in four major cities throughout 2023. Summarise the main trends and highlight significant changes.',
        'type': 'Line Graph',
      },
      {
        'prompt': 'The pie charts show the proportion of energy generated from different sources in Germany in 2010 and 2022. Compare and summarise the key changes.',
        'type': 'Pie Chart',
      },
      {
        'prompt': 'The table below shows the number of visitors to five national museums in London over a three-year period. Summarise the information by selecting and reporting the main features.',
        'type': 'Table',
      },
      {
        'prompt': 'The diagram illustrates the process of water purification in a modern treatment plant. Summarise the information by describing each stage of the process.',
        'type': 'Process Diagram',
      },
    ];

    const task2Bank = [
      {
        'prompt': 'Some people believe that university education should be free for all students. Others disagree, arguing that students should pay tuition fees. Discuss both views and give your opinion.',
        'type': 'Discussion Essay',
      },
      {
        'prompt': 'Nowadays, many people choose to live and work in foreign countries. Do the advantages of this trend outweigh the disadvantages? Give reasons for your answer and include relevant examples.',
        'type': 'Opinion Essay',
      },
      {
        'prompt': 'Some people argue that instead of preventing climate change, we should find ways to adapt to it. To what extent do you agree or disagree? Support your answer with examples.',
        'type': 'Argument Essay',
      },
      {
        'prompt': 'In many countries, children are spending more time playing computer games than playing sports. Why is this happening? What are the effects of this trend on individuals and society?',
        'type': 'Problem-Solution Essay',
      },
      {
        'prompt': 'Some governments have introduced laws to restrict the amount of time young people can spend using social media each day. Do you agree or disagree with this measure?',
        'type': 'Opinion Essay',
      },
    ];

    // Try to fetch from DB, filtered by task number
    final task1Rows = await _randomRows(db, 'writing_prompts',
        where: 'task = ?', whereArgs: [1], limit: 1);
    final task2Rows = await _randomRows(db, 'writing_prompts',
        where: 'task = ?', whereArgs: [2], limit: 1);

    // Pick one from local bank using random index if needed
    final rng = DateTime.now().millisecondsSinceEpoch;
    final t1Idx = rng % task1Bank.length;
    final t2Idx = (rng ~/ 7) % task2Bank.length;

    final task1 = (task1Rows.isNotEmpty &&
            (task1Rows.first['prompt']?.toString() ?? '').isNotEmpty &&
            !(task1Rows.first['prompt']?.toString() ?? '').contains('Practice Prompt'))
        ? task1Rows.first
        : task1Bank[t1Idx];

    final task2 = (task2Rows.isNotEmpty &&
            (task2Rows.first['prompt']?.toString() ?? '').isNotEmpty &&
            !(task2Rows.first['prompt']?.toString() ?? '').contains('Practice Prompt'))
        ? task2Rows.first
        : task2Bank[t2Idx];

    return [
      MockExamQuestion(
        id: 'ielts_writing_task_1',
        category: 'Writing',
        type: 'Task 1 – ${task1['type'] ?? 'Chart/Diagram'}',
        kind: MockQuestionKind.writing,
        prompt: task1['prompt']?.toString() ?? task1Bank[0]['prompt']!,
        explanation:
            'Task 1 dinilai dari task achievement, coherence, lexical resource, dan grammar. Tulis minimal 150 kata.',
        targetWords: 150,
      ),
      MockExamQuestion(
        id: 'ielts_writing_task_2',
        category: 'Writing',
        type: 'Task 2 – ${task2['type'] ?? 'Essay'}',
        kind: MockQuestionKind.writing,
        prompt: task2['prompt']?.toString() ?? task2Bank[0]['prompt']!,
        explanation:
            'Task 2 membutuhkan argumen formal minimal 250 kata. Nilai Task 2 memiliki bobot lebih tinggi dari Task 1.',
        targetWords: 250,
      ),
    ];
  }

  Future<List<MockExamQuestion>> _buildIeltsSpeakingQuestions(
      Database db) async {
    // Rich local speaking banks per part
    const part1Bank = [
      {
        'topic': 'Hometown & Daily Life',
        'questions':
            'Where is your hometown? What do you like most about it? Would you say it is a good place for young people to live?',
      },
      {
        'topic': 'Work & Hobbies',
        'questions':
            'What job do you do? Why did you choose this line of work? What hobbies do you enjoy in your free time?',
      },
      {
        'topic': 'Food & Cooking',
        'questions':
            'What is your favourite type of food? Do you prefer eating out or cooking at home? Has your diet changed in recent years?',
      },
      {
        'topic': 'Technology & Devices',
        'questions':
            'How often do you use your smartphone? What apps do you use most often? Do you think people are too dependent on technology?',
      },
    ];

    const part2Bank = [
      'Describe a book you read recently. You should say:\n• What the book is about\n• Why you decided to read it\n• What you liked or disliked about it\nAnd explain what you learned from reading it.',
      'Describe a memorable journey you took. You should say:\n• Where you went and how you travelled\n• Who was with you\n• What happened during the journey\nAnd explain why the journey was memorable.',
      'Describe an important decision you made in your life. You should say:\n• What the decision was\n• When and why you made it\n• What the outcome was\nAnd explain how the decision has affected your life.',
      'Describe a person who has had a significant influence on your life. You should say:\n• Who this person is\n• How you know them\n• What they did that influenced you\nAnd explain how your life changed as a result.',
      'Describe a skill you would like to learn in the future. You should say:\n• What the skill is\n• Why you want to learn it\n• How you plan to learn it\nAnd explain how this skill would benefit your life.',
    ];

    const part3Bank = [
      {
        'topic': 'Reading Habits in Society',
        'questions':
            'Do you think children read less nowadays than in the past? How has digital technology influenced reading habits? What are the benefits of reading physical books?',
      },
      {
        'topic': 'Travel & Global Culture',
        'questions':
            'What are the environmental impacts of mass tourism? How does international travel promote cultural understanding? Should governments restrict tourism to protect natural sites?',
      },
      {
        'topic': 'Decision Making & Influence',
        'questions':
            'At what age should people be allowed to make their own major life decisions? How do family and culture influence career choices? Is it better to follow your passion or choose a stable career?',
      },
      {
        'topic': 'Technology & Society',
        'questions':
            'Has social media made society more or less connected? What responsibilities do tech companies have for the content on their platforms? Do you think AI will replace most human jobs?',
      },
    ];

    final rng = DateTime.now().millisecondsSinceEpoch;
    final p1Idx = rng % part1Bank.length;
    final p2Idx = (rng ~/ 11) % part2Bank.length;
    final p3Idx = (rng ~/ 17) % part3Bank.length;

    // Try DB queries filtered by part number
    final part1Rows = await _randomRows(db, 'speaking_prompts',
        where: 'part = ?', whereArgs: [1], limit: 1);
    final part2Rows = await _randomRows(db, 'speaking_prompts',
        where: 'part = ? AND (prompt_card IS NOT NULL AND prompt_card != "")',
        whereArgs: [2],
        limit: 1);
    final part3Rows = await _randomRows(db, 'speaking_prompts',
        where: 'part = ?', whereArgs: [3], limit: 1);

    final p1Topic = (part1Rows.isNotEmpty &&
            (part1Rows.first['topic']?.toString() ?? '').isNotEmpty &&
            !(part1Rows.first['topic']?.toString() ?? '').contains('Academic Topic'))
        ? part1Rows.first['topic']!.toString()
        : part1Bank[p1Idx]['topic']!;
    final p1Questions = (part1Rows.isNotEmpty &&
            (part1Rows.first['questions']?.toString() ?? '').isNotEmpty &&
            !(part1Rows.first['questions']?.toString() ?? '').contains('Question A'))
        ? part1Rows.first['questions']!.toString()
        : part1Bank[p1Idx]['questions']!;

    final cueCard = (part2Rows.isNotEmpty &&
            (part2Rows.first['prompt_card']?.toString() ?? '').length > 20 &&
            !(part2Rows.first['prompt_card']?.toString() ?? '').contains('had to '))
        ? part2Rows.first['prompt_card']!.toString()
        : part2Bank[p2Idx];

    final p3Topic = (part3Rows.isNotEmpty &&
            (part3Rows.first['topic']?.toString() ?? '').isNotEmpty &&
            !(part3Rows.first['topic']?.toString() ?? '').contains('Academic Topic'))
        ? part3Rows.first['topic']!.toString()
        : part3Bank[p3Idx]['topic']!;
    final p3Questions = (part3Rows.isNotEmpty &&
            (part3Rows.first['questions']?.toString() ?? '').isNotEmpty &&
            !(part3Rows.first['questions']?.toString() ?? '').contains('Question A'))
        ? part3Rows.first['questions']!.toString()
        : part3Bank[p3Idx]['questions']!;

    return [
      MockExamQuestion(
        id: 'ielts_speaking_part_1',
        category: 'Speaking',
        type: 'Part 1 – $p1Topic',
        kind: MockQuestionKind.speaking,
        prompt: p1Questions,
        explanation: 'Part 1 menguji respons spontan pada topik familiar. Jawab dengan 2–3 kalimat per pertanyaan.',
        speakingSeconds: 240,
      ),
      MockExamQuestion(
        id: 'ielts_speaking_part_2',
        category: 'Speaking',
        type: 'Part 2 – Cue Card',
        kind: MockQuestionKind.speaking,
        prompt: cueCard,
        explanation:
            'Part 2: Anda memiliki 1 menit untuk mempersiapkan jawaban, kemudian berbicara selama 2 menit menggunakan poin-poin pada cue card.',
        speakingSeconds: 120,
      ),
      MockExamQuestion(
        id: 'ielts_speaking_part_3',
        category: 'Speaking',
        type: 'Part 3 – $p3Topic',
        kind: MockQuestionKind.speaking,
        prompt: p3Questions,
        explanation:
            'Part 3 menguji kemampuan berdiskusi dan berargumentasi secara abstrak. Berikan alasan, contoh, dan perbandingan.',
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
    final isJp = language == 'JAPANESE';

    final jpQuestions = [
      MockExamQuestion(
        id: 'fallback_reading_jp_0',
        category: 'Reading',
        type: 'Reading Comprehension',
        kind: MockQuestionKind.multipleChoice,
        passage: 'きょうはいい天気です。わたしはともだちと公園へ行きます。公園でサッカーをします。それから、いっしょに晩ご飯を食べます。',
        prompt: 'きょうは何をしますか？',
        options: const ['ともだちと公園でサッカーをする', '一人で家で勉強する', '学校で先生と話す', '図書館で本を読む'],
        correctAnswerIndex: 0,
        explanation: '文章によると、今日は友達と公園でサッカーをします。',
      ),
      MockExamQuestion(
        id: 'fallback_reading_jp_1',
        category: 'Reading',
        type: 'Reading Comprehension',
        kind: MockQuestionKind.multipleChoice,
        passage: 'わたしの部屋はせまいですが、きれいです。机の上に本が三冊あります。窓のそばにいすがあります。',
        prompt: '机の上に何がありますか？',
        options: const ['本が三冊', 'いすが一つ', 'かばんが二つ', 'ペンが五本'],
        correctAnswerIndex: 0,
        explanation: '文章によると、机の上に本が三冊あります。',
      ),
      MockExamQuestion(
        id: 'fallback_reading_jp_2',
        category: 'Reading',
        type: 'Reading Comprehension',
        kind: MockQuestionKind.multipleChoice,
        passage: 'スーパーの前にバスていがあります。バスていのとなりにゆうびんきょくがあります。ゆうびんきょくのうしろにこうえんがあります。',
        prompt: 'ゆうびんきょくはどこにありますか？',
        options: const ['バスていのとなり', 'こうえんのうしろ', 'スーパーの中', '学校のちかく'],
        correctAnswerIndex: 0,
        explanation: '文章によると、郵便局はバス停の隣にあります。',
      ),
      MockExamQuestion(
        id: 'fallback_reading_jp_3',
        category: 'Reading',
        type: 'Reading Comprehension',
        kind: MockQuestionKind.multipleChoice,
        passage: 'たなかさんは毎朝六時に起きます。シャワーをあびて、朝ごはんを食べます。七時半に家を出て、電車で会社へ行きます。',
        prompt: 'たなかさんは何時に起きますか？',
        options: const ['六時', '七時', '七時半', '八時'],
        correctAnswerIndex: 0,
        explanation: '文章によると、田中さんは毎朝6時に起きます。',
      ),
      MockExamQuestion(
        id: 'fallback_reading_jp_4',
        category: 'Reading',
        type: 'Reading Comprehension',
        kind: MockQuestionKind.multipleChoice,
        passage: '春は花見のきせつです。日本人は公園で桜の花を見ながら食べたり飲んだりします。桜はふつう四月ごろに咲きます。',
        prompt: '桜はいつ咲きますか？',
        options: const ['四月ごろ', '一月ごろ', '七月ごろ', '十月ごろ'],
        correctAnswerIndex: 0,
        explanation: '文章によると、桜は普通四月頃に咲きます。',
      ),
      MockExamQuestion(
        id: 'fallback_reading_jp_5',
        category: 'Reading',
        type: 'Reading Comprehension',
        kind: MockQuestionKind.multipleChoice,
        passage: 'このお知らせを読んでください。来週の月曜日から図書館は午後五時に閉まります。今まで午後七時まで開いていました。',
        prompt: '来週から図書館は何時に閉まりますか？',
        options: const ['午後五時', '午後七時', '午前九時', '午後八時'],
        correctAnswerIndex: 0,
        explanation: 'お知らせによると、来週から図書館は午後5時に閉まります。',
      ),
      MockExamQuestion(
        id: 'fallback_reading_jp_6',
        category: 'Reading',
        type: 'Reading Comprehension',
        kind: MockQuestionKind.multipleChoice,
        passage: '山田さんは料理が上手です。毎日自分でご飯を作ります。好きな料理はカレーと寿司です。今日の晩ご飯は寿司を作りました。',
        prompt: '今日の晩ご飯は何ですか？',
        options: const ['寿司', 'カレー', 'ラーメン', 'うどん'],
        correctAnswerIndex: 0,
        explanation: '文章によると、今日の晩御飯は寿司です。',
      ),
      MockExamQuestion(
        id: 'fallback_reading_jp_7',
        category: 'Reading',
        type: 'Reading Comprehension',
        kind: MockQuestionKind.multipleChoice,
        passage: '電車の中にわすれものをした時は、えきのサービスセンターに行ってください。名前と電話番号を書いて、係りの人に見せてください。',
        prompt: 'わすれものをした時、どこへ行きますか？',
        options: const ['えきのサービスセンター', '警察のほんぶ', '市役所', '郵便局'],
        correctAnswerIndex: 0,
        explanation: '文章によると、忘れ物をした時は駅のサービスセンターへ行きます。',
      ),
      MockExamQuestion(
        id: 'fallback_reading_jp_8',
        category: 'Reading',
        type: 'Reading Comprehension',
        kind: MockQuestionKind.multipleChoice,
        passage: 'わたしは先月、日本語の試験を受けました。結果は来週でます。とても緊張しています。合格したらパーティーをしたいです。',
        prompt: 'この人はなぜ緊張していますか？',
        options: const ['試験の結果を待っているから', 'パーティーに行くから', '仕事が忙しいから', '友達と会うから'],
        correctAnswerIndex: 0,
        explanation: '試験の結果を待っているので、緊張しています。',
      ),
      MockExamQuestion(
        id: 'fallback_reading_jp_9',
        category: 'Reading',
        type: 'Reading Comprehension',
        kind: MockQuestionKind.multipleChoice,
        passage: 'きのうの夜、かぜをひいて頭が痛くなりました。病院へ行って薬をもらいました。今日は会社を休んで、家でゆっくりしています。',
        prompt: '今日この人はどこにいますか？',
        options: const ['家', '病院', '会社', '学校'],
        correctAnswerIndex: 0,
        explanation: '今日は会社を休んで家にいます。',
      ),
      MockExamQuestion(
        id: 'fallback_reading_jp_10',
        category: 'Reading',
        type: 'Reading Comprehension',
        kind: MockQuestionKind.multipleChoice,
        passage: 'このレストランは月曜日から金曜日まで、ひる十一時から夜九時まで開いています。土曜日と日曜日は休みです。',
        prompt: 'このレストランはいつ休みですか？',
        options: const ['土曜日と日曜日', '月曜日と火曜日', '毎日開いています', '金曜日'],
        correctAnswerIndex: 0,
        explanation: 'レストランは土曜日と日曜日が休みです。',
      ),
      MockExamQuestion(
        id: 'fallback_reading_jp_11',
        category: 'Reading',
        type: 'Reading Comprehension',
        kind: MockQuestionKind.multipleChoice,
        passage: '日本では、食事の前に「いただきます」と言います。食事の後には「ごちそうさまでした」と言います。これは大切なマナーです。',
        prompt: '食事の後に何と言いますか？',
        options: const ['ごちそうさまでした', 'いただきます', 'ありがとうございます', 'おやすみなさい'],
        correctAnswerIndex: 0,
        explanation: '食事の後には「ごちそうさまでした」と言います。',
      ),
    ];

    final enQuestions = [
      MockExamQuestion(
        id: 'fallback_reading_en_0',
        category: 'Reading',
        type: 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: 'A university notice explains changes to library opening hours during examination week. The library will now close at 11 PM instead of 9 PM.',
        prompt: 'What is the main purpose of the notice?',
        options: const ['To announce a schedule change', 'To sell a product', 'To describe a person', 'To invite a complaint'],
        correctAnswerIndex: 0,
        explanation: 'The notice announces a change to opening hours.',
      ),
      MockExamQuestion(
        id: 'fallback_reading_en_1',
        category: 'Reading',
        type: 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: 'Researchers found that regular exercise significantly reduces the risk of cardiovascular disease. A 30-minute walk five days a week is sufficient for most adults.',
        prompt: 'According to the text, how much exercise is recommended per week?',
        options: const ['30 minutes, 5 times', '1 hour daily', '15 minutes, 7 times', '2 hours, 3 times'],
        correctAnswerIndex: 0,
        explanation: 'The passage recommends 30 minutes five times a week.',
      ),
      MockExamQuestion(
        id: 'fallback_reading_en_2',
        category: 'Reading',
        type: 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: 'The Amazon rainforest produces approximately 20% of the world\'s oxygen. Deforestation threatens the ecological balance and contributes significantly to climate change.',
        prompt: 'What percentage of the world\'s oxygen does the Amazon produce?',
        options: const ['20%', '10%', '50%', '5%'],
        correctAnswerIndex: 0,
        explanation: 'The Amazon produces approximately 20% of the world\'s oxygen.',
      ),
      MockExamQuestion(
        id: 'fallback_reading_en_3',
        category: 'Reading',
        type: 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: 'Solar power has grown dramatically over the past decade. The cost of installing solar panels has dropped by 89% since 2010, making it the cheapest electricity source in history.',
        prompt: 'By how much has the cost of solar panels dropped since 2010?',
        options: const ['89%', '50%', '30%', '75%'],
        correctAnswerIndex: 0,
        explanation: 'The cost of solar panels dropped by 89% since 2010.',
      ),
      MockExamQuestion(
        id: 'fallback_reading_en_4',
        category: 'Reading',
        type: 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: 'Remote work has transformed the modern workplace. Studies show that employees who work from home report higher job satisfaction but lower social interaction compared to office workers.',
        prompt: 'What is a disadvantage of remote work mentioned in the passage?',
        options: const ['Lower social interaction', 'Less job satisfaction', 'Higher commuting costs', 'More overtime hours'],
        correctAnswerIndex: 0,
        explanation: 'Remote workers have lower social interaction according to the studies.',
      ),
      MockExamQuestion(
        id: 'fallback_reading_en_5',
        category: 'Reading',
        type: 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: 'Plastic pollution in oceans has reached alarming levels. Over eight million tons of plastic enter the sea annually, threatening marine ecosystems and entering the food chain.',
        prompt: 'How much plastic enters the sea each year?',
        options: const ['Over eight million tons', 'Under one million tons', 'Exactly five million tons', 'Three billion kilograms'],
        correctAnswerIndex: 0,
        explanation: 'Over eight million tons of plastic enter the sea annually.',
      ),
      MockExamQuestion(
        id: 'fallback_reading_en_6',
        category: 'Reading',
        type: 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: 'The human brain contains approximately 86 billion neurons. These neurons communicate via electrical signals and form the basis of all thought, memory, and emotion.',
        prompt: 'How many neurons does the human brain contain?',
        options: const ['86 billion', '1 trillion', '10 million', '500 billion'],
        correctAnswerIndex: 0,
        explanation: 'The human brain has approximately 86 billion neurons.',
      ),
      MockExamQuestion(
        id: 'fallback_reading_en_7',
        category: 'Reading',
        type: 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: 'Artificial intelligence is being used increasingly in healthcare diagnostics. AI systems can now detect certain cancers from medical imaging with accuracy comparable to experienced radiologists.',
        prompt: 'What can AI systems do in healthcare according to the passage?',
        options: const ['Detect cancers from medical imaging', 'Perform surgical operations', 'Prescribe medications', 'Replace all doctors'],
        correctAnswerIndex: 0,
        explanation: 'AI can detect certain cancers from medical imaging with high accuracy.',
      ),
      MockExamQuestion(
        id: 'fallback_reading_en_8',
        category: 'Reading',
        type: 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: 'Urban farming is gaining popularity worldwide. By growing food in cities, communities can reduce transport costs, decrease carbon emissions, and provide fresh produce year-round.',
        prompt: 'What is one benefit of urban farming mentioned?',
        options: const ['Reduced transport costs', 'Higher product prices', 'More pesticide use', 'Larger farms'],
        correctAnswerIndex: 0,
        explanation: 'Urban farming can reduce transport costs among other benefits.',
      ),
      MockExamQuestion(
        id: 'fallback_reading_en_9',
        category: 'Reading',
        type: 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: 'Sleep is essential for memory consolidation. During sleep, the brain transfers information from short-term to long-term memory. Adults need 7-9 hours per night for optimal cognitive function.',
        prompt: 'How many hours of sleep do adults need per night?',
        options: const ['7-9 hours', '5-6 hours', '10-12 hours', 'Exactly 8 hours'],
        correctAnswerIndex: 0,
        explanation: 'Adults need 7-9 hours per night for optimal cognitive function.',
      ),
      MockExamQuestion(
        id: 'fallback_reading_en_10',
        category: 'Reading',
        type: 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: 'Biodiversity refers to the variety of life on Earth. Scientists estimate that over 8 million species exist, but only about 1.5 million have been formally documented and classified.',
        prompt: 'How many species have been formally documented?',
        options: const ['About 1.5 million', 'Over 8 million', 'Exactly 3 million', 'Fewer than 100,000'],
        correctAnswerIndex: 0,
        explanation: 'Only about 1.5 million species have been formally documented.',
      ),
      MockExamQuestion(
        id: 'fallback_reading_en_11',
        category: 'Reading',
        type: 'Academic Reading',
        kind: MockQuestionKind.multipleChoice,
        passage: 'Digital literacy has become a critical skill in the 21st century. The ability to evaluate online sources, understand data privacy, and use technology safely is now as important as reading and writing.',
        prompt: 'According to the passage, digital literacy is compared to which other skill?',
        options: const ['Reading and writing', 'Mathematics and science', 'History and geography', 'Art and music'],
        correctAnswerIndex: 0,
        explanation: 'Digital literacy is compared to reading and writing as an essential skill.',
      ),
    ];

    final source = isJp ? jpQuestions : enQuestions;
    return List.generate(limit, (i) => source[i % source.length]);
  }

  List<MockExamQuestion> _fallbackListeningQuestions(
      String language, int limit) {
    final isJp = language == 'JAPANESE';

    final jpQuestions = [
      MockExamQuestion(
        id: 'fallback_listening_jp_0',
        category: 'Listening',
        type: 'Short Conversation',
        kind: MockQuestionKind.multipleChoice,
        transcript: '女：明日のパーティーは何時に始まりますか？男：午後六時に始まりますよ。女：分かりました。ありがとうございます。',
        prompt: 'パーティーは何時に始まりますか？',
        options: const ['午後五時', '午後六時', '午後七時', '午後八時'],
        correctAnswerIndex: 1,
        explanation: '男の人は「午後六時に始まります」と言いました。',
      ),
      MockExamQuestion(
        id: 'fallback_listening_jp_1',
        category: 'Listening',
        type: 'Short Conversation',
        kind: MockQuestionKind.multipleChoice,
        transcript: '男：すみません、駅はどこですか？女：あそこの角を右に曲がってください。まっすぐ行くと左側にあります。男：ありがとうございます。',
        prompt: '駅へはどう行きますか？',
        options: const ['角を右、それからまっすぐ', 'まっすぐ右', 'まず左、次に右', '地下鉄で行く'],
        correctAnswerIndex: 0,
        explanation: '角を右に曲がって、まっすぐ進むと左側にあります。',
      ),
      MockExamQuestion(
        id: 'fallback_listening_jp_2',
        category: 'Listening',
        type: 'Short Conversation',
        kind: MockQuestionKind.multipleChoice,
        transcript: '女：このりんごはいくらですか？男：一つ百五十円です。女：じゃ、三つください。男：ありがとうございます。四百五十円です。',
        prompt: 'りんごを三つ買うといくらですか？',
        options: const ['三百円', '四百五十円', '五百円', '二百円'],
        correctAnswerIndex: 1,
        explanation: 'りんごは1つ150円なので、3つで450円です。',
      ),
      MockExamQuestion(
        id: 'fallback_listening_jp_3',
        category: 'Listening',
        type: 'Short Conversation',
        kind: MockQuestionKind.multipleChoice,
        transcript: '男：田中さん、今日の会議は何時からですか？女：午前十時からです。でも、山田部長が五分遅れると連絡が来ました。男：そうですか。分かりました。',
        prompt: '山田部長は何時ごろ来ますか？',
        options: const ['午前十時五分', '午前十時', '午前九時五十五分', '午前十一時'],
        correctAnswerIndex: 0,
        explanation: '会議は10時からで、山田部長は5分遅れるので10時5分ごろ来ます。',
      ),
      MockExamQuestion(
        id: 'fallback_listening_jp_4',
        category: 'Listening',
        type: 'Short Conversation',
        kind: MockQuestionKind.multipleChoice,
        transcript: '女：もしもし、山田です。今日の練習、何を持っていけばいいですか？男：ユニフォームとシューズを持ってきてください。水は自分で用意してね。',
        prompt: '何を持っていきますか？',
        options: const ['ユニフォームとシューズ', 'ボールと水', 'シューズだけ', 'ユニフォームと水'],
        correctAnswerIndex: 0,
        explanation: 'ユニフォームとシューズを持っていきます。',
      ),
      MockExamQuestion(
        id: 'fallback_listening_jp_5',
        category: 'Listening',
        type: 'Short Conversation',
        kind: MockQuestionKind.multipleChoice,
        transcript: '男：すみません、この電車は新宿に止まりますか？女：いいえ、止まりません。次の駅で乗り換えてください。急行に乗ると新宿まで行けますよ。',
        prompt: 'この人はどうすれば新宿へ行けますか？',
        options: const ['次の駅で急行に乗り換える', 'この電車でそのまま行く', '歩いて行く', 'タクシーに乗る'],
        correctAnswerIndex: 0,
        explanation: '次の駅で急行に乗り換えると新宿へ行けます。',
      ),
      MockExamQuestion(
        id: 'fallback_listening_jp_6',
        category: 'Listening',
        type: 'Short Conversation',
        kind: MockQuestionKind.multipleChoice,
        transcript: '女：先生、宿題はいつまでですか？男：来週の月曜日までです。でも、できれば金曜日までに出してくれると助かります。',
        prompt: '宿題はいつまでに出せばいいですか？',
        options: const ['来週の月曜日まで', '今週の金曜日まで', '今日まで', '来週の水曜日まで'],
        correctAnswerIndex: 0,
        explanation: '提出期限は来週月曜日ですが、できれば金曜日が望ましいです。',
      ),
      MockExamQuestion(
        id: 'fallback_listening_jp_7',
        category: 'Listening',
        type: 'Short Conversation',
        kind: MockQuestionKind.multipleChoice,
        transcript: '男：ちょっと待って！傘を持った？天気予報では午後から雨だって。女：あ、ほんとだ。ありがとう。持っていくね。',
        prompt: 'なぜ女の人は傘を持っていきますか？',
        options: const ['午後から雨が降るから', '毎日傘を使うから', '忘れると困るから', '男の人に頼まれたから'],
        correctAnswerIndex: 0,
        explanation: '天気予報で午後から雨が降るからです。',
      ),
      MockExamQuestion(
        id: 'fallback_listening_jp_8',
        category: 'Listening',
        type: 'Short Conversation',
        kind: MockQuestionKind.multipleChoice,
        transcript: '女：このケーキ、とてもおいしいですね！どこで買いましたか？男：駅の近くの新しいお店です。昨日開いたばかりですよ。女：ぜひ行ってみます。',
        prompt: 'ケーキはどこで買いましたか？',
        options: const ['駅の近くの新しいお店', 'デパートの地下', '友達の家', 'コンビニ'],
        correctAnswerIndex: 0,
        explanation: '駅の近くの新しいお店で買いました。',
      ),
      MockExamQuestion(
        id: 'fallback_listening_jp_9',
        category: 'Listening',
        type: 'Short Conversation',
        kind: MockQuestionKind.multipleChoice,
        transcript: '男：もしもし。今どこ？女：今、バスに乗っているところ。あと二十分くらいで着くと思う。男：わかった。じゃ、入口で待ってるね。',
        prompt: '女の人はあとどのくらいで着きますか？',
        options: const ['約二十分', '約十分', 'もう着いている', '約一時間'],
        correctAnswerIndex: 0,
        explanation: 'バスに乗っていて、あと約20分で着くと言っています。',
      ),
      MockExamQuestion(
        id: 'fallback_listening_jp_10',
        category: 'Listening',
        type: 'Short Conversation',
        kind: MockQuestionKind.multipleChoice,
        transcript: '女：すみません、コーヒーをひとつください。男：ホットとアイス、どちらになさいますか？女：ホットでお願いします。砂糖はいりません。',
        prompt: '女の人はどんなコーヒーを注文しましたか？',
        options: const ['ホット・砂糖なし', 'アイス・砂糖あり', 'ホット・砂糖あり', 'アイス・砂糖なし'],
        correctAnswerIndex: 0,
        explanation: 'ホットコーヒーで砂糖なしを注文しました。',
      ),
      MockExamQuestion(
        id: 'fallback_listening_jp_11',
        category: 'Listening',
        type: 'Short Conversation',
        kind: MockQuestionKind.multipleChoice,
        transcript: '男：山田さん、今日の発表はよかったですね。女：ありがとうございます。でも、緊張してしまって、大事なところを忘れてしまいました。男：そうですか。全然気づきませんでしたよ。',
        prompt: '女の人の発表はどうでしたか？',
        options: const ['大事なところを忘れた', 'とても完璧だった', '時間が足りなかった', '資料を忘れた'],
        correctAnswerIndex: 0,
        explanation: '緊張して大事なところを忘れてしまいました。',
      ),
    ];

    final enQuestions = [
      MockExamQuestion(
        id: 'fallback_listening_en_0',
        category: 'Listening',
        type: 'IELTS Listening Part 1',
        kind: MockQuestionKind.multipleChoice,
        transcript: 'The student asks about accommodation. The officer says the single room costs one hundred and twenty pounds per week.',
        prompt: 'How much is the weekly rent for a single room?',
        options: const ['120 pounds', '150 pounds', '90 pounds', '200 pounds'],
        correctAnswerIndex: 0,
        explanation: 'The officer clearly states the single room costs 120 pounds per week.',
      ),
      MockExamQuestion(
        id: 'fallback_listening_en_1',
        category: 'Listening',
        type: 'IELTS Listening Part 1',
        kind: MockQuestionKind.multipleChoice,
        transcript: 'The caller asks about the museum opening hours. The receptionist says it opens at 9 AM and closes at 5 PM on weekdays, and closes at 3 PM on Sundays.',
        prompt: 'What time does the museum close on Sundays?',
        options: const ['3 PM', '5 PM', '6 PM', '4 PM'],
        correctAnswerIndex: 0,
        explanation: 'The receptionist states the museum closes at 3 PM on Sundays.',
      ),
      MockExamQuestion(
        id: 'fallback_listening_en_2',
        category: 'Listening',
        type: 'IELTS Listening Part 2',
        kind: MockQuestionKind.multipleChoice,
        transcript: 'Welcome to the city tour. Our first stop will be the central market, then the art gallery. After lunch at the harbour restaurant, we will visit the botanical gardens.',
        prompt: 'Where will the group go after lunch?',
        options: const ['Botanical gardens', 'Central market', 'Art gallery', 'Harbour restaurant'],
        correctAnswerIndex: 0,
        explanation: 'After lunch at the harbour restaurant, the group visits the botanical gardens.',
      ),
      MockExamQuestion(
        id: 'fallback_listening_en_3',
        category: 'Listening',
        type: 'IELTS Listening Part 2',
        kind: MockQuestionKind.multipleChoice,
        transcript: 'Good morning. The college library will be closed for renovation from Monday to Wednesday next week. Students may use the computer lab as an alternative.',
        prompt: 'What can students use while the library is closed?',
        options: const ['Computer lab', 'Study café', 'Another library', 'City hall'],
        correctAnswerIndex: 0,
        explanation: 'Students may use the computer lab as an alternative.',
      ),
      MockExamQuestion(
        id: 'fallback_listening_en_4',
        category: 'Listening',
        type: 'IELTS Listening Part 3',
        kind: MockQuestionKind.multipleChoice,
        transcript: 'Tutor: So, for your research project, what topic have you chosen? Student: I have decided to focus on the impact of social media on mental health among teenagers.',
        prompt: 'What is the student\'s research topic?',
        options: const ['Social media and teen mental health', 'Climate change solutions', 'Online shopping trends', 'Language learning apps'],
        correctAnswerIndex: 0,
        explanation: 'The student chose to study the impact of social media on teenage mental health.',
      ),
      MockExamQuestion(
        id: 'fallback_listening_en_5',
        category: 'Listening',
        type: 'IELTS Listening Part 3',
        kind: MockQuestionKind.multipleChoice,
        transcript: 'The assignment deadline has been extended. Dr. Brown announced that students now have until Friday the 15th, rather than the original Monday the 12th.',
        prompt: 'When is the new assignment deadline?',
        options: const ['Friday the 15th', 'Monday the 12th', 'Wednesday the 14th', 'Sunday the 11th'],
        correctAnswerIndex: 0,
        explanation: 'The new deadline is Friday the 15th, extended from Monday the 12th.',
      ),
      MockExamQuestion(
        id: 'fallback_listening_en_6',
        category: 'Listening',
        type: 'IELTS Listening Part 4',
        kind: MockQuestionKind.multipleChoice,
        transcript: 'Today\'s lecture covers renewable energy sources. Solar power is currently the fastest growing energy source globally, with installations doubling every two years.',
        prompt: 'How often does solar installation double?',
        options: const ['Every two years', 'Every five years', 'Every year', 'Every decade'],
        correctAnswerIndex: 0,
        explanation: 'The lecturer states solar installations double every two years.',
      ),
      MockExamQuestion(
        id: 'fallback_listening_en_7',
        category: 'Listening',
        type: 'IELTS Listening Part 4',
        kind: MockQuestionKind.multipleChoice,
        transcript: 'In today\'s talk on migration, we see that about 272 million people live outside their country of birth. Economic opportunity is cited as the primary reason for international migration.',
        prompt: 'What is the main reason for international migration?',
        options: const ['Economic opportunity', 'Climate change', 'Political conflict', 'Family reunification'],
        correctAnswerIndex: 0,
        explanation: 'Economic opportunity is cited as the primary reason.',
      ),
      MockExamQuestion(
        id: 'fallback_listening_en_8',
        category: 'Listening',
        type: 'IELTS Listening Part 1',
        kind: MockQuestionKind.multipleChoice,
        transcript: 'The travel agent confirms the booking. The flight departs at 7:45 AM from Terminal 2. The passenger should arrive at least two hours before departure.',
        prompt: 'From which terminal does the flight depart?',
        options: const ['Terminal 2', 'Terminal 1', 'Terminal 3', 'Terminal 4'],
        correctAnswerIndex: 0,
        explanation: 'The travel agent confirms the departure is from Terminal 2.',
      ),
      MockExamQuestion(
        id: 'fallback_listening_en_9',
        category: 'Listening',
        type: 'IELTS Listening Part 2',
        kind: MockQuestionKind.multipleChoice,
        transcript: 'For the community garden project, volunteers are needed every Saturday morning from 8 to 11. Bring your own gloves. Tools will be provided by the council.',
        prompt: 'What should volunteers bring to the community garden?',
        options: const ['Their own gloves', 'Garden tools', 'Lunch for all', 'Watering cans'],
        correctAnswerIndex: 0,
        explanation: 'Volunteers should bring their own gloves. Tools are provided.',
      ),
      MockExamQuestion(
        id: 'fallback_listening_en_10',
        category: 'Listening',
        type: 'IELTS Listening Part 3',
        kind: MockQuestionKind.multipleChoice,
        transcript: 'Student A: I think we should present the environmental section first. Student B: Agreed. It sets the context for everything else. We can follow with economic impacts.',
        prompt: 'What will the students present first?',
        options: const ['Environmental section', 'Economic impacts', 'Social effects', 'Historical background'],
        correctAnswerIndex: 0,
        explanation: 'Both students agree to present the environmental section first.',
      ),
      MockExamQuestion(
        id: 'fallback_listening_en_11',
        category: 'Listening',
        type: 'IELTS Listening Part 4',
        kind: MockQuestionKind.multipleChoice,
        transcript: 'This week\'s psychology lecture covers cognitive biases. Confirmation bias, the tendency to favor information that confirms existing beliefs, is one of the most well-documented biases.',
        prompt: 'What is confirmation bias?',
        options: const [
          'Favoring information that confirms existing beliefs',
          'Being overly optimistic about outcomes',
          'Making decisions based on first impressions',
          'Avoiding information that is unpleasant'
        ],
        correctAnswerIndex: 0,
        explanation: 'Confirmation bias is the tendency to favor information that confirms existing beliefs.',
      ),
    ];

    final source = isJp ? jpQuestions : enQuestions;
    return List.generate(limit, (i) => source[i % source.length]);
  }

  static const List<String> _fallbackJpMeanings = [
    'Guru',
    'Siswa',
    'Buku',
    'Mobil',
    'Air',
    'Meja',
    'Rumah',
    'Sekolah',
    'Makan',
    'Minum',
  ];

  static const List<String> _fallbackJpGrammarOptions = [
    'から',
    'ので',
    'ながら',
    'てから',
    'ば',
    'たら',
    'と',
    'より',
  ];

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
