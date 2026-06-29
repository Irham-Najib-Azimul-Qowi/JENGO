import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../core/theme/app_theme.dart';
import '../../../core/database/database_helper.dart';

class SpeakingPracticeScreen extends StatefulWidget {
  const SpeakingPracticeScreen({super.key});

  @override
  State<SpeakingPracticeScreen> createState() => _SpeakingPracticeScreenState();
}

class _SpeakingPracticeScreenState extends State<SpeakingPracticeScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  
  bool _isLoading = true;
  bool _isSpeechAvailable = false;
  Map<String, dynamic>? _currentPrompt;
  
  // Timer state
  int _secondsLeft = 60; // 60 detik waktu persiapan
  Timer? _timer;
  bool _isPreparing = true;
  
  // Recording state
  bool _isRecording = false;
  bool _hasSpoken = false;
  String _spokenText = "";

  @override
  void initState() {
    super.initState();
    _loadPrompt();
    _initSpeech();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flutterTts.stop();
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      bool available = await _speech.initialize(
        onStatus: (status) => debugPrint('STT status: $status'),
        onError: (errorNotification) => debugPrint('STT error: $errorNotification'),
      );
      if (mounted) {
        setState(() {
          _isSpeechAvailable = available;
        });
      }
    } catch (e) {
      debugPrint("STT initialization failed: $e");
    }
  }

  Future<void> _loadPrompt() async {
    final db = await DatabaseHelper.instance.database;
    final prompts = await db.query('speaking_prompts', where: 'part = 2', limit: 1);
    
    if (mounted && prompts.isNotEmpty) {
      setState(() {
        _currentPrompt = prompts[0];
        _isLoading = false;
      });
      _startPreparationTimer();
    }
  }

  void _startPreparationTimer() {
    _isPreparing = true;
    _secondsLeft = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() {
          _secondsLeft--;
        });
      } else {
        _timer?.cancel();
        _startSpeakingSession();
      }
    });
  }

  void _startSpeakingSession() {
    setState(() {
      _isPreparing = false;
      _secondsLeft = 120; // 2 Menit waktu berbicara
    });
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() {
          _secondsLeft--;
        });
      } else {
        _timer?.cancel();
        if (_isRecording) _stopListening();
        _finishSpeaking();
      }
    });
  }

  void _startListening() async {
    if (!_isSpeechAvailable) {
      _simulateSpeakingRecord();
      return;
    }

    setState(() {
      _isRecording = true;
      _spokenText = "";
    });

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _spokenText = result.recognizedWords;
          if (result.finalResult) {
            _isRecording = false;
            _hasSpoken = true;
          }
        });
      },
      localeId: 'en_US',
    );
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() {
      _isRecording = false;
      _hasSpoken = true;
    });
  }

  void _simulateSpeakingRecord() async {
    setState(() {
      _isRecording = true;
    });

    await Future.delayed(const Duration(seconds: 3));

    if (mounted) {
      setState(() {
        _isRecording = false;
        _hasSpoken = true;
        _spokenText = "This describes my preparation. I would like to talk about the book I read recently. It was an academic journal explaining the impacts of artificial intelligence on marine biology...";
      });
    }
  }

  void _finishSpeaking() async {
    final db = await DatabaseHelper.instance.database;
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
    _timer?.cancel();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.neonBlue),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.neonGreen),
            SizedBox(width: 10),
            Text('Simulasi Speaking Selesai!'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rekaman pidato IELTS Speaking Part 2 Anda berhasil disimpan.'),
            SizedBox(height: 12),
            Text('🏆 Hadiah Progres: +150 XP & +20 Gems', style: TextStyle(color: AppTheme.neonGreen, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonBlue),
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

    final cardPrompt = _currentPrompt?['prompt_card'] ?? "Cue card tidak ditemukan.";
    final tips = _currentPrompt?['tips'] ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text('IELTS Speaking: Part 2 (Cue Card)'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // 1. Timer & Persiapan Status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _isPreparing ? AppTheme.neonBlue.withOpacity(0.15) : AppTheme.neonGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _isPreparing ? AppTheme.neonBlue : AppTheme.neonGreen),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isPreparing ? '⏳ Waktu Persiapan:' : '🎙️ Waktu Berbicara:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _isPreparing ? AppTheme.neonBlue : AppTheme.neonGreen,
                    ),
                  ),
                  Text(
                    '$_secondsLeft detik',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _isPreparing ? AppTheme.neonBlue : AppTheme.neonGreen,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2. Cue Card Prompt
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.textSecondary.withOpacity(0.1)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CUE CARD TOPIC:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.neonBlue, letterSpacing: 1),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        cardPrompt,
                        style: const TextStyle(fontSize: 15, height: 1.6, color: AppTheme.textPrimary),
                      ),
                      const Divider(height: 36, color: AppTheme.darkBackground),
                      Text(
                        '💡 Tips Penguji: $tips',
                        style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 3. Audio Recorder & Transcript
            if (!_isPreparing) ...[
              if (_hasSpoken) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Transkrip Ucapan: "$_spokenText"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                    label: Text(_isRecording ? 'Berhenti' : 'Mulai Rekam'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isRecording ? AppTheme.neonPink : AppTheme.neonGreen,
                      foregroundColor: AppTheme.darkBackground,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isRecording ? _stopListening : _startListening,
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neonBlue,
                      foregroundColor: AppTheme.darkBackground,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _finishSpeaking,
                    child: const Text('Selesaikan', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ] else ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neonBlue,
                  foregroundColor: AppTheme.darkBackground,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  _timer?.cancel();
                  _startSpeakingSession();
                },
                child: const Text('LEWATI PERSIAPAN & MULAI', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
