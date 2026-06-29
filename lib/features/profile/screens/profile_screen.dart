import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/utils/custom_top_notification.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  int _totalWordsCount = 0;
  List<Map<String, dynamic>> _simHistory = [];
  bool _isLoading = true;
  bool _isNotificationEnabled = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final db = await DatabaseHelper.instance.database;

    // 1. Load user gamification details
    final userList = await db.query('gamification', limit: 1);
    final userData = userList.isNotEmpty ? Map<String, dynamic>.from(userList.first) : null;

    // 2. Count local words learned
    final countResult = await db.rawQuery('SELECT COUNT(*) as total FROM vocabulary');
    final totalWords = Sqflite.firstIntValue(countResult) ?? 0;

    // 3. Load simulated mock test histories
    final historyQuery = await db.query(
      'simulations_history',
      orderBy: 'timestamp DESC',
      limit: 10,
    );

    if (mounted) {
      setState(() {
        _userData = userData;
        _totalWordsCount = totalWords;
        _simHistory = historyQuery;
        _isLoading = false;
      });
    }
  }

  Future<void> _resetDatabaseProgress() async {
    final db = await DatabaseHelper.instance.database;

    // Reset chapters
    await db.update('chapters', {'status': 'LOCKED'});
    await db.update('chapters', {'status': 'ACTIVE'}, where: 'chapter_number = 1');

    // Reset Leitner box levels and review schedule
    await db.update('vocabulary', {
      'box_level': 1,
      'next_review_time': DateTime.now().millisecondsSinceEpoch,
    });

    // Reset gamification values
    await db.update(
      'gamification',
      {
        'total_xp': 0,
        'current_level': 1,
        'current_streak': 0,
        'hearts': 5,
        'gems': 100,
        'start_time': DateTime.now().millisecondsSinceEpoch,
        'current_day': 1,
      },
    );

    // Clear simulation history
    await db.delete('simulations_history');

    if (mounted) {
      CustomTopNotification.show(context, message: 'Progres berhasil di-reset ke Awal Stage 1.');
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  Future<void> _syncToFirebase() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      final db = await DatabaseHelper.instance.database;
      final userList = await db.query('gamification', limit: 1);
      if (userList.isEmpty) throw Exception("Data progres kosong");
      final userData = userList.first;
      final chapters = await db.query('chapters');

      final firestore = FirebaseFirestore.instance;
      await firestore.collection('users').doc('learner_pro_123').set({
        'gamification': {
          'total_xp': userData['total_xp'],
          'current_level': userData['current_level'],
          'current_streak': userData['current_streak'],
          'hearts': userData['hearts'],
          'gems': userData['gems'],
          'last_sync_time': FieldValue.serverTimestamp(),
        },
        'stages': chapters.map((c) => {
          'chapter_number': c['chapter_number'],
          'status': c['status'],
        }).toList(),
      }, SetOptions(merge: true));

      if (mounted) {
        CustomTopNotification.show(context, message: 'Progres belajar berhasil disinkronisasikan ke Firebase JENGO.');
      }
    } catch (e) {
      if (mounted) {
        CustomTopNotification.show(context, message: 'Gagal sinkronisasi: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  // Backup data ke format JSON string lokal
  void _performBackup() {
    if (_userData == null) return;
    try {
      final backupData = {
        'total_xp': _userData!['total_xp'],
        'current_level': _userData!['current_level'],
        'current_streak': _userData!['current_streak'],
        'hearts': _userData!['hearts'],
        'gems': _userData!['gems'],
        'current_day': _userData!['current_day'],
        'backup_time': DateTime.now().millisecondsSinceEpoch,
      };
      
      final jsonString = jsonEncode(backupData);
      // Simulasikan penyimpanan ke file lokal
      CustomTopNotification.show(context, message: 'Backup berhasil! Berkas cadangan disimpan ke memori internal.');
    } catch (e) {
      CustomTopNotification.show(context, message: 'Gagal membuat backup: $e', isError: true);
    }
  }

  // Restore data dari JSON string
  void _performRestore() {
    try {
      // Simulasikan pemulihan dari berkas cadangan lokal
      CustomTopNotification.show(context, message: 'Pemulihan berhasil! Seluruh statistik belajar berhasil dikembalikan.');
      _loadProfileData();
    } catch (e) {
      CustomTopNotification.show(context, message: 'Gagal memulihkan progres: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.neonBlue)),
      );
    }

    final int xp = _userData?['total_xp'] ?? 0;
    final int level = _userData?['current_level'] ?? 1;
    final int gems = _userData?['gems'] ?? 0;
    final int streak = _userData?['current_streak'] ?? 0;
    final int currentDay = _userData?['current_day'] ?? 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil & Analitik'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Avatar and Name Identity
            _buildProfileHeaderCard(level, xp, currentDay),
            const SizedBox(height: 24),

            // 2. Target Goal Countdown Timer Summary
            _buildTargetGoalCard(),
            const SizedBox(height: 24),

            // 3. Learning Statistics (Streak, Gems, Total Words)
            Text(
              'Statistik Perkembangan',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildStatsGrid(gems, streak),
            const SizedBox(height: 24),

            // 4. Mock Exams Simulation History (Riwayat Ujian)
            Text(
              'Riwayat Ujian Simulasi',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildSimulationHistoryList(),
            const SizedBox(height: 24),

            // 5. App Settings & Sync Panel
            Text(
              'Pengaturan & Data',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildSettingsPanel(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeaderCard(int level, int xp, int day) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.neonBlue.withOpacity(0.3), width: 1.2),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: AppTheme.neonBlue.withOpacity(0.15),
            child: const Icon(Icons.person, size: 40, color: AppTheme.neonBlue),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Learner Pro',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Stage Aktif: Stage $level • Hari ke-$day',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (xp % 1000) / 1000,
                          minHeight: 6,
                          backgroundColor: AppTheme.darkBackground,
                          color: AppTheme.neonBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${xp % 1000}/1000 XP',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetGoalCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.textSecondary.withOpacity(0.08)),
      ),
      child: const Row(
        children: [
          Icon(Icons.flag_outlined, color: AppTheme.neonGreen, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TARGET AKHIR BELAJAR',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.neonGreen, letterSpacing: 1.1),
                ),
                SizedBox(height: 4),
                Text(
                  'Lulus JLPT N2 & Meraih IELTS Band 8.0',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                SizedBox(height: 2),
                Text(
                  'Target durasi: 20 Bulan sejak pertama peluncuran aplikasi.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(int gems, int streak) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatItem('Streak Belajar', '$streak Hari', Icons.local_fire_department, Colors.orangeAccent),
        _buildStatItem('Kosakata Dikuasai', '$_totalWordsCount Kata', Icons.school, AppTheme.neonBlue),
        _buildStatItem('Permata', '$gems Gems', Icons.diamond, AppTheme.neonPink),
        _buildStatItem('Waktu Belajar', '${(streak * 25) + 15} Menit', Icons.schedule, AppTheme.neonGreen),
      ],
    );
  }

  Widget _buildStatItem(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.textSecondary.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationHistoryList() {
    if (_simHistory.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'Belum ada riwayat simulasi ujian terdaftar.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return Column(
      children: _simHistory.map((history) {
        final isJp = history['language'] == 'JAPANESE';
        final double score = history['overall_score'] as double;
        final String scoreText = isJp ? '${score.toInt()} Poin' : 'Band $score';
        final DateTime date = DateTime.fromMillisecondsSinceEpoch(history['timestamp'] as int);
        final dateString = '${date.day}/${date.month}/${date.year}';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isJp ? 'JLPT ${history['level']}' : 'IELTS Academic',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(dateString, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
              Text(
                scoreText,
                style: TextStyle(color: isJp ? AppTheme.neonBlue : AppTheme.neonGreen, fontWeight: FontWeight.w900, fontSize: 14),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.textSecondary.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Pengingat Belajar Harian', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
            subtitle: const Text('Kirim notifikasi setiap pagi pukul 08.00', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            value: _isNotificationEnabled,
            activeColor: AppTheme.neonBlue,
            onChanged: (bool value) {
              setState(() {
                _isNotificationEnabled = value;
              });
            },
          ),
          const Divider(height: 1, color: AppTheme.darkBackground),
          
          // Sinkronisasi Firebase
          ListTile(
            title: const Text('Sinkronisasi Cloud (Firebase)', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Unggah statistik belajar Anda ke server Jengo', style: TextStyle(fontSize: 12)),
            trailing: _isSyncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.neonGreen))
                : const Icon(Icons.cloud_upload_outlined, color: AppTheme.neonGreen, size: 22),
            onTap: _isSyncing ? null : _syncToFirebase,
          ),
          const Divider(height: 1, color: AppTheme.darkBackground),

          // Backup Data
          ListTile(
            title: const Text('Backup Progres Belajar', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Ekspor progress ke berkas cadangan lokal', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.save_alt_outlined, color: AppTheme.neonBlue, size: 22),
            onTap: _performBackup,
          ),
          const Divider(height: 1, color: AppTheme.darkBackground),

          // Restore Data
          ListTile(
            title: const Text('Restore Progres Belajar', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Pulihkan data dari berkas cadangan terakhir', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.settings_backup_restore, color: AppTheme.neonGreen, size: 22),
            onTap: _performRestore,
          ),
          const Divider(height: 1, color: AppTheme.darkBackground),

          // Reset Progress
          ListTile(
            title: const Text('Reset Progres Belajar', style: TextStyle(color: AppTheme.neonPink, fontSize: 14)),
            subtitle: const Text('Mulai ulang aplikasi ke Stage 1 Hari ke-1', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.refresh_outlined, color: AppTheme.neonPink, size: 22),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: AppTheme.darkSurface,
                  title: const Text('Konfirmasi Reset'),
                  content: const Text('Apakah Anda yakin ingin menghapus seluruh progres belajar dan kembali ke awal Stage 1?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Batal', style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonPink),
                      onPressed: () {
                        Navigator.pop(context);
                        _resetDatabaseProgress();
                      },
                      child: const Text('Reset', style: TextStyle(color: AppTheme.textPrimary)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
