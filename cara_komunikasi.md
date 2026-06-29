# Cara Komunikasi: AI Developer & Aplikasi Jengo dengan Firebase

---

## Bagian 1 — Cara Saya (AI) Berkomunikasi Selama Pengembangan

### 1.1 Saluran Komunikasi AI → Kode

Saya tidak berkomunikasi secara langsung dengan server Firebase pada saat pengembangan. Saya bekerja **hanya melalui manipulasi file kode sumber** di workspace lokal Anda. Alur kerjanya adalah:

```
Instruksi Anda
      ↓
Saya analisis file yang relevan (baca kode, log, struktur)
      ↓
Saya tulis/edit file Dart, JSON asset, AndroidManifest, pubspec
      ↓
Anda jalankan `flutter run` di terminal
      ↓
Flutter compile & deploy ke HP fisik Anda
      ↓
Aplikasi yang berjalan di HP LALU berkomunikasi dengan Firebase
```

Jadi selama sesi pengembangan ini, semua perubahan yang saya buat adalah **perubahan kode lokal**. Firebase hanya aktif saat aplikasi dijalankan di perangkat.

### 1.2 Alat yang Saya Gunakan untuk Membaca/Tulis File

| Alat              | Fungsi                                               |
|-------------------|------------------------------------------------------|
| `view_file`       | Membaca isi file (kode Dart, JSON, YAML, dsb.)       |
| `write_to_file`   | Membuat file baru dari awal                          |
| `replace_file_content` | Mengedit bagian spesifik dari file yang ada   |
| `run_command`     | Menjalankan perintah di terminal (flutter analyze, git, dll.) |
| `grep_search`     | Mencari pola tertentu di seluruh kodebase            |
| `list_dir`        | Melihat struktur folder                              |

### 1.3 Cara Saya Memastikan Kode Benar

Saya tidak bisa "mencoba" kode secara langsung. Cara verifikasi yang saya gunakan:

1. **`flutter analyze <file.dart>`** — mendeteksi error sintaks dan type mismatch sebelum compile
2. **Membaca log hasil `flutter run`** dari task background
3. **Mengecek output `git status` dan `git log`** untuk memastikan perubahan tersimpan dengan benar

---

## Bagian 2 — Cara Aplikasi Jengo Berkomunikasi dengan Firebase

### 2.1 Inisialisasi Firebase

Firebase diinisialisasi di `lib/main.dart` sebelum aplikasi berjalan:

```dart
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

Konfigurasi platform diambil dari `lib/firebase_options.dart` yang di-generate otomatis oleh Firebase CLI.

### 2.2 Produk Firebase yang Digunakan

| Produk Firebase       | Digunakan Untuk                                              |
|------------------------|--------------------------------------------------------------|
| **Cloud Firestore**    | Sinkronisasi materi pembelajaran (vocab, reading, grammar, dll.) |
| **Firebase Auth**      | *(siap digunakan, belum aktif diimplementasi)*               |
| **Firebase Storage**   | *(bucket tersedia, belum dipakai untuk file audio)*          |

### 2.3 Alur Sinkronisasi Firestore → SQLite

Sinkronisasi terjadi di `lib/core/services/firebase_sync_service.dart` dan dipanggil dari `lib/features/splash/screens/splash_screen.dart`.

#### Kapan sync dipicu:

```
Splash Screen buka
      ↓
Cek kolom `is_synced` di tabel `gamification` (SQLite lokal)
      ↓
Jika is_synced == 0 DAN ada koneksi internet
      ↓
Panggil FirebaseSyncService.syncFirebaseToSqlite()
      ↓
Download collection Firestore → masukkan ke SQLite lokal
      ↓
Set is_synced = 1 (tidak sync ulang otomatis kecuali di-reset)
```

#### Collection Firestore yang diunduh:

| Koleksi Firestore          | Tabel SQLite Tujuan  |
|----------------------------|----------------------|
| `japanese_vocab`           | `vocabulary`         |
| `english_vocab`            | `vocabulary`         |
| `japanese_kanji`           | `kanji`              |
| `japanese_grammar`         | `grammar`            |
| `english_grammar`          | `grammar`            |
| `japanese_sentences`       | `sentences`          |
| `english_speaking_prompts` | `speaking_prompts`   |
| `english_writing_prompts`  | `writing_prompts`    |

#### Kode inti sync (contoh satu collection):

```dart
final snapshot = await FirebaseFirestore.instance
    .collection('japanese_vocab')
    .get();

