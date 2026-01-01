# Cleona Chat -- Manual Pengguna

Versi 4.2 | Per November 2026

---

## Daftar isi

1. [Apa itu Cleona Chat?](#1-apa-itu-cleona-chat)
2. [Mulai menggunakan](#2-mulai-menggunakan)
3. [Kontak](#3-kontak)
4. [Pesan](#4-pesan)
5. [Grup](#5-grup)
6. [Saluran publik](#6-saluran-publik)
7. [Panggilan](#7-panggilan)
8. [Kalender](#8-kalender)
9. [Jajak pendapat](#9-jajak-pendapat)
10. [Beberapa identitas](#10-beberapa-identitas)
11. [Beberapa perangkat](#11-beberapa-perangkat)
12. [Pemulihan](#12-pemulihan)
13. [Pengaturan](#13-pengaturan)
14. [Keamanan](#14-keamanan)
15. [Pembaruan perangkat lunak](#15-pembaruan-perangkat-lunak)
16. [Pertanyaan yang sering diajukan](#16-pertanyaan-yang-sering-diajukan)

---

## 1. Apa itu Cleona Chat?

### Messenger-mu, data-mu

Cleona Chat adalah messenger yang bekerja sepenuhnya tanpa server pusat.
Pesan-pesanmu bepergian dari perangkatmu ke perangkat lawan bicaramu --
tanpa melewati kantor pusat perusahaan, tanpa cloud, tanpa pusat data. Jika
di tengah jalan perangkat lain membantu, ia hanya meneruskan paket-paket
yang terenkripsi. Tidak ada perusahaan yang dapat membaca, menyimpan, atau
menyebarkan pesanmu, karena sederhana tidak ada perusahaan yang berada di
antaranya.

### Tanpa akun, tanpa nomor telepon

Pada Cleona kamu tidak memerlukan nomor telepon maupun alamat email untuk
masuk. Identitasmu terdiri dari sepasang kunci kriptografis yang dibuat
secara otomatis di perangkatmu saat pertama kali dinyalakan. Artinya:
Tidak ada yang dapat melacakmu melalui nomor telepon atau alamat email,
kecuali kamu sendiri memberikan data kontakmu.

### Enkripsi yang tahan masa depan

Cleona menggunakan apa yang disebut enkripsi pasca-kuantum. Artinya: Bahkan
komputer kuantum di masa depan pun tidak akan dapat membobol pesanmu. Kamu
tidak perlu memahami detailnya -- yang penting hanyalah bahwa komunikasimu
dilindungi sebaik mungkin sesuai dengan teknologi saat ini.

### Bagaimana cara kerjanya tanpa server?

Jaringan Cleona hanya terdiri dari perangkat-perangkat penggunanya. Setiap
perangkat adalah sebuah simpul, tidak ada simpul yang lebih penting daripada
yang lain, dan setiap simpul hanya mengenal tetangganya sendiri. Empat hal
menjadikan jaringan ini istimewa:

- **Tanpa titik tetap.** Di dalam aplikasi tidak ada alamat server, dan
  jaringan tidak bergantung pada satu simpul pun. Tidak ada satu pun yang
  bisa dimatikan untuk menghentikan Cleona.
- **Segera.** Pesanmu berangkat pada saat kamu mengirimkannya. Ia tidak
  menunggu irama tertentu maupun hal lain.
- **Penyamaran di samping.** Perangkatmu terus-menerus mengirim paket-paket
  penyamaran kecil, sehingga dari luar tidak bisa terlihat kapan kamu benar-
  benar sedang menulis. Tidak ada pesan yang bergantung padanya -- penyamaran
  hanya berjalan di samping.
- **Kode, bukan nama.** Siapa pun yang meneruskan pesan hanya melihat sebuah
  kode yang berubah setiap hari. Secara normal, tidak ada satu pun dari mereka
  yang mengenal pengirim dan penerima sekaligus; pengecualiannya tercantum di
  Bab 14.

**Tiga jalur, semuanya sekaligus.** Saat kamu mengirim pesan, Cleona tidak
mencoba satu jalur demi satu jalur, melainkan semua jalur yang cocok
sekaligus. Begitu lawan bicaramu mengonfirmasi penerimaan, jalur-jalur lain
dibatalkan.

1. **Di jaringan yang sama:** Jika kalian berada di Wi-Fi yang sama, pesan
   langsung berpindah.
2. **Melalui tetangga tetap:** Di internet, perangkatmu meneruskan pesan ke
   tetangga tetapnya. Tetangga itu meneruskannya ke tetangga tetap lawan
   bicaramu (hingga tiga sekaligus), dan salah satunya mengantarkannya.
3. **Kotak surat:** Jika lawan bicaramu offline, Cleona menitipkan pesan yang
   terenkripsi kepada tiga tetangga. Pesan itu tinggal di sana hingga 7 hari.
   Saat lawan bicaramu kembali online, ia mengambilnya.

**Bagaimana kamu masuk ke jaringan?** Di dalam aplikasi tidak ada alamat
server. Titik masukmu kamu dapatkan dari kontak pertamamu: Undangannya
memuat alamat-alamat tempat perangkatmu menemukan tetangga pertamanya. Di
Wi-Fi yang sama, perangkat-perangkat Cleona juga saling menemukan sendiri.
Dari sana, perangkatmu mengenal tetangga lain lewat setiap tetangga.

### Platform

Cleona tersedia untuk Android, iOS, macOS, Linux, dan Windows. Di komputer
dan di Android, pesan dan panggilan tiba dalam hitungan detik. Di iPhone hal
itu berlaku selama aplikasi terbuka. Jika aplikasi tidak terbuka, iOS hanya
membangunkannya sebentar sesekali; iOS yang menentukan kapan. Cleona lalu
mengambil semua yang disimpan untukmu dan menampilkan pemberitahuan dengan
angka pada ikon aplikasi. Panggilan tidak mencapai iPhone yang aplikasinya
tidak terbuka. Itu aturan Apple, bukan kekurangan Cleona.

---

## 2. Mulai menggunakan

### Memasang aplikasi

**Android:**
1. Unduh berkas APK dari situs web Cleona atau dari GitHub Releases.
2. Buka berkas itu di ponselmu. Jika perlu, izinkan pemasangan dari sumber
   yang tidak dikenal (Android akan menanyakanmu secara otomatis).
3. Ketuk "Pasang" dan tunggu hingga pemasangan selesai.

**iOS:**
1. Buka tautan undangan TestFlight di iPhone-mu.
2. Ketuk "Pasang". TestFlight adalah cara resmi Apple untuk membagikan
   aplikasi beta.
3. Setelah terpasang, kamu menemukan Cleona di layar utama ponselmu.

**macOS:**
1. Unduh berkas DMG dari situs web Cleona atau dari GitHub Releases.
2. Buka DMG tersebut dan seret Cleona ke folder Aplikasi-mu.
3. Saat pertama kali dinyalakan, macOS mungkin menanyakan apakah kamu ingin
   membuka aplikasi dari pengembang yang teridentifikasi -- konfirmasikan.

**Linux (Ubuntu/Debian):**
1. Unduh berkas .deb dari situs web Cleona atau dari GitHub Releases.
2. Pasang dengan klik ganda atau di terminal: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Jalankan Cleona melalui menu aplikasi atau di terminal dengan `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Unduh berkas .rpm dari situs web Cleona atau dari GitHub Releases.
2. Pasang dengan: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Jalankan Cleona melalui menu aplikasi atau di terminal dengan `cleona-chat-beta`.

**Linux (semua distribusi -- AppImage):**
1. Unduh berkas .AppImage dari situs web Cleona atau dari GitHub Releases.
2. Jadikan berkas dapat dieksekusi: klik kanan, properti, dapat dieksekusi, atau di terminal: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Jalankan dengan klik ganda atau di terminal: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Nama paket berlaku untuk beta, yang saat ini merupakan satu-satunya versi
yang dirilis; namanya `cleona-chat-beta`.

**Windows:**
1. Unduh installer dari situs web Cleona atau dari GitHub Releases.
2. Jalankan berkas instalasi dan ikuti petunjuknya.
3. Jalankan Cleona melalui menu Start atau pintasan desktop.

### Membuat identitas

Saat pertama kali dinyalakan, Cleona secara otomatis membuat identitas baru
untukmu. Kamu bisa memberi dirimu nama tampilan -- itu adalah nama yang dilihat
oleh kontak-kontakmu. Nama ini bisa diubah kapan saja.

### Menuliskan frasa seed -- hal yang paling penting

Setelah membuat identitasmu, Cleona menampilkan 24 kata kepadamu. Itulah
**frasa seed**-mu -- kunci pemulihan pribadimu.

**Tuliskan 24 kata ini pada kertas dan simpan dengan aman.**

Mengapa ini begitu penting?

- Jika ponselmu rusak, hilang, atau dicuri, kamu bisa memulihkan seluruh
  identitasmu di perangkat baru dengan 24 kata ini.
- Tanpa frasa seed, tidak ada jalan kembali. Tidak ada tombol "lupa kata
  sandi" dan tidak ada dukungan yang bisa mengembalikan akunmu -- karena
  memang tidak ada akun di server. Kontak-kontakmu pun tidak bisa memulihkan
  identitasmu, betapa pun banyaknya. Perangkat kedua dengan identitas yang
  sama hadir di versi berikutnya (lihat Bab 11).
- Jangan pernah memberikan frasa seed kepada orang lain. Siapa pun yang
  mengetahui kata-kata ini bisa menyamar sebagai dirimu.

Kamu menemukan 24 kata nanti di pengaturan di bawah "Cadangan" ->
"Tampilkan frasa pemulihan", jika kamu ingin membacanya sekali lagi. Di
Android kamu mengonfirmasinya dengan kunci layarmu.

### Menambahkan kontak pertama

Untuk mengobrol dengan seseorang, kamu harus menambahkan orang itu sebagai
kontak lebih dulu. Ada beberapa cara untuk itu -- semuanya dijelaskan di
bagian selanjutnya.

---

## 3. Kontak

### Undanganmu

Kontak di Cleona hanya terbentuk melalui undangan. Undanganmu sudah tersedia
sejak pertama kali dinyalakan -- bahkan tanpa internet dan sebelum perangkatmu
menemukan satu tetangga pun. Kamu menemukannya di halaman detail identitasmu
(ketuk namamu sendiri di bilah atas).

Undangan tersedia dalam dua bentuk yang berisi persis sama:

- sebagai **kode QR**, jika lawan bicaramu berada di sebelahmu, dan
- sebagai **baris teks**, yang kamu kirim melalui email, SMS, atau melalui
  messenger lain.

Undangan tidak memuat nomor telepon maupun nama dari sembarang direktori. Ia
memuat kunci-kunci publikmu dan alamat-alamat tempat lawan bicaramu menjangkau
kamu dan tetangga-tetanggamu. Bagi seseorang yang baru memasang Cleona,
undanganmu karena itu juga menjadi pintu masuk ke jaringan.

### Memindai kode QR (disarankan)

Jika kalian bertemu langsung:

1. Kamu menunjukkan kode QR undanganmu kepada lawan bicaramu.
2. Lawan bicaramu mengetuk tombol plus, memilih "Pindai kode QR" dan
   mengarahkan kamera ke layarmu. Ini juga bisa dilakukan dengan kamera web
   sebuah komputer.
3. Permintaan dikirim kepadamu dan **diterima secara otomatis** -- karena
   kamu sendiri yang baru saja menunjukkan kodenya.

Satu kode QR hanya berlaku sekali: Permintaan valid pertama diterima,
setelah itu undangan habis terpakai. Kode QR adalah metode paling aman,
karena dengan itu kalian tahu persis dengan siapa kalian bertukar kontak.

### NFC (mendekatkan ponsel)

Jika kedua perangkat mendukung NFC:

1. Buka keduanya fungsi tambah kontak.
2. Tempelkan ponsel kalian punggung-ke-punggung.
3. Undangan ditransfer dan diterima secara otomatis.

NFC menawarkan keamanan tinggi seperti kode QR, karena pertukaran hanya
berfungsi jika kalian berdiri berdampingan secara fisik.

### Mengirim baris teks

Jika kalian tidak bisa bertemu:

1. Buka undanganmu dan salin baris teks.
2. Kirimkan kepada orang yang seharusnya menambahkanmu -- melalui email, SMS,
   atau melalui messenger lain.
3. Orang tersebut menempelkan baris itu di Cleona dalam dialog tambah kontak.
4. Permintaan muncul di sisimu di bawah **"Permintaan"**. Di sini permintaan
   **tidak** diterima secara otomatis: Kamu sendiri yang memutuskan, karena
   kamu tidak bisa tahu siapa yang membaca baris itu di tengah jalan.

### Menerima permintaan kontak

Sebuah permintaan masuk belum membentuk kontak. Ia mengajukan sebuah
pertanyaan kepadamu dan muncul di tab **"Permintaan"**. Di sana kamu melihat
nama dan tingkat verifikasi dan dapat memilih:

- **Terima** -- baru sekarang orang ini menjadi kontakmu.
- **Tolak** -- permintaan dibuang.
- **Blokir** -- orang ini tidak bisa mengirim permintaan lebih lanjut
  kepadamu.

### Jangan pernah digunakan sebagai tetangga tetap

Di menu sebuah kontak kamu menemukan saklar **"Jangan pernah digunakan
sebagai tetangga tetap"** (bawaan: mati). Jika dinyalakan, kontak ini tidak
meneruskan pesan untukmu dan karenanya juga tidak mengetahui kapan kamu
mengirim atau menerima pesan. Ini ditujukan untuk kasus ketika ancaman
datang dari lingkunganmu sendiri.

Dari orang asing (bukan kontak maupun anggota grup bersama), Cleona tidak
memasukkan apa pun selain permintaan seperti itu -- tidak ada pesan, panggilan,
maupun berkas. Dan bahkan permintaan itu
hanya sampai jika pengirim sebelumnya menyelesaikan sebuah tugas komputasi
kecil. Itu membuat spam massal menjadi mahal.

### Tingkat verifikasi

Cleona menunjukkan kepadamu seberapa terpastinya identitas sebuah kontak:

| Tingkat | Arti |
|---------|-----------|
| Tidak terverifikasi | Kalian terhubung, tetapi tidak ada yang memastikan bahwa di baliknya benar-benar orang yang tepat. |
| Dilihat | Pertukaran kunci berhasil, kalian bisa berkomunikasi terenkripsi. |
| Terverifikasi | Kalian telah bertemu langsung dan terhubung melalui pemindaian kamera atau NFC. |
| Dipercaya | Kamu secara eksplisit menandai kontak ini sebagai tepercaya. |

"Terverifikasi" hanya ada untuk pertukaran langsung. Sebuah undangan yang
datang melalui obrolan atau email tidak akan pernah mencapai tingkat ini --
meskipun berisi data yang sama.

Jika kunci sebuah kontak berubah tanpa pemberitahuan, Cleona meresetnya ke
"Tidak terverifikasi". Ini melindungimu agar tidak ada yang menyamar sebagai
kontakmu tanpa disadari.

---
## 4. Pesan

### Mengirim dan menerima teks

Ketik saja pesanmu ke kolom input di bawah dan tekan Enter atau tombol
kirim. Pesanmu otomatis dienkripsi sebelum meninggalkan perangkatmu.

Pesan masuk muncul di riwayat obrolan.

### Apa arti tanda pada pesanmu

| Tanda | Arti |
|---------|-----------|
| Jam | Pesan sudah dibuat, tetapi belum ada jalur yang mengantarkannya. |
| Satu centang | Pesan sedang dalam perjalanan. Ini berlaku juga selama ia menunggu lawan bicaramu di kotak surat. |
| Dua centang | Terkirim: Perangkat lawan bicaramu telah mengonfirmasi penerimaan. |
| Tanda peringatan | Selama 14 hari tidak ada jalur yang mengantarkan pesan. Ketuk untuk mengirimnya kembali. |

**Offline bukanlah kesalahan.** Jika lawan bicaramu tidak terjangkau, pesan
tetap pada satu centang sampai diambil -- ia tidak hilang. Jika perangkatmu
sendiri tidak memiliki koneksi, pesan tetap pada jam dan berangkat sendiri
begitu ada jalur kembali. Tanda peringatan baru muncul jika pesan selama
14 hari tidak menemukan jalur; maka kamu bisa mengirimnya kembali.

Hal ini juga berlaku untuk iPhone yang aplikasinya tidak terbuka: pesan
menunggu di kotak surat sampai iOS membangunkan aplikasi sebentar atau sampai
lawan bicaramu membukanya. Itu bisa memakan waktu lebih lama daripada di
perangkat lain.

Dua centang hanya ada jika penerima sendiri mengonfirmasi penerimaan. Tanda
terima ini terenkripsi dan ditandatangani -- tidak ada siapa pun di tengah
jalan yang bisa memalsukannya untuk menipumu seolah pesan telah terkirim.

### Mengirim gambar, video, dan berkas

Kamu punya beberapa cara:

- **Ikon paperclip** di kolom input: Ketuk untuk memilih berkas, gambar,
  atau video dari galerimu atau sistem berkasmu.
- **Seret dan lepas** (Desktop): Seret berkas langsung ke jendela obrolan.
- **Tempel dari papan klip** (Desktop): Salin gambar dan tempel di obrolan.

Berkas kecil (di bawah 256 KB) ikut bersama dalam pesan. Berkas yang lebih
besar dipecah menjadi potongan-potongan dan dilengkapi koreksi kesalahan,
sehingga potongan yang hilang tidak jadi masalah. Jika kalian berdua online,
mereka di-stream melalui seorang tetangga; jika tidak, mereka diletakkan di
perangkat-perangkat yang selalu terjangkau, sampai lawan bicaramu
mengambilnya.

Mulai dari 256 KB, Cleona menanyakanmu per berkas sebelum berkas dikirim:
Sebuah berkas besar tidak bisa mengambil jalur pesanmu. Isinya tetap
terenkripsi, dan lawan bicaramu tidak mengetahui alamat internetmu. Tetapi
transfernya terlihat dari luar sebagai sebuah peristiwa, dan perangkat asing
yang meneruskannya atau menyimpannya melihat siapa yang mengunggah dan siapa
yang mengambil. Persetujuanmu hanya berlaku untuk berkas itu saja.

### Pesan suara

1. Tahan tombol mikrofon di kolom input.
2. Ucapkan pesanmu.
3. Lepaskan tombol untuk mengirim pesan.

Jika pengenalan suara diaktifkan di perangkatmu (lihat Pengaturan), pesan
suaramu otomatis ditranskripsi menjadi teks. Lawan bicaramu lalu melihat
baik rekaman maupun teks yang sudah ditranskripsi.

### Membalas pesan (mengutip)

Untuk membalas pesan tertentu:

1. Buka menu tiga-titik di samping pesan.
2. Pilih "Balas".
3. Di atas kolom input muncul sebuah banner dengan pesan yang dikutip.
4. Tulis balasanmu dan kirim.

Pesan yang dikutip ditampilkan dalam balasanmu, sehingga hubungannya menjadi
jelas.

### Mengedit dan menghapus pesan

- **Edit:** Menu tiga-titik pesan, lalu "Edit".
  Ubah teks dan kirim ulang. Lawan bicaramu melihat bahwa pesan itu telah
  diedit. Pengeditan dimungkinkan dalam 15 menit setelah pengiriman.
- **Hapus:** Menu tiga-titik pesan, lalu "Hapus". Pesan dihapus di sisimu
  dan di sisi lawan bicaramu. Kamu bisa menghapus pesan-pesanmu sendiri
  kapan saja -- tidak ada batas waktu untuk penghapusan.

### Reaksi emoji

Daripada menulis balasan, kamu bisa bereaksi pada sebuah pesan dengan emoji:

1. Buka menu tiga-titik atau tahan pesan lama.
2. Pilih emoji dari pilihan cepat atau buka pemilih emoji untuk pilihan
   lengkap.
3. Reaksimu muncul di bawah pesan.

### Menyalin teks

Melalui menu tiga-titik sebuah pesan, kamu bisa menyalin teks pesan ke papan
klip.

### Mencari pesan

Di bagian atas jendela obrolan kamu menemukan fungsi pencarian. Masukkan
kata kunci, dan Cleona menunjukkan semua hasil di obrolan saat ini. Dengan
tombol panah kamu bisa berpindah-pindah antar hasil.

Di beranda ada tambahan pula filter pencarian lintas tab, untuk menelusuri
semua percakapan dengan sebuah kata.

### Pratinjau tautan

Saat kamu mengirim tautan, Cleona otomatis membuat pratinjau (judul,
deskripsi, gambar pratinjau). Pratinjau ini dibuat oleh perangkatmu dan ikut
dikirim -- lawan bicaramu tidak perlu membuat koneksi ke situs yang
ditautkan.

Apa yang terjadi saat kamu mengetuk tautan yang diterima, kamu atur di
pengaturan di bawah "Buka tautan": "Normal", "Utamakan jendela privat" (di
perangkat yang tidak bisa membuka jendela privat, tautan terbuka normal),
atau "Tanya setiap kali".

---

## 5. Grup

### Membuat grup

1. Pindah ke tab "Grup".
2. Ketuk tombol plus.
3. Beri grup sebuah nama.
4. Pilih kontak-kontak yang ingin kamu undang.
5. Ketuk "Buat".

Kontak yang diundang menerima pemberitahuan dan bisa bergabung ke grup.

### Bagaimana pesan grup dilindungi

Di grup dengan hingga 16 anggota, Cleona mengirim setiap pesan ke setiap
anggota satu per satu -- masing-masing hanya dienkripsi untuk anggota itu,
seolah kamu menulis pesan terpisah untuk setiap orang. Centang pada sebuah pesan grup
menunjukkan kondisi anggota yang paling tertinggal.

Jika grup tumbuh melebihi 16 anggota, grup menggunakan sebuah kunci bersama.
Kunci itu berubah setiap hari dan diundi ulang jika seorang anggota keluar
atau dihapus; anggota baru hanya bisa membaca sejak ia bergabung. Di sana
centang tidak lagi menunjukkan kondisi setiap anggota, melainkan bahwa pesan
telah diletakkan di jaringan. Jika grup menyusut menjadi 12 anggota atau
kurang, grup kembali ke pengiriman satu per satu.

### Gambar di grup dan saluran

Di pengaturan sebuah grup atau saluran, kamu menetapkan dengan "Selalu muat
gambar" apakah gambar dimuat segera atau baru saat kamu mengetuknya.

### Mengundang anggota

Bahkan setelah pembuatan, kamu bisa mengundang kontak lain:

1. Buka info grup (menu tiga-titik di gambaran umum grup atau bilah atas
   di obrolan grup).
2. Ketuk "Undang".
3. Pilih kontak-kontak yang ingin kamu tambahkan.

### Peran

Setiap grup memiliki tiga peran:

- **Pemilik (Owner):** Memiliki kendali penuh. Bisa menambah dan
  menghapus anggota, menunjuk admin, dan mengelola grup. Pemilik juga bisa
  mengalihkan statusnya ke anggota lain.
- **Admin:** Bisa menghapus anggota dan membantu pengelolaan.
- **Anggota:** Bisa membaca dan menulis pesan.

### Meninggalkan grup

1. Buka menu tiga-titik di gambaran umum grup.
2. Pilih "Keluar".
3. Konfirmasi keputusanmu.

Jika kamu meninggalkan grup, pesan-pesanmu yang sudah ada tetap terlihat oleh
anggota lain.

---

## 6. Saluran publik

### Apa itu saluran?

Saluran adalah forum diskusi publik di dalam jaringan Cleona. Berbeda dengan
grup, di sini siapa pun bisa ikut membaca tanpa perlu diundang. Hanya pemilik
dan admin yang bisa menerbitkan kiriman -- pelanggan ikut membaca.

### Menemukan dan bergabung ke saluran

1. Pindah ke tab "Saluran".
2. Buka tab "Cari".
3. Telusuri saluran yang tersedia berdasarkan nama atau topik.
4. Ketuk sebuah saluran lalu "Berlangganan".

Saluran bisa disaring berdasarkan bahasa. Beberapa saluran ditandai sebagai
"Tidak untuk di bawah umur" -- ini hanya terlihat jika kamu di profilmu telah
mengonfirmasi bahwa kamu berusia di atas 18 tahun.

### Membuat saluran sendiri

1. Pindah ke tab "Saluran".
2. Ketuk tombol plus.
3. Masukkan nama saluran (harus unik di seluruh jaringan).
4. Pilih bahasa dan apakah saluran akan publik atau privat.
5. Opsional: Tambahkan deskripsi dan gambar.
6. Ketuk "Buat".

Pada saluran publik, kamu bisa menetapkan apakah konten diklasifikasikan
sebagai "Tidak untuk di bawah umur".

### Melaporkan konten

Jika kamu melihat konten yang tidak pantas di saluran publik, kamu bisa
melaporkannya. Cleona menggunakan sistem moderasi terdesentralisasi: Laporan
dinilai oleh anggota jaringan yang dipilih secara acak (sejenis "dewan juri").
Jika pelanggaran ditemukan, saluran mendapat peringatan. Jika pelanggaran
diulang, saluran diturunkan di indeks pencarian atau diblokir.

### Saluran sistem

Cleona memiliki dua saluran sistem bawaan:

- **Bug Log:** Jika Cleona mendeteksi kesalahan, ia menanyakanmu apakah kamu
  ingin mengirim laporan kesalahan; sebelumnya kamu melihat dengan persis
  apa yang dipublikasikan. Laporan ini masuk ke saluran Bug Log, di mana
  komunitas bisa melihatnya. Sebuah laporan tidak memuat nama maupun isi
  percakapanmu, melainkan sebuah pseudonim. Pada beta, laporan itu tambahan
  menyebut pengenal (User-ID)-mu, agar para pengembang bisa menanyakan lebih
  lanjut. Kamu juga bisa mengirim laporan log secara manual (dengan dialog
  pratinjau dan persetujuan eksplisit).
- **Feature Requests:** Di sini pengguna bisa mengajukan permintaan fitur
  dan memberi suara untuk usulan yang sudah ada. Usulan diurutkan
  berdasarkan suara.

Setiap komputer menyimpan hingga 25 MB per saluran sistem, setiap ponsel
hingga 5 MB; jika penuh, yang paling lama pergi lebih dulu -- tidak pernah
yang sudah kamu lihat sendiri.

---
## 7. Panggilan

### Memulai panggilan suara

1. Buka obrolan dengan kontak yang ingin kamu telepon.
2. Ketuk ikon telepon di bilah atas.
3. Tunggu hingga lawan bicaramu menerima panggilan.

Selama percakapan kamu melihat garis waktu, durasi percakapan, dan memiliki
akses ke senyap dan pengeras suara.

Untuk menutup, ketuk tombol tutup berwarna merah.

Jika kamu melihat "Tidak dapat dihubungi", perangkat lawan bicaramu sedang
tidak dapat dijangkau, misalnya iPhone yang aplikasinya tidak terbuka. Kirim
pesan saja.

### Memulai panggilan video

1. Buka obrolan dengan kontak.
2. Ketuk ikon kamera di bilah atas.
3. Gambar videomu muncul di jendela kecil, gambar lawan bicaramu di area
   besar.

Kamu bisa berganti antara kamera depan dan belakang selama percakapan.

### Panggilan masuk

Jika seseorang meneleponmu, muncul jendela pemberitahuan dengan nama penelepon.
Kamu bisa:

- **Terima** -- percakapan dimulai.
- **Tolak** -- penelepon diberi tahu.

Jika kamu sedang berada dalam percakapan, panggilan baru tidak berbunyi; kamu
mendapatkan sebagai gantinya sebuah pesan "Panggilan tak terjawab". Hal yang
sama berlaku untuk panggilan grup yang tidak kamu jawab -- pesannya lalu
berada di obrolan grup.

Jika seseorang menelepon salah satu identitasmu yang saat itu tidak sedang
ditampilkan, telepon tetap berbunyi; layar panggilan menyebut identitas
yang mana darimu yang sedang ditelepon.

Di iPhone, telepon hanya berbunyi selama aplikasi terbuka. Siapa pun yang
meneleponmu saat aplikasi tidak terbuka melihat "Tidak dapat dihubungi"
setelah 10 detik. Begitu kamu membuka aplikasi, kamu menemukan pesan tentang
panggilan tak terjawab.

### Panggilan grup

Kamu juga bisa melakukan panggilan grup dengan beberapa orang yang ikut
bersamaan. Panggilan diorganisir melalui pohon penerusan cerdas, sehingga
tidak setiap peserta harus terhubung langsung dengan setiap peserta lain.
Semua percakapan dienkripsi sepanjang waktu.

Setiap anggota grup bisa memulai panggilan grup. Dua peserta yang bukan
kontak satu sama lain tidak pernah melihat alamat internet masing-masing:
Suara dan gambar mereka mengalir melalui seorang peserta yang menjadi kontak
keduanya. Jika tidak ada yang seperti itu, keduanya tidak terhubung, dan
kartu peserta menampilkan "Tidak ada kontak bersama dalam panggilan". Jika
sebuah penerusan sibuk, suara tetap ada, dan video hilang untuk pasangan
itu.

### Enkripsi pada panggilan

Semua panggilan dienkripsi dengan kunci sekali pakai yang hanya ada selama
percakapan berlangsung. Setelah menutup, kunci-kunci ini langsung dihapus.
Tidak ada yang bisa mendekripsi percakapan yang telah lampau secara
belakangan.

Terus terang: Panggilan berlangsung, sedapat mungkin, langsung antara
perangkat, karena sedikit keterlambatan pun mengganggu saat berbicara. Berbeda
dengan pesan, provider internetmu karena itu pada sebuah panggilan bisa melihat
ke alamat internet mana kamu terhubung. Apa yang kalian katakan tidak bisa
dilihatnya.

Pada sebuah panggilan, kontakmu juga melihat alamat internetmu. Jika kamu
tidak menginginkannya pada seorang kontak, matikan di menunya "Izinkan
panggilan" (bawaan: on). Jika kamu mematikannya kemudian, alamat yang sudah
ia lihat tetap ia ketahui.

---

## 8. Kalender

Cleona memiliki kalender bawaan yang bekerja terenkripsi dan sepenuhnya
terdesentralisasi -- tanpa layanan cloud.

### Tampilan

Kalender menawarkan lima tampilan: Hari, Minggu, Bulan, Tahun, dan tampilan
Tugas. Bergantilah di antaranya melalui tab di bagian atas layar kalender.

### Membuat janji

Ketuk slot waktu atau gunakan tombol tambah untuk membuat janji baru. Kamu
bisa memasukkan judul, tanggal, waktu, lokasi, dan catatan. Janji disimpan
terenkripsi di perangkatmu.

### Janji berulang

Janji bisa berulang harian, mingguan, bulanan, atau tahunan. Kamu bisa
menyesuaikan pola (mis. setiap Selasa kedua, setiap tanggal satu bulan) dan
menetapkan tanggal akhir atau jumlah pengulangan.

### Mengundang kontak

Saat membuat atau mengedit janji, kamu bisa mengundang kontak-kontak Cleona-
mu. Mereka menerima undangan kalender terenkripsi dan bisa membalas dengan
ya, tidak, atau mungkin. Perubahan pada janji otomatis dikirim ke semua
yang diundang.

### Tampilan bebas/sibuk

Kamu bisa membagikan ketersediaanmu dengan kontak tanpa membocorkan detail
janji. Ada tiga tingkat privasi: detail lengkap, hanya blok waktu, atau
tersembunyi. Kamu bisa menetapkan standar dan menimpanya per kontak.

### Pengingat

Janji bisa memiliki pengingat yang memicu pemberitahuan sistem sebelum janji
dimulai. Kamu bisa menunda pengingat bila perlu.

### Sinkronisasi kalender eksternal

Cleona bisa sinkronisasi dengan layanan kalender eksternal:

- **CalDAV** -- Hubungkan ke server apa pun yang kompatibel dengan CalDAV
  (Nextcloud, Radicale dll.).
- **Google Kalender** -- Sinkronisasi melalui Google Calendar API dengan
  autentikasi OAuth2 yang aman.
- **Server CalDAV lokal** -- Cleona bisa menjalankan server CalDAV lokal di
  perangkatmu, sehingga aplikasi kalender desktop (Thunderbird, Outlook,
  Apple Kalender, Evolution) bisa sinkronisasi dengan kalender Cleona-mu.
- **Kalender sistem Android** -- Janji dari Cleona bisa dipindahkan ke
  aplikasi kalender bawaan perangkat Android-mu.
- **Berkas ICS** -- Impor dan ekspor janji dalam format iCalendar standar.

### Ekspor PDF

Kamu bisa mencetak atau mengekspor setiap tampilan kalender (Hari, Minggu,
Bulan, Tahun) sebagai dokumen PDF.

---

## 9. Jajak pendapat

Kamu bisa membuat jajak pendapat di obrolan atau grup mana pun untuk mengumpulkan
pendapat atau merencanakan janji.

### Tipe jajak pendapat

Cleona mendukung lima jenis jajak pendapat:

- **Pilihan tunggal** -- Peserta memilih satu opsi.
- **Pilihan ganda** -- Peserta bisa memilih beberapa opsi.
- **Jajak jadwal** -- Temukan satu janji yang cocok untuk semua. Setiap
  peserta menandai janji sebagai tersedia, mungkin, atau tidak tersedia.
- **Skala** -- Nilai sesuatu pada skala numerik (mis. 1 sampai 5).
- **Teks bebas** -- Peserta menulis jawaban mereka sendiri.

### Membuat jajak pendapat

Buka obrolan dan ketuk ikon jajak pendapat (atau gunakan menu lampiran).
Pilih tipe jajak pendapat, rumuskan pertanyaanmu dan opsinya, lalu kirim
jajak pendapat. Ia muncul sebagai pesan di obrolan.

### Memberi suara

Ketuk jajak pendapat untuk memberikan suaramu. Kamu bisa mengubah atau
menarik kembali suaramu kapan saja.

### Pemberian suara anonim

Jajak pendapat bisa dikonfigurasi untuk pemberian suara anonim. Jika
diaktifkan, suara bersifat anonim secara kriptografis -- tidak ada siapa
pun, bahkan pembuat jajak pendapat, yang bisa melihat siapa memilih apa.
Jumlah suara tetap terlihat.

### Jajak jadwal ke kalender

Jika sebuah jajak jadwal selesai, janji pemenang bisa langsung diubah menjadi
entri kalender dengan satu ketukan.

---
## 10. Beberapa identitas

### Mengapa beberapa identitas?

Bayangkan kamu ingin memisahkan kehidupan kerja dan kehidupan pribadi --
seperti dengan dua nomor telepon berbeda, tetapi tanpa ponsel kedua. Di
Cleona kamu bisa menggunakan beberapa identitas di satu perangkat. Setiap
identitas memiliki nama sendiri, foto profil sendiri, kontak sendiri, dan
percakapan sendiri.

### Membuat identitas baru

1. Di bilah atas kamu melihat identitas saat ini sebagai tab.
2. Ketuk tanda plus (+) di sebelah kanan tab identitasmu.
3. Masukkan nama untuk identitas baru.
4. Selesai -- identitas baru langsung aktif.

### Berganti antar identitas

Ketuk saja tab identitas di bilah atas. Pergantian langsung -- tidak ada
waktu tunggu, tidak ada muat ulang.

### Semuanya berjalan bersamaan

Satu hal penting: Semua identitasmu aktif bersamaan. Bahkan jika kamu
sedang tampil sebagai "Kerja", identitas "Pribadi"-mu tetap menerima pesan.
Kamu tidak melewatkan apa pun, apa pun identitas yang sedang kamu pilih.

### Halaman detail identitas

Jika kamu mengetuk tab identitas yang sedang aktif, halaman detail terbuka.
Di sini kamu bisa:

- Menampilkan kode QR-mu untuk kontak.
- Mengubah atau menghapus foto profilmu.
- Menambahkan deskripsi profil.
- Mengubah nama tampilanmu.
- Memilih desain (skin) untuk identitas ini.
- Menghapus identitas, jika kamu tidak membutuhkannya lagi.

### Menghapus identitas

Jika kamu menghapus sebuah identitas, kontak-kontakmu diberi tahu. Identitas
dan semua data terkait dihapus dari perangkatmu. Proses ini tidak bisa
dibalik.

---

## 11. Beberapa perangkat

### Satu identitas, satu perangkat -- untuk sementara

Saat ini sebuah identitas berjalan di satu perangkat. Perangkat kedua untuk
identitas yang sama hadir di versi berikutnya; karena itu di pengaturan di
bawah "Perangkat" -> "Kelola perangkat" tertulis "Tautkan perangkat lain"
masih sebagai "Belum tersedia".

Bila kelak hadir, berlaku: Semua perangkat setara, tidak ada perangkat utama.
Perangkat tambahan kamu siapkan dengan 24 katamu, dan salah satu perangkatmu
yang selama ini dipakai menyetujuinya. Paling banyak 5 perangkat.

Jika kamu hari ini memasukkan 24 katamu di perangkat baru, kamu berpindah:
Identitas dipulihkan di perangkat baru, dan perangkatmu yang lama
kemudian menghapus identitas itu di tempatnya (lihat Bab 12).

Di beberapa perangkat, kamu hari ini bisa menggunakan identitas yang
berbeda-beda (Bab 10).

### Rotasi kunci identitas

Jika kamu menduga bahwa ada orang yang mendapatkan kuncimu, kamu bisa membuat
kunci baru di bawah "Kelola perangkat" -> "Rotasi kunci". Kontak-kontakmu
diberi tahu, undangan-undanganmu yang masih terbuka dicabut. Penting:
Setelah itu, 24 kata saja hanya menghasilkan kunci-kunci lama. Buat karena
itu langsung setelahnya paket pemulihan baru; kamu hanya bisa memulihkan lagi
bersama-sama dengan paket itu.

---

## 12. Pemulihan

### Menggunakan frasa seed

Jika kamu kehilangan perangkatmu atau menyiapkan yang baru:

1. Pasang Cleona di perangkat baru.
2. Pilih saat mulai "Pulihkan".
3. Masukkan 24 katamu.
4. Cleona membuat ulang semua identitasmu darinya -- dengan kunci yang sama
   seperti sebelumnya. Bagi kontak-kontakmu, kamu adalah orang yang sama.

### Apa yang kembali -- dan apa tidak

Identitasmu ada di 24 kata, kontak-kontakmu dan riwayatmu tidak. Yang kembali
adalah akses jaringanmu melalui **paket pemulihan**: Perangkatmu menitipkan
sebuah paket kecil terenkripsi di jaringan. Hanya 24 katamu yang bisa
menemukan dan membukanya. Di dalamnya tercantum apa yang dibutuhkan
perangkat barumu untuk menjangkau kembali kontak-kontakmu, dan apa yang
selama itu dititipkan untukmu di jaringan. Untuk itu tidak ada kontak yang
perlu online.

Riwayat obrolan yang lama tidak dibawa kembali oleh sebuah pemulihan.

Paket pemulihan berumur 7 hari dan diperbarui oleh perangkatmu selama ia
berjalan; di pengaturan kamu melihat sampai kapan ia berlaku. Jika lebih
dari 7 hari tidak ada satu pun perangkatmu yang berjalan, paket itu
kedaluwarsa. Maka 24 kata tetap memulihkan identitasmu, tetapi
kontak-kontakmu harus kamu undang kembali; apa yang selama itu dititipkan
untukmu di jaringan hilang.

### Memulihkan berarti berpindah

Jika perangkatmu yang lama kemudian mendapati bahwa identitas dipulihkan di
tempat lain, ia menghapus identitas itu di tempatnya -- beserta riwayatnya.
Karena itu: Siapa pun yang memiliki 24 katamu bisa mengambil identitasmu
dengan cara ini dari perangkatmu. Sampai semua kontak kembali ada,
aplikasinya mengingatkanmu; dengan "Selesaikan dan perbarui kunci" kamu
mengakhiri pemulihan itu sendiri.

### Apa yang tidak bisa dipulihkan oleh siapa pun

Ini penting, dan karena itu kami mengatakannya dengan jelas:

- **Tidak ada selain kamu yang bisa memulihkan identitasmu.** Bukan
  pengembang, bukan dukungan, dan bukan pula kontak-kontakmu -- betapa pun
  banyaknya. Tidak ada kunci induk dan tidak ada bagian kuncimu yang
  dititipkan pada orang lain.
- **Jika kamu kehilangan 24 kata dan tidak punya perangkat lagi, identitasmu
  hilang.** Maka yang tersisa hanyalah membuat yang baru dan mengundang
  kontakmu kembali.

Perlindungan terbaik: Tuliskan 24 kata pada kertas dan simpan dengan aman.

---
## 13. Pengaturan

Pengaturan kamu jangkau melalui ikon gerigi di sudut kanan atas.

### Pemberitahuan dan nada dering

- Pilih dari enam nada dering berbeda untuk panggilan masuk.
- Atur nada pesan.
- Di perangkat Android, kamu bisa tambahan mengaktifkan atau menonaktifkan
  getaran.
- **"Bisukan semua"** membiarkan di perangkat ini tidak ada lagi pesan yang
  berbunyi, bergetar, atau melapor -- untuk semua identitas. Panggilan tetap
  berbunyi.
- **"Jam tenang"** kamu tetapkan per identitas dengan dari/sampai. Dalam
  waktu itu tidak ada pesan identitas ini yang berbunyi, bergetar, atau
  melapor; pesan-pesan itu tetap sampai.
- **"Notifikasi tanpa konten"** (bawaan: mati) hanya menunjukkan bahwa sebuah
  pesan, undangan, atau pengingat tiba -- tanpa pengirim, nama, dan teks.
  Panggilan tetap menampilkan nama.
- Apa yang setelah start tiba sekaligus, dilaporkan Cleona dalam sebuah
  pemberitahuan gabungan ("5 pesan baru dalam 2 percakapan"); semuanya yang
  setelahnya masing-masing satu. Sebuah ketukan pada pemberitahuan pesan
  membuka percakapan itu, juga di identitas lain.

### Desain (Skin)

Cleona menawarkan sepuluh desain berbeda: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold, dan Contrast. Desain Contrast memenuhi
tingkat aksesibilitas tertinggi (WCAG AAA) dan sangat mudah dibaca saat
kemampuan penglihatan terbatas.

Setiap identitas bisa memiliki desainnya sendiri. Kamu mengubah desain di
halaman detail identitas (ketuk tab identitas aktif).

Tambahan, kamu bisa di pengaturan di bawah "Tampilan" berganti antara tema
terang, gelap, dan sistem.

### Mengubah bahasa

Cleona tersedia dalam 34 bahasa, termasuk bahasa dengan aksara kanan-ke-kiri
(mis. Arab, Ibrani). Ubah bahasa di pengaturan di bawah "Bahasa".

### Pengarsipan media

Jika di rumah kamu memiliki penyimpanan jaringan (NAS) atau folder yang
dibagikan, Cleona bisa memindahkan mediamu ke sana secara otomatis. Yang
didukung adalah SMB, SFTP, FTPS, dan WebDAV.

Begini cara penyimpanan bertingkat:
- 30 hari pertama: Semua tetap di perangkatmu.
- Setelah 30 hari: Gambar pratinjau tetap di perangkat, yang asli
  diarsipkan.
- Setelah 90 hari: Hanya gambar pratinjau kecil yang tetap di perangkat.
- Setelah setahun: Hanya penanda yang tetap, yang asli tersimpan aman di
  arsip.

Kamu bisa kapan saja mengetuk media yang terarsip untuk mengambilnya kembali --
asalkan kamu terhubung ke jaringan rumahmu. Media yang sangat penting bisa
dipasangi pin agar tidak pernah dipindahkan.

Di bawah "Anggaran penyimpanan" kamu menetapkan berapa banyak MB media yang
tetap di perangkat (bawaan: 100 MB di ponsel, 2 GB di komputer). Jika penuh,
media yang paling lama dan tidak dipasangi pin diarsipkan lebih dulu. Yang
asli hanya dihapus jika ia sudah aman di arsip -- pesan teks selalu tetap
ada.

### Transkripsi untuk pesan suara

Jika diaktifkan, pesan suaramu diubah menjadi teks secara lokal di
perangkatmu (dengan model sumber terbuka Whisper). Teks yang ditranskripsi
dikirim bersama rekaman ke lawan bicaramu. Transkripsi terjadi sepenuhnya di
perangkatmu -- tidak ada data yang pergi ke layanan eksternal.

Model mana (tiny, base, small) yang diunduh, kamu atur sekali untuk
perangkat itu; bahasanya (otomatis atau tetap) per identitas.

### Unduh otomatis

Kamu bisa mengatur mulai dari ukuran berapa media akan otomatis diunduh.
Misalnya, kamu bisa membiarkan gambar diunduh otomatis, tetapi memutuskan
secara manual untuk video besar.

### Perangkat

Di bawah "Perangkat" -> "Kelola perangkat" kamu melihat perangkat ini.
Memasangkan perangkat lain hadir di versi berikutnya (Bab 11).

### Jaringan

Cleona tidak memerlukan pengaturan jaringan untuk berfungsi. Ada tiga
saklar jaringan:

- **Penerusan port di router** (bawaan: on). Cleona meminta router-mu sendiri
  untuk membuka pintu bagi Cleona. Jika berhasil, perangkatmu lebih mudah
  dijangkau oleh lain dan membantu jaringan. Cleona di sini hanya berbicara
  dengan router-mu, bukan dengan internet.
- **Entri alamat publik** (bawaan: on). Jika perangkatmu masih terlalu sedikit
  tetangganya, ia mencari di direktori publik (Nostr) titik masuk lain, dan
  jika ia sendiri mudah dijangkau, ia mencatatkan diri di sana. Entri itu
  memuat sebuah alamat, bukan nama dan bukan kontak. Jika kamu mematikannya,
  perangkatmu menemukan tetangga hanya lagi melalui undangan, jaringan lokal,
  dan tetangga yang sudah ia kenal.
- **Lebih sedikit paket penyamaran di Wi-Fi** (bawaan: mati). Di Wi-Fi atau
  dengan kabel, kamu bisa mematikan paket-paket penyamaran kosong. Namun
  kemudian di sana terlihat lagi kapan kamu menulis. Di jaringan seluler
  tidak ada saklar ini -- di sana Cleona toh hanya mengirim satu paket
  penyamaran per menit.

Lalu lintas penyamaran secara keseluruhan tidak bisa dimatikan. Itu
sengaja: Hanya jika ia selalu berjalan, aktivitas perangkatmu tidak
mengungkapkan apakah kamu sedang menulis.

Di atas ketiga saklar itu berada **Mode hemat data**: Di jaringan seluler
Cleona mengusulkannya, tetapi tidak pernah menyalakannya sendiri. Ia
menghemat data, tetapi sebagai gantinya perangkatmu dari luar lebih mudah
dikenali.

Di bawahnya kamu mengatur **"Cache untuk media orang lain"**: Perangkatmu
menyimpan potongan-potongan terenkripsi dari media orang lain hingga 7 hari,
agar media itu mencapai penerimanya (bawaan: 100 MB di ponsel, 1 GB di
komputer). Ukuran yang lebih kecil langsung membebaskan ruangnya --
potongan yang paling lama lebih dulu.

---

## 14. Keamanan

### Apa itu enkripsi pasca-kuantum?

Enkripsi saat ini berdasarkan pada masalah matematika yang sangat sulit
dipecahkan oleh komputer biasa. Komputer kuantum di masa depan bisa
menyelesaikan beberapa masalah ini dengan cepat. Enkripsi pasca-kuantum
menggunakan metode tambahan yang juga tahan terhadap komputer kuantum.

Cleona menggabungkan kedua pendekatan: enkripsi klasik untuk keandalan dan
metode pasca-kuantum untuk keamanan masa depan. Dengan begitu kamu dilindungi
terhadap ancaman saat ini dan masa depan bersamaan.

Untuk setiap pesan dibuat kunci sendiri. Bahkan jika penyerang berhasil
membobol kunci sebuah pesan, ia tidak bisa membaca pesan lain dengannya.

### Mengapa tanpa server lebih aman

Pada messenger biasa, pesan-pesanmu mengalir melalui server penyedia. Bahkan
jika di sana terenkripsi: Penyedia memiliki akses ke metadata (siapa
berkomunikasi kapan dengan siapa, seberapa sering, dari mana) dan dalam
keadaan tertentu harus menyerahkannya atas perintah hakim.

Pada Cleona tidak ada titik pusat seperti itu. Tidak ada tempat di mana
semua metadata berkumpul, dan tidak ada direktori di mana orang bisa mencari
siapa kamu atau siapa yang kamu kenal.

### Siapa yang melihat bahwa kamu sedang menulis dengan seseorang?

Enkripsi melindungi **apa** yang kamu tulis. Sama pentingnya, tidak ada satu
pengamat pun yang mengetahui **dengan siapa** dan **kapan** kamu menulis.
Untuk itu Cleona menjaga begini:

- **Di internet tidak pernah langsung.** Jika perangkatmu mengirim pesan
  langsung ke alamat internet lawan bicaramu, provider-mu bisa melihat dengan
  siapa kamu menulis. Karena itu sebuah pesan di internet selalu melalui
  tetangga tetap kalian: milikmu dan milik lawan bicaramu.
- **Tetangga yang kamu percayai.** Tetangga tetapmu, sedapat mungkin, adalah
  perangkat dari kontakmu sendiri -- hingga tiga yang saat ini dijangkau dari
  luar. Jika satu hilang, kontak lain menggantikan. Sebuah kontak tidak bisa
  dibeli dengan server; simpul sembarang di jaringan bisa. Jika kamu belum
  punya kontak yang terjangkau, Cleona mengambil tetangga lain. Undanganmu
  tidak pernah menyebut satu pun kontakmu, agar tidak ada yang mengetahui
  alamat seorang teman lewat mereka.
- **Kode, bukan nama.** Tetangga-tetangga tidak melihat nama maupun
  pengenal, melainkan hanya sebuah kode. Ia berlaku khusus untuk kalian
  berdua, ke satu arah, untuk satu hari -- keesokan harinya kode lain. Tetanggamu
  tahu dari mana paket datang, tetapi tidak ke mana akhirnya pergi. Tetangga
  lawan bicaramu tahu ke mana ia pergi, tetapi tidak dari mana ia datang.
  Secara normal, tidak ada di tengah jalan yang melihat kedua ujung.
- **Lalu lintas penyamaran.** Perangkatmu terus-menerus, dalam selang yang
  tidak teratur, mengirim paket-paket penyamaran ke tetangganya. Mereka
  sama besar dengan paket asli, melalui port yang sama, dan dari luar tidak
  bisa dibedakan dari paket itu. Apakah sedang ada manusia menulis atau
  perangkat hanya berjalan, tidak bisa terlihat dengannya. Pesanmu tidak
  pernah menunggu lalu lintas penyamaran -- mereka langsung berangkat, lalu
  lintas itu hanya berjalan di samping.

**Apa yang dibayar oleh lalu lintas penyamaran:** Di Wi-Fi sekitar 13 MB per
hari. Di jaringan seluler Cleona hanya mengirim satu paket penyamaran per
menit, itu sekitar 1,7 MB per hari. Alasan pelambatan di jaringan seluler
bukan jumlah data, melainkan baterai: Setiap paket membangunkan modem
radio.

**Apa yang tidak bisa disembunyikan Cleona** -- terus terang:

- Tidak ada pengamat **tunggal** yang melihat siapa menulis dengan siapa --
  bukan provider-mu bukan simpul-simpul di tengah jalan. Tetapi siapa yang
  mengawasi **kedua ujung bersamaan**, misalnya sebuah negara yang mengawasi
  koneksi milikmu dan milik lawan bicaramu atau menangkap kedua tetangga,
  bisa mengaitkan dari waktu ke waktu: Paket keluar di sisimu, segera setelahnya
  paket masuk di sisi lawan bicaramu. Cukup sering diulang, itu menghasilkan
  sebuah keterkaitan.
- Lalu lintas penyamaran mempersulit pengaitan ini, tetapi tidak mencegahnya.
  Ia menyembunyikan pesan-pesan individual, bukan volume: Siapa yang mengirim
  sangat banyak, menambah lalu lintas total perangkatnya.
- Seorang kontak yang menjadi tetangga tetapmu, mengetahui **kapan** dan
  **berapa banyak** kamu mengirim dan menerima -- bukan dengan siapa dan
  bukan apa. Jika ancaman datang dari lingkunganmu sendiri, kamu bisa
  mengecualikan setiap kontak dari itu (lihat Bab 3, "Jangan pernah digunakan
  sebagai tetangga tetap").
- Jika dua pengguna baru hanya memiliki satu tetangga yang sama, pesan mereka
  mengalir melalui simpul itu tepat, dan ia melihat kedua ujung. Begitu salah
  satu dari keduanya memiliki tetangga lain, hal itu berakhir.
- Undanganmu memuat alamat-alamat internetmu. Siapa pun yang memiliki baris
  teks itu melihat di mana kamu online -- berikan hanya kepada orang yang
  kamu percayai dengan itu.
- Seorang tetangga yang meneruskan melihat bahwa dua kode saling bertukar
  paket -- bukan siapa di baliknya, dan bukan apa isinya.
- Sebuah sinyal dari panggilan yang sedang berlangsung bisa, jika tetangga
  pertama saat itu tidak menjawab, melalui sebuah simpul yang melihat kedua
  ujung; ia mengetahui bahwa kalian menelepon bersama.
- Sebuah berkas besar yang kamu setujui dilihat oleh komputer yang
  meneruskannya atau menyimpannya di kedua ujung (lihat Bab 4).
- Pada panggilan, perlindungan terhadap provider tidak berlaku, dan kontakmu
  melihat alamat internetmu (lihat Bab 7).

### Apa yang terjadi jika lawan bicaramu offline?

1. Cleona memulai semua jalur yang cocok bersamaan: di Wi-Fi yang sama
   langsung, di internet melalui dua tetangga -- dan tambahan kotak surat.
2. Untuk kotak surat, Cleona menitipkan pesan terenkripsi kepada tiga
   tetangga. Begitu dua mengonfirmasi penerimaan, pesan dianggap diletakkan.
3. Cleona untuk itu lebih memilih tetangga di mana lawan bicaramu juga
   memeriksa -- pertama tetangga yang disebut undangannya.
4. Pesan menunggu di sana hingga 7 hari. Jika lawan bicaramu kembali, ia
   mengambilnya dan mengonfirmasi penerimaan kepadamu. Baru kemudian kamu
   melihat dua centang.

Kotak surat hanya bisa dikosongkan oleh lawan bicaramu: Mengambil dan
menghapus hanya bisa dengan kunci yang hanya ia miliki, dan penghapusan baru
dilakukan setelah ia mengonfirmasi penerimaan. Tetangga-tetangga hanya
melihat paket-paket terenkripsi di bawah nilai yang berubah setiap hari.

### Orang asing tidak bisa lewat

Dari seseorang yang bukan kontakmu maupun anggota grup bersama, Cleona
menerima tepat dua hal: pertanyaan
tentang kunci publikmu, selama salah satu undanganmu masih terbuka, dan
permintaan kontak. Permintaan harus membawa undangan yang valid darimu, dan
pengirim harus sebelumnya menyelesaikan tugas komputasi. Semua yang lain --
pesan, panggilan, berkas -- dibuang sebelum mencapai aplikasi sama sekali.
Yang hanya punya kartu nama tercetakmu tidak bisa begitu saja meneleponmu.
Seorang anggota grup bersama hanya bisa menjangkaumu di grup itu -- dengan
pesan grup dan panggilan grup, tidak pernah satu lawan satu.

### Anti-sensor

Cleona dibuat sehingga sulit diblokir:

- **Tanpa server, tanpa alamat tetap.** Di aplikasi tidak ada alamat yang
  bisa diblokir, dan jaringan tidak bergantung pada satu simpul pun.
- **Tanpa port tetap.** Setiap perangkat memilih port acak saat pertama kali
  dinyalakan. Tidak ada nomor port yang dikenal di mana lalu lintas Cleona
  bisa dikenali.
- **Seperti data acak.** Pembentukan koneksi antara dua perangkat dikodekan
  sedemikian rupa sehingga tidak bisa dibedakan dari data acak.
- **Banyak titik masuk.** Setiap undangan, setiap tetangga, dan setiap
  perangkat di Wi-Fi yang sama adalah jalur yang mungkin kembali ke
  jaringan.

### Penyimpanan kunci yang aman

Di platform yang didukung, Cleona menyimpan kunci enkripsi-mu di gantungan
kunci aman sistem operasi (Android Keystore, iOS Keychain, macOS Keychain).
Jika tersedia, hal itu menawarkan perlindungan berbasis perangkat keras untuk
kunci-mu.

### Enkripsi basis data

Pesan dan percakapanmu berada dalam basis data terenkripsi -- satu sendiri
untuk setiap identitas, masing-masing dengan kunci sendiri. Tidak hanya
basis datanya sendiri yang dienkripsi, tetapi juga berkas-berkas sementara-
nya; tidak ada yang ditulis ke disk tanpa enkripsi, bahkan sebentar. Pengaturan,
kontak, dan media juga disimpan terenkripsi.

Kunci diturunkan dari 24 katamu dan hanya ada di perangkatmu. Bahkan siapa
yang mendapatkan perangkatmu dan membaca datanya, tanpa kunci ini hanya
menemukan data yang tidak terbaca.

Tanpa enkripsi hanya jika kamu sendiri mengeluarkan isi dari Cleona:
- jika kamu menyimpan sebuah berkas dari obrolan ke perangkatmu,
- jika kamu dengan tombol tangkapan layar meletakkan sebuah gambar ke
  galeri gambarmu,
- jika kamu membagikan sesuatu ke aplikasi lain,
- jika kamu menyiapkan pengarsipan media (Bab 13): Yang asli terarsip
  berada tanpa enkripsi di penyimpanan jaringan rumahmu, agar kamu bisa
  membukanya di sana juga tanpa Cleona,
- jika kamu mencerminkan janji ke kalender sistem Android: Di sana aplikasi
  lain dengan akses kalender bisa membacanya.

Apa yang sudah keluar begitu tidak ikut terhapus bersama pesan dan tidak
ikut berakhir bersamanya.

### Perlindungan di layar

Di Android, Windows, dan macOS, Cleona tidak mengizinkan perekaman layar
oleh aplikasi lain. Jika kamu butuh sebuah gambar, gunakan tombol tangkapan
layar di bilah atas: Ia meletakkan gambar itu ke galeri gambarmu -- tanpa
enkripsi. Dalam sebuah percakapan yang tidak mengizinkan meneruskan, tidak
ada tangkapan layar.

---

## 15. Pembaruan perangkat lunak

### Bagaimana saya mendapatkan pembaruan?

Cleona bisa diperbarui melalui berbagai cara. Tujuannya adalah agar kamu bisa
menerima pembaruan bahkan ketika jalur distribusi individual gagal atau
diblokir:

1. **App Store / Play Store:** Begitu Cleona tersedia di sana dan kamu
   memasangnya melalui sebuah store, kamu menerima pembaruan seperti biasa
   melalui store. Di iPhone, pembaruan datang melalui TestFlight.
2. **GitHub Releases:** Di halaman GitHub proyek kamu menemukan paket
   instalasi bertanda tangan untuk semua platform.
3. **Pembaruan melalui jaringan:** Cleona bisa mengambil pembaruan langsung
   melalui jaringan -- tanpa server unduhan. Versi baru dipecah menjadi
   potongan-potongan terkoreksi yang tersebar di jaringan; sebagian dari
   potongan itu bahkan ikut bepergian dalam lalu lintas penyamaran. Perangkatmu
   mengumpulkan cukup potongan dan menyusun pembaruan. Yang ditransfer
   biasanya hanya perubahannya -- beberapa MB saja, bukan seluruh aplikasi.
   Itu berlaku untuk Linux, Windows, dan Android; di macOS kamu mengunduh
   versi baru dari situs web atau dari GitHub.
4. **Tautan undangan:** Kamu bisa membuat tautan undangan yang memuat semua
   yang dibutuhkan pengguna baru untuk memasang Cleona dan terhubung dengan
   jaringan.
5. **Transfer fisik:** Di lingkungan tanpa internet, kamu bisa membagikan
   Cleona kepada lain melalui USB-stick atau di jaringan lokal.

### Begini jalannya pembaruan

1. Cleona mengumpulkan potongan-potongan pembaruan baru otomatis di latar
   belakang dan menyusunnya.
2. Baru ketika pembaruan **lengkap** dan **tanda tangannya diperiksa**,
   Cleona menawarkannya kepadamu. Kamu jadi tidak pernah ditawari
   pembaruan yang setengah atau belum diperiksa.
3. Jika kamu mengetuk "Pasang", pemasangan dimulai tanpa pertanyaan lagi.
   Di Android, tambahan sistem menampilkan dialog pemasangannya.

Versi yang lebih lama tidak ditawarkan -- pembaruan selalu hanya maju. Jika
sebuah versi sudah begitu lama sehingga tidak bisa lagi bekerja sama dengan
jaringan, Cleona menunjukkan hal itu dengan jelas dan memintamu untuk
memperbarui.

### Pemeriksaan tanda tangan

Setiap pembaruan ditandatangani dua kali: dengan metode klasik dan pasca-
kuantum. Cleona memeriksa kedua tanda tangan otomatis. Dengan begitu
dipastikan bahwa hanya pembaruan dari pengembang resmi yang diterima --
bahkan jika pembaruan datang melalui jaringan dari perangkat asing.
Pembaruan tidak pernah dibuat otomatis dari pengembangan, melainkan hanya
ketika pengembang menandatanganinya dengan tangan.

---
## 16. Pertanyaan yang sering diajukan

### "Apakah saya bisa menggunakan Cleona tanpa internet?"

Cleona memerlukan koneksi jaringan, tetapi tidak harus internet: Di Wi-Fi
yang sama, perangkat-perangkat Cleona saling menemukan sendiri dan bisa saling
menulis tanpa akses internet. Kalian tidak harus bersamaan online: Jika ia
offline, pesan menunggu hingga 7 hari di kotak surat di tiga tetangga, sampai
ia mengambilnya.

### "Bagaimana jika saya kehilangan frasa seed?"

Selama masih ada perangkat dengan identitasmu yang berjalan, tidak ada yang
hilang -- di sana kamu tinggal melanjutkan menulis. Di perangkat tempat kamu
membuat identitas, kamu biasanya bisa membaca 24 kata lagi (lihat
Bab 2). Jangan bersandar pada itu: Pemasangan ulang menghapus salinan itu,
dan di Android menghapus atau mengubah kunci layar juga memusnahkannya.
Jika kamu tidak punya kata-kata maupun
perangkat, tidak ada jalan kembali -- bahkan tidak melalui kontakmu,
pengembang, atau siapa pun. Karena itu begitu penting menyimpan 24
kata dengan aman.

### "Apakah ada yang bisa membaca pesan saya?"

Tidak. Setiap pesan dienkripsi dengan kunci sekali pakai yang hanya berlaku
untuk pesan itu. Hanya kamu dan lawan bicaramu yang bisa mendekripsi pesan.
Tidak ada server pusat, tidak ada kunci induk, dan tidak ada akses untuk
pengembang. Bahkan jika sebuah perangkat di jalur transport meneruskan pesan,
ia hanya melihat data terenkripsi yang berantakan dan sebuah kode. Tetanggamu
tahu bahwa paket itu datang darimu, tetapi tidak kepada siapa ia pergi;
tetangga lawan bicaramu tahu kepada siapa ia pergi, tetapi tidak dari siapa.

### "Mengapa saya tidak memerlukan nomor telepon?"

Karena identitasmu murni kriptografis. Daripada nomor telepon atau alamat
email yang dikaitkan dengan namamu asli, sepasang kunci yang dibuat di
perangkatmu mengidentifikasikanmu. Kontak kamu tambahkan melalui kode QR, NFC,
atau baris teks undanganmu -- bukan melalui buku telepon. Itu berarti
lebih banyak privasi, karena akun messenger-mu tidak terikat pada identitas
nyatamu.

### "Bagaimana saya menemukan orang di Cleona?"

Cleona sengaja tidak memiliki pencarian kontak berdasarkan nomor telepon atau
nama -- itu akan jadi masalah privasi. Sebagai gantinya, kamu bertukar
undangan langsung: melalui kode QR, NFC, atau sebagai baris teks melalui cara
lain. Itu seperti bertukar kartu nama daripada mencari di buku telepon.

### "Apakah Cleona berfungsi juga di luar negeri?"

Ya. Selama kamu punya koneksi internet, Cleona berfungsi di mana pun di dunia.
Karena tidak ada server pusat dan tidak ada alamat tetap, layanan tidak bisa
begitu saja dimatikan untuk negara tertentu. Bagaimana Cleona mempersulit
blokir, ada di bab "Keamanan" di bawah "Anti-sensor". Namun, sebuah negara
yang memblokir setiap lalu lintas asing di perbatasan bisa juga menghentikan
Cleona.

### "Apakah Cleona gratis?"

Ya. Cleona bisa digunakan gratis dan tanpa iklan. Karena tidak ada server
pusat, tidak ada juga biaya server untuk operasi. Di pengaturan di bawah
"Dukung Cleona" -> "Donasi" kamu bisa mendukung pengembangan secara sukarela.

### "Pesan saya hanya ada satu centang -- apa artinya?"

Pesan sedang dalam perjalanan, tetapi lawan bicaramu belum mengonfirmasi
penerimaan -- kebanyakan karena ia sedang offline. Itu bukan kesalahan: Pesan
menunggu hingga 7 hari di kotak surat. Begitu ia mengambilnya, kamu melihat
dua centang. Jam berarti belum ada jalur yang mengantarkan pesan -- ia
berangkat sendiri begitu ada jalur; tanda peringatan berarti pesan selama
14 hari tidak menemukan jalur dan kamu bisa mengirimnya kembali.

### "Mengapa pesan tiba terlambat di iPhone saya?"

iOS tidak membiarkan aplikasi berjalan terus-menerus di latar belakang.
Cleona hanya dibangunkan sebentar sesekali; iOS yang menentukan kapan. Cleona
lalu mengambil semuanya. Begitu kamu membuka aplikasi, Cleona mengambil yang
disimpan untukmu.

### "Apakah saya bisa berpindah dari WhatsApp ke Cleona?"

Ya, tetapi kamu tidak bisa memindahkan obrolan WhatsApp-mu. Cleona dan
WhatsApp adalah sistem yang sangat berbeda. Kamu harus menambahkan kontakmu
satu per satu di Cleona. Paling mudah jika kamu mengirim baris teks
undanganmu ke kontakmu. Setiap permintaan yang datang begitu, kamu konfirmasi
sendiri di bawah "Permintaan".

### "Apakah saya bisa menggunakan Cleona di beberapa perangkat bersamaan?"

Belum. Perangkat kedua untuk identitas yang sama hadir di versi berikutnya
(Bab 11). Di beberapa perangkat, kamu hari ini bisa menggunakan identitas
yang berbeda-beda.

### "Bagaimana saya mendapatkan pembaruan jika App Store diblokir?"

Cleona bisa mengambil pembaruan langsung melalui jaringan, tanpa bergantung
pada App Store, situs web, atau server unduhan. Jika perangkat lain di
jaringan memiliki versi terbaru, perangkatmu bisa mengambil pembaruan dari
sana. Keaslian diperiksa melalui tanda tangan digital pengembang. Sebagai
alternatif, sebuah kontak bisa membagikan aplikasi kepadamu melalui tautan
undangan atau USB-stick. Lebih lanjut di bab "Pembaruan perangkat lunak".

---

## Bantuan dan kontak

Jika kamu punya pertanyaan atau menemui masalah, kamu menemukan informasi
terkini di situs web Cleona dan di GitHub. Karena Cleona adalah proyek
terdesentralisasi, tidak ada dukungan pelanggan klasik -- tetapi komunitas
aktif yang dengan senang hati membantu.

---

*Manual ini menjelaskan Cleona Chat versi 4.2. Fungsi-fungsi individual
bisa berubah atau bertambah di versi yang lebih baru.*