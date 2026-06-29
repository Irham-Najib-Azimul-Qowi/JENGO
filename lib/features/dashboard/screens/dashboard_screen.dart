import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/navigation/app_router.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header Row (Streak, Hearts, Gems)
              _buildTopStatusBar(context),
              const SizedBox(height: 24),

              // 2. User Welcome & Level Title
              Text(
                'Selamat Pagi,',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                    ),
              ),
              Text(
                'Pelajar Ambisius',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              _buildLevelBadge(context, 5, 'Pelajar Mahir'),
              const SizedBox(height: 24),

              // 3. Dual-Track Exam Readiness Cards
              Text(
                'Kesiapan Target Ujian',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildReadinessCard(
                      context,
                      'JLPT N2',
                      0.45, // 45%
                      'Target: Lulus N2',
                      AppTheme.neonBlue,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildReadinessCard(
                      context,
                      'IELTS 8.0',
                      0.60, // 60%
                      'Target: Band 8.0',
                      AppTheme.neonGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // 4. Large Neon Call to Action
              _buildStartLessonButton(context),
              const SizedBox(height: 20),

              // 5. Quick Navigation Section
              _buildQuickNavSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopStatusBar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildStatusIcon(context, Icons.local_fire_department, '7 Hari', Colors.orangeAccent),
        _buildStatusIcon(context, Icons.favorite, '5 Nyawa', AppTheme.neonPink),
        _buildStatusIcon(context, Icons.blur_on, '150 Gems', AppTheme.neonBlue),
      ],
    );
  }

  Widget _buildStatusIcon(BuildContext context, IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelBadge(BuildContext context, int level, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.neonBlue.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.neonBlue.withOpacity(0.5)),
      ),
      child: Text(
        'LEVEL $level • $title',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.neonBlue,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
      ),
    );
  }

  Widget _buildReadinessCard(
      BuildContext context, String examName, double progress, String subText, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              examName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: color,
                  ),
            ),
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 8,
                    backgroundColor: AppTheme.darkBackground,
                    color: color,
                  ),
                ),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              subText,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartLessonButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRouter.dailyLesson),
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.neonBlue, AppTheme.neonGreen],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.neonBlue.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'MULAI MISI HARI INI',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.darkBackground,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickNavSection(BuildContext context) {
    return Card(
      color: AppTheme.darkSurface.withOpacity(0.5),
      child: ListTile(
        onTap: () => Navigator.pushNamed(context, AppRouter.learningPath),
        leading: const Icon(Icons.map, color: AppTheme.neonGreen, size: 28),
        title: const Text(
          'Jalur Belajar 20 Bulan',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Lihat peta perjalanan JLPT N2 & IELTS 8.0'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textSecondary),
      ),
    );
  }
}
