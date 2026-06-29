import '../database/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class SrsEngine {
  // Singleton Instance
  SrsEngine._privateConstructor();
  static final SrsEngine instance = SrsEngine._privateConstructor();

  // interval pengulangan berdasarkan Box Leitner (dalam hari)
  // Box 1: 1 hari, Box 2: 3 hari, Box 3: 7 hari, Box 4: 14 hari, Box 5: 30 hari
  int _getIntervalDays(int boxLevel) {
    switch (boxLevel) {
      case 1:
        return 1;
      case 2:
        return 3;
      case 3:
        return 7;
      case 4:
        return 14;
      case 5:
        return 30;
      default:
        return 1;
    }
  }

  /// Mengambil daftar kosakata yang "Jatuh Tempo" untuk di-review hari ini
  /// [language] - 'JAPANESE' atau 'ENGLISH'
  /// [limit] - batas maksimal jumlah kata dalam satu sesi review
  Future<List<Map<String, dynamic>>> getDueVocabulary(String language, int limit) async {
    final db = await DatabaseHelper.instance.database;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;

    // Kueri: ambil kata yang next_review_time <= waktu sekarang
    return await db.query(
      'vocabulary',
      where: 'language = ? AND next_review_time <= ?',
      whereArgs: [language, nowMs],
      orderBy: 'next_review_time ASC',
      limit: limit,
    );
  }

  /// Memperbarui status kosakata setelah diulas oleh pengguna
  /// [vocabId] - id kosakata dalam database
  /// [isCorrect] - true jika pengguna ingat, false jika lupa
  Future<void> updateReviewResult(int vocabId, bool isCorrect) async {
    final db = await DatabaseHelper.instance.database;

    // 1. Ambil data kata saat ini
    final List<Map<String, dynamic>> result = await db.query(
      'vocabulary',
      where: 'id = ?',
      whereArgs: [vocabId],
      limit: 1,
    );

    if (result.isEmpty) return;

    final vocab = result.first;
    int currentBox = vocab['box_level'] as int? ?? 1;

    int nextBox;
    if (isCorrect) {
      // Jika benar, naikkan ke Box berikutnya (maksimal Box 5)
      nextBox = currentBox < 5 ? currentBox + 1 : 5;
    } else {
      // Jika salah/lupa, reset kembali ke Box 1
      nextBox = 1;
    }

    // 2. Hitung waktu peninjauan berikutnya
    final int intervalDays = _getIntervalDays(nextBox);
    final DateTime nextReviewDate = DateTime.now().add(Duration(days: intervalDays));
    final int nextReviewTimeMs = nextReviewDate.millisecondsSinceEpoch;

    // 3. Update database
    await db.update(
      'vocabulary',
      {
        'box_level': nextBox,
        'next_review_time': nextReviewTimeMs,
      },
      where: 'id = ?',
      whereArgs: [vocabId],
    );

    // 4. Berikan reward XP ke pengguna jika benar
    if (isCorrect) {
      await _awardXpForReview();
    }
  }

  // Berikan 10 XP untuk setiap ulasan kata yang benar
  Future<void> _awardXpForReview() async {
    final db = await DatabaseHelper.instance.database;
    final userList = await db.query('gamification', limit: 1);
    if (userList.isEmpty) return;

    final user = userList.first;
    int currentXp = user['total_xp'] as int;
    int currentLevel = user['current_level'] as int;

    int newXp = currentXp + 10;
    int newLevel = (newXp / 1000).floor() + 1; // Naik level per 1000 XP

    await db.update(
      'gamification',
      {
        'total_xp': newXp,
        'current_level': newLevel > currentLevel ? newLevel : currentLevel,
      },
      where: 'id = ?',
      whereArgs: [user['id']],
    );
  }
}
