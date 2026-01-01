# Cleona Chat -- Panduan Pengguna

Version 3.1.125 | Juli 2026

---

## Daftar Isi

1. [Apa itu Cleona Chat?](#1-was-ist-cleona-chat)
2. [Langkah Awal](#2-erste-schritte)
3. [Kontak](#3-kontakte)
4. [Pesan](#4-nachrichten)
5. [Grup](#5-gruppen)
6. [Kanal Publik](#6-oeffentliche-kanaele)
7. [Panggilan](#7-anrufe)
8. [Kalender](#8-kalender)
9. [Polling](#9-umfragen)
10. [Beberapa Identitas](#10-mehrere-identitaeten)
11. [Multi-Device](#11-multi-device)
12. [Pemulihan](#12-wiederherstellung)
13. [Pengaturan](#13-einstellungen)
14. [Keamanan](#14-sicherheit)
15. [Pembaruan Software](#15-software-updates)
16. [Pertanyaan yang Sering Diajukan](#16-haeufige-fragen)

---

## 1. Apa itu Cleona Chat?

### Messenger-mu, datamu

Cleona Chat adalah messenger yang bekerja sepenuhnya tanpa server pusat.
Pesanmu berjalan langsung dari perangkatmu ke perangkat lawan bicaramu --
tanpa melalui kantor pusat perusahaan, tanpa cloud, tanpa pusat data. Tidak
ada perusahaan yang bisa membaca, menyimpan, atau membagikan pesanmu, karena
memang tidak ada perusahaan yang berada di tengah-tengah.

### Tanpa akun, tanpa nomor telepon

Di Cleona, kamu tidak memerlukan nomor telepon maupun alamat email untuk
mendaftar. Identitasmu terdiri dari sepasang kunci kriptografis yang dibuat
otomatis di perangkatmu saat pertama kali dijalankan. Artinya: tidak ada yang
bisa melacakmu lewat nomor telepon atau alamat email, kecuali kamu sendiri
yang membagikan data kontakmu.

### Enkripsi yang siap menghadapi masa depan

Cleona menggunakan apa yang disebut enkripsi Post-Quantum. Artinya: bahkan
komputer kuantum di masa depan pun tidak akan bisa membobol pesanmu. Kamu
tidak perlu memahami detailnya -- yang penting, komunikasimu terlindungi
semaksimal mungkin sesuai teknologi terkini.

### Bagaimana cara kerjanya tanpa server?

Bayangkan kamu dan kontak-kontakmu bersama-sama membentuk sebuah jaringan.
Setiap perangkat ikut membantu meneruskan pesan. Jika lawan bicaramu sedang
online, pesan langsung terkirim ke sana. Jika lawan bicaramu sedang offline,
kontak-kontak bersama akan menyimpan pesan itu sementara dan mengirimkannya
begitu penerima kembali online. Jadi, kontak-kontakmu sekaligus juga menjadi
jaringanmu.

### Platform

Cleona tersedia untuk Android, iOS, macOS, Linux, dan Windows.

---

## 2. Langkah Awal

### Menginstal aplikasi

**Android:**
1. Unduh file APK dari situs web Cleona atau dari GitHub Releases.
2. Buka file tersebut di ponselmu. Jika perlu, izinkan instalasi dari sumber
   tidak dikenal (Android akan menanyakan hal ini secara otomatis).
3. Ketuk "Instal" dan tunggu hingga instalasi selesai.

**iOS:**
1. Buka tautan undangan TestFlight di iPhone-mu.
2. Ketuk "Instal". TestFlight adalah cara resmi Apple untuk mendistribusikan
   aplikasi beta.
3. Setelah instalasi, kamu akan menemukan Cleona di layar utama.

**macOS:**
1. Unduh file DMG dari situs web Cleona atau dari GitHub Releases.
2. Buka DMG tersebut dan seret Cleona ke folder Applications.
3. Saat pertama kali dijalankan, macOS mungkin menanyakan apakah kamu ingin
   membuka aplikasi dari pengembang yang teridentifikasi -- konfirmasi hal
   ini.

**Linux (Ubuntu/Debian):**
1. Unduh file .deb dari situs web Cleona atau dari GitHub Releases.
2. Instal dengan klik ganda atau lewat terminal: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Jalankan Cleona lewat menu aplikasi atau di terminal dengan `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Unduh file .rpm dari situs web Cleona atau dari GitHub Releases.
2. Instal dengan: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Jalankan Cleona lewat menu aplikasi atau di terminal dengan `cleona-chat`.

**Linux (semua distribusi -- AppImage):**
1. Unduh file .AppImage dari situs web Cleona atau dari GitHub Releases.
2. Jadikan file tersebut dapat dieksekusi: klik kanan, Properties, Executable,
   atau di terminal: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Jalankan dengan klik ganda atau di terminal: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Unduh installer dari situs web Cleona atau dari GitHub Releases.
2. Jalankan file instalasi tersebut dan ikuti petunjuknya.
3. Jalankan Cleona lewat menu Start atau pintasan di desktop.

### Membuat identitas

Saat pertama kali dijalankan, Cleona otomatis membuat identitas baru untukmu.
Kamu bisa memberi dirimu sebuah nama tampilan -- ini adalah nama yang akan
dilihat oleh kontak-kontakmu. Nama ini bisa diubah kapan saja.

### Menuliskan Seed-Phrase -- hal terpenting dari semuanya

Setelah identitasmu dibuat, Cleona akan menampilkan 24 kata. Itulah
**Seed-Phrase**-mu -- kunci pemulihan pribadimu.

**Tuliskan 24 kata ini di atas kertas dan simpan dengan aman.**

Mengapa ini begitu penting?

- Jika ponselmu rusak, hilang, atau dicuri, kamu bisa memulihkan seluruh
  identitasmu di perangkat baru hanya dengan 24 kata ini.
- Tanpa Seed-Phrase, tidak ada jalan kembali. Tidak ada tombol "lupa
  password" dan tidak ada dukungan pelanggan yang bisa mengembalikan akunmu
  -- karena memang tidak ada akun di server mana pun.
- Jangan pernah membagikan Seed-Phrase kepada orang lain. Siapa pun yang tahu
  kata-kata ini bisa menyamar sebagai dirimu.

Kamu juga bisa menemukan Seed-Phrase nanti di Pengaturan bagian "Keamanan",
jika sewaktu-waktu ingin membacanya kembali.

### Menambahkan kontak pertama

Untuk bisa mengobrol dengan seseorang, kamu harus menambahkan orang tersebut
sebagai kontak terlebih dahulu. Ada beberapa cara untuk melakukannya -- semua
akan dijelaskan di bagian berikutnya.

---

## 3. Kontak

### Memindai QR-Code (disarankan)

Cara paling mudah untuk menambahkan kontak:

1. Lawan bicaramu membuka halaman detail identitasnya (ketuk namanya sendiri
   di bilah atas) dan menunjukkan QR-Code miliknya kepadamu.
2. Kamu ketuk tombol plus dan pilih "Pindai QR-Code".
3. Arahkan ponselmu ke QR-Code milik lawan bicaramu.
4. Permintaan kontak akan otomatis terkirim. Begitu lawan bicaramu
   menerimanya, kalian bisa saling mengirim pesan.

Jika kalian bertemu langsung, QR-Code adalah metode paling aman karena kamu
tahu persis dengan siapa kamu bertukar kontak.

### NFC (mendekatkan ponsel)

Jika kedua perangkat mendukung NFC:

1. Buka fitur Tambah Kontak di kedua perangkat.
2. Dekatkan kedua ponsel bagian belakang ke belakang.
3. Data kontak akan otomatis dipertukarkan.

Sama seperti QR-Code, NFC menawarkan keamanan tinggi karena pertukaran hanya
berfungsi jika kalian berdiri berdekatan secara fisik.

### Membagikan tautan (URI cleona://)

Kamu juga bisa mengirim tautan kontakmu lewat email, SMS, atau messenger
lain:

1. Buka halaman detail identitasmu.
2. Salin tautan cleona:// milikmu.
3. Kirim tautan tersebut kepada orang yang ingin menambahkanmu.
4. Orang tersebut membuka tautan itu, atau menempelkannya di dialog Tambah
   Kontak.

Perhatikan: dengan metode ini kamu mempercayai bahwa tautan tersebut tidak
diubah selama proses pengiriman. Untuk kontak yang sangat sensitif, kami
menyarankan QR-Code atau NFC.

### Menerima permintaan kontak

Jika seseorang mengirimimu permintaan kontak, permintaan itu akan muncul di
Inbox-mu (tab terakhir di bilah bawah). Di sana kamu bisa:

- **Terima** -- orang tersebut ditambahkan ke daftar kontakmu.
- **Tolak** -- permintaan tersebut dibuang.
- **Blokir** -- orang tersebut tidak bisa mengirimimu permintaan lagi.

### Tingkat Verifikasi

Cleona menunjukkan seberapa yakin identitas sebuah kontak telah dikonfirmasi:

| Tingkat | Arti |
|-------|-----------|
| Tidak Diketahui | Kamu hanya menerima Node-ID atau sebuah tautan. |
| Terlihat | Pertukaran kunci berhasil, kalian bisa berkomunikasi terenkripsi. |
| Terverifikasi | Kalian telah bertemu langsung dan melakukan verifikasi lewat QR-Code atau NFC. |
| Dipercaya | Kamu telah secara eksplisit menandai kontak ini sebagai dapat dipercaya. |

Semakin tinggi tingkatnya, semakin yakin kamu bahwa kamu benar-benar
berbicara dengan orang yang tepat.

---

## 4. Pesan

### Mengirim dan menerima teks

Cukup ketikkan pesanmu di kolom input di bagian bawah lalu tekan Enter atau
tombol Kirim. Pesanmu otomatis dienkripsi sebelum meninggalkan perangkatmu.

Pesan masuk akan muncul di riwayat obrolan. Sebuah tanda centang menunjukkan
apakah pesanmu sudah terkirim.

### Mengirim gambar, video, dan file

Kamu punya beberapa cara:

- **Ikon klip kertas** di kolom input: ketuk untuk memilih file, gambar, atau
  video dari galeri atau sistem file-mu.
- **Seret dan lepas** (Desktop): cukup seret file ke dalam jendela obrolan.
- **Tempel dari clipboard** (Desktop): salin gambar dan tempelkan di obrolan.

File kecil (di bawah 256 KB) langsung dikirim bersama pesan. File yang lebih
besar dikirim dengan cara dua tahap: file diumumkan terlebih dahulu, lalu
dikirim dalam bagian-bagian.

### Pesan suara

1. Tahan tombol mikrofon di kolom input.
2. Ucapkan pesanmu.
3. Lepaskan tombol untuk mengirim pesan.

Jika transkripsi suara diaktifkan di perangkatmu (lihat Pengaturan), pesan
suaramu akan otomatis ditranskripsikan menjadi teks. Lawan bicaramu akan
melihat baik rekaman suara maupun teks hasil transkripsi.

### Membalas pesan (kutipan)

Untuk membalas pesan tertentu:

1. Buka menu titik tiga di sebelah pesan.
2. Pilih "Balas".
3. Sebuah banner berisi kutipan pesan akan muncul di atas kolom input.
4. Tulis balasanmu dan kirim.

Pesan yang dikutip akan ditampilkan di dalam balasanmu, sehingga jelas pesan
mana yang dimaksud.

### Mengedit dan menghapus pesan

- **Mengedit:** Menu titik tiga pada pesan, lalu "Edit". Ubah teksnya dan
  kirim ulang. Lawan bicaramu akan melihat bahwa pesan telah diedit.
  Mengedit dimungkinkan dalam 15 menit setelah pesan dikirim.
- **Menghapus:** Menu titik tiga pada pesan, lalu "Hapus". Pesan akan
  dihapus baik di sisimu maupun di sisi lawan bicaramu. Kamu bisa menghapus
  pesanmu sendiri kapan saja -- tidak ada batas waktu untuk penghapusan.

### Reaksi emoji

Alih-alih menulis balasan, kamu bisa bereaksi terhadap sebuah pesan dengan
emoji:

1. Buka menu titik tiga atau tekan lama pesan tersebut.
2. Pilih emoji dari pilihan cepat, atau buka emoji-picker untuk pilihan
   lengkap.
3. Reaksimu akan muncul di bawah pesan.

### Menyalin teks

Lewat menu titik tiga pada sebuah pesan, kamu bisa menyalin teks pesan ke
clipboard.

### Mencari pesan

Di bagian atas jendela obrolan, kamu akan menemukan fitur pencarian.
Masukkan kata kunci, dan Cleona akan menampilkan semua hasil yang cocok di
obrolan saat ini. Gunakan tombol panah untuk berpindah antar hasil.

Di halaman utama, ada juga filter pencarian lintas tab yang memungkinkanmu
mencari kata kunci di semua percakapan sekaligus.

### Pratinjau tautan

Saat kamu mengirim tautan, Cleona otomatis membuat pratinjau (judul,
deskripsi, gambar pratinjau). Pratinjau ini dibuat oleh perangkatmu sendiri
dan dikirim bersama pesan -- lawan bicaramu tidak perlu membuat koneksi ke
situs web yang ditautkan.

Jika kamu mengetuk tautan yang diterima, kamu akan ditanya apakah ingin
membukanya di browser biasa, mode penyamaran (incognito), atau tidak sama
sekali.

---

## 5. Grup

### Membuat grup

1. Beralih ke tab "Grup".
2. Ketuk tombol plus.
3. Beri nama grup tersebut.
4. Pilih kontak yang ingin kamu undang.
5. Ketuk "Buat".

Kontak yang diundang akan menerima notifikasi dan bisa bergabung ke grup
tersebut.

### Mengundang anggota

Kamu juga bisa mengundang kontak lain setelah grup dibuat:

1. Buka informasi grup (menu titik tiga di ringkasan grup atau bilah atas di
   obrolan grup).
2. Ketuk "Undang".
3. Pilih kontak yang ingin kamu tambahkan.

### Peran

Setiap grup memiliki tiga peran:

- **Pemilik (Owner):** Memiliki kendali penuh. Bisa menambah dan menghapus
  anggota, menunjuk Admin, dan mengelola grup. Pemilik juga bisa
  mengalihkan statusnya ke anggota lain.
- **Admin:** Bisa menghapus anggota dan membantu pengelolaan.
- **Anggota:** Bisa membaca dan menulis pesan.

### Meninggalkan grup

1. Buka menu titik tiga di ringkasan grup.
2. Pilih "Keluar".
3. Konfirmasi keputusanmu.

Jika kamu meninggalkan grup, pesan-pesanmu yang sebelumnya tetap terlihat
oleh anggota lain.

---

## 6. Kanal Publik

### Apa itu kanal?

Kanal adalah forum diskusi publik di dalam jaringan Cleona. Berbeda dengan
grup, di sini siapa pun bisa ikut membaca tanpa perlu diundang. Hanya
pemilik dan Admin yang bisa memposting -- para pelanggan (subscriber) hanya
membaca.

### Menemukan dan bergabung ke kanal

1. Beralih ke tab "Kanal".
2. Buka tab "Cari".
3. Telusuri kanal yang tersedia berdasarkan nama atau topik.
4. Ketuk sebuah kanal lalu ketuk "Langganan".

Kanal bisa difilter berdasarkan bahasa. Beberapa kanal ditandai "Dewasa" --
kanal-kanal ini hanya terlihat jika kamu telah mengonfirmasi di profilmu
bahwa kamu berusia di atas 18 tahun.

### Membuat kanal sendiri

1. Beralih ke tab "Kanal".
2. Ketuk tombol plus.
3. Masukkan nama kanal (harus unik di seluruh jaringan).
4. Pilih bahasa dan apakah kanal ini bersifat publik atau privat.
5. Opsional: tambahkan deskripsi dan gambar.
6. Ketuk "Buat".

Untuk kanal publik, kamu bisa menentukan apakah kontennya diklasifikasikan
sebagai "Dewasa".

### Melaporkan konten

Jika kamu menemukan konten yang tidak pantas di sebuah kanal publik, kamu
bisa melaporkannya. Cleona menggunakan sistem moderasi yang terdesentralisasi:
laporan akan dinilai oleh anggota jaringan yang dipilih secara acak (semacam
"dewan juri"). Jika pelanggaran terbukti, kanal tersebut akan menerima
peringatan. Jika pelanggaran berulang, kanal akan diturunkan peringkatnya di
indeks pencarian atau diblokir.

### Kanal sistem

Cleona memiliki dua kanal sistem bawaan:

- **Bug Log:** Jika Cleona mendeteksi sebuah error, aplikasi akan
  menanyakan apakah kamu ingin mengirim laporan bug yang telah dianonimkan.
  Laporan ini masuk ke kanal Bug Log, di mana komunitas bisa melihatnya.
  Tidak ada data pribadi yang dikirim -- hanya deskripsi teknis error. Kamu
  juga bisa mengirim laporan log secara manual (dengan dialog pratinjau dan
  persetujuan eksplisit).
- **Feature Requests:** Di sini pengguna bisa mengajukan permintaan fitur
  dan memberikan suara untuk usulan yang sudah ada. Usulan-usulan tersebut
  diurutkan berdasarkan jumlah suara.

Kedua kanal sistem ini memiliki batas ukuran 25 MB dan diawasi oleh sistem
moderasi juri.

---

## 7. Panggilan

### Memulai panggilan suara

1. Buka obrolan dengan kontak yang ingin kamu hubungi.
2. Ketuk ikon telepon di bilah atas.
3. Tunggu hingga lawan bicaramu menerima panggilan.

Selama percakapan, kamu akan melihat garis waktu, durasi panggilan, dan
memiliki akses untuk membisukan mikrofon serta pengeras suara.

Untuk mengakhiri, ketuk tombol merah Akhiri Panggilan.

### Memulai panggilan video

1. Buka obrolan dengan kontak tersebut.
2. Ketuk ikon kamera di bilah atas.
3. Gambar videomu akan muncul di jendela kecil, sementara gambar lawan
   bicaramu tampil di area besar.

Kamu bisa berpindah antara kamera depan dan belakang selama panggilan
berlangsung.

### Panggilan masuk

Jika seseorang meneleponmu, akan muncul jendela notifikasi dengan nama
penelepon. Kamu bisa:

- **Terima** -- percakapan dimulai.
- **Tolak** -- penelepon akan diberi tahu.

Jika kamu sedang dalam panggilan lain, panggilan baru akan otomatis ditolak.

### Panggilan grup

Kamu juga bisa melakukan panggilan grup dengan beberapa orang sekaligus.
Panggilan diatur melalui pohon penerusan cerdas (routing tree), sehingga
tidak setiap peserta perlu terhubung langsung dengan peserta lain. Semua
percakapan terenkripsi secara menyeluruh (end-to-end).

### Enkripsi pada panggilan

Semua panggilan dienkripsi dengan kunci sekali pakai yang hanya berlaku
selama durasi percakapan. Setelah panggilan berakhir, kunci-kunci ini
langsung dihapus. Tidak ada yang bisa mendekripsi percakapan yang sudah
lewat.

---

## 8. Kalender

Cleona memiliki kalender bawaan yang terenkripsi dan bekerja sepenuhnya
terdesentralisasi -- tanpa layanan cloud.

### Tampilan

Kalender menawarkan lima tampilan: Hari, Minggu, Bulan, Tahun, dan tampilan
Tugas. Beralihlah di antara tampilan-tampilan ini lewat tab di bagian atas
layar kalender.

### Membuat acara

Ketuk sebuah slot waktu atau gunakan tombol Tambah untuk membuat acara baru.
Kamu bisa memasukkan judul, tanggal, waktu, lokasi, dan catatan. Acara
disimpan terenkripsi di perangkatmu.

### Acara berulang

Acara bisa diatur untuk berulang harian, mingguan, bulanan, atau tahunan.
Kamu bisa menyesuaikan polanya (misalnya setiap Selasa kedua, setiap tanggal
1 bulan) dan menetapkan tanggal berakhir atau jumlah pengulangan.

### Mengundang kontak

Saat membuat atau mengedit sebuah acara, kamu bisa mengundang kontak
Cleona-mu. Mereka akan menerima undangan kalender yang terenkripsi dan bisa
membalas dengan Menerima, Menolak, atau Mungkin. Perubahan pada acara
otomatis dikirim ke semua yang diundang.

### Tampilan Bebas/Sibuk

Kamu bisa berbagi ketersediaan waktumu dengan kontak tanpa membocorkan
detail acara. Ada tiga tingkat privasi: detail lengkap, hanya blok waktu,
atau tersembunyi. Kamu bisa menetapkan pengaturan default dan
mengesampingkannya untuk kontak tertentu.

### Pengingat

Acara bisa memiliki pengingat yang memicu notifikasi sistem sebelum acara
dimulai. Kamu bisa menunda (snooze) pengingat sesuai kebutuhan.

### Sinkronisasi kalender eksternal

Cleona bisa disinkronkan dengan layanan kalender eksternal:

- **CalDAV** -- Hubungkan dengan server yang kompatibel dengan CalDAV
  (Nextcloud, Radicale, dll).
- **Google Calendar** -- Sinkronisasi lewat Google Calendar API dengan
  autentikasi OAuth2 yang aman.
- **Server CalDAV lokal** -- Cleona bisa menjalankan server CalDAV lokal di
  perangkatmu, sehingga aplikasi kalender desktop (Thunderbird, Outlook,
  Apple Calendar, Evolution) bisa disinkronkan dengan kalender Cleona-mu.
- **Kalender sistem Android** -- Acara dari Cleona bisa dipindahkan ke
  aplikasi kalender bawaan perangkat Android-mu.
- **File ICS** -- Impor dan ekspor acara dalam format standar iCalendar.

### Ekspor PDF

Kamu bisa mencetak atau mengekspor setiap tampilan kalender (Hari, Minggu,
Bulan, Tahun) sebagai dokumen PDF.

---

## 9. Polling

Kamu bisa membuat polling di obrolan atau grup mana pun untuk mengumpulkan
pendapat atau merencanakan jadwal.

### Jenis polling

Cleona mendukung lima jenis polling:

- **Pilihan Tunggal** -- Peserta memilih satu opsi.
- **Pilihan Ganda** -- Peserta bisa memilih beberapa opsi.
- **Polling Jadwal** -- Menemukan waktu yang cocok untuk semua orang. Setiap
  peserta menandai waktu sebagai tersedia, mungkin, atau tidak tersedia.
- **Skala** -- Menilai sesuatu pada skala angka (misalnya 1 sampai 5).
- **Teks Bebas** -- Peserta menuliskan jawaban mereka sendiri.

### Membuat polling

Buka sebuah obrolan dan ketuk ikon polling (atau gunakan menu lampiran).
Pilih jenis polling, rumuskan pertanyaan dan opsi-opsinya, lalu kirim
polling tersebut. Polling akan muncul sebagai pesan di obrolan.

### Memberikan suara

Ketuk sebuah polling untuk memberikan suaramu. Kamu bisa mengubah atau
menarik kembali suaramu kapan saja.

### Voting anonim

Polling bisa dikonfigurasi untuk voting anonim. Jika diaktifkan, suara akan
anonim secara kriptografis -- tidak ada yang bisa melihat siapa memilih apa,
bahkan pembuat polling sekalipun. Jumlah suara tetap terlihat.

### Polling jadwal menjadi acara kalender

Setelah sebuah polling jadwal selesai, waktu pemenang bisa langsung diubah
menjadi entri kalender hanya dengan satu ketukan.

---

## 10. Beberapa Identitas

### Mengapa perlu beberapa identitas?

Bayangkan kamu ingin memisahkan kehidupan profesional dan pribadimu --
mirip seperti punya dua nomor telepon berbeda, tapi tanpa harus punya dua
ponsel. Di Cleona, kamu bisa menggunakan beberapa identitas di satu
perangkat. Setiap identitas memiliki nama sendiri, foto profil sendiri,
kontak sendiri, dan percakapan sendiri.

### Membuat identitas baru

1. Di bilah atas, kamu akan melihat identitasmu saat ini sebagai sebuah tab.
2. Ketuk tanda plus (+) di sebelah kanan tab-tab identitasmu.
3. Masukkan nama untuk identitas baru tersebut.
4. Selesai -- identitas baru langsung aktif.

### Berpindah antar identitas

Cukup ketuk tab identitas di bilah atas. Perpindahan terjadi seketika --
tanpa waktu tunggu, tanpa perlu memuat ulang.

### Semuanya berjalan bersamaan

Poin penting: semua identitasmu aktif secara bersamaan. Meskipun kamu
sedang menampilkan identitas "Kerja", identitas "Pribadi"-mu tetap menerima
pesan. Kamu tidak akan melewatkan apa pun, apa pun identitas yang sedang
kamu pilih.

### Halaman detail identitas

Jika kamu mengetuk tab identitas yang sedang aktif, halaman detail akan
terbuka. Di sini kamu bisa:

- Menampilkan QR-Code-mu untuk kontak.
- Mengubah atau menghapus foto profilmu.
- Menambahkan deskripsi profil.
- Mengubah nama tampilanmu.
- Memilih desain (skin) untuk identitas ini.
- Menghapus identitas jika kamu tidak lagi membutuhkannya.

### Menghapus identitas

Jika kamu menghapus sebuah identitas, kontak-kontakmu akan diberi tahu.
Identitas beserta semua data terkait akan dihapus dari perangkatmu. Proses
ini tidak bisa dibatalkan.

---

## 11. Multi-Device

### Menggunakan Cleona di beberapa perangkat

Kamu bisa menggunakan identitas yang sama di hingga 5 perangkat sekaligus.
Satu perangkat menjadi perangkat utama (menyimpan Seed-Phrase), dan
perangkat lain akan dihubungkan dengannya.

### Menghubungkan perangkat baru

1. Buka Pengaturan di perangkat utamamu.
2. Masuk ke "Perangkat Terhubung".
3. Pilih "Hubungkan Perangkat Baru".
4. Instal Cleona di perangkat baru dan pilih "Hubungkan dengan Perangkat
   yang Sudah Ada" saat memulai.
5. Pindai QR-Code pairing yang ditampilkan di perangkat utamamu, atau
   gunakan tautan pairing.

Perangkat yang terhubung akan menerima sertifikat delegasi dari perangkat
utama. Pesan yang dikirim dari perangkat terhubung ditandatangani secara
kriptografis dengan kunci delegasi, sehingga kontak bisa memverifikasi bahwa
pesan tersebut benar-benar berasal dari identitasmu.

### Cara kerjanya

- Perangkat utama menyimpan Seed-Phrase-mu dan kunci master.
- Perangkat terhubung menerima kunci tanda tangan turunan dan sertifikat
  delegasi -- mereka tidak pernah menerima Seed-Phrase itu sendiri.
- Semua perangkat berbagi identitas dan kontak yang sama. Pesan akan sampai
  di semua perangkat.
- Sertifikat delegasi diperbarui otomatis sebelum masa berlakunya habis.

### Pengelolaan perangkat

Buka Pengaturan lalu masuk ke "Perangkat Terhubung" untuk melihat semua
perangkat yang terhubung, statusnya, dan aktivitas terakhirnya. Kamu bisa
mencabut akses perangkat terhubung kapan saja, jika perangkat itu hilang
atau dicuri.

### Rotasi kunci darurat

Jika kamu menduga sebuah perangkat telah disusupi, kamu bisa memicu rotasi
kunci darurat. Kunci-kunci baru akan dibuat, dan rotasi tersebut harus
dikonfirmasi oleh mayoritas perangkatmu yang lain. Hal ini mencegah satu
perangkat yang dicuri melakukan rotasi kunci secara sepihak.

---

## 12. Pemulihan

### Menggunakan Seed-Phrase

Jika kamu kehilangan perangkatmu atau menyiapkan perangkat baru:

1. Instal Cleona di perangkat baru.
2. Pilih "Pulihkan" saat memulai.
3. Masukkan 24 kata milikmu.
4. Cleona akan memulihkan identitasmu dan secara otomatis menghubungi
   kontak-kontakmu sebelumnya.
5. Kontak-kontakmu akan membalas dengan data kontak, keanggotaan grup, dan
   riwayat pesan.

Pemulihan berlangsung dalam tiga tahap:
- Pertama, kontak dan grup-mu kembali.
- Kemudian, 50 pesan terakhir dari setiap percakapan.
- Terakhir, seluruh riwayat pesan secara lengkap.

Cukup satu kontakmu saja yang online agar proses pemulihan bisa berjalan.

### Guardian Recovery (Orang Tepercaya)

Kamu bisa menunjuk hingga lima orang tepercaya sebagai "Guardian". Dengan
cara ini, kunci pemulihanmu dibagi menjadi lima bagian, dan setiap Guardian
menerima satu bagian. Untuk memulihkan identitasmu, cukup tiga dari lima
bagian tersebut yang dibutuhkan.

Artinya: bahkan jika kamu kehilangan Seed-Phrase-mu, tiga Guardian-mu bisa
bersama-sama memulihkan akunmu. Tidak ada satu Guardian pun yang bisa sendiri
mengakses datamu -- selalu dibutuhkan minimal tiga orang.

Begini cara menyiapkan Guardian:
1. Buka Pengaturan.
2. Masuk ke "Keamanan".
3. Pilih "Guardian Recovery".
4. Pilih lima kontak yang kamu percaya.

### Mengapa kontak adalah backup-mu

Pada messenger konvensional, datamu tersimpan di server penyedia layanan.
Di Cleona tidak ada server -- tetapi kontak-kontakmu mengambil alih peran
ini. Saat kamu mengirim pesan, kontak-kontak bersama akan menyimpan salinan
terenkripsi untuk jaga-jaga jika penerima sedang offline. Saat pemulihan,
kontak-kontakmu akan mengembalikan datamu.

Artinya: semakin banyak kontak aktif yang kamu miliki, semakin andal
backup-mu. Satu kontak saja yang rutin online sudah cukup untuk pemulihan
yang berhasil.

---

## 13. Pengaturan

Kamu bisa mengakses Pengaturan lewat ikon roda gigi di pojok kanan atas.

### Notifikasi dan nada dering

- Pilih dari enam nada dering berbeda untuk panggilan masuk.
- Atur nada pesan.
- Di perangkat Android, kamu juga bisa mengaktifkan atau menonaktifkan
  getaran.

### Desain (Skin)

Cleona menawarkan sepuluh desain berbeda: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold, dan Contrast. Desain Contrast memenuhi
tingkat aksesibilitas tertinggi (WCAG AAA) dan sangat mudah dibaca bagi
mereka yang memiliki keterbatasan penglihatan.

Setiap identitas bisa memiliki desainnya sendiri. Kamu mengubah desain di
halaman detail identitas (ketuk tab identitas yang sedang aktif).

Selain itu, di Pengaturan bagian "Tampilan", kamu bisa beralih antara tema
terang, gelap, dan tema sistem.

### Mengubah bahasa

Cleona tersedia dalam 33 bahasa, termasuk bahasa dengan penulisan
kanan-ke-kiri (misalnya Arab, Ibrani). Ubah bahasa di Pengaturan bagian
"Bahasa".

### Batas penyimpanan

Kamu bisa menentukan berapa banyak ruang penyimpanan yang boleh digunakan
Cleona di perangkatmu (antara 100 MB dan 2 GB). Jika batas ini tercapai,
media lama akan otomatis dipindahkan ke arsip atau dihapus -- pesan teks
selalu tetap tersimpan.

### Pengarsipan media

Jika kamu memiliki penyimpanan jaringan (NAS) atau folder bersama di rumah,
Cleona bisa memindahkan media milikmu ke sana secara otomatis. Yang
didukung: SMB, SFTP, FTPS, dan WebDAV.

Begini cara kerja penyimpanan bertingkat:
- 30 hari pertama: semuanya tetap tersimpan di perangkatmu.
- Setelah 30 hari: sebuah gambar pratinjau tetap ada di perangkat, sementara
  aslinya diarsipkan.
- Setelah 90 hari: hanya gambar pratinjau kecil yang tersisa di perangkat.
- Setelah satu tahun: hanya placeholder yang tersisa, sementara aslinya
  tersimpan aman di arsip.

Kamu bisa mengetuk media yang diarsipkan kapan saja untuk mengambilnya
kembali -- asalkan kamu terhubung dengan jaringan rumahmu. Media yang
sangat penting bisa disematkan (pin) agar tidak pernah dipindahkan ke
arsip.

### Transkripsi untuk pesan suara

Jika diaktifkan, pesan suaramu akan diubah menjadi teks secara lokal di
perangkatmu (menggunakan model open-source Whisper). Teks hasil transkripsi
dikirim bersama rekamannya kepada lawan bicaramu. Transkripsi berlangsung
sepenuhnya di perangkatmu -- tidak ada data yang dikirim ke layanan
eksternal.

### Unduh otomatis

Kamu bisa mengatur mulai dari ukuran berapa media akan diunduh secara
otomatis. Misalnya, kamu bisa membiarkan gambar terunduh otomatis, tapi
memutuskan sendiri untuk video berukuran besar.

### Perangkat terhubung

Kelola perangkat-perangkat terhubungmu di bagian ini pada Pengaturan. Lihat
bab Multi-Device untuk detailnya.

---

## 14. Keamanan

### Apa arti enkripsi Post-Quantum?

Enkripsi saat ini didasarkan pada masalah matematika yang sangat sulit
dipecahkan oleh komputer biasa. Komputer kuantum di masa depan bisa jadi
mampu memecahkan sebagian masalah ini dengan cepat. Enkripsi Post-Quantum
menggunakan metode tambahan yang juga tahan terhadap komputer kuantum.

Cleona menggabungkan kedua pendekatan tersebut: enkripsi klasik untuk
keandalan dan metode Post-Quantum untuk ketahanan masa depan. Dengan begitu,
kamu terlindungi dari ancaman masa kini maupun masa depan sekaligus.

Setiap pesan memiliki kuncinya sendiri yang unik. Bahkan jika seorang
penyerang berhasil membobol kunci satu pesan, ia tetap tidak bisa membaca
pesan lainnya.

### Mengapa tanpa server lebih aman

Pada messenger konvensional, pesanmu melewati server milik penyedia
layanan. Meskipun mungkin dienkripsi di sana, penyedia layanan tetap
memiliki akses ke metadata (siapa berkomunikasi dengan siapa, kapan,
seberapa sering, dari mana), dan dalam kondisi tertentu harus
menyerahkannya atas perintah pengadilan.

Di Cleona tidak ada titik pusat semacam itu. Pesanmu berjalan langsung dari
perangkat ke perangkat. Tidak ada tempat di mana semua metadata berkumpul.
Tidak ada yang bisa merekonstruksi pola komunikasimu hanya dari satu titik
data.

### Apa yang terjadi jika kamu offline?

Jika kamu mengirim pesan dan penerima sedang offline:

1. Cleona pertama-tama mencoba mengirim pesan secara langsung.
2. Jika tidak berhasil, pesan diteruskan lewat kontak-kontak bersama.
3. Secara bersamaan, pesan tersebut dipecah menjadi potongan-potongan
   terenkripsi dan disebar ke beberapa node di jaringan (mirip seperti
   puzzle yang terdiri dari 10 bagian, di mana 7 bagian sudah cukup untuk
   menyusun kembali gambarnya).
4. Pesan disimpan hingga 7 hari.

Begitu penerima kembali online, pesan-pesan tersebut akan diantarkan. Kamu
akan mendapat konfirmasi saat pesanmu telah sampai.

### Anti-Sensor

Jika jaringanmu memblokir metode koneksi standar (UDP), Cleona otomatis
beralih ke transmisi alternatif (TLS) yang lebih sulit dideteksi dan
diblokir. Hal ini berlangsung secara transparan -- kamu tidak perlu
mengonfigurasi apa pun.

### Penyimpanan kunci yang aman

Pada platform yang mendukung, Cleona menyimpan kunci enkripsimu di
keychain aman milik sistem operasi (Android Keystore, iOS Keychain, macOS
Keychain). Jika tersedia, hal ini memberikan perlindungan berbasis hardware
untuk kunci-kuncimu.

### Enkripsi database

Semua pesan, kontak, dan pengaturanmu tersimpan terenkripsi di perangkatmu.
Bahkan jika seseorang mendapatkan akses ke sistem file-mu, ia tidak akan
bisa membaca apa pun tanpa kunci kriptografismu. Kunci ini diturunkan dari
identitasmu dan hanya ada di perangkatmu.

### Jaringan tertutup

Cleona beroperasi sebagai jaringan tertutup. Setiap paket jaringan
diautentikasi, sehingga hanya perangkat Cleona yang sah yang bisa ikut
serta. Hal ini mencegah pihak luar menyusupkan pesan palsu atau menyadap
lalu lintas jaringan.

---

## 15. Pembaruan Software

### Bagaimana cara mendapatkan pembaruan?

Cleona bisa diperbarui lewat berbagai cara. Tujuannya adalah agar kamu tetap
bisa mendapatkan pembaruan bahkan jika salah satu jalur distribusi
mengalami gangguan atau diblokir:

1. **App Store / Play Store:** Jika kamu menginstal Cleona lewat sebuah App
   Store, kamu akan mendapatkan pembaruan seperti biasa lewat Store
   tersebut.
2. **GitHub Releases:** Di halaman GitHub proyek ini, kamu akan menemukan
   paket instalasi bertanda tangan (signed) untuk semua platform.
3. **Pembaruan dalam jaringan (In-Network-Updates):** Jika pengguna Cleona
   lain di jaringanmu sudah memiliki versi terbaru, Cleona bisa mengambil
   pembaruan langsung lewat jaringan P2P -- tanpa server eksternal. Dalam
   proses ini, versi baru dipecah menjadi fragmen dengan koreksi kesalahan
   dan disebar melalui beberapa node. Perangkatmu mengumpulkan fragmen yang
   cukup dan menyusun kembali pembaruan tersebut. Keasliannya diverifikasi
   melalui tanda tangan Ed25519 dari pengembang.
4. **Tautan undangan:** Kamu bisa membuat tautan undangan yang berisi semua
   yang dibutuhkan pengguna baru untuk menginstal Cleona dan terhubung ke
   jaringan.
5. **Transfer fisik:** Di lingkungan tanpa internet, kamu bisa membagikan
   Cleona lewat flashdisk USB atau lewat jaringan lokal ke orang lain.

### Notifikasi pembaruan

Jika ada pembaruan baru yang tersedia, Cleona akan menampilkan notifikasi
di layar utama. Jika pembaruan juga tersedia lewat jaringan
(In-Network-Update), kamu punya pilihan untuk mengunduhnya langsung dari
jaringan.

### Distribusi biner

Secara default, perangkatmu ikut membantu meneruskan pembaruan ke pengguna
lain di jaringan. Jika kamu tidak menginginkan hal ini, kamu bisa
menonaktifkan fitur ini di Pengaturan bagian "Jaringan". Penggunaan
penyimpanan untuk fragmen pembaruan dibatasi (5 MB pada perangkat mobile,
20 MB pada perangkat desktop) dan dibersihkan secara berkala.

### Verifikasi tanda tangan

Setiap pembaruan ditandatangani secara kriptografis. Cleona otomatis
memverifikasi tanda tangan tersebut sebelum pembaruan diinstal. Dengan
begitu, dipastikan hanya pembaruan dari pengembang resmi yang diterima --
bahkan jika pembaruan tersebut diperoleh lewat jaringan P2P.

---

## 16. Pertanyaan yang Sering Diajukan

### "Bisakah saya menggunakan Cleona tanpa internet?"

Tidak, Cleona memerlukan koneksi jaringan untuk mengirim dan menerima
pesan. Namun, kamu tidak perlu online bersamaan dengan lawan bicaramu:
pesan yang dikirim saat penerima sedang offline akan disimpan sementara
dan otomatis diantarkan begitu kedua belah pihak terhubung kembali. Di
jaringan lokal (misalnya di WLAN yang sama), kalian bahkan bisa
berkomunikasi tanpa akses internet sama sekali.

### "Bagaimana jika saya kehilangan Seed-Phrase saya?"

Jika kamu telah menyiapkan Guardian, tiga dari lima orang tepercayamu bisa
bersama-sama memulihkan aksesmu. Tanpa Guardian dan tanpa Seed-Phrase,
sayangnya tidak ada cara untuk mendapatkan kembali identitasmu. Karena itu,
sangat penting untuk menyimpan 24 kata tersebut dengan aman.

### "Bisakah seseorang membaca pesan saya?"

Tidak. Setiap pesan dienkripsi dengan kunci sekali pakai yang hanya berlaku
untuk pesan itu saja. Hanya kamu dan lawan bicaramu yang bisa mendekripsi
pesan tersebut. Tidak ada server pusat, tidak ada kunci utama (master key),
dan tidak ada akses untuk pengembang. Bahkan jika sebuah perangkat
meneruskan pesan di sepanjang jalur transmisi, yang terlihat hanyalah data
acak yang terenkripsi.

### "Mengapa saya tidak memerlukan nomor telepon?"

Karena identitasmu murni bersifat kriptografis. Alih-alih nomor telepon
atau alamat email yang terhubung dengan nama aslimu, kamu diidentifikasi
oleh sepasang kunci yang dibuat di perangkatmu. Kamu menambahkan kontak
lewat QR-Code, NFC, atau tautan -- bukan lewat buku telepon. Artinya lebih
banyak privasi, karena akun messenger-mu tidak terikat dengan identitas
nyatamu.

### "Bagaimana cara saya menemukan orang di Cleona?"

Cleona sengaja tidak memiliki fitur pencarian kontak berdasarkan nomor
telepon atau nama -- itu akan menjadi masalah privasi. Sebagai gantinya,
kamu bertukar data kontak secara langsung: lewat QR-Code, NFC, tautan
cleona://, atau di kanal publik. Ini seperti bertukar kartu nama, bukan
mencari di buku telepon.

### "Apakah Cleona berfungsi di luar negeri?"

Ya. Selama kamu memiliki koneksi internet, Cleona berfungsi di mana pun di
dunia. Karena tidak ada server pusat, layanan ini juga tidak bisa diblokir
untuk negara tertentu. Cleona juga memiliki fallback anti-sensor: jika
koneksi normal (UDP) diblokir, Cleona otomatis beralih ke transmisi
alternatif (TLS) yang lebih sulit dideteksi dan diblokir.

### "Apakah Cleona gratis?"

Ya. Cleona bisa digunakan secara gratis dan tanpa iklan. Karena tidak ada
server pusat, tidak ada biaya server untuk operasionalnya. Di dalam
aplikasi, kamu bisa menemukan opsi "Donasi" untuk mendukung pengembangan
secara sukarela.

### "Pesan saya memiliki ikon jam -- apa artinya?"

Itu berarti pesan tersebut belum terkirim. Lawan bicaramu kemungkinan
sedang offline. Begitu pesan berhasil dikirim, ikonnya akan berubah. Pesan
disimpan hingga 7 hari untuk keperluan pengiriman.

### "Bisakah saya beralih dari WhatsApp ke Cleona?"

Bisa, tapi kamu tidak bisa memindahkan obrolan WhatsApp-mu. Cleona dan
WhatsApp adalah sistem yang sangat berbeda. Kamu harus menambahkan
kontak-kontakmu satu per satu di Cleona. Cara paling mudah adalah dengan
memposting tautan cleona:// milikmu di grup WhatsApp dan meminta orang lain
untuk menambahkanmu di sana.

### "Bisakah saya menggunakan Cleona di beberapa perangkat sekaligus?"

Ya. Kamu bisa menghubungkan hingga 5 perangkat dengan identitas yang sama.
Satu perangkat menjadi perangkat utama (menyimpan Seed-Phrase), dan
perangkat lain dihubungkan lewat proses pairing yang aman. Semua perangkat
berbagi identitas, kontak, dan percakapan yang sama. Lihat bab Multi-Device
untuk detailnya.

### "Bagaimana cara mendapatkan pembaruan jika App Store diblokir?"

Cleona bisa mendapatkan pembaruan langsung lewat jaringan P2P, tanpa
bergantung pada App Store, situs web, atau server unduhan. Jika pengguna
lain di jaringan sudah memiliki versi terbaru, perangkatmu bisa mengunduh
pembaruan dari sana. Keasliannya diverifikasi lewat tanda tangan digital
dari pengembang. Alternatifnya, seorang kontak bisa membagikan aplikasi
ini kepadamu lewat tautan undangan atau flashdisk USB. Info lebih lanjut
ada di bab "Pembaruan Software".

---

## Bantuan dan Kontak

Jika kamu memiliki pertanyaan atau mengalami masalah, kamu bisa menemukan
informasi terbaru di situs web Cleona dan di GitHub. Karena Cleona adalah
proyek yang terdesentralisasi, tidak ada dukungan pelanggan konvensional --
tetapi ada komunitas aktif yang senang membantu.

---

*Panduan ini menjelaskan Cleona Chat Version 3.1.125. Fitur-fitur tertentu
dapat berubah atau bertambah pada versi yang lebih baru.*
