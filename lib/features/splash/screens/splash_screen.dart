import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/firebase_sync_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  String _syncStatusText = "Mempersiapkan aplikasi...";

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();
    _checkSyncAndNavigate();
  }

  Future<void> _checkSyncAndNavigate() async {
    final dbHelper = DatabaseHelper.instance;
    final db = await dbHelper.database;
    
    // Ambil data gamifikasi untuk memeriksa status sinkronisasi
    final userList = await db.query('gamification', limit: 1);
    int isSynced = 0;
    if (userList.isNotEmpty) {
      isSynced = userList.first['is_synced'] as int? ?? 0;
    }

    if (isSynced == 0) {
      // Jalankan sinkronisasi Firebase
      bool success = await FirebaseSyncService.instance.syncFirebaseToSqlite(
        dbHelper,
        (progress) {
          if (mounted) {
            setState(() {
              _syncStatusText = progress;
            });
          }
        },
      );
      
      if (success) {
        print("First-launch Firebase materials sync completed successfully.");
      } else {
        print("Firebase sync skipped (offline) or failed. Local assets will be used.");
      }
    } else {
      // Sudah tersinkronisasi, beri jeda animasi sebentar saja
      if (mounted) {
        setState(() {
          _syncStatusText = "Membuka beranda belajar...";
        });
      }
      await Future.delayed(const Duration(milliseconds: 1800));
    }

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/main_nav');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo Glow Neon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppTheme.neonBlue, AppTheme.neonGreen],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.neonBlue.withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.translate,
                  size: 50,
                  color: AppTheme.darkBackground,
                ),
              ),
              const SizedBox(height: 24),
              // App Name
              Text(
                'JENGO',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      shadows: [
                        Shadow(
                          color: AppTheme.neonBlue.withOpacity(0.8),
                          blurRadius: 10,
                        ),
                      ],
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Master JLPT N2 & IELTS 8.0',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      letterSpacing: 1.2,
                    ),
              ),
              const SizedBox(height: 48),
              // Circular Loader
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: AppTheme.neonGreen,
                  strokeWidth: 2.5,
                ),
              ),
              const SizedBox(height: 16),
              // Status Text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _syncStatusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
