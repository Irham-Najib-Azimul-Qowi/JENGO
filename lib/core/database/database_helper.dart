import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class DatabaseHelper {
  static const _databaseName = "jengo.db";
  static const _databaseVersion = 8;

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
    if (oldVersion < 6) {
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
    if (oldVersion < 7) {
      await _createLanguageProgressTable(db);
      final userList = await db.query('gamification', limit: 1);
      final user = userList.isNotEmpty ? userList.first : <String, Object?>{};
      final currentStage = user['current_level'] as int? ?? 1;
      final currentDay = user['current_day'] as int? ?? 1;
      await _seedLanguageProgress(db,
          currentStage: currentStage, currentDay: currentDay);
    }
    if (oldVersion < 8) {
      await _refreshChapterCurriculum(db);
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

    await _createLanguageProgressTable(db);

    // 2. Buat Tabel Chapters (20 Stage Bulanan)
    await db.execute('''
      CREATE TABLE chapters (
        id INTEGER PRIMARY KEY,
        chapter_number INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        status TEXT NOT NULL -- 'LOCKED', 'ACTIVE', 'COMPLETED'
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
        difficulty_level TEXT, -- N5, N4, N3, N2, A1, A2, B1, B2, C1, HIRAGANA, KATAKANA
        example_sentence TEXT DEFAULT '',
        box_level INTEGER DEFAULT 1, -- Leitner Box (1-5)
        next_review_time INTEGER NOT NULL -- Timestamp
      )
    ''');

    // 4. Buat Tabel Kanji
    await db.execute('''
      CREATE TABLE kanji (
        id INTEGER PRIMARY KEY,
        kanji TEXT NOT NULL,
        meaning TEXT NOT NULL,
        onyomi TEXT NOT NULL,
        kunyomi TEXT NOT NULL,
        strokes INTEGER DEFAULT 0,
        level TEXT NOT NULL -- N5, N4, N3, N2
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
        time_spent INTEGER NOT NULL,
        review_data TEXT NOT NULL,
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

    await _seedLanguageProgress(db);

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

  Future<void> _refreshChapterCurriculum(Database db) async {
    for (int i = 1; i <= 20; i++) {
      await db.update(
        'chapters',
        {
          'title': _getStageTitle(i),
          'description': _getStageDescription(i),
        },
        where: 'chapter_number = ?',
        whereArgs: [i],
      );
    }
  }

  Future<void> _createLanguageProgressTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS language_progress (
        language TEXT PRIMARY KEY,
        current_stage INTEGER NOT NULL DEFAULT 1,
        current_day INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _seedLanguageProgress(
    Database db, {
    int currentStage = 1,
    int currentDay = 1,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final language in const ['JAPANESE', 'ENGLISH']) {
      await db.insert(
        'language_progress',
        {
          'language': language,
          'current_stage': currentStage,
          'current_day': currentDay,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<Map<String, int>> getLanguageProgress(String language) async {
    final db = await database;
    await _createLanguageProgressTable(db);
    await _seedLanguageProgress(db);

    final rows = await db.query(
      'language_progress',
      where: 'language = ?',
      whereArgs: [language],
      limit: 1,
    );
    if (rows.isEmpty) {
      await _seedLanguageProgress(db);
      return {'stage': 1, 'day': 1};
    }

    return {
      'stage': rows.first['current_stage'] as int? ?? 1,
      'day': rows.first['current_day'] as int? ?? 1,
    };
  }

  Future<bool> advanceLanguageProgressIfCurrent({
    required String language,
    required int completedStage,
    required int completedDay,
  }) async {
    final db = await database;
    final progress = await getLanguageProgress(language);
    final currentStage = progress['stage'] ?? 1;
    final currentDay = progress['day'] ?? 1;

    if (completedStage != currentStage || completedDay != currentDay) {
      return false;
    }

    var nextStage = currentStage;
    var nextDay = currentDay + 1;
    if (nextDay > 30) {
      nextDay = 1;
      if (nextStage < 20) {
        nextStage++;
      }
    }

    await db.update(
      'language_progress',
      {
        'current_stage': nextStage,
        'current_day': nextDay,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'language = ?',
      whereArgs: [language],
    );
    return true;
  }

  Future<void> skipLanguageToStage({
    required String language,
    required int stage,
  }) async {
    final db = await database;
    await _createLanguageProgressTable(db);
    await _seedLanguageProgress(db);
    await db.update(
      'language_progress',
      {
        'current_stage': stage,
        'current_day': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'language = ?',
      whereArgs: [language],
    );
  }

  Future<void> resetLanguageProgress() async {
    final db = await database;
    await _createLanguageProgressTable(db);
    await db.delete('language_progress');
    await _seedLanguageProgress(db);
  }

  String _getStageTitle(int i) {
    switch (i) {
      case 1:
        return "Stage 1: Hiragana Dasar / English A1 Sounds";
      case 2:
        return "Stage 2: Hiragana Lanjutan / English A1 Words";
      case 3:
        return "Stage 3: Review Hiragana / English A1 Review";
      case 4:
        return "Stage 4: Katakana Dasar / English A1 Phrases";
      case 5:
        return "Stage 5: Katakana Lanjutan / English A2 Words";
      case 6:
        return "Stage 6: Review Kana / English A2 Review";
      case 7:
        return "Stage 7: Kosakata Dasar / English Daily Vocab";
      case 8:
        return "Stage 8: Salam & Ungkapan / English Greetings";
      case 9:
        return "Stage 9: Angka & Jumlah / English Numbers";
      case 10:
        return "Stage 10: Hari & Waktu / English Time";
      case 11:
        return "Stage 11: Warna & Sifat / English Adjectives";
      case 12:
        return "Stage 12: Kata Benda Sederhana / English Nouns";
      case 13:
        return "Stage 13: Kalimat Dasar / English Basic Sentences";
      case 14:
        return "Stage 14: Partikel Dasar / English Basic Grammar";
      case 15:
        return "Stage 15: Kanji N5 Awal / English Intermediate Vocab";
      case 16:
        return "Stage 16: Kanji & Pola N5 / English Paragraphs";
      case 17:
        return "Stage 17: N4 Bridge / IELTS Foundation";
      case 18:
        return "Stage 18: N3 Bridge / IELTS Skills";
      case 19:
        return "Stage 19: N2 Readiness / IELTS Mock Skills";
      default:
        return "Stage 20: Final Certification Readiness";
    }
  }

  String _getStageDescription(int i) {
    switch (i) {
      case 1:
        return "JP: A-I-U-E-O, hiragana dasar, audio, romaji penuh, arti Indonesia. EN: bunyi, kata paling dasar, instruksi sederhana.";
      case 2:
        return "JP: Hiragana lanjutan dengan audio, romaji penuh, dan pengenalan bentuk mirip. EN: kosakata A1 sehari-hari.";
      case 3:
        return "JP: Review semua hiragana tanpa kalimat kompleks. EN: review A1 dengan pilihan jawaban.";
      case 4:
        return "JP: Katakana dasar, audio, romaji penuh, arti Indonesia. EN: frasa A1 pendek.";
      case 5:
        return "JP: Katakana lanjutan dan kata serapan sangat sederhana. EN: kosakata A2 bertahap.";
      case 6:
        return "JP: Review kana campuran hiragana-katakana. Belum masuk grammar atau bacaan panjang. EN: review A2.";
      case 7:
        return "JP: Kosakata dasar N5 dengan kana/romaji bantuan. EN: daily vocabulary tanpa grammar kompleks.";
      case 8:
        return "JP: Salam, ungkapan umum, dan respons pendek. EN: greetings and simple responses.";
      case 9:
        return "JP: Angka, jumlah, umur, harga sederhana. EN: numbers and quantities.";
      case 10:
        return "JP: Hari, tanggal, jam, dan rutinitas sangat pendek. EN: days, dates, and time.";
      case 11:
        return "JP: Warna, sifat sederhana, benda sekitar. EN: basic adjectives.";
      case 12:
        return "JP: Kata benda sederhana dan pasangan kata. EN: simple nouns and collocations.";
      case 13:
        return "JP: Kalimat dasar pola A wa B desu, kore/sore/are. EN: simple sentence building.";
      case 14:
        return "JP: Partikel dasar wa, ga, o, ni, de dengan contoh pendek. EN: grammar foundation.";
      case 15:
        return "JP: Kanji N5 awal setelah kana dan kosakata dasar cukup kuat. EN: intermediate vocabulary.";
      case 16:
        return "JP: Kanji N5, pola N5, dan bacaan sangat pendek. EN: short paragraphs.";
      case 17:
        return "JP: Transisi N4 dengan listening dan reading pendek. EN: IELTS foundation tasks.";
      case 18:
        return "JP: Transisi N3 bertahap, romaji makin dikurangi. EN: IELTS reading/listening skills.";
      case 19:
        return "JP: Kesiapan N2 dengan latihan terarah. EN: IELTS mock skills and band estimation.";
      default:
        return "JP: Final checkpoint menuju JLPT N2. EN: final checkpoint menuju IELTS target.";
    }
  }

  // Metode Pengisian (Seeding) Kosakata dalam Jumlah Besar secara Cepat
  Future<void> seedVocabularyList(
      List<dynamic> vocabList, String language) async {
    final db = await database;
    final batch = db.batch();
    for (var vocab in vocabList) {
      final String word = (vocab['word'] ?? '').toString().trim();
      final String translation =
          (vocab['meaning'] ?? vocab['translation'] ?? '').toString().trim();
      // Lewati entri kosong
      if (word.isEmpty || translation.isEmpty) continue;

      // Ambil contoh kalimat pertama jika tersedia
      String exampleSentence = '';
      final examples = vocab['examples'];
      if (examples is List && examples.isNotEmpty) {
        final first = examples.first?.toString() ?? '';
        if (!first.toLowerCase().contains('no example')) {
          exampleSentence = first;
        }
      }

      batch.insert(
        'vocabulary',
        {
          'word': word,
          'reading': (vocab['reading'] ?? '').toString(),
          'translation': translation,
          'language': language,
          'difficulty_level': (vocab['level'] ?? '').toString(),
          'example_sentence': exampleSentence,
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
      final String kanji = (k['kanji'] ?? '').toString().trim();
      final String meaning = (k['meaning'] ?? '').toString().trim();
      if (kanji.isEmpty || meaning.isEmpty) continue;
      batch.insert(
        'kanji',
        {
          'id': k['id'],
          'kanji': kanji,
          'level': (k['level'] ?? 'N5').toString(),
          'meaning': meaning,
          'onyomi': (k['onyomi'] ?? '').toString(),
          'kunyomi': (k['kunyomi'] ?? '').toString(),
          'strokes': k['strokes'] is int ? k['strokes'] : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Metode Seeding Bacaan (Reading)
  Future<void> seedReadingList(
      List<dynamic> readingList, String language) async {
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
  Future<void> seedListeningList(
      List<dynamic> listeningList, String language) async {
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
  Future<void> seedGrammarList(
      List<dynamic> grammarList, String language) async {
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
