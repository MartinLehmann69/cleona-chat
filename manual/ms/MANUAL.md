# Cleona Chat -- Manual Pengguna

Version 3.1.125 | Julai 2026

---

## Kandungan

1. [Apakah itu Cleona Chat?](#1-was-ist-cleona-chat)
2. [Langkah Pertama](#2-erste-schritte)
3. [Kontak](#3-kontakte)
4. [Mesej](#4-nachrichten)
5. [Kumpulan](#5-gruppen)
6. [Saluran Awam](#6-oeffentliche-kanaele)
7. [Panggilan](#7-anrufe)
8. [Kalendar](#8-kalender)
9. [Tinjauan](#9-umfragen)
10. [Pelbagai Identiti](#10-mehrere-identitaeten)
11. [Multi-Peranti](#11-multi-device)
12. [Pemulihan](#12-wiederherstellung)
13. [Tetapan](#13-einstellungen)
14. [Keselamatan](#14-sicherheit)
15. [Kemas Kini Perisian](#15-software-updates)
16. [Soalan Lazim](#16-haeufige-fragen)

---

## 1. Apakah itu Cleona Chat?

### Messenger anda, data anda

Cleona Chat ialah messenger yang beroperasi sepenuhnya tanpa pelayan pusat.
Mesej anda bergerak terus dari peranti anda ke peranti rakan bicara anda --
tanpa melalui mana-mana pejabat syarikat, tanpa cloud, tanpa pusat data.
Tiada syarikat boleh membaca, menyimpan atau berkongsi mesej anda kerana
memang tiada syarikat yang berada di tengah-tengah.

### Tiada akaun, tiada nombor telefon

Dengan Cleona, anda tidak memerlukan nombor telefon atau alamat e-mel untuk
mendaftar. Identiti anda terdiri daripada sepasang kunci kriptografi yang
dijana secara automatik pada peranti anda semasa permulaan pertama. Ini
bermakna: tiada sesiapa dapat mengesan anda melalui nombor telefon atau
alamat e-mel, melainkan anda sendiri berkongsi maklumat hubungan anda.

### Penyulitan tahan masa depan

Cleona menggunakan apa yang dipanggil penyulitan pasca-kuantum
(post-quantum). Ini bermakna: walaupun komputer kuantum masa depan tidak
akan dapat memecahkan mesej anda. Anda tidak perlu memahami butiran
teknikalnya -- yang penting ialah komunikasi anda dilindungi dengan sebaik
mungkin mengikut tahap teknologi terkini.

### Bagaimana ia berfungsi tanpa pelayan?

Bayangkan anda dan kontak anda membentuk satu rangkaian bersama. Setiap
peranti membantu menghantar mesej. Jika rakan bicara anda sedang dalam
talian, mesej terus sampai kepadanya. Jika rakan bicara anda sedang luar
talian, kontak bersama akan menyimpan mesej itu buat sementara waktu dan
menghantarnya sebaik sahaja penerima kembali dalam talian. Jadi kontak anda
juga adalah rangkaian anda.

### Platform

Cleona tersedia untuk Android, iOS, macOS, Linux dan Windows.

---

## 2. Langkah Pertama

### Memasang aplikasi

**Android:**
1. Muat turun fail APK daripada laman web Cleona atau daripada GitHub Releases.
2. Buka fail tersebut pada telefon anda. Jika perlu, benarkan pemasangan
   daripada sumber tidak dikenali (Android akan bertanya secara automatik).
3. Ketik "Pasang" dan tunggu sehingga pemasangan selesai.

**iOS:**
1. Buka pautan jemputan TestFlight pada iPhone anda.
2. Ketik "Pasang". TestFlight ialah cara rasmi Apple untuk mengedarkan
   aplikasi beta.
3. Selepas pemasangan, anda akan menemui Cleona pada skrin utama anda.

**macOS:**
1. Muat turun fail DMG daripada laman web Cleona atau daripada GitHub Releases.
2. Buka fail DMG dan seret Cleona ke dalam folder Applications anda.
3. Semasa permulaan pertama, macOS mungkin bertanya sama ada anda mahu
   membuka aplikasi daripada pembangun yang dikenal pasti -- sahkan ini.

**Linux (Ubuntu/Debian):**
1. Muat turun fail .deb daripada laman web Cleona atau daripada GitHub Releases.
2. Pasang dengan dwi-klik atau dalam terminal: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Mulakan Cleona melalui menu aplikasi atau dalam terminal dengan `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Muat turun fail .rpm daripada laman web Cleona atau daripada GitHub Releases.
2. Pasang dengan: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Mulakan Cleona melalui menu aplikasi atau dalam terminal dengan `cleona-chat`.

**Linux (semua distro -- AppImage):**
1. Muat turun fail .AppImage daripada laman web Cleona atau daripada GitHub Releases.
2. Jadikan fail tersebut boleh dilaksanakan: klik kanan, Properties, Executable,
   atau dalam terminal: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Mulakan dengan dwi-klik atau dalam terminal: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Muat turun installer daripada laman web Cleona atau daripada GitHub Releases.
2. Jalankan fail pemasangan dan ikut arahan yang diberikan.
3. Mulakan Cleona melalui menu Start atau pintasan desktop.

### Mencipta identiti

Semasa permulaan pertama, Cleona secara automatik mencipta identiti baharu
untuk anda. Anda boleh memberikan nama paparan -- iaitu nama yang akan
dilihat oleh kontak anda. Nama ini boleh diubah pada bila-bila masa.

### Menulis Seed-Phrase -- perkara paling penting sekali

Selepas identiti anda dicipta, Cleona akan memaparkan 24 patah perkataan.
Ini ialah **Seed-Phrase** anda -- kunci pemulihan peribadi anda.

**Tuliskan 24 perkataan ini di atas kertas dan simpan di tempat yang selamat.**

Kenapa ini begitu penting?

- Jika telefon anda rosak, hilang atau dicuri, anda boleh menggunakan 24
  perkataan ini untuk memulihkan keseluruhan identiti anda pada peranti
  baharu.
- Tanpa Seed-Phrase, tiada jalan untuk kembali. Tiada butang "lupa kata
  laluan" dan tiada sokongan pelanggan yang boleh mengembalikan akaun anda
  -- kerana memang tiada akaun pada mana-mana pelayan.
- Jangan sekali-kali berkongsi Seed-Phrase dengan orang lain. Sesiapa yang
  mengetahui perkataan ini boleh menyamar sebagai anda.

Anda juga boleh menemui Seed-Phrase kemudian dalam tetapan di bawah
"Keselamatan", sekiranya anda mahu melihatnya semula.

### Menambah kontak pertama

Untuk berbual dengan seseorang, anda perlu menambah orang tersebut sebagai
kontak terlebih dahulu. Terdapat beberapa cara untuk melakukan ini --
semuanya diterangkan dalam bahagian seterusnya.

---

## 3. Kontak

### Mengimbas QR-Code (disyorkan)

Cara paling mudah untuk menambah kontak:

1. Rakan bicara anda membuka halaman butiran identitinya (ketik nama sendiri
   pada bar atas) dan menunjukkan QR-Code miliknya kepada anda.
2. Anda ketik butang tambah (+) dan pilih "Imbas QR-Code".
3. Halakan telefon anda ke QR-Code rakan bicara anda.
4. Permintaan kontak akan dihantar secara automatik. Sebaik sahaja rakan
   bicara anda menerimanya, anda berdua boleh mula berbual.

Jika anda bertemu secara peribadi, QR-Code ialah kaedah paling selamat
kerana anda tahu dengan pasti dengan siapa anda bertukar kontak.

### NFC (rapatkan telefon)

Jika kedua-dua peranti menyokong NFC:

1. Kedua-dua pihak membuka fungsi Tambah Kontak.
2. Rapatkan belakang telefon kedua-dua pihak antara satu sama lain.
3. Maklumat kontak akan bertukar secara automatik.

Seperti QR-Code, NFC menawarkan tahap keselamatan yang tinggi kerana
pertukaran hanya berfungsi jika anda berdiri bersebelahan secara fizikal.

### Berkongsi pautan (URI cleona://)

Anda juga boleh menghantar pautan kontak anda melalui e-mel, SMS, atau
melalui messenger lain:

1. Buka halaman butiran identiti anda.
2. Salin pautan cleona:// anda.
3. Hantar pautan tersebut kepada orang yang ingin menambah anda.
4. Orang lain itu membuka pautan tersebut, atau menampalnya dalam dialog
   Tambah Kontak.

Perhatian: dengan kaedah ini, anda mempercayai bahawa pautan tersebut tidak
diubah semasa dihantar. Untuk kontak yang amat sensitif, kami syorkan
menggunakan QR-Code atau NFC.

### Menerima permintaan kontak

Apabila seseorang menghantar permintaan kontak kepada anda, ia akan muncul
dalam Peti Masuk anda (tab terakhir pada bar bawah). Di situ anda boleh:

- **Terima** -- orang tersebut ditambah ke dalam kontak anda.
- **Tolak** -- permintaan tersebut dibuang.
- **Sekat** -- orang tersebut tidak boleh menghantar sebarang permintaan
  lagi kepada anda.

### Tahap Pengesahan

Cleona menunjukkan sejauh mana identiti sesuatu kontak telah disahkan:

| Tahap | Maksud |
|-------|-----------|
| Tidak Diketahui | Anda hanya menerima Node-ID atau pautan. |
| Dilihat | Pertukaran kunci berjaya, anda berdua boleh berkomunikasi secara tersulit. |
| Disahkan | Anda berdua telah bertemu secara peribadi dan mengesahkan melalui QR-Code atau NFC. |
| Dipercayai | Anda telah menandakan kontak ini secara khusus sebagai boleh dipercayai. |

Semakin tinggi tahapnya, semakin yakin anda bahawa anda benar-benar bercakap
dengan orang yang betul.

---

## 4. Mesej

### Menghantar dan menerima teks

Taip sahaja mesej anda dalam medan input di bawah dan tekan Enter atau
butang Hantar. Mesej anda disulitkan secara automatik sebelum meninggalkan
peranti anda.

Mesej masuk akan dipaparkan dalam sejarah perbualan. Tanda semak menunjukkan
sama ada mesej anda telah dihantar sampai.

### Menghantar gambar, video dan fail

Anda mempunyai beberapa cara:

- **Ikon Klip Kertas** dalam medan input: Ketik untuk memilih fail, gambar
  atau video daripada galeri atau sistem fail anda.
- **Seret dan Lepas** (Desktop): Seret sahaja fail ke dalam tetingkap chat.
- **Tampal daripada Papan Klip** (Desktop): Salin gambar dan tampalkannya
  dalam chat.

Fail kecil (di bawah 256 KB) akan dihantar terus bersama mesej. Fail yang
lebih besar dihantar melalui proses dua peringkat: fail diumumkan dahulu,
kemudian dihantar secara berperingkat.

### Mesej suara

1. Tekan dan tahan butang mikrofon dalam medan input.
2. Rakam mesej anda.
3. Lepaskan butang untuk menghantar mesej.

Jika pengecaman suara diaktifkan pada peranti anda (lihat Tetapan), mesej
suara anda akan ditranskripsikan secara automatik menjadi teks. Rakan bicara
anda kemudiannya akan melihat kedua-dua rakaman dan teks yang
ditranskripsikan.

### Membalas mesej (Petik)

Untuk membalas mesej tertentu:

1. Buka menu tiga titik di sebelah mesej.
2. Pilih "Balas".
3. Banner dengan mesej yang dipetik akan muncul di atas medan input.
4. Tulis balasan anda dan hantar.

Mesej yang dipetik akan dipaparkan dalam balasan anda supaya kaitannya
jelas.

### Menyunting dan memadam mesej

- **Sunting:** Menu tiga titik pada mesej, kemudian "Sunting". Ubah teks dan
  hantar semula. Rakan bicara anda akan nampak bahawa mesej itu telah
  disunting. Penyuntingan boleh dilakukan dalam masa 15 minit selepas
  dihantar.
- **Padam:** Menu tiga titik pada mesej, kemudian "Padam". Mesej akan
  dibuang daripada peranti anda dan rakan bicara anda. Anda boleh memadam
  mesej anda sendiri pada bila-bila masa -- tiada had masa untuk pemadaman.

### Reaksi Emoji

Daripada menulis balasan, anda boleh bereaksi kepada mesej dengan emoji:

1. Buka menu tiga titik atau tekan dan tahan mesej tersebut.
2. Pilih emoji daripada pilihan pantas atau buka pemilih emoji untuk pilihan
   penuh.
3. Reaksi anda akan muncul di bawah mesej.

### Menyalin teks

Melalui menu tiga titik pada sesuatu mesej, anda boleh menyalin teks mesej
ke papan klip.

### Mencari mesej

Di bahagian atas tetingkap chat, anda akan menemui fungsi carian. Masukkan
kata kunci carian, dan Cleona akan menunjukkan semua hasil yang sepadan
dalam chat semasa. Anda boleh melompat antara hasil menggunakan kekunci anak
panah.

Di skrin utama, terdapat juga penapis carian merentas tab, yang membolehkan
anda mencari kata kunci dalam semua perbualan.

### Pratonton pautan

Apabila anda menghantar pautan, Cleona secara automatik menjana pratonton
(tajuk, penerangan, imej pratonton). Pratonton ini dijana oleh peranti anda
dan dihantar bersama mesej -- rakan bicara anda tidak perlu membuat sebarang
permintaan rangkaian ke laman web yang dipautkan.

Apabila anda ketik pautan yang diterima, anda akan ditanya sama ada anda
mahu membukanya dalam pelayar biasa, dalam mod inkognito, atau tidak
membukanya langsung.

---

## 5. Kumpulan

### Mencipta kumpulan

1. Beralih ke tab "Kumpulan".
2. Ketik butang tambah (+).
3. Berikan nama kepada kumpulan tersebut.
4. Pilih kontak yang ingin anda jemput.
5. Ketik "Cipta".

Kontak yang dijemput akan menerima pemberitahuan dan boleh menyertai
kumpulan tersebut.

### Menjemput ahli

Anda juga boleh menjemput kontak tambahan selepas kumpulan dicipta:

1. Buka Maklumat Kumpulan (menu tiga titik dalam senarai kumpulan atau bar
   atas dalam chat kumpulan).
2. Ketik "Jemput".
3. Pilih kontak yang ingin anda tambah.

### Peranan

Setiap kumpulan mempunyai tiga peranan:

- **Pemilik (Owner):** Mempunyai kawalan penuh. Boleh menambah dan
  mengeluarkan ahli, melantik Admin, dan menguruskan kumpulan. Pemilik juga
  boleh memindahkan statusnya kepada ahli lain.
- **Admin:** Boleh mengeluarkan ahli dan membantu dalam pengurusan.
- **Ahli:** Boleh membaca dan menulis mesej.

### Meninggalkan kumpulan

1. Buka menu tiga titik dalam senarai kumpulan.
2. Pilih "Keluar".
3. Sahkan keputusan anda.

Apabila anda meninggalkan sesuatu kumpulan, mesej anda yang sedia ada akan
kekal boleh dilihat oleh ahli lain.

---

## 6. Saluran Awam

### Apakah saluran?

Saluran ialah forum perbincangan awam dalam rangkaian Cleona. Berbeza
dengan kumpulan, sesiapa sahaja boleh membaca di sini tanpa perlu dijemput.
Hanya pemilik dan Admin boleh menerbitkan kandungan -- pelanggan
(subscriber) hanya membaca.

### Mencari dan menyertai saluran

1. Beralih ke tab "Saluran".
2. Buka tab "Carian".
3. Cari saluran yang tersedia mengikut nama atau topik.
4. Ketik saluran tersebut dan kemudian "Langgan".

Saluran boleh ditapis mengikut bahasa. Sesetengah saluran ditanda sebagai
"Bukan Untuk Bawah Umur" -- ini hanya kelihatan jika anda telah mengesahkan
dalam profil anda bahawa umur anda melebihi 18 tahun.

### Mencipta saluran sendiri

1. Beralih ke tab "Saluran".
2. Ketik butang tambah (+).
3. Masukkan nama saluran (mesti unik dalam keseluruhan rangkaian).
4. Pilih bahasa dan sama ada saluran tersebut awam atau peribadi.
5. Pilihan: Tambah penerangan dan gambar.
6. Ketik "Cipta".

Untuk saluran awam, anda boleh menetapkan sama ada kandungan tersebut
dikategorikan sebagai "Bukan Untuk Bawah Umur".

### Melaporkan kandungan

Jika anda menemui kandungan yang tidak sesuai dalam sesuatu saluran awam,
anda boleh melaporkannya. Cleona menggunakan sistem moderasi
terdesentralisasi: laporan dinilai oleh ahli rangkaian yang dipilih secara
rawak (sejenis "juri"). Jika pelanggaran disahkan, saluran tersebut akan
menerima amaran. Jika pelanggaran berulang, saluran itu akan diturunkan
tarafnya dalam indeks carian atau disekat.

### Saluran Sistem

Cleona mempunyai dua saluran sistem terbina dalam:

- **Bug Log:** Apabila Cleona mengesan ralat, ia akan bertanya sama ada anda
  mahu menghantar laporan ralat yang dinamakan semula (anonymised). Laporan
  ini akan berakhir di saluran Bug Log, di mana ia boleh dilihat oleh
  komuniti. Tiada data peribadi dihantar -- hanya penerangan ralat teknikal.
  Anda juga boleh menghantar laporan log secara manual (dengan dialog
  pratonton dan persetujuan yang jelas).
- **Feature Requests:** Di sini pengguna boleh menghantar cadangan ciri dan
  mengundi cadangan sedia ada. Cadangan disusun mengikut undian.

Kedua-dua saluran sistem mempunyai had saiz 25 MB dan dipantau oleh sistem
moderasi juri.

---

## 7. Panggilan

### Memulakan panggilan suara

1. Buka chat dengan kontak yang ingin anda hubungi.
2. Ketik ikon telefon pada bar atas.
3. Tunggu sehingga rakan bicara anda menerima panggilan.

Semasa perbualan, anda akan melihat garis masa yang menunjukkan tempoh
panggilan, dan mempunyai akses kepada fungsi senyap (mute) dan pembesar
suara.

Untuk menamatkan panggilan, ketik butang merah Tamatkan Panggilan.

### Memulakan panggilan video

1. Buka chat dengan kontak tersebut.
2. Ketik ikon kamera pada bar atas.
3. Video anda akan muncul dalam tetingkap kecil, manakala video rakan bicara
   anda dipaparkan di kawasan besar.

Anda boleh menukar antara kamera depan dan belakang semasa perbualan.

### Panggilan masuk

Apabila seseorang menghubungi anda, satu tetingkap pemberitahuan akan
muncul dengan nama pemanggil. Anda boleh:

- **Terima** -- perbualan bermula.
- **Tolak** -- pemanggil akan diberitahu.

Jika anda sudah berada dalam satu panggilan, panggilan baharu akan ditolak
secara automatik.

### Panggilan kumpulan

Anda juga boleh membuat panggilan kumpulan yang disertai oleh beberapa
orang serentak. Panggilan diuruskan melalui pokok penghalaan pintar
(routing tree), supaya tidak setiap peserta perlu bersambung terus dengan
setiap peserta lain. Semua perbualan disulitkan hujung ke hujung sepanjang
masa.

### Penyulitan panggilan

Semua panggilan disulitkan menggunakan kunci sekali guna yang hanya wujud
sepanjang tempoh perbualan. Selepas panggilan tamat, kunci tersebut dipadam
serta-merta. Tiada sesiapa boleh menyahsulit perbualan yang telah lalu.

---

## 8. Kalendar

Cleona mempunyai kalendar terbina dalam yang berfungsi secara tersulit dan
sepenuhnya terdesentralisasi -- tanpa perkhidmatan cloud.

### Paparan

Kalendar menawarkan lima paparan: Hari, Minggu, Bulan, Tahun dan paparan
Tugasan. Beralih antaranya melalui tab pada bahagian atas skrin kalendar.

### Mencipta acara

Ketik slot masa atau gunakan butang Tambah untuk mencipta acara baharu.
Anda boleh memasukkan tajuk, tarikh, masa, lokasi dan nota. Acara disimpan
secara tersulit pada peranti anda.

### Acara berulang

Acara boleh berulang secara harian, mingguan, bulanan atau tahunan. Anda
boleh menyesuaikan corak (contohnya setiap Selasa kedua, setiap hari
pertama bulan) dan menetapkan tarikh tamat atau bilangan ulangan.

### Menjemput kontak

Semasa mencipta atau menyunting acara, anda boleh menjemput kontak Cleona
anda. Mereka akan menerima jemputan kalendar yang disulitkan dan boleh
membalas dengan Terima, Tolak atau Mungkin. Sebarang perubahan pada acara
akan dihantar secara automatik kepada semua yang dijemput.

### Paparan Lapang/Sibuk

Anda boleh berkongsi ketersediaan anda dengan kontak tanpa mendedahkan
butiran acara. Terdapat tiga tahap privasi: butiran penuh, hanya blok masa,
atau tersembunyi. Anda boleh menetapkan tetapan lalai dan mengatasinya
(override) mengikut kontak.

### Peringatan

Acara boleh mempunyai peringatan yang akan mencetuskan pemberitahuan
sistem sebelum acara bermula. Anda boleh menangguhkan (snooze) peringatan
jika perlu.

### Penyegerakan kalendar luaran

Cleona boleh menyegerakkan dengan perkhidmatan kalendar luaran:

- **CalDAV** -- Sambung ke mana-mana pelayan yang serasi dengan CalDAV
  (Nextcloud, Radicale dan sebagainya).
- **Google Calendar** -- Penyegerakan melalui Google Calendar API dengan
  pengesahan OAuth2 yang selamat.
- **Pelayan CalDAV Tempatan** -- Cleona boleh menjalankan pelayan CalDAV
  tempatan pada peranti anda, membolehkan aplikasi kalendar desktop
  (Thunderbird, Outlook, Apple Calendar, Evolution) menyegerak dengan
  kalendar Cleona anda.
- **Kalendar Sistem Android** -- Acara daripada Cleona boleh dipindahkan ke
  aplikasi kalendar terbina dalam peranti Android anda.
- **Fail ICS** -- Import dan eksport acara dalam format piawai iCalendar.

### Eksport PDF

Anda boleh mencetak atau mengeksport mana-mana paparan kalendar (Hari,
Minggu, Bulan, Tahun) sebagai dokumen PDF.

---

## 9. Tinjauan

Anda boleh mencipta tinjauan dalam mana-mana chat atau kumpulan untuk
mendapatkan pandangan atau merancang temujanji.

### Jenis tinjauan

Cleona menyokong lima jenis tinjauan:

- **Pilihan Tunggal** -- Peserta memilih satu pilihan.
- **Pilihan Berganda** -- Peserta boleh memilih beberapa pilihan.
- **Tinjauan Tarikh** -- Cari tarikh yang sesuai untuk semua orang. Setiap
  peserta menandakan tarikh sebagai boleh, mungkin, atau tidak boleh.
- **Skala** -- Menilai sesuatu pada skala berangka (contohnya 1 hingga 5).
- **Teks Bebas** -- Peserta menulis jawapan sendiri.

### Mencipta tinjauan

Buka chat dan ketik ikon tinjauan (atau gunakan menu lampiran). Pilih jenis
tinjauan, tulis soalan dan pilihan anda, kemudian hantar tinjauan tersebut.
Ia akan muncul sebagai mesej dalam chat.

### Mengundi

Ketik tinjauan untuk memberikan undi anda. Anda boleh menukar atau menarik
balik undi anda pada bila-bila masa.

### Undian tanpa nama (anonim)

Tinjauan boleh dikonfigurasikan untuk undian tanpa nama. Jika diaktifkan,
undi disulitkan secara anonim -- tiada sesiapa, malah pencipta tinjauan
sendiri, dapat melihat siapa mengundi untuk apa. Bilangan undi tetap
kelihatan.

### Tinjauan tarikh ke kalendar

Apabila tinjauan tarikh selesai, tarikh yang menang boleh terus ditukar
menjadi entri kalendar hanya dengan satu ketikan.

---

## 10. Pelbagai Identiti

### Kenapa pelbagai identiti?

Bayangkan anda ingin memisahkan kehidupan kerja dan kehidupan peribadi anda
-- seperti menggunakan dua nombor telefon berbeza, tetapi tanpa telefon
kedua. Dalam Cleona, anda boleh menggunakan beberapa identiti pada satu
peranti. Setiap identiti mempunyai nama sendiri, gambar profil sendiri,
kontak sendiri, dan perbualan sendiri.

### Mencipta identiti baharu

1. Pada bar atas, anda akan melihat identiti semasa anda sebagai tab.
2. Ketik tanda tambah (+) di sebelah kanan tab identiti anda.
3. Masukkan nama untuk identiti baharu.
4. Selesai -- identiti baharu terus aktif serta-merta.

### Bertukar antara identiti

Ketik sahaja tab identiti pada bar atas. Pertukaran berlaku serta-merta --
tiada masa menunggu, tiada muat semula.

### Semua berjalan serentak

Perkara penting untuk diingati: semua identiti anda aktif secara serentak.
Walaupun anda sedang dipaparkan sebagai "Kerja", identiti "Peribadi" anda
tetap menerima mesej. Anda tidak akan terlepas apa-apa, tidak kira identiti
mana yang sedang anda pilih.

### Halaman butiran identiti

Apabila anda ketik tab identiti yang sedang aktif, halaman butiran akan
dibuka. Di sini anda boleh:

- Memaparkan QR-Code anda untuk kontak.
- Menukar atau membuang gambar profil anda.
- Menambah penerangan profil.
- Menukar nama paparan anda.
- Memilih tema (skin) untuk identiti ini.
- Memadam identiti, jika anda tidak lagi memerlukannya.

### Memadam identiti

Apabila anda memadam sesuatu identiti, kontak anda akan diberitahu
mengenainya. Identiti dan semua data berkaitan akan dibuang daripada
peranti anda. Tindakan ini tidak boleh dibatalkan.

---

## 11. Multi-Peranti

### Menggunakan Cleona pada beberapa peranti

Anda boleh menggunakan identiti yang sama pada sehingga 5 peranti serentak.
Satu peranti adalah peranti utama (primary) -- ia menyimpan Seed-Phrase --
manakala peranti lain akan dipautkan dengannya.

### Memautkan peranti baharu

1. Buka Tetapan pada peranti utama anda.
2. Pergi ke "Peranti Terpaut".
3. Pilih "Pautkan Peranti Baharu".
4. Pasang Cleona pada peranti baharu tersebut dan pilih "Pautkan dengan
   Peranti Sedia Ada" semasa permulaan.
5. Imbas kod QR pemasangan yang dipaparkan pada peranti utama anda, atau
   gunakan pautan pemasangan (pairing link).

Peranti terpaut akan menerima sijil delegasi daripada peranti utama. Mesej
yang dihantar daripada peranti terpaut ditandatangani secara kriptografi
dengan kunci delegasi, membolehkan kontak mengesahkan bahawa mesej itu
benar-benar berasal daripada identiti anda.

### Bagaimana ia berfungsi

- Peranti utama menyimpan Seed-Phrase anda dan kunci induk (master key).
- Peranti terpaut menerima kunci tandatangan terbitan (derived) dan sijil
  delegasi -- mereka tidak akan sekali-kali menerima Seed-Phrase itu
  sendiri.
- Semua peranti berkongsi identiti dan kontak yang sama. Mesej akan sampai
  pada semua peranti.
- Sijil delegasi diperbaharui secara automatik sebelum tamat tempoh.

### Pengurusan peranti

Buka Tetapan dan pergi ke "Peranti Terpaut" untuk melihat semua peranti
terpaut anda, status masing-masing, dan aktiviti terkini. Anda boleh
menarik balik (revoke) sesuatu peranti terpaut pada bila-bila masa,
sekiranya ia hilang atau dicuri.

### Putaran kunci kecemasan

Jika anda mengesyaki sesuatu peranti telah dikompromi, anda boleh
mencetuskan putaran kunci kecemasan (emergency key rotation). Kunci baharu
akan dijana, dan putaran ini mesti disahkan oleh majoriti peranti lain
anda. Ini menghalang satu peranti yang dicuri daripada memutarkan kunci
secara sewenang-wenangnya.

---

## 12. Pemulihan

### Menggunakan Seed-Phrase

Jika anda kehilangan peranti anda atau menyediakan peranti baharu:

1. Pasang Cleona pada peranti baharu tersebut.
2. Pilih "Pulihkan" semasa permulaan.
3. Masukkan 24 perkataan anda.
4. Cleona akan memulihkan identiti anda dan secara automatik menghubungi
   kontak sedia ada anda.
5. Kontak anda akan membalas dengan maklumat kontak, keahlian kumpulan, dan
   sejarah mesej.

Pemulihan berlaku dalam tiga peringkat:
- Mula-mula, kontak dan kumpulan anda kembali.
- Kemudian, 50 mesej terkini daripada setiap perbualan.
- Akhir sekali, sejarah mesej yang lengkap.

Memadai jika hanya seorang kontak anda dalam talian untuk pemulihan
berfungsi.

### Guardian Recovery (Orang Kepercayaan)

Anda boleh melantik sehingga lima orang kepercayaan sebagai "Guardian".
Dengan ini, kunci pemulihan anda dibahagikan kepada lima bahagian, di mana
setiap Guardian menerima satu bahagian. Untuk memulihkan identiti anda,
hanya tiga daripada lima bahagian tersebut diperlukan.

Ini bermakna: walaupun anda kehilangan Seed-Phrase anda, tiga daripada
Guardian anda boleh bersama-sama memulihkan akaun anda. Tiada seorang
Guardian pun boleh mengakses data anda secara bersendirian -- sekurang-
kurangnya tiga orang sentiasa diperlukan.

Begini cara menyediakan Guardian:
1. Buka Tetapan.
2. Pergi ke "Keselamatan".
3. Pilih "Guardian Recovery".
4. Pilih lima kontak yang dipercayai.

### Kenapa kontak anda adalah sandaran (backup) anda

Dalam messenger konvensional, data anda disimpan pada pelayan penyedia
perkhidmatan. Dengan Cleona, tiada pelayan sedemikian -- tetapi kontak anda
mengambil alih peranan tersebut. Apabila anda menghantar mesej, kontak
bersama akan menyimpan salinan tersulit sekiranya penerima sedang luar
talian. Semasa pemulihan, kontak andalah yang akan mengembalikan data anda
kepada anda.

Ini bermakna: semakin ramai kontak aktif yang anda ada, semakin boleh
dipercayai sandaran anda. Satu kontak yang kerap dalam talian sudah memadai
untuk pemulihan yang berjaya.

---

## 13. Tetapan

Anda boleh mengakses Tetapan melalui ikon gear di sudut kanan atas.

### Pemberitahuan dan nada dering

- Pilih daripada enam nada dering berbeza untuk panggilan masuk.
- Tetapkan nada mesej.
- Pada peranti Android, anda juga boleh mengaktifkan atau menyahaktifkan
  getaran (vibration).

### Tema (Skin)

Cleona menawarkan sepuluh tema berbeza: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold dan Contrast. Tema Contrast memenuhi
tahap kebolehcapaian (accessibility) tertinggi (WCAG AAA) dan amat mudah
dibaca bagi mereka yang mempunyai penglihatan terhad.

Setiap identiti boleh mempunyai tema sendiri. Anda boleh menukar tema pada
halaman butiran identiti (ketik tab identiti yang aktif).

Selain itu, dalam Tetapan di bawah "Paparan", anda boleh menukar antara
tema cerah, gelap, dan tema sistem.

### Menukar bahasa

Cleona tersedia dalam 33 bahasa, termasuk bahasa yang ditulis dari kanan ke
kiri (contohnya Arab, Ibrani). Tukar bahasa dalam Tetapan di bawah
"Bahasa".

### Had storan

Anda boleh menetapkan berapa banyak ruang storan yang boleh digunakan oleh
Cleona pada peranti anda (antara 100 MB dan 2 GB). Apabila had ini tercapai,
media lama akan dialihkan keluar atau dipadam secara automatik -- mesej
teks sentiasa dikekalkan.

### Pengarkiban media

Jika anda mempunyai storan rangkaian (NAS) atau folder kongsi di rumah,
Cleona boleh mengalihkan media anda ke sana secara automatik. SMB, SFTP,
FTPS dan WebDAV disokong.

Begini cara storan bertingkat (staged storage) berfungsi:
- 30 hari pertama: Semuanya kekal pada peranti anda.
- Selepas 30 hari: Imej pratonton kekal pada peranti, fail asal diarkibkan.
- Selepas 90 hari: Hanya imej pratonton kecil yang kekal pada peranti.
- Selepas setahun: Hanya pemegang tempat (placeholder) yang kekal, fail
  asal disimpan selamat dalam arkib.

Anda boleh ketik mana-mana media yang diarkibkan pada bila-bila masa untuk
mengambilnya semula -- dengan syarat anda bersambung dengan rangkaian rumah
anda. Media yang amat penting boleh disemat (pinned) supaya ia tidak akan
sekali-kali dialihkan keluar.

### Transkripsi untuk mesej suara

Jika diaktifkan, mesej suara anda akan ditukar menjadi teks secara tempatan
pada peranti anda (menggunakan model sumber terbuka Whisper). Teks yang
ditranskripsikan akan dihantar bersama rakaman kepada rakan bicara anda.
Transkripsi berlaku sepenuhnya pada peranti anda -- tiada data dihantar
kepada perkhidmatan luaran.

### Muat turun automatik

Anda boleh menetapkan pada saiz berapa media akan dimuat turun secara
automatik. Contohnya, anda boleh membenarkan gambar dimuat turun secara
automatik, tetapi memutuskan secara manual untuk video yang besar.

### Peranti terpaut

Uruskan peranti terpaut anda di bahagian ini dalam Tetapan. Lihat bab
Multi-Peranti untuk butiran lanjut.

---

## 14. Keselamatan

### Apakah maksud penyulitan pasca-kuantum?

Penyulitan hari ini berasaskan masalah matematik yang amat sukar untuk
diselesaikan oleh komputer biasa. Komputer kuantum mungkin dapat
menyelesaikan sebahagian masalah ini dengan pantas pada masa depan.
Penyulitan pasca-kuantum menggunakan kaedah tambahan yang juga tahan
terhadap komputer kuantum.

Cleona menggabungkan kedua-dua pendekatan: penyulitan klasik untuk
kebolehpercayaan, dan kaedah pasca-kuantum untuk ketahanan masa depan.
Dengan ini, anda dilindungi terhadap ancaman hari ini dan masa depan pada
masa yang sama.

Setiap mesej menjana kunci tersendiri. Walaupun penyerang berjaya
memecahkan kunci sesuatu mesej, dia tidak akan dapat membaca mesej lain
dengannya.

### Kenapa tiada pelayan lebih selamat

Dalam messenger konvensional, mesej anda melalui pelayan penyedia
perkhidmatan. Walaupun ia mungkin disulitkan di sana, penyedia perkhidmatan
tetap mempunyai akses kepada metadata (siapa berkomunikasi dengan siapa,
bila, berapa kerap, dari mana) dan mungkin perlu mendedahkannya atas
perintah mahkamah.

Dengan Cleona, tiada titik pusat sedemikian. Mesej anda bergerak terus dari
peranti ke peranti. Tiada tempat di mana semua metadata bertemu. Tiada
sesiapa boleh membina semula corak komunikasi anda berdasarkan satu titik
data sahaja.

### Apa yang berlaku apabila anda luar talian?

Apabila anda menghantar mesej dan penerima sedang luar talian:

1. Cleona pada mulanya cuba menghantar mesej itu terus.
2. Jika tidak berjaya, mesej itu dihantar melalui kontak bersama.
3. Pada masa yang sama, mesej itu diagihkan sebagai serpihan (fragment)
   tersulit kepada beberapa nod dalam rangkaian (seperti teka-teki jigsaw
   yang terdiri daripada 10 kepingan, di mana 7 daripadanya sudah memadai
   untuk menyusun semula gambar).
4. Mesej itu disimpan sehingga 7 hari.

Sebaik sahaja penerima kembali dalam talian, mesej akan dihantar. Anda akan
menerima pengesahan apabila mesej anda telah sampai.

### Anti-penapisan (Anti-Zensur)

Jika rangkaian anda menyekat kaedah sambungan standard (UDP), Cleona akan
bertukar secara automatik kepada penghantaran alternatif (TLS) yang lebih
sukar dikesan dan disekat. Ini berlaku secara telus -- anda tidak perlu
mengkonfigurasi apa-apa.

### Penyimpanan kunci yang selamat

Pada platform yang disokong, Cleona menyimpan kunci penyulitan anda dalam
gelang kunci selamat sistem operasi (Android Keystore, iOS Keychain, macOS
Keychain). Di mana tersedia, ini menawarkan perlindungan berasaskan
perkakasan untuk kunci anda.

### Penyulitan pangkalan data

Semua mesej, kontak dan tetapan anda disimpan secara tersulit pada peranti
anda. Walaupun seseorang berjaya mengakses sistem fail anda, mereka tidak
akan dapat membaca apa-apa tanpa kunci kriptografi anda. Kunci ini
diterbitkan daripada identiti anda dan hanya wujud pada peranti anda.

### Rangkaian tertutup

Cleona beroperasi sebagai rangkaian tertutup. Setiap paket rangkaian
disahkan, supaya hanya peranti Cleona yang sah dapat menyertai. Ini
menghalang pihak luar daripada menyuntik mesej palsu atau memintas trafik
rangkaian.

---

## 15. Kemas Kini Perisian

### Bagaimana saya mendapat kemas kini?

Cleona boleh dikemas kini melalui pelbagai cara. Matlamatnya ialah supaya
anda tetap dapat menerima kemas kini walaupun sesetengah saluran
pengedaran gagal atau disekat:

1. **App Store / Play Store:** Jika anda memasang Cleona melalui App Store,
   anda akan menerima kemas kini seperti biasa melalui store tersebut.
2. **GitHub Releases:** Pada laman GitHub projek, anda akan menemui pakej
   pemasangan yang ditandatangani untuk semua platform.
3. **Kemas Kini Dalam Rangkaian (In-Network):** Jika pengguna Cleona lain
   dalam rangkaian anda sudah mempunyai versi terkini, Cleona boleh
   mendapatkan kemas kini itu terus melalui rangkaian P2P -- tanpa pelayan
   luaran. Versi baharu dipecahkan kepada serpihan yang boleh dibetulkan
   ralat (error-corrected fragments) dan diagihkan melalui beberapa nod.
   Peranti anda mengumpul serpihan yang mencukupi dan menyusun semula
   kemas kini itu. Ketulenannya disahkan melalui tandatangan Ed25519
   pembangun.
4. **Pautan jemputan:** Anda boleh mencipta pautan jemputan yang
   mengandungi semua yang diperlukan oleh pengguna baharu untuk memasang
   Cleona dan menyambung ke rangkaian.
5. **Pemindahan fizikal:** Dalam persekitaran tanpa internet, anda boleh
   berkongsi Cleona melalui pemacu USB atau rangkaian setempat kepada orang
   lain.

### Pemberitahuan kemas kini

Apabila kemas kini baharu tersedia, Cleona akan memaparkan pemberitahuan
pada skrin utama. Jika kemas kini itu juga tersedia melalui rangkaian
(In-Network-Update), anda boleh memilih untuk memuat turunnya terus
daripada rangkaian.

### Pengedaran binari

Secara lalai, peranti anda membantu mengedarkan kemas kini kepada pengguna
lain dalam rangkaian. Jika anda tidak mahu ini, anda boleh menyahaktifkan
fungsi ini dalam Tetapan di bawah "Rangkaian". Penggunaan storan untuk
serpihan kemas kini adalah terhad (5 MB pada peranti mudah alih, 20 MB pada
peranti desktop) dan dibersihkan secara berkala.

### Pengesahan tandatangan

Setiap kemas kini ditandatangani secara kriptografi. Cleona mengesahkan
tandatangan secara automatik sebelum sesuatu kemas kini dipasang. Ini
memastikan hanya kemas kini daripada pembangun rasmi yang diterima --
walaupun kemas kini itu diperoleh melalui rangkaian P2P.

---

## 16. Soalan Lazim

### "Bolehkah saya menggunakan Cleona tanpa internet?"

Tidak, Cleona memerlukan sambungan rangkaian untuk menghantar dan menerima
mesej. Namun begitu, anda tidak perlu berada dalam talian pada masa yang
sama dengan rakan bicara anda: mesej yang dihantar semasa penerima luar
talian akan disimpan sementara dan dihantar secara automatik sebaik sahaja
kedua-dua pihak bersambung semula. Dalam rangkaian setempat (contohnya
WLAN yang sama), anda juga boleh berkomunikasi antara satu sama lain tanpa
akses internet langsung.

### "Bagaimana jika saya kehilangan Seed-Phrase saya?"

Jika anda telah menyediakan Guardian, tiga daripada lima orang kepercayaan
boleh bersama-sama memulihkan akses anda. Tanpa Guardian dan tanpa
Seed-Phrase, malangnya tiada jalan untuk mendapatkan semula identiti anda.
Oleh itu, amat penting untuk menyimpan 24 perkataan itu dengan selamat.

### "Bolehkah sesiapa membaca mesej saya?"

Tidak. Setiap mesej disulitkan dengan kunci sekali guna yang hanya sah
untuk mesej tersebut sahaja. Hanya anda dan rakan bicara anda yang boleh
menyahsulit mesej itu. Tiada pelayan pusat, tiada kunci induk (master key)
sejagat, dan tiada akses untuk pembangun. Walaupun sesuatu peranti
menghantar semula mesej itu di sepanjang laluan penghantaran, ia hanya
melihat data tersulit yang tidak bermakna.

### "Kenapa saya tidak memerlukan nombor telefon?"

Kerana identiti anda bersifat kriptografi semata-mata. Selain nombor
telefon atau alamat e-mel yang terikat kepada nama sebenar anda, anda
dikenal pasti oleh sepasang kunci yang dijana pada peranti anda. Anda
menambah kontak melalui QR-Code, NFC atau pautan -- bukan melalui buku
telefon. Ini bermakna lebih banyak privasi, kerana akaun messenger anda
tidak terikat kepada identiti sebenar anda.

### "Bagaimana saya mencari orang di Cleona?"

Cleona sengaja tidak menyediakan carian kontak mengikut nombor telefon atau
nama -- ini akan menjadi masalah privasi. Sebaliknya, anda bertukar
maklumat kontak secara terus: melalui QR-Code, NFC, pautan cleona://, atau
dalam saluran awam. Ini seperti bertukar kad perniagaan, bukan mencari
dalam buku telefon.

### "Adakah Cleona berfungsi di luar negara?"

Ya. Selagi anda mempunyai sambungan internet, Cleona berfungsi di mana-mana
sahaja di dunia. Oleh kerana tiada pelayan pusat, perkhidmatan ini tidak
boleh disekat untuk negara tertentu. Cleona juga mempunyai mekanisme
sandaran anti-penapisan: jika sambungan biasa (UDP) disekat, Cleona akan
bertukar secara automatik kepada penghantaran alternatif (TLS) yang lebih
sukar dikesan dan disekat.

### "Adakah Cleona percuma?"

Ya. Cleona boleh digunakan secara percuma dan tanpa iklan. Oleh kerana
tiada pelayan pusat, tiada kos pelayan yang perlu ditanggung untuk
operasinya. Dalam aplikasi, anda akan menemui pilihan "Derma" di mana anda
boleh menyokong pembangunan secara sukarela.

### "Mesej saya mempunyai simbol jam -- apa maksudnya?"

Ini bermakna mesej itu belum lagi dihantar sampai. Rakan bicara anda
mungkin sedang luar talian. Sebaik sahaja mesej itu berjaya dihantar,
simbol tersebut akan berubah. Mesej disimpan sehingga 7 hari untuk
penghantaran.

### "Bolehkah saya bertukar daripada WhatsApp ke Cleona?"

Ya, tetapi anda tidak boleh memindahkan chat WhatsApp anda. Cleona dan
WhatsApp adalah sistem yang jauh berbeza dari segi asasnya. Anda perlu
menambah kontak anda satu persatu dalam Cleona. Cara paling mudah ialah
dengan menyiarkan pautan cleona:// anda dalam kumpulan WhatsApp dan meminta
orang lain menambah anda di sana.

### "Bolehkah saya menggunakan Cleona pada beberapa peranti serentak?"

Ya. Anda boleh memautkan sehingga 5 peranti dengan identiti yang sama.
Satu peranti adalah peranti utama (ia menyimpan Seed-Phrase), manakala
peranti lain dipautkan melalui proses pemasangan (pairing) yang selamat.
Semua peranti berkongsi identiti, kontak dan perbualan yang sama. Lihat
bab Multi-Peranti untuk butiran lanjut.

### "Bagaimana saya mendapat kemas kini jika App Store disekat?"

Cleona boleh mendapatkan kemas kini terus melalui rangkaian P2P, tanpa
bergantung kepada App Store, laman web atau pelayan muat turun. Jika
pengguna lain dalam rangkaian mempunyai versi terkini, peranti anda boleh
memuat turun kemas kini itu daripadanya. Ketulenannya disahkan melalui
tandatangan digital pembangun. Sebagai alternatif, kontak anda boleh
berkongsi aplikasi itu melalui pautan jemputan atau pemacu USB. Lebih
lanjut mengenai ini dalam bab "Kemas Kini Perisian".

---

## Bantuan dan Hubungan

Jika anda mempunyai sebarang soalan atau menghadapi masalah, anda boleh
menemui maklumat terkini di laman web Cleona dan di GitHub. Oleh kerana
Cleona adalah projek terdesentralisasi, tiada sokongan pelanggan
konvensional -- tetapi terdapat komuniti aktif yang sedia membantu.

---

*Manual ini menerangkan Cleona Chat Versi 3.1.125. Sesetengah fungsi
mungkin berubah atau bertambah dalam versi yang lebih baharu.*
