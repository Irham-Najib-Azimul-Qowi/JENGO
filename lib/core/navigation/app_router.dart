import 'package:flutter/material.dart';
import '../../features/splash/screens/splash_screen.dart';
import '../../features/main_navigation.dart';
import '../../features/home/screens/lesson_list_screen.dart';
import '../../features/srs/screens/flashcard_study_screen.dart';
import '../../features/home/screens/daily_lesson_quiz_screen.dart';
import '../../features/home/screens/mock_exam_screen.dart';
import '../../features/home/screens/writing_practice_screen.dart';
import '../../features/home/screens/speaking_practice_screen.dart';
import '../../features/home/screens/daily_mock_practice_screen.dart';
import '../../features/home/screens/tips_tricks_screen.dart';
import '../../features/home/screens/exam_review_screen.dart';

import '../../features/learning_path/screens/learning_path_screen.dart';

class AppRouter {
  static const String splash = '/';
  static const String mainNav = '/main_nav';
  static const String dailyLesson = '/daily_lesson';
  static const String flashcardStudy = '/flashcard_study';
  static const String dailyLessonQuiz = '/daily_lesson_quiz';
  static const String mockExam = '/mock_exam';
  static const String writingPractice = '/writing_practice';
  static const String speakingPractice = '/speaking_practice';
  static const String dailyMockPractice = '/daily_mock_practice';
  static const String tipsTricks = '/tips_tricks';
  static const String examReview = '/exam_review';
  static const String learningPath = '/learning_path';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case mainNav:
        return MaterialPageRoute(builder: (_) => const MainNavigation());
      case dailyLesson:
        final args = settings.arguments as Map<String, dynamic>?;
        final language = args?['language'] as String? ?? 'JAPANESE';
        final stage = args?['stage'] as int? ?? 1;

        return MaterialPageRoute(
          builder: (_) => LessonListScreen(
            language: language,
            stage: stage,
          ),
        );
      case flashcardStudy:
        final args = settings.arguments as Map<String, dynamic>?;
        final language = args?['language'] as String? ?? 'JAPANESE';
        final stage = args?['stage'] as int? ?? 1;
        final day = args?['day'] as int? ?? 1;

        return MaterialPageRoute(
          builder: (_) => FlashcardStudyScreen(
            language: language,
            stage: stage,
            day: day,
          ),
        );
      case dailyLessonQuiz:
        final args = settings.arguments as Map<String, dynamic>?;
        final language = args?['language'] as String? ?? 'JAPANESE';
        final vocabList = args?['vocabList'] as List<dynamic>?;
        final stage = args?['stage'] as int? ?? 1;
        final day = args?['day'] as int? ?? 1;
        final isSkippingQuiz = args?['isSkippingQuiz'] as bool? ?? false;

        return MaterialPageRoute(
          builder: (_) => DailyLessonQuizScreen(
            language: language,
            vocabList: vocabList,
            stage: stage,
            day: day,
            isSkippingQuiz: isSkippingQuiz,
          ),
        );
      case mockExam:
        final args = settings.arguments as Map<String, dynamic>?;
        final language = args?['language'] as String? ?? 'JAPANESE';
        final level = args?['level'] as String? ?? 'N3';

        return MaterialPageRoute(
          builder: (_) => MockExamScreen(
            language: language,
            level: level,
          ),
        );
      case writingPractice:
        return MaterialPageRoute(
          builder: (_) => const WritingPracticeScreen(),
        );
      case speakingPractice:
        return MaterialPageRoute(builder: (_) => const SpeakingPracticeScreen());
      case dailyMockPractice:
        final args = settings.arguments as Map<String, dynamic>?;
        final language = args?['language'] as String? ?? 'JAPANESE';
        final stage = args?['stage'] as int? ?? 1;
        final day = args?['day'] as int? ?? 1;

        return MaterialPageRoute(
          builder: (_) => DailyMockPracticeScreen(
            language: language,
            stage: stage,
            day: day,
          ),
        );
      case tipsTricks:
        final args = settings.arguments as Map<String, dynamic>?;
        final language = args?['language'] as String? ?? 'JAPANESE';

        return MaterialPageRoute(
          builder: (_) => TipsTricksScreen(
            language: language,
          ),
        );
      case examReview:
        final args = settings.arguments as Map<String, dynamic>?;
        final int historyId = args?['historyId'] as int? ?? 1;

        return MaterialPageRoute(
          builder: (_) => ExamReviewScreen(
            historyId: historyId,
          ),
        );
      case learningPath:
        return MaterialPageRoute(
          builder: (_) => const LearningPathScreen(),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }
}
