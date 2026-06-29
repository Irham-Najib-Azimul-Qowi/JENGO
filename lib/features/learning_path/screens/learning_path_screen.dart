import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_helper.dart';

class LearningPathScreen extends StatefulWidget {
  const LearningPathScreen({super.key});

  @override
  State<LearningPathScreen> createState() => _LearningPathScreenState();
}

class _LearningPathScreenState extends State<LearningPathScreen> {
  late Future<List<Map<String, dynamic>>> _chaptersFuture;
  int _selectedAnswerIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  void _loadChapters() {
    setState(() {
      _chaptersFuture = DatabaseHelper.instance.database.then((db) {
        return db.query('chapters', orderBy: 'chapter_number ASC');
      });
    });
  }

  // Fungsi Mensimulasikan Kelulusan Kuis Akhir untuk Membuka Stage Berikutnya
  Future<void> _bypassStageWithQuiz(int stageNumber) async {
    final db = await DatabaseHelper.instance.database;

    // 1. Set Stage saat ini menjadi COMPLETED
    await db.update(
      'chapters',
      {'status': 'COMPLETED'},
      where: 'chapter_number = ?',
      whereArgs: [stageNumber],
    );

    // 2. Set Stage berikutnya (stageNumber + 1) menjadi ACTIVE jika ada
    if (stageNumber < 20) {
      await db.update(
        'chapters',
        {'status': 'ACTIVE'},
        where: 'chapter_number = ?',
        whereArgs: [stageNumber + 1],
      );
    }

    // 3. Berikan hadiah Gems dan XP
    final userList = await db.query('gamification', limit: 1);
    if (userList.isNotEmpty) {
      final user = userList.first;
      int currentXp = user['total_xp'] as int;
      int currentLevel = user['current_level'] as int;
      int currentGems = user['gems'] as int;

      int nextXp = currentXp + 300; // Bonus 300 XP
      int nextGems = currentGems + 50; // Bonus 50 Gems
      
      // Rumus level sederhana: Level naik setiap kelipatan 1000 XP
      int nextLevel = (nextXp / 1000).floor() + 1;

      await db.update(
        'gamification',
        {
          'total_xp': nextXp,
          'current_level': nextLevel > currentLevel ? nextLevel : currentLevel,
          'gems': nextGems,
        },
        where: 'id = ?',
        whereArgs: [user['id']],
      );
    }

    // Muat ulang daftar stage
    _loadChapters();
  }

