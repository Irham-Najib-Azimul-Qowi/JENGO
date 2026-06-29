import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _userData;
  int _activeStage = 1;
  int _currentDayOfStage = 1;
  bool _isLoading = true;
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
    // Jalankan timer untuk memperbarui hitungan detik secara realtime
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && !_isLoading) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHomeData() async {
    final db = await DatabaseHelper.instance.database;

    // 1. Ambil data gamifikasi
    final userList = await db.query('gamification', limit: 1);
    final userData =
        userList.isNotEmpty ? Map<String, dynamic>.from(userList.first) : null;

    // 2. Ambil stage yang sedang aktif
    final activeChapterList = await db.query(
      'chapters',
      where: 'status = ?',
      whereArgs: ['ACTIVE'],
      limit: 1,
    );
    final activeStageNum = activeChapterList.isNotEmpty
        ? activeChapterList.first['chapter_number'] as int
        : 1;

    int dayOfStage = 1;
    if (userData != null) {
      dayOfStage = userData['current_day'] as int? ?? 1;
    }

    if (mounted) {
      setState(() {
        _userData = userData;
        _activeStage = activeStageNum;
        _currentDayOfStage = dayOfStage;
        _isLoading = false;
      });
    }
  }

  // Menghitung Sisa Waktu untuk target 20 Bulan (600 Hari)
  Map<String, dynamic> _calculateCountdown() {
    if (_userData == null) {
      return {
        'days': 600,
        'hours': 0,
        'minutes': 0,
        'seconds': 0,
        'percent': 0.0
      };
    }

    final int startTimeMs = _userData!['start_time'] as int;
    final DateTime startTime = DateTime.fromMillisecondsSinceEpoch(startTimeMs);
    final DateTime targetTime = DateTime(
      startTime.year,
      startTime.month + 20,
      startTime.day,
      startTime.hour,
      startTime.minute,
      startTime.second,
    );

    final DateTime now = DateTime.now();
    final Duration remaining = targetTime.difference(now);

    if (remaining.isNegative) {
      return {
        'days': 0,
        'hours': 0,
        'minutes': 0,
        'seconds': 0,
        'percent': 1.0
      };
    }

    final int totalDurationSeconds = 600 * 24 * 60 * 60; // 600 hari dalam detik
    final int elapsedSeconds = now.difference(startTime).inSeconds;
    double percent = elapsedSeconds / totalDurationSeconds;
    if (percent < 0) percent = 0.0;
    if (percent > 1.0) percent = 1.0;

    return {
      'days': remaining.inDays,
      'hours': remaining.inHours % 24,
      'minutes': remaining.inMinutes % 60,
      'seconds': remaining.inSeconds % 60,
      'percent': percent,
    };
  }

  // Tampilkan Dialog Pemilihan Level untuk JLPT
  void _showJlptLevelSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pilih Tingkat JLPT',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.pop(sheetContext),
                  )
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Pilih tingkat kompetensi ujian JLPT Anda untuk memulai simulasi pengerjaan waktu penuh:',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 24),
              _buildLevelSelectorItem(sheetContext, 'Tingkat N5 (Dasar Pemula)',
                  'N5', AppTheme.neonBlue),
              const SizedBox(height: 12),
              _buildLevelSelectorItem(sheetContext,
                  'Tingkat N4 (Dasar Menengah)', 'N4', AppTheme.neonBlue),
              const SizedBox(height: 12),
              _buildLevelSelectorItem(sheetContext, 'Tingkat N3 (Menengah)',
                  'N3', AppTheme.neonBlue),
              const SizedBox(height: 12),
              _buildLevelSelectorItem(sheetContext,
                  'Tingkat N2 (Lanjutan Profesional)', 'N2', AppTheme.neonBlue),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLevelSelectorItem(
      BuildContext sheetContext, String title, String levelCode, Color color) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.darkBackground,
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.4), width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: () {
          Navigator.pop(sheetContext); // Tutup bottom sheet
          Navigator.pushNamed(
            context,
            '/mock_exam',
            arguments: {'language': 'JAPANESE', 'level': levelCode},
          ).then((_) => _loadHomeData());
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppTheme.textPrimary),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: AppTheme.neonBlue)),
      );
    }

    final countdown = _calculateCountdown();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Status Bar Atas (Streak, Gems, XP)
              _buildTopBar(),
              const SizedBox(height: 20),

              // 2. Countdown Timer 20 Bulan (Nyawa Utama Aplikasi)
              _buildTargetCountdownTimer(countdown),
              const SizedBox(height: 24),

              // 3. Judul Bagian Misi Harian
              Text(
                'Latihan Harian',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                        color: AppTheme.neonBlue.withOpacity(0.3),
                        blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Konsistensi belajar harian untuk melatih retensi memori jangka panjang.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),

              // 4. Dua Card Pilihan Latihan Harian
              _buildLanguageTrackCard(
                context,
                title: 'Latihan Bahasa Jepang',
                subtitle: 'Target Akhir: JLPT N2 (Lulus Kompetensi)',
                stageInfo:
                    'Stage $_activeStage • Hari ke-$_currentDayOfStage dari 30',
                vocabCount: 'Sistem Pengulangan SRS & Kuis Harian',
                gradientColors: [AppTheme.neonBlue, const Color(0xFF0038A8)],
                languageCode: 'JAPANESE',
                icon: Icons.translate,
              ),
              const SizedBox(height: 16),
              _buildLanguageTrackCard(
                context,
                title: 'Latihan Bahasa Inggris',
                subtitle: 'Target Akhir: IELTS Band 8.0 (Akademik)',
                stageInfo:
                    'Stage $_activeStage • Hari ke-$_currentDayOfStage dari 30',
                vocabCount: 'Sistem Pengulangan SRS & Kuis Harian',
                gradientColors: [AppTheme.neonGreen, const Color(0xFF0F7A5E)],
                languageCode: 'ENGLISH',
                icon: Icons.school,
              ),
              const SizedBox(height: 28),

              // 5. Bagian Simulasi Ujian Resmi (Full Tests)
              Text(
                'Simulasi Ujian Resmi',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                        color: AppTheme.neonBlue.withOpacity(0.3),
                        blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Uji kemampuan sesungguhnya dengan simulasi waktu penuh terstandarisasi.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),

              // Dua Card Simulasi Ujian
              _buildSimulationCard(
                title: 'Simulasi Full JLPT',
                subtitle: 'Tes N5 - N2 sesuai struktur resmi ujian asli Jepang',
                accentColor: AppTheme.neonBlue,
                icon: Icons.quiz,
                onTap: () => _showJlptLevelSelector(context),
              ),
              const SizedBox(height: 12),
              _buildSimulationCard(
                title: 'Simulasi Full IELTS',
                subtitle:
                    'Tes Akademik Listening, Reading, Writing, dan Speaking',
                accentColor: AppTheme.neonGreen,
                icon: Icons.assignment,
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/mock_exam',
                    arguments: {'language': 'ENGLISH', 'level': 'C1'},
                  ).then((_) => _loadHomeData());
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final streak = _userData?['current_streak'] ?? 0;
    final gems = _userData?['gems'] ?? 0;
    final level = _userData?['current_level'] ?? 1;
    final xp = _userData?['total_xp'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.textSecondary.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.neonBlue.withOpacity(0.2),
            child: const Icon(Icons.person, color: AppTheme.neonBlue, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Learner Pro',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary),
                ),
                Text(
                  'Lvl $level • $xp XP',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(Icons.local_fire_department,
                  color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 4),
              Text(
                '$streak Hari',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.diamond, color: AppTheme.neonPink, size: 20),
              const SizedBox(width: 4),
              Text(
                '$gems',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // WIDGET TARGET COUNTDOWN TIMER 20 BULAN (Glow Neon Premium)
  Widget _buildTargetCountdownTimer(Map<String, dynamic> cd) {
    final int days = cd['days'] as int;
    final int hours = cd['hours'] as int;
    final int minutes = cd['minutes'] as int;
    final int seconds = cd['seconds'] as int;
    final double percent = cd['percent'] as double;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: AppTheme.neonBlue.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonBlue.withOpacity(0.05),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.alarm, color: AppTheme.neonBlue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'TARGET WAKTU KELULUSAN 20 BULAN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.neonBlue,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const Icon(Icons.offline_bolt,
                  color: AppTheme.neonGreen, size: 18),
            ],
          ),
          const SizedBox(height: 16),
          // Baris Waktu Digital Neon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTimeField(days.toString().padLeft(2, '0'), 'Hari'),
              _buildDividerColon(),
              _buildTimeField(hours.toString().padLeft(2, '0'), 'Jam'),
              _buildDividerColon(),
              _buildTimeField(minutes.toString().padLeft(2, '0'), 'Menit'),
              _buildDividerColon(),
              _buildTimeField(seconds.toString().padLeft(2, '0'), 'Detik'),
            ],
          ),
          const SizedBox(height: 20),
          // Progress Bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Progres Masa Belajar',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                  Text(
                    '${(percent * 100).toStringAsFixed(3)}% Berjalan',
                    style: const TextStyle(
                        color: AppTheme.neonBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: percent,
                  minHeight: 8,
                  backgroundColor: AppTheme.darkBackground,
                  color: AppTheme.neonBlue,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Target ini dihitung mundur sejak pertama kali Anda membuka aplikasi.',
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDividerColon() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Text(
        ':',
        style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _buildTimeField(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildLanguageTrackCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String stageInfo,
    required String vocabCount,
    required List<Color> gradientColors,
    required String languageCode,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Langsung masuk ke daftar 30 latihan stage aktif
            Navigator.pushNamed(
              context,
              '/daily_lesson',
              arguments: {
                'language': languageCode,
                'stage': _activeStage,
              },
            ).then((_) => _loadHomeData());
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        stageInfo,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        vocabCount,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // WIDGET CARD UNTUK SIMULASI UJIAN FULL
  Widget _buildSimulationCard({
    required String title,
    required String subtitle,
    required Color accentColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: accentColor.withOpacity(0.1),
                  radius: 24,
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: accentColor, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
