import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../database/database_helper.dart';

class FirebaseSyncService {
  FirebaseSyncService._privateConstructor();
  static final FirebaseSyncService instance = FirebaseSyncService._privateConstructor();

  Future<bool> syncFirebaseToSqlite(
    DatabaseHelper dbHelper, 
    Function(String progress) onProgressUpdate,
  ) async {
    final db = await dbHelper.database;
    final firestore = FirebaseFirestore.instance;

    onProgressUpdate("Menghubungkan ke Cloud... 🌐");
    
    // Uji konektivitas Firestore dengan batas waktu (timeout) 6 detik
    try {
      await firestore.collection('japanese_kanji').limit(1).get().timeout(
        const Duration(seconds: 6),
      );
    } catch (e) {
      print("Koneksi Firebase gagal atau timeout (Kemungkinan offline): $e");
      onProgressUpdate("Offline: Menggunakan data lokal...");
      return false;
    }

    try {
      // 1. Sync Japanese Kanji
      onProgressUpdate("Mensinkronisasikan Kanji Jepang... ⛩️");
      final kanjiSnap = await firestore.collection('japanese_kanji').get();
      if (kanjiSnap.docs.isNotEmpty) {
        final batch = db.batch();
        for (var doc in kanjiSnap.docs) {
          final data = doc.data();
          batch.insert(
            'kanji',
            {
              'id': data['id'] ?? int.tryParse(doc.id) ?? 0,
              'kanji': data['kanji'] ?? '',
              'level': data['level'] ?? '',
              'meaning': data['meaning'] ?? '',
              'onyomi': data['onyomi'] ?? '',
              'kunyomi': data['kunyomi'] ?? '',
              'strokes': data['strokes'] ?? 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // 2. Sync Japanese Grammar
      onProgressUpdate("Mensinkronisasikan Grammar Jepang... 📚");
      final jpGrammarSnap = await firestore.collection('japanese_grammar').get();
      if (jpGrammarSnap.docs.isNotEmpty) {
        final batch = db.batch();
        for (var doc in jpGrammarSnap.docs) {
          final data = doc.data();
          batch.insert(
            'grammar',
            {
              'id': data['id'] ?? int.tryParse(doc.id) ?? 0,
              'rule_name': data['rule_name'] ?? '',
              'level': data['level'] ?? '',
              'explanation': data['explanation'] ?? '',
              'tips': data['tips'] ?? '',
              'example_sentence': data['example_sentence'] ?? '',
              'example_translation': data['example_translation'] ?? '',
              'language': 'JAPANESE',
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // 3. Sync English Grammar
      onProgressUpdate("Mensinkronisasikan Grammar Inggris... 📖");
      final enGrammarSnap = await firestore.collection('english_grammar').get();
      if (enGrammarSnap.docs.isNotEmpty) {
        final batch = db.batch();
        for (var doc in enGrammarSnap.docs) {
          final data = doc.data();
          batch.insert(
            'grammar',
            {
              'id': data['id'] ?? int.tryParse(doc.id) ?? 0,
              'rule_name': data['rule_name'] ?? '',
              'level': data['level'] ?? '',
              'explanation': data['explanation'] ?? '',
              'tips': data['tips'] ?? '',
              'example_sentence': data['example_sentence'] ?? '',
              'example_translation': data['example_translation'] ?? '',
              'language': 'ENGLISH',
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // 4. Sync Japanese Sentences
      onProgressUpdate("Mensinkronisasikan Contoh Kalimat Jepang... 🇯🇵");
      final jpSentencesSnap = await firestore.collection('japanese_sentences').get();
      if (jpSentencesSnap.docs.isNotEmpty) {
        final batch = db.batch();
        for (var doc in jpSentencesSnap.docs) {
          final data = doc.data();
          batch.insert(
            'sentences',
            {
              'id': data['id'] ?? int.tryParse(doc.id) ?? 0,
              'japanese': data['japanese'] ?? '',
              'english': data['english'] ?? '',
              'indonesian': data['indonesian'] ?? '',
              'word_mapped': data['word_mapped'] ?? '',
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // 5. Sync English Speaking Prompts
      onProgressUpdate("Mensinkronisasikan Topik Speaking... 🗣️");
      final spPromptsSnap = await firestore.collection('english_speaking_prompts').get();
      if (spPromptsSnap.docs.isNotEmpty) {
        final batch = db.batch();
        for (var doc in spPromptsSnap.docs) {
          final data = doc.data();
          batch.insert(
            'speaking_prompts',
            {
              'id': data['id'] ?? int.tryParse(doc.id) ?? 0,
              'part': data['part'] ?? 1,
              'topic': data['topic'] ?? '',
              'questions': data['questions'] is List 
                  ? jsonEncode(data['questions']) 
                  : (data['questions'] ?? '[]'),
              'prompt_card': data['prompt_card'] ?? '',
              'tips': data['tips'] ?? '',
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // 6. Sync English Writing Prompts
      onProgressUpdate("Mensinkronisasikan Topik Writing... ✍️");
      final wrPromptsSnap = await firestore.collection('english_writing_prompts').get();
      if (wrPromptsSnap.docs.isNotEmpty) {
        final batch = db.batch();
        for (var doc in wrPromptsSnap.docs) {
          final data = doc.data();
          batch.insert(
            'writing_prompts',
            {
              'id': data['id'] ?? int.tryParse(doc.id) ?? 0,
              'task': data['task'] ?? 1,
              'type': data['type'] ?? '',
              'prompt': data['prompt'] ?? '',
              'tips': data['tips'] ?? '',
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // 7. Sync Japanese Vocabulary
      onProgressUpdate("Mensinkronisasikan Kosakata Jepang... 📝");
      final jpVocabSnap = await firestore.collection('japanese_vocab').get();
      if (jpVocabSnap.docs.isNotEmpty) {
        final batch = db.batch();
        for (var doc in jpVocabSnap.docs) {
          final data = doc.data();
          batch.insert(
            'vocabulary',
            {
              'word': data['word'] ?? doc.id,
              'reading': data['reading'] ?? '',
              'translation': data['meaning'] ?? '',
              'language': 'JAPANESE',
              'difficulty_level': data['level'] ?? '',
              'box_level': 1,
              'next_review_time': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // 8. Sync English Vocabulary
      onProgressUpdate("Mensinkronisasikan Kosakata Inggris... 🇬🇧");
      final enVocabSnap = await firestore.collection('english_vocab').get();
      if (enVocabSnap.docs.isNotEmpty) {
        final batch = db.batch();
        for (var doc in enVocabSnap.docs) {
          final data = doc.data();
          batch.insert(
            'vocabulary',
            {
              'word': data['word'] ?? doc.id,
              'reading': data['reading'] ?? '',
              'translation': data['meaning'] ?? '',
              'language': 'ENGLISH',
              'difficulty_level': data['level'] ?? '',
              'box_level': 1,
              'next_review_time': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // Berhasil, set status is_synced = 1 di tabel gamification
      await db.update(
        'gamification',
        {'is_synced': 1},
      );
      
      onProgressUpdate("Sinkronisasi Selesai! ✨");
      return true;
    } catch (e) {
      print("Error selama proses sinkronisasi: $e");
      onProgressUpdate("Gagal sinkronisasi. Menggunakan cadangan lokal...");
      return false;
    }
  }
}
