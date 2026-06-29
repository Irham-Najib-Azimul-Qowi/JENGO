import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/navigation/app_router.dart';
import 'core/database/database_helper.dart';

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inisialisasi Firebase secara Global
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("FIREBASE INITIALIZED SUCCESSFULLY!");
  } catch (e) {
    print("Error initializing Firebase at startup: $e");
  }

  // Inisialisasi database lokal Sqflite
  final dbHelper = DatabaseHelper.instance;
  final db = await dbHelper.database; // Memicu onCreate jika belum ada

  // Seeding awal jika tabel vocabulary kosong
  final List<Map<String, dynamic>> existingVocab = await db.query('vocabulary', limit: 1);
  if (existingVocab.isEmpty) {
    try {
      // A. BAHASA JEPANG
      // 1. Muat & parse kosakata Jepang (N5-N2)
      final String jpVocabString = await rootBundle.loadString('assets/materials/japanese/vocab.json');
      final List<dynamic> jpVocabList = jsonDecode(jpVocabString);
      await dbHelper.seedVocabularyList(jpVocabList, 'JAPANESE');

      // 2. Muat & parse Kanji Jepang
      final String jpKanjiString = await rootBundle.loadString('assets/materials/japanese/kanji.json');
      final List<dynamic> jpKanjiList = jsonDecode(jpKanjiString);
      await dbHelper.seedKanjiList(jpKanjiList);

      // 3. Muat & parse Reading Jepang
      final String jpReadingString = await rootBundle.loadString('assets/materials/japanese/reading.json');
      final List<dynamic> jpReadingList = jsonDecode(jpReadingString);
      await dbHelper.seedReadingList(jpReadingList, 'JAPANESE');

      // 4. Muat & parse Listening Jepang
      final String jpListeningString = await rootBundle.loadString('assets/materials/japanese/listening.json');
      final List<dynamic> jpListeningList = jsonDecode(jpListeningString);
      await dbHelper.seedListeningList(jpListeningList, 'JAPANESE');

      // 5. Muat & parse Tata Bahasa Jepang
      final String jpGrammarString = await rootBundle.loadString('assets/materials/japanese/grammar.json');
      final List<dynamic> jpGrammarList = jsonDecode(jpGrammarString);
      await dbHelper.seedGrammarList(jpGrammarList, 'JAPANESE');

      // 6. Muat & parse Kalimat Tatoeba Jepang
      final String jpSentencesString = await rootBundle.loadString('assets/materials/japanese/sentences.json');
      final List<dynamic> jpSentencesList = jsonDecode(jpSentencesString);
      await dbHelper.seedSentencesList(jpSentencesList);


      // B. BAHASA INGGRIS
      // 1. Muat & parse kosakata Inggris (IELTS/AWL)
      final String enVocabString = await rootBundle.loadString('assets/materials/english/vocab.json');
      final List<dynamic> enVocabList = jsonDecode(enVocabString);
      await dbHelper.seedVocabularyList(enVocabList, 'ENGLISH');

      // 2. Muat & parse Reading Inggris
      final String enReadingString = await rootBundle.loadString('assets/materials/english/reading.json');
      final List<dynamic> enReadingList = jsonDecode(enReadingString);
      await dbHelper.seedReadingList(enReadingList, 'ENGLISH');

      // 3. Muat & parse Listening Inggris
      final String enListeningString = await rootBundle.loadString('assets/materials/english/listening.json');
      final List<dynamic> enListeningList = jsonDecode(enListeningString);
      await dbHelper.seedListeningList(enListeningList, 'ENGLISH');

      // 4. Muat & parse Tata Bahasa Inggris
      final String enGrammarString = await rootBundle.loadString('assets/materials/english/grammar.json');
      final List<dynamic> enGrammarList = jsonDecode(enGrammarString);
      await dbHelper.seedGrammarList(enGrammarList, 'ENGLISH');

      // 5. Muat & parse IELTS Speaking Prompts
      final String enSpeakingString = await rootBundle.loadString('assets/materials/english/speaking_prompts.json');
      final List<dynamic> enSpeakingList = jsonDecode(enSpeakingString);
      await dbHelper.seedSpeakingPrompts(enSpeakingList);

      // 6. Muat & parse IELTS Writing Prompts
      final String enWritingString = await rootBundle.loadString('assets/materials/english/writing_prompts.json');
      final List<dynamic> enWritingList = jsonDecode(enWritingString);
      await dbHelper.seedWritingPrompts(enWritingList);
      
      print("DATABASE SEEDING COMPLETED FOR ALL MATERIALS!");
    } catch (e) {
      print("Error seeding database materials: $e");
    }
  }

  runApp(
    MultiProvider(
      providers: [
        // Kita bisa mendaftarkan ChangeNotifier provider di sini nanti
        Provider<DatabaseHelper>.value(value: dbHelper),
      ],
      child: const JengoApp(),
    ),
  );
}

class JengoApp extends StatelessWidget {
  const JengoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JENGO',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // Selalu gunakan dark mode premium
      darkTheme: AppTheme.darkTheme,
      initialRoute: AppRouter.splash,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