for (final doc in snapshot.docs) {
  await db.insert(
    'vocabulary',
    doc.data(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
```

### 2.4 Upload Materi ke Firestore

Script Python `upload_assets_to_firebase.py` dijalankan **oleh developer** (bukan oleh aplikasi) untuk mengisi Firestore dari file JSON asset lokal:

```
assets/materials/japanese/vocab.json
          ↓
upload_assets_to_firebase.py
          ↓
Firestore collection `japanese_vocab`
```

Aplikasi tidak pernah upload data ke Firestore — hanya **mengunduh** dari Firestore ke SQLite lokal.

### 2.5 Sinkronisasi Manual dari Profil Pengguna

Di `lib/features/profile/screens/profile_screen.dart`, ada tombol **"Sinkronisasi Cloud (Firebase)"** yang mengunggah statistik belajar pengguna ke Firestore:

```dart
await FirebaseFirestore.instance
    .collection('users')
    .doc('learner_pro_123')
    .set({
      'gamification': { ... },
      'stages': [ ... ],
    }, SetOptions(merge: true));
```

Ini bersifat **upload satu arah** — statistik XP, streak, dan progress stage dikirim ke Firestore.

---

## Bagian 3 — Kredensial Firebase yang Digunakan

> **Perhatian**: Kredensial berikut adalah milik proyek Firebase Anda. Jangan dibagikan secara publik. File `google-services.json` dan `firebase_options.dart` sudah di-commit ke repo; pertimbangkan untuk menambahkan keduanya ke `.gitignore` untuk proyek produksi.

### 3.1 Identitas Proyek Firebase

| Parameter          | Nilai                                      |
|--------------------|---------------------------------------------|
| **Project ID**     | `jengo-772e8`                               |
| **Project Number** | `781605410912`                              |
| **Storage Bucket** | `jengo-772e8.firebasestorage.app`           |

### 3.2 Kredensial Android (`google-services.json`)

Lokasi file: `google-services.json` dan `android/app/google-services.json`

| Parameter                | Nilai                                                                       |
|--------------------------|-----------------------------------------------------------------------------|
| **Mobile SDK App ID**    | `1:781605410912:android:72f6f9fb86af82a97c8b05`                             |
| **Package Name**         | `com.example.jengo`                                                         |
| **API Key (Android)**    | `AIzaSyBd-KtZcZYM6sLP81IXf314F_O7Jz5TTgA`                                  |
| **OAuth Client ID**      | `781605410912-q9ki8bhf97hdi9smjd695kj42fih9qvv.apps.googleusercontent.com`  |
| **OAuth Client Type**    | `3` (Web client / installed app)                                             |

### 3.3 Kredensial Flutter (`firebase_options.dart`)

Lokasi file: `lib/firebase_options.dart`

File ini di-generate oleh `flutterfire configure` dan berisi konfigurasi per platform. Untuk Android, nilainya sama dengan `google-services.json`. Konfigurasi ini dipakai oleh `Firebase.initializeApp()` saat startup.

### 3.4 Firestore Security Rules

Lokasi file: `firestore.rules`

Rules Firestore mengatur siapa yang boleh baca/tulis collection. Pastikan rules ini diperketat sebelum aplikasi go production.

---

## Bagian 4 — Diagram Komunikasi Lengkap

```
HP Fisik Pengguna
┌────────────────────────────────────────────┐
│                                            │
│  Flutter App (Jengo APK)                   │
│        │                                   │
│        ▼                                   │
│  SQLite (Lokal)                            │
│   - vocabulary                             │
│   - kanji                                 │
│   - reading                               │
│   - simulations_history                   │
│   - gamification                          │
│        ▲                                   │
│        │ sync (online only, is_synced==0)  │
│        ▼                                   │
│  Firebase SDK (FlutterFire)               │
└───────────────┬────────────────────────────┘
                │ HTTPS / gRPC
                ▼
Google Firebase — Project: jengo-772e8
┌────────────────────────────────────────────┐
│  Cloud Firestore                           │
│   - japanese_vocab                        │
│   - english_vocab                         │
│   - japanese_grammar                      │
│   - english_grammar                       │
│   - japanese_sentences                    │
│   - english_speaking_prompts              │
│   - english_writing_prompts               │
│   - users/{id}  ← stats dari profil       │
└────────────────────────────────────────────┘
                ▲
                │ (diisi oleh developer, bukan app)
upload_assets_to_firebase.py
                ▲
                │
assets/materials/
   japanese/vocab.json
   english/vocab.json
   reading.json, dll.
```

---

## Ringkasan

| Siapa           | Berkomunikasi Ke           | Kapan                                                        |
|-----------------|----------------------------|--------------------------------------------------------------|
| AI (Antigravity)| File kode lokal            | Selama sesi pengembangan (menulis/mengedit file)              |
| Aplikasi Jengo  | SQLite lokal               | Setiap saat (read/write data harian, kuis, simulasi)         |
| Aplikasi Jengo  | Firestore (download)       | Sekali saat pertama kali pakai (is_synced = 0)               |
| Aplikasi Jengo  | Firestore (upload stats)   | Manual lewat tombol di halaman Profil pengguna               |
| Developer       | Firestore (upload materi)  | Lewat script Python `upload_assets_to_firebase.py`           |
