# Panduan Setup Firebase untuk Aplikasi JENGO (Flutter)

Panduan ini berisi langkah-langkah yang harus Anda lakukan untuk menyiapkan proyek Firebase agar saya dapat mengintegrasikan layanan Cloud Firestore, Authentication, dan Firebase Storage ke dalam kode aplikasi.

---

## 🛠️ Langkah 1: Buat Proyek di Firebase Console

1.  Buka web browser dan masuk ke [Firebase Console](https://console.firebase.google.com/).
2.  Login menggunakan akun Google Anda.
3.  Klik **Add Project** (Tambah Proyek).
4.  Masukkan nama proyek: **JENGO**, lalu klik **Continue**.
5.  (Opsional) Aktifkan Google Analytics jika diinginkan, lalu klik **Create Project**.
6.  Tunggu hingga proses pembuatan selesai dan klik **Continue**.

---

## 🔑 Langkah 2: Aktifkan Layanan Firebase yang Dibutuhkan

Di panel sebelah kiri Firebase Console, aktifkan tiga layanan berikut:

### 1. Firebase Authentication (Untuk Login Pengguna)
*   Buka menu **Build > Authentication** lalu klik **Get Started**.
*   Pada tab **Sign-in method**, aktifkan penyedia berikut:
    *   **Email/Password** (Aktifkan statusnya).
    *   **Google** (Aktifkan, pilih email dukungan proyek Anda, lalu simpan).

### 2. Cloud Firestore (Untuk Sinkronisasi Progres Belajat)
*   Buka menu **Build > Firestore Database** lalu klik **Create Database**.
*   Pilih lokasi server terdekat (misal: `asia-southeast2` untuk Jakarta/Singapura).
*   Pilih **Start in test mode** (Mode pengujian agar kita bebas membaca/menulis data tanpa hambatan aturan keamanan di awal pengembangan), lalu klik **Create**.

### 3. Firebase Storage (Untuk Menyimpan File Audio Listening)
*   Buka menu **Build > Storage** lalu klik **Get Started**.
*   Pilih **Start in test mode**, klik **Next**, lalu pilih lokasi penyimpanan default dan klik **Done**.

---

## 🚀 Langkah 3: Konfigurasi Firebase ke dalam Proyek Flutter

Untuk menghubungkan Firebase ke proyek Flutter, kita akan menggunakan alat resmi **FlutterFire CLI**. Silakan ikuti langkah-langkah di terminal komputer Anda:

1.  **Instal Firebase CLI (jika belum ada):**
    *   Buka PowerShell dan jalankan perintah instalasi Node.js package manager (npm) berikut:
        ```bash
        npm install -g firebase-tools
        ```
2.  **Login ke Firebase via Terminal:**
    *   Jalankan perintah berikut dan ikuti instruksi login di browser Anda:
        ```bash
        firebase login
        ```
3.  **Instal FlutterFire CLI secara Global:**
    *   Jalankan perintah berikut:
        ```bash
        dart pub global activate flutterfire_cli
        ```
    *   *Catatan:* Jika ada peringatan PATH, pastikan folder bin Dart sudah terdaftar di environment variable Anda.
4.  **Jalankan Perintah Konfigurasi di Folder Proyek:**
    *   Buka terminal di direktori proyek (`d:\folder_pnm\android\New folder`) dan jalankan:
        ```bash
        flutterfire configure
        ```
    *   CLI akan meminta Anda memilih proyek Firebase yang baru saja dibuat (**JENGO**).
    *   Pilih platform target (pilih **android** dan **ios** dengan menekan spasi, lalu tekan Enter).
    *   FlutterFire CLI akan mengunduh file konfigurasi bawaan dan secara otomatis membuat berkas baru bernama **`lib/firebase_options.dart`** di dalam proyek Anda.

---

## 📄 Langkah 4: Berikan Berkas Konfigurasi kepada Saya

Setelah proses di atas selesai, saya membutuhkan file berikut untuk melanjutkan pengodean:
1.  Berkas **`lib/firebase_options.dart`** (dihasilkan oleh FlutterFire CLI).
2.  Berkas **`android/app/google-services.json`** (dibuat otomatis oleh Flutterfire CLI di dalam sub-folder Android).

Setelah Anda menyelesaikan langkah-langkah di atas, beri tahu saya agar kita bisa langsung memasukkan modul inisialisasi Firebase dan memuat materi pembelajaran berkualitas tinggi dalam jumlah besar ke Firebase Storage/Firestore!