  void _showFinalQuizDialog(BuildContext context, int stageNumber) {
    _selectedAnswerIndex = -1;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.darkSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppTheme.neonBlue),
              ),
              title: Row(
                children: [
                  const Icon(Icons.quiz, color: AppTheme.neonBlue),
                  const SizedBox(width: 10),
                  Text('Kuis Akhir Stage $stageNumber'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Jawab pertanyaan evaluasi di bawah dengan benar untuk lulus & membuka Stage berikutnya!',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Q: Mana dari kosakata berikut yang merupakan bentuk formal N2 Jepang dari "Akan tetapi / Namun"?',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  // Pilihan Jawaban
                  _buildQuizOption(
                    setDialogState,
                    index: 0,
                    text: 'A. Namun (Shikashinagara) [N2]',
                    isSelected: _selectedAnswerIndex == 0,
                  ),
                  _buildQuizOption(
                    setDialogState,
                    index: 1,
                    text: 'B. Tapi (Demo) [N5]',
                    isSelected: _selectedAnswerIndex == 1,
                  ),
                  _buildQuizOption(
                    setDialogState,
                    index: 2,
                    text: 'C. Tapi (Dakedo) [N4]',
                    isSelected: _selectedAnswerIndex == 2,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Batal', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonBlue),
                  onPressed: _selectedAnswerIndex == -1
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                          if (_selectedAnswerIndex == 0) {
                            // Lulus Kuis
                            _bypassStageWithQuiz(stageNumber);
                            _showSuccessDialog(context, stageNumber);
                          } else {
                            // Gagal Kuis
                            _showFailureDialog(context);
                          }
                        },
                  child: const Text('Kirim', style: TextStyle(color: AppTheme.darkBackground)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildQuizOption(
    StateSetter setDialogState, {
    required int index,
    required String text,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        setDialogState(() {
          _selectedAnswerIndex = index;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.neonBlue.withOpacity(0.1) : AppTheme.darkBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.neonBlue : AppTheme.textSecondary.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppTheme.neonBlue : AppTheme.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog(BuildContext context, int stageNumber) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.neonGreen),
        ),
        title: const Row(
          children: [
            Icon(Icons.stars, color: AppTheme.neonGreen),
            const SizedBox(width: 10),
            Text('LULUS! 🎉'),
          ],
        ),
        content: Text(
          'Selamat! Anda lulus Kuis Akhir untuk Stage $stageNumber. '
          'Anda mendapatkan bonus 300 XP, 50 Gems, dan Stage ${stageNumber + 1} sekarang telah TERBUKA!',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonGreen),
            onPressed: () => Navigator.pop(context),
            child: const Text('Mantap', style: TextStyle(color: AppTheme.darkBackground)),
          ),
        ],
      ),
    );
  }

  void _showFailureDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.neonPink),
        ),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: AppTheme.neonPink),
            const SizedBox(width: 10),
            Text('Jawaban Salah ❌'),
          ],
        ),
        content: const Text(
          'Jawaban Anda kurang tepat. Pelajari kembali materi Stage ini dan coba lagi nanti!',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonPink),
            onPressed: () => Navigator.pop(context),
            child: const Text('Coba Lagi', style: TextStyle(color: AppTheme.textPrimary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Peta Perjalanan Stage'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _chaptersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.neonBlue));
          } else if (snapshot.hasError) {
            return Center(child: Text('Gagal memuat: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Belum ada data stage.'));
          }

          final chapters = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              final stageNumber = chapter['chapter_number'] as int;
              final title = chapter['title'] as String;
              final description = chapter['description'] as String;
              final status = chapter['status'] as String; // ACTIVE, LOCKED, COMPLETED

              return Column(
                children: [
                  _buildStageCard(
                    context,
                    stageNumber: stageNumber,
                    title: title,
                    description: description,
                    status: status,
                  ),
                  if (index < chapters.length - 1) _buildPathConnector(status == 'COMPLETED'),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStageCard(
    BuildContext context, {
    required int stageNumber,
    required String title,
    required String description,
    required String status,
  }) {
    final isLocked = status == 'LOCKED';
    final isCurrent = status == 'ACTIVE';
    final isCompleted = status == 'COMPLETED';

    Color borderColor = AppTheme.textSecondary.withOpacity(0.2);
    Color headerBgColor = AppTheme.darkSurface;
    Color statusColor = AppTheme.textSecondary;

    if (isCurrent) {
      borderColor = AppTheme.neonBlue;
      headerBgColor = AppTheme.neonBlue.withOpacity(0.1);
      statusColor = AppTheme.neonBlue;
    } else if (isCompleted) {
      borderColor = AppTheme.neonGreen;
      headerBgColor = AppTheme.neonGreen.withOpacity(0.1);
      statusColor = AppTheme.neonGreen;
    }

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: headerBgColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'STAGE $stageNumber (BULAN $stageNumber)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isLocked ? AppTheme.textSecondary : AppTheme.textPrimary,
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Body Card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 18,
                        color: isLocked ? AppTheme.textSecondary : AppTheme.textPrimary,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                // Tombol Kuis Akhir untuk me-bypass/membuka stage berikutnya
                if (!isLocked) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.quiz),
                          label: Text(isCompleted ? 'ULANG KUIS AKHIR' : 'IKUT KUIS AKHIR'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isCompleted ? AppTheme.neonGreen : AppTheme.neonBlue,
                            side: BorderSide(
                              color: isCompleted ? AppTheme.neonGreen : AppTheme.neonBlue,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            _showFinalQuizDialog(context, stageNumber);
                          },
                        ),
                      ),
                    ],
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathConnector(bool isActive) {
    return Container(
      width: 4,
      height: 32,
      color: isActive ? AppTheme.neonGreen : AppTheme.textSecondary.withOpacity(0.2),
    );
  }
}
