import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/utils/custom_top_notification.dart';

class LessonListScreen extends StatefulWidget {
  final String language;
  final int stage;

  const LessonListScreen({
    super.key,
    required this.language,
    required this.stage,
  });

  @override
  State<LessonListScreen> createState() => _LessonListScreenState();
}

class _LessonListScreenState extends State<LessonListScreen> {
  int _currentActiveDay = 1;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final db = await DatabaseHelper.instance.database;
    final userList = await db.query('gamification', limit: 1);
    if (userList.isNotEmpty) {
      final user = userList.first;
      int activeLevel = user['current_level'] as int? ?? 1;
      int activeDay = user['current_day'] as int? ?? 1;

      int displayActiveDay = activeDay;
      if (widget.stage < activeLevel) {
        displayActiveDay = 31; // Semua pelajaran selesai di stage lampau
      } else if (widget.stage > activeLevel) {
        displayActiveDay = 0; // Semua pelajaran terkunci di stage masa depan
      }

      if (mounted) {
        setState(() {
          _currentActiveDay = displayActiveDay;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.neonBlue)),
      );
    }

    final isJapanese = widget.language == 'JAPANESE';
    final String languageTitle = isJapanese ? 'Bahasa Jepang' : 'Bahasa Inggris';
    final Color accentColor = isJapanese ? AppTheme.neonBlue : AppTheme.neonGreen;

    return Scaffold(
      appBar: AppBar(
        title: Text('Stage ${widget.stage}: $languageTitle'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Progres Ringkasan Stage
          _buildStageProgressHeader(accentColor),
          const SizedBox(height: 12),

          // Daftar 30 Pelajaran
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: 30,
              itemBuilder: (context, index) {
                final int dayNumber = index + 1;
                final bool isCompleted = dayNumber < _currentActiveDay;
                final bool isActive = dayNumber == _currentActiveDay;
                final bool isLocked = dayNumber > _currentActiveDay;

                return _buildLessonListItem(
                  context,
                  dayNumber: dayNumber,
                  isCompleted: isCompleted,
                  isActive: isActive,
                  isLocked: isLocked,
                  accentColor: accentColor,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageProgressHeader(Color color) {
    // Batasi progres agar masuk akal
    int completedDays = _currentActiveDay > 0 ? (_currentActiveDay - 1) : 0;
    if (completedDays > 30) completedDays = 30;
    final double progressPercent = completedDays / 30;

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Progres Bulan Ini',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '$completedDays / 30 Hari',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progressPercent,
              minHeight: 10,
              backgroundColor: AppTheme.darkBackground,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonListItem(
    BuildContext context, {
    required int dayNumber,
    required bool isCompleted,
    required bool isActive,
    required bool isLocked,
    required Color accentColor,
  }) {
    Color itemColor = AppTheme.textSecondary.withOpacity(0.5);
    Widget iconWidget = const Icon(Icons.lock, color: AppTheme.textSecondary, size: 20);
    BoxDecoration itemDecoration = BoxDecoration(
      color: AppTheme.darkSurface.withOpacity(0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.textSecondary.withOpacity(0.1)),
    );

    if (isCompleted) {
      itemColor = AppTheme.neonGreen;
      iconWidget = const Icon(Icons.check_circle, color: AppTheme.neonGreen, size: 24);
      itemDecoration = BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.neonGreen.withOpacity(0.3)),
      );
    } else if (isActive) {
      itemColor = accentColor;
      iconWidget = Icon(Icons.play_circle_fill, color: accentColor, size: 28);
      itemDecoration = BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.15),
            blurRadius: 8,
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLocked
              ? () {
                  CustomTopNotification.show(
                    context,
                    message: 'Pelajaran ini terkunci atau Anda harus menyelesaikan hari sebelumnya!',
                    isError: true,
                  );
                }
              : () {
                  // Arahkan ke sesi Flashcard hari ini
                  Navigator.pushNamed(
                    context,
                    '/flashcard_study',
                    arguments: {
                      'language': widget.language,
                      'stage': widget.stage,
                      'day': dayNumber,
                    },
                  ).then((_) {
                    // Muat ulang progress saat kembali dari belajar
                    _loadProgress();
                  });
                },
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: itemDecoration,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isLocked ? Colors.transparent : itemColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: isLocked
                            ? Border.all(color: AppTheme.textSecondary.withOpacity(0.3))
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '$dayNumber',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isLocked ? AppTheme.textSecondary : itemColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pelajaran Hari ke-$dayNumber',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isLocked ? AppTheme.textSecondary : AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          isCompleted
                              ? 'Selesai'
                              : (isActive ? 'Mulai Sekarang' : 'Terkunci'),
                          style: TextStyle(
                            fontSize: 12,
                            color: isLocked
                                ? AppTheme.textSecondary.withOpacity(0.5)
                                : (isActive ? accentColor : AppTheme.neonGreen),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                iconWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
