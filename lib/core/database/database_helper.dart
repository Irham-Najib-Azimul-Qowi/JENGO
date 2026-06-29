import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class DatabaseHelper {
  static const _databaseName = "jengo.db";
  static const _databaseVersion = 4;

  // Singleton Instance
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      await db.execute("DROP TABLE IF EXISTS gamification");
      await db.execute("DROP TABLE IF EXISTS chapters");
      await db.execute("DROP TABLE IF EXISTS vocabulary");
      await db.execute("DROP TABLE IF EXISTS kanji");
      await db.execute("DROP TABLE IF EXISTS reading");
      await db.execute("DROP TABLE IF EXISTS listening");
      await db.execute("DROP TABLE IF EXISTS grammar");
      await db.execute("DROP TABLE IF EXISTS sentences");
      await db.execute("DROP TABLE IF EXISTS speaking_prompts");
      await db.execute("DROP TABLE IF EXISTS writing_prompts");
      await db.execute("DROP TABLE IF EXISTS simulations_history");
      await _onCreate(db, newVersion);
    }
  }

  Future _onCreate(Database db, int version) async {
    // 1. Buat Tabel Gamifikasi
    await db.execute('''
      CREATE TABLE gamification (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_xp INTEGER NOT NULL,
        current_level INTEGER NOT NULL,
        current_streak INTEGER NOT NULL,
        hearts INTEGER NOT NULL,
        gems INTEGER NOT NULL,
        start_time INTEGER NOT NULL,
        current_day INTEGER DEFAULT 1,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    // 2. Buat Tabel Chapters (20 Stage Bulanan)
    await db.execute('''
      CREATE TABLE chapters (
        id INTEGER PRIMARY KEY,
        chapter_number INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        status TEXT NOT NULL -- ACTIVE, LOCKED, COMPLETED
      )
    ''');

    // 3. Buat Tabel Kosakata (Vocabulary)
    await db.execute('''
      CREATE TABLE vocabulary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL,
        reading TEXT,
        translation TEXT NOT NULL,
        language TEXT NOT NULL, -- JAPANESE, ENGLISH
        difficulty_level TEXT NOT NULL,
        box_level INTEGER DEFAULT 1, -- Untuk Leitner/SRS (Box 1-5)
        next_review_time INTEGER NOT NULL
      )
    ''');

    // 4. Buat Tabel Kanji (Jepang)
    await db.execute('''
      CREATE TABLE kanji (
        id INTEGER PRIMARY KEY,
        kanji TEXT NOT NULL,
        level TEXT NOT NULL,
        meaning TEXT NOT NULL,
        onyomi TEXT NOT NULL,
        kunyomi TEXT NOT NULL,
        strokes INTEGER NOT NULL
      )
    ''');

    // 5. Buat Tabel Reading (Membaca)
    await db.execute('''
      CREATE TABLE reading (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        level TEXT NOT NULL,
        passage TEXT NOT NULL,
        translation TEXT NOT NULL,
        language TEXT NOT NULL, -- JAPANESE, ENGLISH
        questions TEXT NOT NULL -- Menyimpan JSON string soal
      )
    ''');

    // 6. Buat Tabel Listening (Mendengar)
    await db.execute('''
      CREATE TABLE listening (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        level TEXT NOT NULL,
        audio TEXT NOT NULL,
        transcript TEXT NOT NULL,
        translation TEXT NOT NULL,
        language TEXT NOT NULL, -- JAPANESE, ENGLISH
        questions TEXT NOT NULL -- Menyimpan JSON string soal
      )
    ''');

    // 7. Buat Tabel Grammar (Tata Bahasa)
    await db.execute('''
      CREATE TABLE grammar (
        id INTEGER PRIMARY KEY,
        rule_name TEXT NOT NULL,
        level TEXT NOT NULL,
        explanation TEXT NOT NULL,
        tips TEXT NOT NULL,
        example_sentence TEXT NOT NULL,
        example_translation TEXT NOT NULL,
        language TEXT NOT NULL -- JAPANESE, ENGLISH
      )
    ''');

    // 8. Buat Tabel Sentences (Tatoeba Contoh Kalimat)
    await db.execute('''
      CREATE TABLE sentences (
        id INTEGER PRIMARY KEY,
        japanese TEXT NOT NULL,
        english TEXT NOT NULL,
        indonesian TEXT NOT NULL,
        word_mapped TEXT NOT NULL
      )
    ''');

    // 9. Buat Tabel Speaking Prompts (IELTS Speaking)
    await db.execute('''
      CREATE TABLE speaking_prompts (
        id INTEGER PRIMARY KEY,
        part INTEGER NOT NULL,
        topic TEXT NOT NULL,
        questions TEXT, -- Menyimpan JSON string daftar pertanyaan
        prompt_card TEXT,
        tips TEXT NOT NULL
      )
    ''');

    // 10. Buat Tabel Writing Prompts (IELTS Writing)
    await db.execute('''
      CREATE TABLE writing_prompts (
        id INTEGER PRIMARY KEY,
        task INTEGER NOT NULL,
        type TEXT NOT NULL,
        prompt TEXT NOT NULL,
        tips TEXT NOT NULL
      )
    ''');

    // 11. Buat Tabel Riwayat Simulasi Ujian (simulations_history)
    await db.execute('''
      CREATE TABLE simulations_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        language TEXT NOT NULL,
        level TEXT NOT NULL,
        overall_score REAL NOT NULL,
        sectional_scores TEXT NOT NULL,
        correct_answers INTEGER NOT NULL,
        total_questions INTEGER NOT NULL,
        weaknesses TEXT NOT NULL,
        recommendations TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    await db.insert('gamification', {
      'total_xp': 0,
      'current_level': 1,
      'current_streak': 0,
      'hearts': 5,
      'gems': 50,
      'start_time': DateTime.now().millisecondsSinceEpoch,
      'current_day': 1,
      'is_synced': 0,
    });

    for (int i = 1; i <= 20; i++) {
      await db.insert('chapters', {
        'id': i,
        'chapter_number': i,
        'title': _getStageTitle(i),
        'description': _getStageDescription(i),
        'status': i == 1 ? 'ACTIVE' : 'LOCKED',
      });
    }
  }

  String _getStageTitle(int i) {
    switch (i) {
      case 1: return "Stage 1: Hiragana & Basic English Vocab";
      case 2: return "Stage 2: Katakana & A1 Practice";
      case 3: return "Stage 3: N5 Vocabulary & A2 English";
      case 4: return "Stage 4: Basic Conversational Japanese";
      case 5: return "Stage 5: N4 Vocabulary & B1 English";
      case 6: return "Stage 6: N4 Grammar & Particles";
      case 7: return "Stage 7: Kanji Introduction & B2 English";
      case 8: return "Stage 8: Kanji Radicals & Sentence Building";
      case 9: return "Stage 9: N3 Vocabulary & Grammar";
      case 10: return "Stage 10: Intermediate Japanese Drills";
      case 11: return "Stage 11: Kanji Mastery (N3)";
      case 12: return "Stage 12: Complex Grammar (N3-N2)";
      case 13: return "Stage 13: N2 Vocabulary & Academic English";
      case 14: return "Stage 14: N2 Grammar Points";
      case 15: return "Stage 15: Advanced Kanji (N2)";
      case 16: return "Stage 16: JLPT N2 & IELTS Prep";
      case 17: return "Stage 17: Mock Exam Focus (JLPT & IELTS)";
      case 18: return "Stage 18: Advanced Contextual Training";
      case 19: return "Stage 19: Certification Readiness";
      default: return "Stage 20: Final Mastery & Graduation";
    }
  }

  String _getStageDescription(int i) {
    switch (i) {
      case 1: return "JP: Hiragana Flashcards & basic characters. EN: A1 Vocabulary & grammar foundation.";
      case 2: return "JP: Katakana Flashcards & simple pronunciation. EN: A1 Reading & listening comprehension.";
      case 3: return "JP: N5 Vocabulary Flashcards & simple particles. EN: A2 Vocabulary & typing drills.";
      case 4: return "JP: N5 Daily verbs & mixed drills. EN: A2 Reading, writing & speaking.";
      case 5: return "JP: N4 Vocabulary Flashcards & past tense verbs. EN: B1 Vocabulary & dictation.";
      case 6: return "JP: N4 Grammar points & mixed listening. EN: B1 Business vocab & writing prompt.";
      case 7: return "JP: Basic N3 Kanji characters. EN: B2 High-frequency academic vocabulary.";
      case 8: return "JP: Radical writing & reading passages. EN: B2 Active reading & speaking shadowing.";
      case 9: return "JP: N3 Vocabulary Flashcards & honorifics. EN: Advanced vocabulary expansion.";
      case 10: return "JP: Mixed listening & reading drills. EN: Speaking & writing self-evaluation.";
      case 11: return "JP: Kanji compound flashcards & onyomi/kunyomi. EN: Essay writing & dictation.";
      case 12: return "JP: Complex Grammar (N3-N2). EN: Academic listening & reading comprehension.";
      case 13: return "JP: N2 Vocabulary Flashcards. EN: Advanced IELTS vocabulary drills.";
      case 14: return "JP: N2 Grammar rules & context matching. EN: IELTS Academic writing practices.";
      case 15: return "JP: N2 Kanji character writing & reading. EN: IELTS Listening & dictation.";
      case 16: return "JP: N2 Mock Exam drills & reading. EN: IELTS Speaking & writing mocks.";
      case 17: return "JP: Full-length N2 reading/listening. EN: IELTS band 8.0 prep & evaluations.";
      case 18: return "JP: News reading & audio transcription. EN: IELTS Reading & academic speaking.";
      case 19: return "JP: Simulated JLPT N2 timed test. EN: IELTS band 8.0 full mock test.";
      default: return "JP: JLPT N2 final checkpoint. EN: IELTS Band 8.0 graduation checkpoint.";
    }
  }

  // Metode Pengisian (Seeding) Kosakata dalam Jumlah Besar secara Cepat
  Future<void> seedVocabularyList(List<dynamic> vocabList, String language) async {
    final db = await database;
    final batch = db.batch();
    for (var vocab in vocabList) {
      batch.insert(
        'vocabulary',
        {
          'word': vocab['word'],
          'reading': vocab['reading'] ?? '',
          'translation': vocab['meaning'] ?? '',
          'language': language,
          'difficulty_level': vocab['level'] ?? '',
          'box_level': 1,
          'next_review_time': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Metode Seeding Kanji Jepang
  Future<void> seedKanjiList(List<dynamic> kanjiList) async {
    final db = await database;
    final batch = db.batch();
    for (var k in kanjiList) {
      batch.insert(
        'kanji',
        {
          'id': k['id'],
          'kanji': k['kanji'],
          'level': k['level'],
          'meaning': k['meaning'],
          'onyomi': k['onyomi'],
          'kunyomi': k['kunyomi'],
          'strokes': k['strokes']
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Metode Seeding Bacaan (Reading)
  Future<void> seedReadingList(List<dynamic> readingList, String language) async {
    final db = await database;
    final batch = db.batch();
    for (var r in readingList) {
      batch.insert(
        'reading',
        {
          'id': r['id'],
          'title': r['title'],
          'level': r['level'],
          'passage': r['passage'],
          'translation': r['translation'],
          'language': language,
          'questions': jsonEncode(r['questions'])
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Metode Seeding Mendengar (Listening)
  Future<void> seedListeningList(List<dynamic> listeningList, String language) async {
    final db = await database;
    final batch = db.batch();
    for (var l in listeningList) {
      batch.insert(
        'listening',
        {
          'id': l['id'],
          'title': l['title'],
          'level': l['level'],
          'audio': l['audio'],
          'transcript': l['transcript'],
          'translation': l['translation'],
          'language': language,
          'questions': jsonEncode(l['questions'])
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Metode Seeding Grammar (Tata Bahasa)
  Future<void> seedGrammarList(List<dynamic> grammarList, String language) async {
    final db = await database;
    final batch = db.batch();
    for (var g in grammarList) {
      batch.insert(
        'grammar',
        {
          'id': g['id'],
          'rule_name': g['rule_name'],
          'level': g['level'],
          'explanation': g['explanation'],
          'tips': g['tips'],
          'example_sentence': g['example_sentence'],
          'example_translation': g['example_translation'],
          'language': language
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Metode Seeding Sentences (Tatoeba)
  Future<void> seedSentencesList(List<dynamic> sentenceList) async {
    final db = await database;
    final batch = db.batch();
    for (var s in sentenceList) {
      batch.insert(
        'sentences',
        {
          'id': s['id'],
          'japanese': s['japanese'],
          'english': s['english'],
          'indonesian': s['indonesian'],
          'word_mapped': s['word_mapped']
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Metode Seeding IELTS Speaking Prompts
  Future<void> seedSpeakingPrompts(List<dynamic> speakingList) async {
    final db = await database;
    final batch = db.batch();
    for (var sp in speakingList) {
      batch.insert(
        'speaking_prompts',
        {
          'id': sp['id'],
          'part': sp['part'],
          'topic': sp['topic'],
          'questions': jsonEncode(sp['questions']),
          'prompt_card': sp['prompt_card'],
          'tips': sp['tips']
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Metode Seeding IELTS Writing Prompts
  Future<void> seedWritingPrompts(List<dynamic> writingList) async {
    final db = await database;
    final batch = db.batch();
    for (var wp in writingList) {
      batch.insert(
        'writing_prompts',
        {
          'id': wp['id'],
          'task': wp['task'],
          'type': wp['type'],
          'prompt': wp['prompt'],
          'tips': wp['tips']
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
