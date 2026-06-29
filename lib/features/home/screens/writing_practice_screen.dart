import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_helper.dart';

class WritingPracticeScreen extends StatefulWidget {
  const WritingPracticeScreen({super.key});

  @override
  State<WritingPracticeScreen> createState() => _WritingPracticeScreenState();
}

class _WritingPracticeScreenState extends State<WritingPracticeScreen> {
  final TextEditingController _essayController = TextEditingController();
  bool _isLoading = true;
  Map<String, dynamic>? _currentPrompt;
  int _wordCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPrompt();
    _essayController.addListener(_updateWordCount);
  }

  @override
  void dispose() {
    _essayController.dispose();
    super.dispose();
  }

  Future<void> _loadPrompt() async {
    final db = await DatabaseHelper.instance.database;
    final prompts = await db.query('writing_prompts', limit: 10);
    
    if (mounted && prompts.isNotEmpty) {
      setState(() {
        _currentPrompt = prompts[0]; // Load task 2 essay prompt
        _isLoading = false;
      });
    }
  }

  void _updateWordCount() {
    final text = _essayController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _wordCount = 0;
      });
      return;
    }
    setState(() {
      _wordCount = text.split(RegExp(r'\s+')).length;
    });
  }

  void _submitEssay() async {
    final db = await DatabaseHelper.instance.database;
    
    // Berikan reward ke user
    final userList = await db.query('gamification', limit: 1);
    if (userList.isNotEmpty) {
      final user = userList.first;
      final currentXp = user['total_xp'] as int? ?? 1500;
      final currentGems = user['gems'] as int? ?? 250;

      await db.update(
        'gamification',
        {
          'total_xp': currentXp + 150,
          'gems': currentGems + 20,
        },
        where: 'id = ?',
        whereArgs: [user['id']],
      );
    }

    _showResultDialog();
  }

  void _showResultDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.neonGreen),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.neonGreen),
            SizedBox(width: 10),
            Text('Esai Diserahkan!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Esai Anda telah berhasil disimpan ke database lokal.'),
            const SizedBox(height: 12),
            Text('✍️ Jumlah Kata: $_wordCount kata', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('🏆 Hadiah Progres: +150 XP & +20 Gems', style: TextStyle(color: AppTheme.neonGreen)),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonGreen),
            onPressed: () {
              Navigator.pop(context); // Tutup dialog
              Navigator.pop(context); // Kembali ke dashboard
            },
            child: const Text('Kembali ke Dashboard', style: TextStyle(color: AppTheme.darkBackground)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.neonBlue)),
      );
    }

    final promptText = _currentPrompt?['prompt'] ?? "Soal menulis esai tidak ditemukan.";
    final taskNum = _currentPrompt?['task'] ?? 2;
    final tipsText = _currentPrompt?['tips'] ?? "";

    return Scaffold(
      appBar: AppBar(
        title: Text('IELTS Writing Practice: Task $taskNum'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Soal Latihan
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.textSecondary.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PROMPT SOAL:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.neonGreen, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Text(
                    promptText,
                    style: const TextStyle(fontSize: 14, height: 1.5, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tipsText,
                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2. Editor Teks Esai
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.textSecondary.withOpacity(0.2)),
                ),
                child: TextField(
                  controller: _essayController,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary, height: 1.5),
                  decoration: const InputDecoration(
                    hintText: 'Tulis esai akademik Anda di sini (Minimal 250 kata)...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Status Bar Counter & Tombol Kirim
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Jumlah Kata: $_wordCount',
                  style: TextStyle(
                    color: _wordCount >= 250 ? AppTheme.neonGreen : AppTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _wordCount >= 50 ? AppTheme.neonGreen : AppTheme.textSecondary.withOpacity(0.2),
                    foregroundColor: AppTheme.darkBackground,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _wordCount >= 50 ? _submitEssay : null,
                  child: const Text('SUBMIT ESAI', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
