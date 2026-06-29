import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class TipsTricksScreen extends StatelessWidget {
  final String language;

  const TipsTricksScreen({
    super.key,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final isJp = language == 'JAPANESE';
    final Color color = isJp ? AppTheme.neonBlue : AppTheme.neonGreen;

    return Scaffold(
      appBar: AppBar(
        title: Text('Strategi & Tips ${isJp ? 'JLPT' : 'IELTS'}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isJp ? [AppTheme.neonBlue, const Color(0xFF002244)] : [AppTheme.neonGreen, const Color(0xFF003311)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.15), blurRadius: 10),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(isJp ? Icons.menu_book : Icons.lightbulb, color: Colors.white, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    isJp ? 'PANDUAN TAKTIS JLPT N5-N2' : 'PANDUAN EMAS IELTS BAND 8.0',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white, letterSpacing: 1.1),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isJp
                        ? 'Tips membaca cepat, kata kunci menyimak, manajemen waktu, dan strategi lolos skor standar kelulusan.'
                        : 'Strategi pemetaan paragraf, transkripsi audio, struktur menulis opini akademik, dan kelancaran wawancara.',
                    style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            Text(
              'Strategi Komponen Tes',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),

            if (isJp) ...[
              _buildStrategyItem(
                context,
                title: '1. Teknik Membaca (Dokkai)',
                description: 'Jangan membaca seluruh teks dari awal. Cari kata penghubung seperti 「しかし」 (tetapi) atau 「つまり」 (artinya) karena biasanya kesimpulan utama berada langsung di belakang kata tersebut. Selalu baca pertanyaan sebelum melihat teks.',
                icon: Icons.chrome_reader_mode,
                color: color,
              ),
              _buildStrategyItem(
                context,
                title: '2. Teknik Listening (Choukai)',
                description: 'Perhatikan kata kunci penolakan di akhir percakapan seperti 「〜が」 atau 「ちょっと…」. Jawaban benar sering kali berupa parafrasa (sinonim kata) dari apa yang diucapkan dalam audio.',
                icon: Icons.hearing,
                color: color,
              ),
              _buildStrategyItem(
                context,
                title: '3. Manajemen Waktu JLPT',
                description: 'Bagian kosakata & tata bahasa harus dikerjakan secepat mungkin (maksimal 30 detik per soal) untuk menghemat sisa waktu untuk teks bacaan panjang yang membutuhkan konsentrasi lebih.',
                icon: Icons.timer,
                color: color,
              ),
              _buildStrategyItem(
                context,
                title: '4. Kesalahan Umum Ujian',
                description: 'Tertukar membaca Kanji dengan Onyomi dan Kunyomi. Selalu perhatikan hiragana pendamping (okurigana) untuk memastikan pembacaan kanji kata kerja yang tepat.',
                icon: Icons.warning_amber,
                color: color,
              ),
            ] else ...[
              _buildStrategyItem(
                context,
                title: '1. IELTS Reading (Paragraph Matching)',
                description: 'Gunakan teknik skimming untuk mencari tema umum paragraf terlebih dahulu. Jangan terjebak mencari arti kata asing; fokus pada sinonim kata kunci pertanyaan di dalam teks.',
                icon: Icons.article,
                color: color,
              ),
              _buildStrategyItem(
                context,
                title: '2. IELTS Listening (Signpost Words)',
                description: 'Dengarkan kata penunjuk arah percakapan seperti "However", "Moving on to", atau "Consequently". Kata-kata ini menandai transisi ke informasi jawaban berikutnya.',
                icon: Icons.headphones,
                color: color,
              ),
              _buildStrategyItem(
                context,
                title: '3. IELTS Writing Task 2 Structure',
                description: 'Selalu gunakan format 4 paragraf: 1) Introduction & Thesis statement, 2) Body Paragraph 1 (Argumen pertama + contoh), 3) Body Paragraph 2 (Argumen kedua + contoh), 4) Conclusion. Gunakan variasi kata penghubung akademis.',
                icon: Icons.edit,
                color: color,
              ),
              _buildStrategyItem(
                context,
                title: '4. IELTS Speaking Band 8.0 Flow',
                description: 'Pada Part 2, gunakan strategi 1-menit persiapan untuk mencatat poin-poin cerita. Saat berbicara, jangan berhenti bergumam atau diam; parafrasa kata jika Anda lupa kosakata spesifik.',
                icon: Icons.mic,
                color: color,
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStrategyItem(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.textSecondary.withOpacity(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
