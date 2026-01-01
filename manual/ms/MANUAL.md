# Cleona Chat -- Manual Pengguna

Versi 4.2 | Setakat November 2026

---

## Isi kandungan

1. [Apakah Cleona Chat?](#1-apakah-cleona-chat)
2. [Mula menggunakan](#2-mula-menggunakan)
3. [Kontak](#3-kontak)
4. [Pesan](#4-pesan)
5. [Kumpulan](#5-kumpulan)
6. [Saluran awam](#6-saluran-awam)
7. [Panggilan](#7-panggilan)
8. [Kalendar](#8-kalendar)
9. [Undian](#9-undian)
10. [Beberapa identiti](#10-beberapa-identiti)
11. [Beberapa peranti](#11-beberapa-peranti)
12. [Pemulihan](#12-pemulihan)
13. [Tetapan](#13-tetapan)
14. [Keselamatan](#14-keselamatan)
15. [Kemas kini perisian](#15-kemas-kini-perisian)
16. [Soalan kerap ditanya](#16-soalan-kerap-ditanya)

---

## 1. Apakah Cleona Chat?

### Messenger kamu, data kamu

Cleona Chat ialah sebuah messenger yang berfungsi sepenuhnya tanpa
server pusat. Pesan kamu berjalan dari peranti kamu ke peranti lawan
bicara kamu -- tanpa membelit melalui ibu pejabat sebuah syarikat,
tanpa awan, tanpa pusat data. Jika di tengah jalan ada peranti lain
yang membantu, ia hanya memajukan paket yang terenkripsi. Tiada
syarikat yang dapat membaca, menyimpan atau menyebarkan pesan kamu,
kerana memang tiada syarikat yang berada di tengah-tengah.

### Tiada akaun, tiada nombor telefon

Pada Cleona kamu tidak memerlukan nombor telefon mahupun alamat e-mel
untuk mendaftar. Identiti kamu terdiri daripada sepasang kunci
kriptografik yang dihasilkan secara automatik pada peranti kamu ketika
ia dihidupkan buat pertama kali. Maksudnya: tiada siapa yang dapat
mencari kamu melalui nombor telefon atau alamat e-mel kamu, melainkan
kamu sendiri memberikan butiran kontak kamu.

### Enkripsi tahan masa hadapan

Cleona menggunakan apa yang dipanggil enkripsi pasca-kuantum.
Maksudnya: walaupun komputer kuantum pada masa hadapan tidak akan dapat
membobol pesan kamu. Kamu tidak perlu memahami butirannya -- yang
penting hanyalah bahawa komunikasi kamu dilindungi sebaik mungkin
mengikut teknologi semasa.

### Bagaimana ia berfungsi tanpa server?

Rangkaian Cleona hanya terdiri daripada peranti-peranti penggunanya.
Setiap peranti ialah sebuah nod, tiada nod yang lebih penting daripada
yang lain, dan setiap nod hanya mengenal jirannya sendiri. Empat
perkara menjadikan rangkaian ini istimewa:

- **Tiada titik tetap.** Tiada alamat server di dalam aplikasi, dan
  rangkaian tidak bergantung pada satu nod pun. Tiada apa-apa yang
  boleh dimatikan untuk menghentikan Cleona.
- **Serta-merta.** Pesan kamu berangkat pada ketika kamu
  menghantarnya. Ia tidak menunggu sebarang detik mahupun apa-apa yang
  lain.
- **Penyamaran di sisi.** Peranti kamu sentiasa menghantar paket
  penyamaran yang kecil, supaya dari luar tidak dapat dilihat bila kamu
  benar-benar sedang menulis. Tiada pesan yang bergantung padanya --
  penyamaran hanya berjalan di samping.
- **Kod bukan nama.** Sesiapa yang memajukan sebuah pesan hanya
  melihat sebuah kod yang berubah setiap hari. Dalam keadaan biasa,
  tiada satu pun daripada mereka mengenal pengirim dan penerima
  serentak; pengecualiannya tercatat dalam Bab 14.

**Tiga laluan, semuanya serentak.** Apabila kamu menghantar sebuah
pesan, Cleona tidak mencuba satu laluan demi satu laluan, tetapi semua
laluan yang sesuai serentak. Sebaik sahaja lawan bicara kamu mengesahkan
penerimaan, laluan-laluan lain dihentikan.

1. **Dalam rangkaian yang sama:** Jika kamu berdua berada dalam Wi-Fi
   yang sama, pesan berpindah terus.
2. **Melalui jiran tetap:** Di internet, peranti kamu menyerahkan pesan
   kepada jiran tetapnya. Jiran itu memajukannya kepada jiran tetap
   lawan bicara kamu (sehingga tiga serentak), dan salah satunya
   menghantarnya.
3. **Peti surat:** Jika lawan bicara kamu luar talian, Cleona
   menitipkan pesan yang terenkripsi kepada tiga jiran. Ia kekal di
   sana sehingga 7 hari. Apabila lawan bicara kamu kembali dalam
   talian, ia mengambilnya.

**Bagaimana kamu masuk ke rangkaian?** Tiada alamat server di dalam
aplikasi. Titik masuk kamu kamu peroleh daripada kontak pertama kamu:
jemputannya mengandungi alamat-alamat yang peranti kamu gunakan untuk
mencari jiran-jiran pertamanya. Dalam Wi-Fi yang sama, peranti Cleona
juga saling menemui sendiri. Mulai saat itu, peranti kamu mengenal
jiran lain dengan setiap jiran yang ia temui.

### Platform

Cleona tersedia untuk Android, iOS, macOS, Linux dan Windows. Pada
komputer dan pada Android, mesej dan panggilan tiba dalam beberapa saat.
Pada iPhone, hal ini berlaku selagi aplikasi dibuka. Apabila aplikasi
tidak dibuka, iOS hanya membangunkannya sebentar sekali-sekala; iOS
menentukan bila. Cleona kemudian mengambil semua yang disimpan untuk kamu
dan memaparkan pemberitahuan dengan nombor pada ikon aplikasi. Panggilan
tidak sampai ke iPhone yang aplikasinya tidak dibuka. Ini peraturan Apple,
bukan kecacatan Cleona.

---

## 2. Mula menggunakan

### Memasang aplikasi

**Android:**
1. Muat turun fail APK dari laman web Cleona atau dari GitHub Releases.
2. Buka fail itu pada telefon kamu. Jika perlu, benarkan pemasangan
   daripada sumber tidak diketahui (Android akan bertanya kepada kamu
   secara automatik).
3. Ketik "Pasang" dan tunggu sehingga pemasangan selesai.

**iOS:**
1. Buka pautan jemputan TestFlight pada iPhone kamu.
2. Ketik "Pasang". TestFlight ialah cara rasmi Apple untuk mengedarkan
   aplikasi beta.
3. Selepas pemasangan, kamu akan jumpai Cleona pada skrin utama kamu.

**macOS:**
1. Muat turun fail DMG dari laman web Cleona atau dari GitHub Releases.
2. Buka DMG tersebut dan seret Cleona ke dalam folder Program kamu.
3. Semasa pelancaran pertama, macOS mungkin akan bertanya sama ada
   kamu ingin membuka aplikasi seorang pembangun yang dikenal pasti --
   sahkan ia.

**Linux (Ubuntu/Debian):**
1. Muat turun fail .deb dari laman web Cleona atau dari GitHub Releases.
2. Pasang dengan dwiklik atau dalam terminal: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Mulakan Cleona melalui menu aplikasi atau dalam terminal dengan `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Muat turun fail .rpm dari laman web Cleona atau dari GitHub Releases.
2. Pasang dengan: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Mulakan Cleona melalui menu aplikasi atau dalam terminal dengan `cleona-chat-beta`.

**Linux (semua pengedaran -- AppImage):**
1. Muat turun fail .AppImage dari laman web Cleona atau dari GitHub Releases.
2. Jadikan fail itu boleh dilaksanakan: klik kanan, sifat, boleh
   dilaksanakan, atau dalam terminal: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Mulakan dengan dwiklik atau dalam terminal: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Nama pakej itu berkenaan beta, yang buat masa ini satu-satunya versi
yang diterbitkan; namanya `cleona-chat-beta`.

**Windows:**
1. Muat turun pemasang dari laman web Cleona atau dari GitHub Releases.
2. Jalankan fail pemasangan dan ikut arahan.
3. Mulakan Cleona melalui menu Mula atau pintasan desktop.

### Mencipta identiti

Semasa pelancaran pertama, Cleona mencipta secara automatik sebuah
identiti baharu untuk kamu. Kamu boleh memberikan diri kamu sebuah nama
paparan -- itulah nama yang dilihat oleh kontak kamu. Nama ini boleh
diubah pada bila-bila masa.

### Menulis frasa seed -- yang paling penting sekali

Selepas mencipta identiti kamu, Cleona memaparkan 24 perkataan kepada
kamu. Itulah **frasa seed** kamu -- kunci pemulihan peribadi kamu.

**Tulis 24 perkataan ini di atas kertas dan simpan ia dengan selamat.**

Mengapa ia begitu penting?

- Jika telefon kamu rosak, hilang atau dicuri, kamu boleh memulihkan
  seluruh identiti kamu pada sebuah peranti baharu dengan 24
  perkataan ini.
- Tanpa frasa seed, tiada jalan kembali. Tiada butang "lupa kata laluan"
  dan tiada sokongan yang dapat memulangkan akaun kamu -- kerana tiada
  akaun pada sebuah server langsung. Kontak kamu juga tidak dapat
  memulihkan identiti kamu, walau sebanyak mana pun. Sebuah peranti
  kedua dengan identiti yang sama akan hadir dalam versi kemudian
  (lihat Bab 11).
- Jangan sesekali berikan frasa seed kepada orang lain. Sesiapa yang
  mengenal perkataan ini boleh menyamar sebagai kamu.

Kamu jumpa 24 perkataan itu kemudian dalam tetapan di bawah "Sandaran" ->
"Tunjuk frasa pemulihan", sekiranya kamu ingin membacanya semula. Pada
Android kamu mengesahkannya dengan kunci skrin kamu.

### Menambah kontak pertama

Untuk bersembang dengan seseorang, kamu perlu menambah orang itu
sebagai kontak dahulu. Ada beberapa cara untuk berbuat demikian --
semuanya diterangkan dalam bahagian seterusnya.

---

## 3. Kontak

### Jemputan kamu

Kontak di Cleona hanya terbentuk melalui sebuah jemputan. Jemputan
kamu sudah ada sejak pelancaran pertama -- walaupun tanpa internet dan
sebelum peranti kamu menemui sebarang jiran. Kamu boleh menjumpainya
pada halaman butiran identiti kamu (ketik nama kamu sendiri pada bar
atas).

Jemputan didapati dalam dua bentuk yang mengandungi perkara yang sama:

- sebagai **kod QR**, apabila lawan bicara kamu berdiri di sebelah kamu,
  dan
- sebagai **baris teks**, yang kamu hantar melalui e-mel, SMS atau
  melalui messenger lain.

Jemputan tidak mengandungi nombor telefon mahupun nama daripada sebuah
direktori. Ia mengandungi kunci awam kamu dan alamat-alamat yang
digunakan oleh lawan bicara kamu untuk mencapai kamu dan jiran-jiran
kamu. Bagi seseorang yang baru memasang Cleona, jemputan kamu itulah
juga pintu masuk ke rangkaian.

### Mengimbas kod QR (disyorkan)

Apabila kamu berjumpa secara peribadi:

1. Kamu memaparkan kod QR jemputan kamu kepada lawan bicara kamu.
2. Lawan bicara kamu mengetik butang plus, memilih "Imbas kod QR" dan
   menghalakan kamera ke skrin kamu. Ini berfungsi juga dengan kamera
   web sebuah komputer.
3. Permintaan itu dihantar kepada kamu dan **diterima secara automatik**
   -- kerana kamu sendiri baru saja memaparkan kod itu.

Satu kod QR hanya sah sekali: permintaan sah yang pertama diterima,
selepas itu jemputan telah digunakan. Kod QR ialah kaedah paling selamat,
kerana kamu berdua tahu dengan tepat dengan siapa kamu bertukar kontak.

### NFC (menyentuhkan telefon antara satu sama lain)

Jika kedua-dua peranti menyokong NFC:

1. Buka fungsi tambah kontak pada kedua-dua peranti.
2. Sentuhkan telefon kamu secara belakang-ke-belakang.
3. Jemputan dipindahkan dan diterima secara automatik.

NFC menawarkan keselamatan yang tinggi seperti kod QR, kerana
pertukaran hanya berfungsi apabila kamu berdua berdiri secara fizikal
bersebelahan.

### Menghantar baris teks

Apabila kamu tidak dapat berjumpa:

1. Buka jemputan kamu dan salin baris teks.
2. Hantarkan kepada orang yang sepatutnya menambah kamu -- melalui
   e-mel, SMS atau melalui messenger lain.
3. Orang tersebut menampal baris itu dalam dialog tambah kontak di
   Cleona.
4. Permintaan itu muncul pada kamu di bawah **"Permintaan"**. Di sini ia
   **tidak** diterima secara automatik: kamu membuat keputusan sendiri,
   kerana kamu tidak tahu siapa yang telah membaca baris itu di
   tengah jalan.

### Menerima permintaan kontak

Satu permintaan masuk belum menghasilkan sebuah kontak. Ia mengajukan
sebuah soalan kepada kamu dan muncul dalam tab **"Permintaan"**. Di situ
kamu melihat nama dan tahap pengesahan, dan boleh memilih:

- **Terima** -- barulah orang itu menjadi kontak kamu.
- **Tolak** -- permintaan dibuang.
- **Sekat** -- orang itu tidak boleh menghantar permintaan lain kepada
  kamu.

### Jangan sekali-kali gunakan sebagai jiran tetap

Dalam menu sebuah kontak kamu akan jumpai suis **"Jangan sekali-kali
gunakan sebagai jiran tetap"** (lalai: tutup). Jika dihidupkan, kontak
ini tidak memajukan pesan untuk kamu dan oleh itu juga tidak tahu bila
kamu menghantar atau menerima pesan. Ia direka untuk situasi apabila
ancaman datang dari kalangan kamu sendiri.

Daripada orang yang tidak dikenali (bukan kontak kamu mahupun ahli sebuah
kumpulan bersama), Cleona tidak membenarkan apa-apa melainkan permintaan
sedemikian -- tiada pesan, tiada panggilan, tiada
fail. Dan permintaan itu pun hanya tiba jika pengirim telah menyelesaikan
sebuah tugas pengiraan kecil terlebih dahulu. Ini menjadikan spam
berleluhan mahal.

### Tahap pengesahan

Cleona menunjukkan kepada kamu betapa terjaminnya identiti sebuah
kontak:

| Tahap | Maksud |
|-------|--------|
| Tidak disahkan | Kamu berdua berhubung, tetapi tiada apa yang mengesahkan bahawa orang yang betul berada di sebaliknya. |
| Dilihat | Pertukaran kunci berjaya, kamu boleh berkomunikasi secara terenkripsi. |
| Disahkan | Kamu berdua telah berjumpa secara peribadi dan berhubung melalui imbasan kamera atau NFC. |
| Dipercayai | Kamu telah menandai kontak ini secara jelas sebagai boleh dipercayai. |

"Disahkan" hanya wujud untuk pertukaran secara peribadi. Sebuah
jemputan yang datang melalui sembang atau e-mel tidak akan mencapai tahap
ini -- walaupun ia mengandungi data yang sama.

Jika kunci sebuah kontak berubah tanpa dimaklumkan, Cleona menetapkannya
semula ke "Tidak disahkan". Ini melindungi kamu daripada seseorang yang
menyamar sebagai kontak kamu tanpa kamu sedar.

---

## 4. Pesan

### Menghantar dan menerima teks

Ketik sahaja pesan kamu ke dalam medan input di bawah dan tekan Enter
atau butang hantar. Pesan kamu dienkripsi secara automatik sebelum ia
meninggalkan peranti kamu.

Pesan masuk muncul dalam sejarah sembang.

### Apa yang dimaksudkan oleh tanda pada pesan kamu

| Tanda | Maksud |
|-------|--------|
| Jam | Pesan telah dicipta, tetapi belum ada laluan yang membawanya. |
| Satu tanda semak | Pesan sedang dalam perjalanan. Ini juga terpakai selagi ia menunggu lawan bicara kamu di dalam peti surat. |
| Dua tanda semak | Dihantar: Peranti lawan bicara kamu telah mengesahkan penerimaan. |
| Tanda amaran | Selama 14 hari tiada laluan yang membawa pesan itu. Ketik ia untuk menghantarnya semula. |

**Luar talian bukan ralat.** Jika lawan bicara kamu tidak dapat dihubungi,
pesan kekal pada satu tanda semak sehingga ia diambil -- ia tidak hilang.
Jika peranti kamu sendiri tiada sambungan, pesan kekal pada jam dan
berangkat dengan sendirinya sebaik sahaja ada semula laluan. Tanda amaran
hanya muncul apabila pesan itu tidak menemui sebarang laluan selama 14
hari; kemudian kamu boleh menghantarnya semula.

Hal ini juga terpakai untuk iPhone yang aplikasinya tidak dibuka: mesej
menunggu dalam peti surat sehingga iOS membangunkan aplikasi sebentar atau
sehingga lawan bicara kamu membukanya. Perkara itu mungkin mengambil masa
lebih lama daripada pada peranti lain.

Dua tanda semak hanya wujud apabila penerima sendiri mengesahkan
penerimaan. Resit ini terenkripsi dan ditandatangani -- tiada siapa di
tengah jalan dapat memalsukannya untuk memperdayakan kamu dengan
penghantaran palsu.

### Menghantar gambar, video dan fail

Kamu ada beberapa pilihan:

- **Ikon klip kertas** dalam medan input: Ketik ia untuk memilih sebuah
  fail, gambar atau video dari galeri atau sistem fail kamu.
- **Seret dan lepas** (desktop): Seret sebuah fail terus ke tetingkap
  sembang.
- **Tampal dari papan keratan** (desktop): Salin sebuah gambar dan
  tampalkan dalam sembang.

Fail kecil (di bawah 256 KB) dihantar terus bersama pesan. Fail yang
lebih besar dipecahkan kepada cebisan dan dilengkapi pembetulan ralat,
supaya cebisan yang hilang tidak memberi kesan. Jika kamu berdua dalam
talian, ia distrim melalui seorang jiran; jika tidak, ia disimpan pada
peranti yang sentiasa boleh dihubungi sehingga lawan bicara kamu
mengambilnya.

Mulai 256 KB, Cleona bertanya kepadamu bagi setiap fail sebelum ia
dihantar: Sebuah fail besar tidak boleh mengambil laluan pesan kamu.
Kandungannya kekal terenkripsi, dan lawan bicara kamu tidak mengetahui
alamat internet kamu. Tetapi pemindahan itu kelihatan dari luar sebagai
sebuah peristiwa, dan sebuah peranti asing yang memajukan atau
menyimpannya melihat siapa memuat naik dan siapa mengambil. Persetujuan
kamu hanya sah untuk fail itu sahaja.

### Pesan suara

1. Tahan butang mikrofon dalam medan input.
2. Ucapkan pesan kamu.
3. Lepaskan butang untuk menghantar pesan.

Jika pengecaman suara diaktifkan pada peranti kamu (lihat Tetapan), pesan
suara kamu akan ditranskripsi sebagai teks secara automatik. Lawan bicara
kamu kemudian melihat kedua-dua rakaman dan teks yang ditranskripsi.

### Membalas pesan (memetik)

Untuk membalas sebuah pesan tertentu:

1. Buka menu titik tiga di sebelah pesan.
2. Pilih "Balas".
3. Satu sepanduk dengan pesan yang dipetik muncul di atas medan input.
4. Tulis balasan kamu dan hantarkan.

Pesan yang dipetik dipaparkan dalam balasan kamu, supaya kaitannya jelas.

### Menyunting dan memadam pesan

- **Sunting:** Menu titik tiga pada pesan, kemudian "Sunting". Ubah teks
  dan hantarkan semula. Lawan bicara kamu melihat bahawa pesan telah
  disunting. Penyuntingan boleh dilakukan dalam tempoh 15 minit selepas
  menghantar.
- **Padam:** Menu titik tiga pada pesan, kemudian "Padam". Pesan
  dibuang pada peranti kamu dan peranti lawan bicara kamu. Kamu boleh
  memadam pesan kamu sendiri pada bila-bila masa -- tiada teting masa
  untuk memadam.

### Tindak balas emoji

Daripada menulis sebuah balasan, kamu boleh memberi tindak balas dengan
emoji pada sebuah pesan:

1. Buka menu titik tiga atau tahan lama pesan tersebut.
2. Pilih sebuah emoji dari pilihan pantas atau buka pemilih emoji untuk
   pilihan penuh.
3. Tindak balas kamu muncul di bawah pesan.

### Menyalin teks

Melalui menu titik tiga pada sebuah pesan, kamu boleh menyalin teks pesan
ke dalam papan keratan.

### Mencari pesan

Di bahagian atas tetingkap sembang kamu akan jumpai fungsi carian.
Masukkan satu kata carian, dan Cleona memaparkan semua hasil dalam
sembang semasa. Dengan kekunci anak panah kamu boleh berpindah antara
hasil.

Pada halaman utama ada tambahan sebuah penapis carian merentas tab,
yang kamu boleh gunakan untuk melayari semua perbualan mengikut satu
kata.

### Pratonton pautan

Apabila kamu menghantar sebuah pautan, Cleona menjana secara automatik
sebuah pratonton (tajuk, perihal, gambar pratonton). Pratonton ini
dicipta oleh peranti kamu dan dihantar bersama -- lawan bicara kamu
tidak perlu membina sambungan ke laman web berpautan itu.

Apa yang berlaku apabila kamu mengetik sebuah pautan yang diterima, kamu
tetapkan dalam tetapan di bawah "Buka pautan": "Biasa", "Utamakan
tetingkap peribadi" (jika peranti tidak boleh membuka tetingkap peribadi,
pautan dibuka secara biasa) atau "Tanya setiap kali".

---

## 5. Kumpulan

### Mencipta kumpulan

1. Tukar ke tab "Kumpulan".
2. Ketik butang plus.
3. Berikan kumpulan itu sebuah nama.
4. Pilih kontak-kontak yang kamu ingin jemput.
5. Ketik "Cipta".

Kontak yang dijemput menerima pemberitahuan dan boleh menyertai
kumpulan.

### Bagaimana pesan kumpulan dilindungi

Dalam sebuah kumpulan dengan sehingga 16 ahli, Cleona menghantar setiap
pesan kepada setiap ahli secara berasingan -- masing-masing hanya
dienkripsi untuk ahli tersebut, seolah-olah kamu telah menulis sebuah
pesan tersendiri kepada setiap seorang. Tanda semak pada sebuah pesan
kumpulan menunjukkan kedudukan ahli yang paling ketinggalan.

Apabila kumpulan melebihi 16 ahli, ia menggunakan sebuah kunci berkongsi.
Kunci itu berubah setiap hari dan diambil semula secara baharu apabila
seorang ahli keluar atau dibuang; ahli baharu hanya membaca mulai dari
penyertaannya. Di situ tanda semak tidak lagi menunjukkan kedudukan setiap
ahli, tetapi bahawa pesan telah disimpan dalam rangkaian. Jika kumpulan
menyusut kepada 12 ahli atau kurang, ia kembali kepada penghantaran
berasingan.

### Gambar dalam kumpulan dan saluran

Dalam tetapan sebuah kumpulan atau saluran, kamu menetapkan dengan
"Sentiasa muatkan imej" sama ada gambar dimuatkan serta-merta atau hanya
apabila kamu mengetiknya.

### Menjemput ahli

Walaupun selepas penciptaan, kamu boleh menjemput kontak lain:

1. Buka maklumat kumpulan (menu titik tiga dalam senarai kumpulan atau
   bar atas dalam sembang kumpulan).
2. Ketik "Jemput".
3. Pilih kontak yang kamu ingin tambah.

### Peranan

Setiap kumpulan ada tiga peranan:

- **Pemilik (Owner):** Mempunyai kawalan penuh. Boleh menambah dan
  membuang ahli, melantik admin dan menguruskan kumpulan. Pemilik juga
  boleh memindahkan statusnya kepada ahli lain.
- **Admin:** Boleh membuang ahli dan membantu pengurusan.
- **Ahli:** Boleh membaca dan menulis pesan.

### meninggalkan kumpulan

1. Buka menu titik tiga dalam senarai kumpulan.
2. Pilih "Tinggalkan".
3. Sahkan keputusan kamu.

Apabila kamu meninggalkan sebuah kumpulan, pesan kamu yang sedia ada
kekal dapat dilihat oleh ahli lain.

---

## 6. Saluran awam

### Apakah saluran?

Saluran ialah forum perbincangan awam dalam rangkaian Cleona. Berbeza
dengan kumpulan, di sini sesiapa boleh membaca tanpa perlu dijemput.
Hanya pemilik dan admin boleh menerbitkan kiriman -- pelanggan hanya
membaca.

### Mencari dan menyertai saluran

1. Tukar ke tab "Saluran".
2. Buka tab "Cari".
3. Layari saluran yang tersedia mengikut nama atau topik.
4. Ketik sebuah saluran dan kemudian "Langgan".

Saluran boleh ditapis mengikut bahasa. Sesetengah saluran ditanda
sebagai "Tidak sesuai untuk bawah umur" -- saluran ini hanya dapat
dilihat jika kamu telah mengesahkan dalam profil kamu bahawa kamu berumur
lebih 18 tahun.

### Mencipta saluran sendiri

1. Tukar ke tab "Saluran".
2. Ketik butang plus.
3. Masukkan nama saluran (mesti unik dalam seluruh rangkaian).
4. Pilih bahasa dan sama ada saluran itu awam atau persendirian.
5. Pilihan: Tambah perihal dan gambar.
6. Ketik "Cipta".

Pada saluran awam kamu boleh tetapkan sama ada kandungan diklasifikasi
sebagai "Tidak sesuai untuk bawah umur".

### Melaporkan kandungan

Jika kamu perasan kandungan tidak sesuai dalam sebuah saluran awam, kamu
boleh melaporkannya. Cleona menggunakan sistem moderation teragih:
laporan dinilai oleh ahli rangkaian yang dipilih secara rawak (sejenis
"juri"). Jika pelanggaran dikesan, saluran menerima amaran. Jika
pelanggaran berulang, saluran diturunkan pangkat atau disekat dalam
indeks carian.

### Saluran sistem

Cleona mempunyai dua saluran sistem terbina:

- **Log Pepijat:** Apabila Cleona mengesan ralat, ia bertanya sama ada
  kamu ingin menghantar laporan ralat; sebelum itu kamu melihat dengan
  tepat apa yang diterbitkan. Laporan ini mendarat di saluran Log
  Pepijat, di mana ia boleh dilihat oleh komuniti. Sebuah laporan tidak
  membawa nama dan tidak membawa kandungan perbualan kamu, tetapi sebuah
  pseudonim. Dalam beta, laporan itu tambahan menyebut pengecam kamu
  (User-ID), supaya pembangun boleh bertanya lanjut. Kamu juga boleh
  menghantar laporan log secara manual (dengan dialog pratonton dan
  persetujuan jelas).
- **Permintaan Ciri:** Di sini pengguna boleh menghantar permintaan
  fungsi dan mengundi cadangan sedia ada. Cadangan disusun mengikut
  undi.

Setiap komputer menyimpan sehingga 25 MB bagi setiap saluran sistem,
setiap telefon sehingga 5 MB; apabila penuh, yang paling lama dibuang
dahulu -- tidak pernah apa yang kamu sendiri telah lihat.

---
## 7. Panggilan

### Memulakan panggilan suara

1. Buka sembang dengan kontak yang kamu ingin panggil.
2. Ketik ikon telefon pada bar atas.
3. Tunggu sehingga lawan bicara kamu menerima panggilan.

Semasa perbualan kamu melihat sebuah garis masa, tempoh perbualan dan
mempunyai akses kepada senyap dan pembesar suara.

Untuk menamatkan panggilan, ketik butang tamat panggilan berwarna
merah.

Jika kamu melihat "Tidak dapat dihubungi", peranti lawan bicara kamu tidak
dapat dihubungi pada masa ini, contohnya iPhone yang aplikasinya tidak
dibuka. Hantar mesej sebagai gantinya.

### Memulakan panggilan video

1. Buka sembang dengan kontak.
2. Ketik ikon kamera pada bar atas.
3. Video kamu muncul dalam tetingkap kecil, manakala video lawan
   bicara kamu di kawasan besar.

Kamu boleh beralih antara kamera depan dan belakang semasa
perbualan.

### Panggilan masuk

Apabila seseorang memanggil kamu, sebuah tetingkap pemberitahuan dengan
nama pemanggil muncul. Kamu boleh:

- **Terima** -- perbualan bermula.
- **Tolak** -- pemanggil dimaklumkan.

Jika kamu sedang dalam satu perbualan, panggilan baharu tidak berdering;
kamu sebaliknya menerima sebuah pesan "Panggilan tidak dijawab". Perkara
yang sama berlaku untuk sebuah panggilan kumpulan yang kamu tidak terima
-- pesan itu kemudian tercatat dalam sembang kumpulan.

Jika seseorang memanggil salah satu identiti kamu yang sedang tidak
dipaparkan, ia tetap berdering; skrin panggilan menyebut identiti kamu
yang mana dipanggil.

Pada iPhone, ia hanya berdering semasa aplikasi dibuka. Sesiapa yang
memanggil kamu semasa aplikasi tidak dibuka melihat "Tidak dapat
dihubungi" selepas 10 saat. Sebaik sahaja kamu membuka aplikasi, kamu
menemui mesej tentang panggilan tidak dijawab.

### Panggilan kumpulan

Kamu juga boleh membuat panggilan kumpulan, di mana beberapa orang
menyertai serentak. Panggilan disusun melalui sebuah pokok pemajakan
pintar, supaya tidak setiap peserta perlu berhubung terus dengan setiap
peserta lain. Semua perbualan terenkripsi sepenuhnya sepanjang masa.

Setiap ahli kumpulan boleh memulakan sebuah panggilan kumpulan. Dua
peserta yang bukan kontak antara satu sama lain tidak pernah melihat
alamat internet masing-masing: Suara dan gambar mereka berjalan melalui
seorang peserta yang merupakan kontak bagi kedua-duanya. Jika tiada
orang sedemikian, kedua-duanya tidak bersambung, dan jubin menyebut
"Tiada kenalan bersama dalam panggilan". Jika sebuah pemajakan sibuk,
suara kekal, dan video gugur bagi pasangan itu.

### Enkripsi pada panggilan

Semua panggilan dienkripsi dengan kunci sekali guna yang hanya wujud
sepanjang perbualan. Selepas menamatkan panggilan, kunci ini dipadam
serta-merta. Tiada siapa yang dapat menyahsulitkan sebuah perbualan
silam selepas itu.

Jujurlah: Panggilan berjalan, sebolehnya, terus antara peranti, kerana
sedikit kelewatan pun mengganggu pertuturan. Tidak seperti pesan,
pembekal internet kamu oleh itu boleh melihat pada sebuah panggilan
alamat internet mana yang kamu hubungkan. Apa yang kamu berdua
katakan, ia tidak nampak.

Semasa sebuah panggilan, kontak kamu juga melihat alamat internet kamu.
Jika kamu tidak mahu hal ini bagi seorang kontak, matikan "Benarkan
panggilan" dalam menunya (lalai: aktif). Jika kamu mematikannya kemudian,
alamat yang telah dilihatnya tetap diketahuinya.

---

## 8. Kalendar

Cleona mengandungi sebuah kalendar terbina yang berfungsi secara
terenkripsi dan sepenuhnya teragih -- tanpa perkhidmatan awan.

### Paparan

Kalendar menawarkan lima paparan: Hari, Minggu, Bulan, Tahun dan
paparan Tugas. Tukar antara mereka melalui tab di bahagian atas skrin
kalendar.

### Mencipta temujanji

Ketik pada sebuah slot masa atau gunakan butang tambah untuk mencipta
sebuah temujanji baharu. Kamu boleh memasukkan tajuk, tarikh, masa,
lokasi dan nota. Temujanji disimpan secara terenkripsi pada peranti
kamu.

### Temujanji berulang

Temujanji boleh berulang secara harian, mingguan, bulanan atau tahunan.
Kamu boleh melaraskan corak (contohnya setiap Selasa kedua, setiap
hari pertama bulan) dan menetapkan tarikh tamat atau bilangan
pengulangan.

### Menjemput kontak

Semasa mencipta atau menyunting sebuah temujanji, kamu boleh menjemput
kontak Cleona kamu. Mereka menerima jemputan kalendar terenkripsi dan
boleh membalas dengan Hadir, Tidak hadir atau Mungkin. Perubahan pada
temujanji dihantar secara automatik kepada semua yang dijemput.

### Paparan Bebas/Sibuk

Kamu boleh berkongsi ketersediaan kamu dengan kontak tanpa
mendedahkan butiran temujanji. Ada tiga tahap privasi: butiran penuh,
hanya blok masa atau tersembunyi. Kamu boleh menetapkan satu lalai dan
mengatasinya per kontak.

### Peringatan

Temujanji boleh mempunyai peringatan yang mencetuskan pemberitahuan
sistem sebelum temujanji bermula. Kamu boleh menunda peringatan jika
perlu.

### Segerak kalendar luaran

Cleona boleh disegerakkan dengan perkhidmatan kalendar luaran:

- **CalDAV** -- Hubungkan dengan mana-mana pelayan serasi CalDAV
  (Nextcloud, Radicale dan lain-lain).
- **Google Kalendar** -- Penyegerakan melalui Google Calendar API dengan
  pengesahan OAuth2 selamat.
- **Pelayan CalDAV tempatan** -- Cleona boleh memulakan sebuah pelayan
  CalDAV tempatan pada peranti kamu, supaya aplikasi kalendar desktop
  (Thunderbird, Outlook, Apple Kalendar, Evolution) boleh disegerakkan
  dengan kalendar Cleona kamu.
- **Kalendar sistem Android** -- Temujanji dari Cleona boleh
  dipindahkan ke dalam aplikasi kalendar terbina pada peranti Android
  kamu.
- **Fail ICS** -- Import dan eksport temujanji dalam format iCalendar
  standard.

### Eksport PDF

Kamu boleh mencetak atau mengeksport setiap paparan kalendar (Hari,
Minggu, Bulan, Tahun) sebagai dokumen PDF.

---

## 9. Undian

Kamu boleh mencipta undian dalam mana-mana sembang atau kumpulan untuk
mengumpul pendapat atau merancang temujanji.

### Jenis undian

Cleona menyokong lima jenis undian:

- **Pilihan tunggal** -- Peserta memilih satu pilihan.
- **Pilihan berbilang** -- Peserta boleh memilih beberapa pilihan.
- **Undian temujanji** -- Cari sebuah temujanji yang sesuai untuk semua.
  Setiap peserta menandakan temujanji sebagai tersedia, mungkin atau
  tidak tersedia.
- **Skala** -- Nilai sesuatu pada skala berangka (contohnya 1 hingga 5).
- **Teks bebas** -- Peserta menulis jawapan mereka sendiri.

### Mencipta undian

Buka sebuah sembang dan ketik ikon undian (atau gunakan menu lampiran).
Pilih jenis undian, rangka soalan kamu dan pilihan-pilihan, dan
hantarkan undian. Ia muncul sebagai pesan dalam sembang.

### Mengundi

Ketik sebuah undian untuk mengundi. Kamu boleh mengubah atau
menarik balik undi kamu pada bila-bila masa.

### Pengundian tanpa nama

Undian boleh dikonfigurasi untuk pengundian tanpa nama. Jika
diaktifkan, undi adalah tanpa nama secara kriptografik -- tiada siapa,
bahkan pencipta undian, dapat melihat siapa mengundi apa. Jumlah undi
tetap dapat dilihat.

### Undian temujanji ke kalendar

Apabila sebuah undian temujanji selesai, temujanji yang menang boleh
ditukar dengan satu ketik terus menjadi sebuah entri kalendar.

---
## 10. Beberapa identiti

### Mengapa beberapa identiti?

Bayangkan kamu ingin mengasingkan kehidupan kerja dan kehidupan peribadi
kamu -- serupa seperti dengan dua nombor telefon berbeza, tetapi tanpa
telefon kedua. Pada Cleona kamu boleh menggunakan beberapa identiti pada
satu peranti. Setiap identiti mempunyai nama sendiri, gambar profil
sendiri, kontak sendiri dan perbualan sendiri.

### Mencipta identiti baharu

1. Pada bar atas kamu melihat identiti semasa kamu sebagai sebuah tab.
2. Ketik simbol plus (+) di sebelah kanan tab identiti kamu.
3. Masukkan nama untuk identiti baharu.
4. Siap -- identiti baharu aktif serta-merta.

### Beralih antara identiti

Ketik sahaja tab identiti pada bar atas. Peralihan adalah serta-merta --
tiada masa menunggu, tiada muat semula.

### Semua berjalan serentak

Satu perkara penting: Semua identiti kamu aktif serentak. Walaupun kamu
sedang dipaparkan sebagai "Kerja", identiti "Peribadi" kamu terus
menerima pesan. Kamu tidak terlepas apa-apa, tidak kira identiti mana
yang kamu pilih sekarang.

### Halaman butiran identiti

Apabila kamu mengetik tab identiti yang sedang aktif, halaman butiran
terbuka. Di sini kamu boleh:

- Memaparkan kod QR kamu untuk kontak.
- Mengubah atau membuang gambar profil kamu.
- Menambah perihal profil.
- Mengubah nama paparan kamu.
- Memilih sebuah reka bentuk (skin) untuk identiti ini.
- Memadam identiti, jika kamu tidak lagi memerlukannya.

### Memadam identiti

Apabila kamu memadam sebuah identiti, kontak kamu dimaklumkan tentang
hal itu. Identiti dan semua data berkaitan dibuang dari peranti kamu.
Proses ini tidak boleh dibatalkan.

---

## 11. Beberapa peranti

### Satu identiti, satu peranti -- buat masa ini

Hari ini sebuah identiti berjalan pada satu peranti. Sebuah peranti kedua
untuk identiti yang sama akan hadir dalam versi kemudian; dalam tetapan
di bawah "Peranti" -> "Urus peranti" pilihan "Pautkan peranti lain" oleh
itu masih tertulis "Belum tersedia".

Apabila ia hadir, yang berikut berlaku: Semua peranti setara, tiada
peranti utama. Sebuah peranti tambahan kamu daftarkan dengan 24
perkataan kamu, dan salah satu peranti kamu sedia ada bersetuju.
Maksimum 5 peranti.

Jika kamu hari ini memasukkan 24 perkataan kamu pada sebuah peranti
baharu, kamu berpindah: Identiti dipulihkan pada peranti baharu itu, dan
peranti kamu yang dahulu membuang identiti itu padanya selepas itu
(lihat Bab 12).

Pada beberapa peranti kamu hari ini boleh menggunakan identiti yang
berbeza (Bab 10).

### Putar kunci

Jika kamu mengesyaki seseorang telah mendapat kunci kamu, kamu boleh
menjana kunci baharu di bawah "Urus peranti" -> "Putar kunci". Kontak
kamu dimaklumkan, jemputan terbuka kamu ditarik balik. Penting: Selepas
itu, 24 perkataan semata-mata hanya menghasilkan semula kunci lama. Oleh
itu, ciptakan terus selepas itu sebuah pakej pemulihan baharu; kamu
hanya boleh memulihkan bersama-sama dengan pakej itu.

---

## 12. Pemulihan

### Menggunakan frasa seed

Apabila kamu kehilangan peranti kamu atau menetapkan satu yang baharu:

1. Pasang Cleona pada peranti baharu.
2. Pilih "Pulihkan" semasa permulaan.
3. Masukkan 24 perkataan kamu.
4. Cleona menghasilkan semula semua identiti kamu daripadanya -- dengan
   kunci yang sama seperti sebelum. Bagi kontak kamu, kamu masih orang
   yang sama.

### Apa yang kembali -- dan apa yang tidak

Identiti kamu ada dalam 24 perkataan itu, kontak kamu dan sejarah sembang
kamu tiada. Kembali akses rangkaian kamu melalui **pakej pemulihan**:
Peranti kamu menitipkan sebuah pakej kecil yang terenkripsi dalam
rangkaian. Hanya 24 perkataan kamu boleh menjumpai dan membukanya. Di
dalamnya tercatat apa yang peranti baharu kamu perlukan untuk mencapai
semula kontak kamu, dan apa yang dalam masa itu tersimpan untuk kamu
dalam rangkaian. Untuk ini tiada kontak perlu dalam talian.

Sejarah sembang sedia ada tidak kembali melalui pemulihan.

Pakej pemulihan bertahan 7 hari dan diperbaharui oleh peranti kamu
selagi ia berjalan; dalam tetapan kamu melihat sehingga bila ia sah.
Jika tiada satu pun peranti kamu berjalan lebih daripada 7 hari, ia
telah tamat tempoh. Kemudian 24 perkataan tetap memulihkan identiti
kamu, tetapi kontak kamu kamu perlu jemput semula; apa yang dalam masa
itu tersimpan untuk kamu dalam rangkaian telah hilang.

### Memulihkan bermakna berpindah

Jika peranti kamu yang dahulu kemudian mendapati identiti itu telah
dipulihkan di tempat lain, ia membuang identiti itu padanya -- bersama
sejarah sembangnya. Oleh itu: Sesiapa yang ada 24 perkataan kamu boleh
mengambil identiti kamu dengan cara ini daripada peranti kamu. Sehingga
semua kontak kembali, aplikasi mengingatkan kamu; dengan "Selesaikan
dan baharui kunci" kamu mengakhiri pemulihan itu sendiri.

### Apa yang tiada siapa dapat pulihkan

Ini penting, dan kami menyatakannya dengan jelas:

- **Tiada siapa selain kamu dapat memulihkan identiti kamu.** Bukan
  pembangun, bukan sokongan, dan bukan juga kontak kamu -- walau
  sebanyak mana pun. Tiada kunci induk dan tiada sebahagian kunci kamu
  yang disimpan pada orang lain.
- **Jika kamu telah hilang 24 perkataan dan tiada lagi peranti,
  identiti kamu hilang.** Maka yang tinggal hanyalah mencipta satu yang
  baharu dan menjemput semula kontak kamu.

Perlindungan terbaik: Tulis 24 perkataan di atas kertas dan simpan ia
dengan selamat.

---
## 13. Tetapan

Kamu boleh capai tetapan melalui ikon gear di penjuru kanan atas.

### Pemberitahuan dan nada dering

- Pilih daripada enam nada dering berbeza untuk panggilan masuk.
- Tetapkan sebuah nada pesan.
- Pada peranti Android kamu boleh tambahan mengaktifkan atau
  menyahaktifkan getaran.
- **"Senyapkan semua"** menyebabkan tiada pesan lagi berdering, bergetar
  atau menyatakan diri pada peranti ini -- bagi semua identiti.
  Panggilan tetap berdering.
- **"Waktu senyap"** kamu tetapkan bagi setiap identiti dengan Dari/Hingga.
  Dalam tempoh ini tiada pesan identiti itu yang berdering, bergetar atau
  menyatakan diri; pesan tetap tiba.
- **"Pemberitahuan tanpa kandungan"** (lalai: tutup) hanya menunjukkan
  bahawa sebuah pesan, jemputan atau peringatan telah tiba -- tanpa
  pengirim, nama dan teks. Panggilan tetap menunjukkan nama.
- Apa yang tiba serentak selepas permulaan, Cleona laporkan dalam satu
  laporan kumpulan ("5 pesan baharu dalam 2 perbualan"); semua yang
  kemudian satu demi satu. Satu ketik pada pemberitahuan pesan membuka
  perbualan, juga dalam identiti lain.

### Reka bentuk (skin)

Cleona menawarkan sepuluh reka bentuk berbeza: Teal, Ocean, Sunset,
Forest, Amethyst, Fire, Storm, Slate, Gold dan Contrast. Reka bentuk
Contrast memenuhi tahap kebolehcapaian tertinggi (WCAG AAA) dan amat
mudah dibaca bagi penglihatan terhad.

Setiap identiti boleh mempunyai reka bentuknya sendiri. Kamu mengubah
reka bentuk pada halaman butiran identiti (ketik tab identiti aktif).

Tambahan pula kamu boleh beralih antara tema terang, gelap dan tema
sistem dalam tetapan di bawah "Paparan".

### Menukar bahasa

Cleona tersedia dalam 34 bahasa, termasuk bahasa dengan skrip
kanan-ke-kiri (contohnya Arab, Ibrani). Tukar bahasa dalam tetapan di
bawah "Bahasa".

### Pengarkiban media

Jika kamu ada storan rangkaian (NAS) atau folder dikongsi di rumah,
Cleona boleh memindahkan media kamu ke sana secara automatik. SMB,
SFTP, FTPS dan WebDAV disokong.

Begini cara storan berperingkat berfungsi:
- 30 hari pertama: Semua kekal pada peranti kamu.
- Selepas 30 hari: Sebuah gambar kecil kekal pada peranti, asal
  diarkibkan.
- Selepas 90 hari: Hanya sebuah gambar kecil kecil kekal pada peranti.
- Selepas setahun: Hanya sebuah pemegang tempat kekal, asal tersimpan
  selamat dalam arkib.

Kamu boleh mengetik media yang diarkibkan pada bila-bila masa untuk
mengambilnya semula -- dengan syarat kamu bersambung dengan rangkaian
rumah kamu. Media yang amat penting boleh disemat supaya ia tidak
sekali-kali dipindahkan keluar.

Di bawah "Bajet storan" kamu menetapkan berapa banyak MB media yang
kekal pada peranti (lalai: 100 MB pada telefon, 2 GB pada komputer).
Jika penuh, media yang paling lama dan tidak disemat diarkibkan dahulu.
Asal hanya dipadam apabila ia tersimpan selamat dalam arkib -- pesan teks
sentiasa kekal.

### Transkripsi untuk pesan suara

Jika diaktifkan, pesan suara kamu ditukarkan menjadi teks secara
setempat pada peranti kamu (dengan model sumber terbuka Whisper). Teks
yang ditranskripsi dihantar bersama rakaman kepada lawan bicara kamu.
Transkripsi berlaku sepenuhnya pada peranti kamu -- tiada data pergi ke
perkhidmatan luaran.

Model mana (tiny, base, small) dimuat turun, kamu tetapkan sekali bagi
peranti; bahasa (automatik atau tetap) bagi setiap identiti.

### Muat turun automatik

Kamu boleh menetapkan dari saiz mana media harus dimuat turun secara
automatik. Jadi kamu boleh, contohnya, memuat turun gambar secara
automatik, tetapi membuat keputusan secara manual untuk video besar.

### Peranti

Di bawah "Peranti" -> "Urus peranti" kamu melihat peranti ini. Memautkan
sebuah peranti tambahan akan hadir dalam versi kemudian (Bab 11).

### Rangkaian

Cleona tidak memerlukan tetapan rangkaian untuk berfungsi. Ada
tiga suis rangkaian:

- **Pemetaan port pada penghala** (lalai: aktif). Cleona meminta
  penghala kamu sendiri membuka sebuah pintu untuk Cleona. Jika ia
  berjaya, peranti kamu lebih mudah dihubungi oleh orang lain dan
  membantu rangkaian. Cleona hanya berkomunikasi dengan penghala kamu,
  bukan dengan internet.
- **Entri alamat awam** (lalai: aktif). Jika peranti kamu masih
  mempunyai terlalu sedikit jiran, ia melihat dalam sebuah direktori
  awam (Nostr) untuk titik masuk lain, dan jika ia sendiri mudah
  dihubungi, ia mendaftarkan diri di sana. Entri mengandungi sebuah
  alamat, tiada nama dan tiada kontak. Jika kamu mematikannya, peranti
  kamu hanya menjumpai jiran melalui jemputan, rangkaian tempatan dan
  jiran yang ia sudah kenal.
- **Kurangkan paket penyamaran pada Wi-Fi** (lalai: tidak aktif). Pada
  Wi-Fi atau kabel kamu boleh mematikan paket penyamaran kosong. Tetapi
  maka dapat dilihat semula bila kamu menulis. Pada data mudah alih
  tiada suis ini -- di sana Cleona hanya menghantar satu paket
  penyamaran seminit.

Trafik penyamaran secara keseluruhannya tidak boleh dimatikan. Ini
sengaja: Hanya jika ia sentiasa berjalan, aktiviti peranti kamu tidak
memberitahu apa-apa tentang sama ada kamu sedang menulis.

Di atas ketiga-tiga suis itu ada **mod jimat data**: Pada data mudah
alih Cleona mengesyorkannya, tetapi tidak pernah menghidupkannya sendiri.
Ia menjimatkan data, tetapi peranti kamu lebih mudah dikenali dari luar.

Di bawahnya kamu menetapkan **"Cache untuk media orang lain"**: Peranti
kamu menyimpan cebisan terenkripsi media orang lain sehingga 7 hari,
supaya cebisan itu sampai kepada penerimanya (lalai: 100 MB pada telefon,
1 GB pada komputer). Saiz yang lebih kecil membebaskan ruang serta-merta
-- cebisan yang paling lama dahulu.

---

## 14. Keselamatan

### Apakah maksud enkripsi pasca-kuantum?

Enkripsi masa kini berdasarkan masalah matematik yang amat sukar
diselesaikan oleh komputer biasa. Komputer kuantum boleh menyelesaikan
sesetengah masalah ini dengan pantas pada masa hadapan. Enkripsi
pasca-kuantum menggunakan kaedah tambahan yang tahan terhadap komputer
kuantum juga.

Cleona menggabungkan kedua-dua pendekatan: enkripsi klasik untuk
kebolehpercayaan dan kaedah pasca-kuantum untuk keselamatan masa hadapan.
Jadi kamu dilindungi terhadap ancaman masa kini dan masa hadapan serentak.

Bagi setiap pesan individu, sebuah kunci tersendiri dijana. Walaupun
seorang penyerang dapat membobol kunci sebuah pesan, ia tidak boleh
membaca pesan lain dengannya.

### Mengapa tiada server lebih selamat

Pada messenger konvensional, pesan kamu melalui server pembekal.
Walaupun ia mungkin terenkripsi di sana: pembekal mempunyai akses kepada
metadata (siapa berkomunikasi dengan siapa, bila, berapa kerap, dari
mana) dan mungkin terpaksa menyerahkannya mengikut perintah mahkamah.

Pada Cleona tiada titik pusat sedemikian. Tiada lokasi di mana semua
metadata berkumpul, dan tiada direktori di mana seseorang boleh
menyemak siapa kamu atau siapa kamu kenal.

### Siapa yang tahu bahawa kamu menulis dengan seseorang?

Enkripsi melindungi **apa** yang kamu tulis. Sama pentingnya, tiada
pemerhati **tunggal** yang tahu **dengan siapa** dan **bila** kamu
menulis. Cleona memastikan ini seperti berikut:

- **Di internet tidak pernah terus.** Jika peranti kamu menghantar
  sebuah pesan terus ke alamat internet lawan bicara kamu, pembekal
  kamu boleh melihat dengan siapa kamu menulis. Oleh itu sebuah pesan
  di internet sentiasa melalui jiran tetap kamu berdua: jiran kamu dan
  jiran lawan bicara kamu.
- **Jiran yang kamu percayai.** Jiran tetap kamu, sebolehnya, ialah
  peranti kontak kamu sendiri -- sehingga tiga yang sedang boleh
  dihubungi dari luar. Jika satu gugur, kontak lain menggantikan.
  Sebuah kontak tidak boleh dibeli dengan server; sebuah nod sewenang-
  wenangnya dalam rangkaian boleh. Jika kamu belum mempunyai kontak yang
  boleh dihubungi, Cleona mengambil seorang jiran lain. Jemputan kamu
  tidak pernah menyebut mana-mana kontak kamu, supaya tiada siapa dapat
  mengetahui alamat seorang rakan melalui mereka.
- **Kod bukan nama.** Jiran tidak melihat nama mahupun pengecam,
  tetapi hanya sebuah kod. Ia sah hanya untuk kamu berdua, dalam satu
  arah, untuk sehari -- keesokan hari ia satu yang lain. Jiran kamu tahu
  dari mana paket datang, tetapi tidak ke mana ia akhirnya pergi. Jiran
  lawan bicara kamu tahu ke mana ia pergi, tetapi tidak dari mana ia
  datang. Dalam keadaan biasa tiada siapa di tengah jalan melihat
  kedua-dua hujung.
- **Trafik penyamaran.** Peranti kamu sentiasa menghantar, pada selang
  masa tidak sekata, paket penyamaran kepada jirannya. Saiznya sama
  seperti paket sebenar, melalui port yang sama dan dari luar tidak
  dapat dibezakan daripadanya. Sama ada seseorang sedang menulis atau
  peranti hanya berjalan, tidak dapat dilihat. Pesan kamu tidak pernah
  menunggu trafik penyamaran -- ia berangkat serta-merta, ia hanya
  berjalan di samping.

**Berapa kos trafik penyamaran:** Pada Wi-Fi kira-kira 13 MB sehari.
Pada data mudah alih Cleona hanya menghantar satu paket penyamaran
seminit, itu kira-kira 1.7 MB sehari. Sebab penghadan pada data mudah
alih bukan jumlah data, tetapi bateri: Setiap pakat mengejutkan modem
radio.

**Apa yang Cleona tidak dapat sembunyikan** -- jujurlah:

- Tiada pemerhati **tunggal** yang melihat siapa menulis dengan siapa --
  bukan pembekal kamu bukan nod di tengah jalan. Tetapi sesiapa yang
  memerhati **kedua-dua hujung serentak**, contohnya sebuah kerajaan
  yang memerhati sambungan kamu dan sambungan lawan bicara kamu atau
  memerangkap kedua-dua jiran, boleh mengaitkan dari masa ke masa:
  paket keluar dari kamu, sebentar kemudian paket masuk pada lawan
  bicara kamu. Diulang cukup kerap, itu menghasilkan sebuah hubungan.
- Trafik penyamaran menyukarkan perkaitan ini, tetapi tidak
  menghalangnya. Ia menyembunyikan pesan individu, bukan jumlah: Sesiapa
  yang menghantar sangat banyak meningkatkan jumlah trafik perantinya.
- Sebuah kontak yang menjadi jiran tetap kamu tahu **bila** dan
  **berapa banyak** kamu menghantar dan menerima -- bukan dengan siapa
  dan bukan apa. Jika ancaman datang dari kalangan kamu sendiri, kamu
  boleh mengeluarkan setiap kontak daripadanya (lihat Bab 3, "Jangan
  sekali-kali gunakan sebagai jiran tetap").
- Jika dua pengguna baharu hanya mempunyai jiran yang sama itu,
  pesan mereka melalui nod ini tepat, dan ia melihat kedua-dua hujung.
  Sebaik sahaja salah seorang daripada mereka mempunyai jiran lain,
  ia berakhir.
- Jemputan kamu mengandungi alamat internet kamu. Sesiapa yang ada
  baris teks itu melihat di mana kamu dalam talian -- berikan ia hanya
  kepada orang yang kamu percayai.
- Seorang jiran yang memajukan melihat bahawa dua kod bertukar paket --
  bukan siapa di sebaliknya, dan bukan apa isinya.
- Sebuah isyarat panggilan yang sedang berjalan boleh, jika jiran pertama
  tidak menjawab pada saat itu, melalui sebuah nod yang melihat kedua-dua
  hujung; nod itu mengetahui bahawa kamu berdua bertelefon bersama.
- Sebuah fail besar yang kamu setujui, dilihat oleh komputer yang
  memajukan atau menyimpannya pada kedua-dua hujung (lihat Bab 4).
- Pada panggilan, perlindungan daripada pembekal tidak berkenaan, dan
  kontak kamu melihat alamat internet kamu (lihat Bab 7).

### Apa berlaku apabila lawan bicara kamu luar talian?

1. Cleona memulakan semua laluan yang sesuai serentak: dalam Wi-Fi yang
   sama terus, di internet melalui dua jiran -- dan tambahan peti surat.
2. Untuk peti surat Cleona menitipkan pesan yang terenkripsi kepada tiga
   jiran. Sebaik sahaja dua mengesahkan penerimaan, ia dianggap
   disimpan.
3. Cleona mengutamakan jiran yang lawan bicara kamu juga periksa --
   dahulu jiran yang jemputannya menyebut.
4. Pesan menunggu di sana sehingga 7 hari. Apabila lawan bicara kamu
   kembali, ia mengambilnya dan mengesahkan penerimaan kepada kamu.
   Baru kemudian kamu melihat dua tanda semak.

Peti surat hanya boleh dikosongkan oleh lawan bicara kamu: Mengambil dan
memadam hanya boleh dengan sebuah kunci yang hanya dimilikinya, dan
pemadaman hanya berlaku selepas ia mengesahkan penerimaan. Jiran hanya
melihat paket yang terenkripsi di bawah satu nilai yang berubah setiap
hari.

### Orang asing tidak dapat masuk

Daripada seseorang yang bukan kontak kamu mahupun ahli sebuah kumpulan
bersama, Cleona menerima tepat dua
perkara: soalan tentang kunci awam kamu, selagi salah satu jemputan kamu
masih aktif, dan sebuah permintaan kontak. Permintaan mesti membawa
jemputan yang sah daripada kamu, dan pengirim mesti menyelesaikan sebuah
tugas pengiraan terlebih dahulu. Segala yang lain -- pesan, panggilan,
fail -- dibuang sebelum ia mencapai aplikasi langsung. Sesiapa yang hanya
ada kad nama bercetak kamu, jadi tidak boleh hanya memanggil kamu. Ahli
sebuah kumpulan bersama hanya mencapai kamu dalam kumpulan itu -- dengan
pesan kumpulan dan panggilan kumpulan, tidak pernah secara berasingan.

### Anti-penapisan

Cleona dibina supaya sukar disekat:

- **Tiada server, tiada alamat tetap.** Tiada alamat di dalam aplikasi
  yang boleh disekat, dan rangkaian tidak bergantung pada satu nod pun.
- **Tiada port tetap.** Setiap peranti memilih sebuah port rawak semasa
  permulaan pertama. Tiada nombor port yang diketahui di mana trafik
  Cleona boleh dikenalpasti.
- **Seperti data rawak.** Pembinaan sambungan antara dua peranti
  dikodkan supaya tidak dapat dibezakan daripada data rawak.
- **Banyak titik masuk.** Setiap jemputan, setiap jiran dan setiap
  peranti dalam Wi-Fi yang sama ialah laluan mungkin kembali ke
  rangkaian.

### Storan kunci selamat

Pada platform yang disokong, Cleona menyimpan kunci enkripsi kamu dalam
rantai kunci selamat sistem pengoperasian (Android Keystore, iOS
Keychain, macOS Keychain). Jika tersedia, ia menawarkan perlindungan
berasaskan perkakasan untuk kunci kamu.

### Enkripsi pangkalan data

Pesan dan perbualan kamu berada dalam sebuah pangkalan data yang
terenkripsi -- satu berasingan untuk setiap identiti, masing-masing
dengan kunci sendiri. Tidak hanya pangkalan data itu sendiri yang
terenkripsi, tetapi juga fail sementaranya; tiada apa yang ditulis tanpa
enkripsi ke cakera, walau sekejap pun. Tetapan, kontak dan media juga
disimpan secara terenkripsi.

Kunci diterbitkan daripada 24 perkataan kamu dan hanya wujud pada peranti
kamu. Walaupun seseorang mendapat peranti kamu dan membaca datanya, tanpa
kunci ini ia hanya menjumpai data yang tidak terbaca.

Tanpa enkripsi hanya di mana kamu sendiri mengeluarkan kandungan daripada
Cleona:
- apabila kamu menyimpan sebuah fail dari sembang ke peranti kamu,
- apabila kamu meletakkan sebuah gambar ke dalam galeri gambar kamu
  dengan butang tangkap layar,
- apabila kamu berkongsi sesuatu dengan aplikasi lain,
- apabila kamu menetapkan pengarkiban media (Bab 13): Asal yang
  diarkibkan berada tanpa enkripsi pada storan rangkaian kamu di rumah,
  supaya kamu boleh membukanya di sana juga tanpa Cleona,
- apabila kamu mencerminkan temujanji ke kalendar sistem Android: Di
  sana aplikasi lain dengan akses kalendar boleh membacanya.

Apa yang telah keluar begitu tidak dipadam bersama pesan dan tidak
luput bersamanya.

### Perlindungan pada skrin

Pada Android, Windows dan macOS, Cleona tidak membenarkan rakaman skrin
oleh aplikasi lain. Jika kamu perlukan sebuah gambar, gunakan butang
tangkap layar pada bar atas: Ia meletakkan gambar itu ke dalam galeri
gambar kamu -- tanpa enkripsi. Dalam sebuah perbualan yang pemajuan tidak
dibenarkan, tiada tangkap layar.

---

## 15. Kemas kini perisian

### Bagaimana saya mendapatkan kemas kini?

Cleona boleh dikemas kini melalui pelbagai cara. Matlamatnya ialah
bahawa kamu juga boleh menerima kemas kini apabila saluran pengedaran
individu gagal atau disekat:

1. **App Store / Play Store:** Sebaik sahaja Cleona muncul di sana dan
   kamu memasangnya melalui sebuah store, kamu menerima kemas kini
   seperti biasa melalui store itu. Pada iPhone, kemas kini datang
   melalui TestFlight.
2. **GitHub Releases:** Pada halaman GitHub projek kamu akan jumpai
   pakej pemasangan bertandatangani untuk semua platform.
3. **Kemas kini melalui rangkaian:** Cleona boleh mendapatkan sebuah
   kemas kini terus melalui rangkaian -- tanpa pelayan muat turun.
   Versi baharu dipecahkan kepada cebisan dengan pembetulan ralat, yang
   bertaburan dalam rangkaian; sebahagiannya malah berjalan bersama
   trafik penyamaran. Peranti kamu mengumpul cukup cebisan dan
   menyusun kemas kini itu. Biasanya hanya perubahan yang dipindahkan --
   beberapa MB sahaja dan bukan keseluruhan aplikasi. Ini berlaku untuk
   Linux, Windows dan Android; pada macOS kamu memuat turun versi baharu
   dari laman web atau dari GitHub.
4. **Pautan jemputan:** Kamu boleh mencipta pautan jemputan yang
   mengandungi semua yang diperlukan oleh seorang pengguna baharu untuk
   memasang Cleona dan menyambung ke rangkaian.
5. **Pemindahan fizikal:** Dalam persekitaran tanpa internet kamu boleh
   menghantar Cleona kepada orang lain melalui pemacu USB atau dalam
   rangkaian tempatan.

### Bagaimana sebuah kemas kini berjalan

1. Cleona mengumpul cebisan sebuah kemas kini baharu secara automatik di
   latar belakang dan menyusunnya.
2. Baru apabila kemas kini **lengkap** dan **tandatangannya disahkan**,
   Cleona menawarkannya kepada kamu. Jadi kamu tidak pernah ditawarkan
   kemas kini separuh atau tidak disahkan.
3. Jika kamu mengetik "Pasang", pemasangan bermula tanpa soalan lanjut.
   Pada Android sistem tambahan memaparkan dialog pemasangannya.

Versi lama tidak ditawarkan -- sebuah kemas kini sentiasa hanya ke
hadapan. Jika satu versi sudah terlalu lama sehingga ia tidak lagi boleh
bekerja dengan rangkaian, Cleona memaparkannya dengan jelas dan
meminta kamu mengemas kini.

### Pengesahan tandatangan

Setiap kemas kini ditandatangani berganda: dengan sebuah kaedah klasik
dan sebuah kaedah pasca-kuantum. Cleona mengesahkan kedua-dua
tandatangan secara automatik. Jadi dipastikan bahawa hanya kemas kini
daripada pembangun rasmi diterima -- walaupun kemas kini datang melalui
rangkaian dari peranti asing. Sebuah kemas kini tidak pernah terhasil
secara automatik daripada pembangunan, tetapi hanya apabila pembangun
menandatanganinya secara manual.

---
## 16. Soalan kerap ditanya

### "Bolehkah saya gunakan Cleona tanpa internet?"

Cleona memerlukan sebuah sambungan rangkaian, tetapi tidak semestinya
internet: Dalam Wi-Fi yang sama peranti Cleona saling menemui sendiri
dan boleh menulis antara satu sama lain sepenuhnya tanpa akses internet.
Kamu tidak perlu berada dalam talian serentak dengan lawan bicara kamu:
Jika ia luar talian, pesan menunggu sehingga 7 hari dalam peti surat
pada tiga jiran, sehingga ia mengambilnya.

### "Bagaimana jika saya hilang frasa seed saya?"

Selagi masih ada satu peranti dengan identiti kamu berjalan, tiada apa
yang hilang -- di sana kamu hanya terus menulis. Pada peranti yang kamu
ciptakan identiti itu, kamu kebiasaannya boleh membaca semula 24
perkataan (lihat
Bab 2). Jangan bergantung padanya: Pemasangan semula membuang salinan
itu, dan pada Android membuang atau menukar kunci skrin turut
memusnahkannya. Jika kamu tiada perkataan mahupun
peranti, tiada jalan kembali -- juga tidak melalui kontak kamu,
pembangun atau sesiapa pun lain. Oleh itu amat penting untuk menyimpan
24 perkataan dengan selamat.

### "Bolehkah seseorang membaca pesan saya?"

Tidak. Setiap pesan dienkripsi dengan sebuah kunci sekali guna yang
hanya sah untuk pesan itu satu sahaja. Hanya kamu dan lawan bicara kamu
boleh menyahsulitkan pesan. Tiada server pusat, tiada kunci induk dan
tiada akses untuk pembangun. Walaupun sebuah peranti memajukan pesan
dalam laluan pengangkutan, ia hanya melihat hujah data yang terenkripsi
dan sebuah kod. Jiran kamu tahu bahawa paket itu datang daripada kamu,
tetapi tidak ke mana ia pergi; jiran lawan bicara kamu tahu ke mana ia
pergi, tetapi tidak dari siapa.

### "Mengapa saya tidak memerlukan nombor telefon?"

Kerana identiti kamu sepenuhnya kriptografik. Daripada sebuah nombor
telefon atau alamat e-mel yang dikaitkan dengan nama sebenar kamu, kamu
dikenalpasti oleh sepasang kunci yang dihasilkan pada peranti kamu.
Kontak kamu tambah melalui kod QR, NFC atau baris teks jemputan kamu --
bukan melalui buku telefon. Ini bermaksud
lebih privasi, kerana akaun messenger kamu tidak terikat dengan identiti
sebenar kamu.

### "Bagaimana saya mencari orang di Cleona?"

Cleona sengaja tidak ada carian kontak mengikut nombor telefon atau
nama -- itu akan menjadi masalah privasi. Sebaliknya kamu bertukar
jemputan secara langsung: melalui kod QR, NFC atau sebagai baris teks
melalui cara lain. Ini seperti bertukar kad nama bukan menyemak dalam
buku telefon.

### "Adakah Cleona berfungsi di luar negara?"

Ya. Selagi kamu ada sambungan internet, Cleona berfungsi di mana sahaja
di dunia. Oleh kerana tiada server pusat dan tiada alamat tetap,
perkhidmatan tidak boleh hanya dimatikan untuk negara tertentu. Bagaimana
Cleona menyukarkan penyekatan, tercatat dalam bab "Keselamatan" di bawah
"Anti-penapisan". Sebuah negara yang menyekat setiap trafik tidak
dikenali di sempadan bagaimanapun juga boleh menghentikan Cleona.

### "Adakah Cleona percuma?"

Ya. Cleona boleh digunakan secara percuma dan tanpa iklan. Oleh kerana
tiada server pusat, tiada kos pelayan untuk operasi. Dalam tetapan di
bawah "Sokong Cleona" -> "Derma" kamu boleh menyokong
pembangunan secara sukarela.

### "Pesan saya hanya ada satu tanda semak -- apa maksudnya?"

Pesan sedang dalam perjalanan, tetapi lawan bicara kamu belum
mengesahkan penerimaan -- kebiasaannya kerana ia sedang luar talian. Ini
bukan ralat: Pesan menunggu sehingga 7 hari dalam peti surat. Sebaik
sahaja ia mengambilnya, kamu melihat dua tanda semak. Sebuah jam
bermaksud bahawa belum ada laluan yang membawa pesan itu -- ia berangkat
dengan sendirinya sebaik sahaja ada laluan; sebuah tanda amaran, bahawa
pesan itu tidak menemui sebarang laluan selama 14 hari dan kamu boleh
menghantarnya semula.

### "Mengapa mesej tiba lewat pada iPhone saya?"

iOS tidak membenarkan aplikasi berjalan secara kekal di latar belakang.
Cleona hanya dibangunkan sebentar sekali-sekala; iOS menentukan bila. Ia
kemudian mengambil segala-galanya. Sebaik sahaja kamu membuka aplikasi,
Cleona mengambil apa yang disimpan untuk kamu.

### "Bolehkah saya berpindah dari WhatsApp ke Cleona?"

Ya, tetapi kamu tidak boleh memindahkan sembang WhatsApp kamu. Cleona
dan WhatsApp ialah sistem yang sangat berbeza. Kamu perlu menambah
kontak kamu secara individu dalam Cleona. Paling mudah jika kamu
menghantar baris teks jemputan kamu kepada kontak kamu. Setiap
permintaan yang tiba begitu, kamu sahkan sendiri di bawah "Permintaan".

### "Bolehkah saya gunakan Cleona pada beberapa peranti serentak?"

Belum boleh. Sebuah peranti kedua untuk identiti yang sama akan hadir
dalam versi kemudian (Bab 11). Pada beberapa peranti kamu hari ini boleh
menggunakan identiti yang berbeza.

### "Bagaimana saya mendapatkan kemas kini jika App Store disekat?"

Cleona boleh mendapatkan kemas kini terus melalui rangkaian, tanpa
bergantung kepada sebuah App Store, laman web atau pelayan muat turun.
Jika peranti lain dalam rangkaian mempunyai versi terkini, peranti kamu
boleh memuat turun kemas kini dari sana. Ketulenan disahkan melalui
sebuah tandatangan digital pembangun. Secara alternatif seorang kontak
boleh menghantar aplikasi kepadamu melalui pautan jemputan atau pemacu
USB. Lagi lanjut dalam bab "Kemas kini perisian".

---

## Bantuan dan kontak

Jika kamu ada soalan atau menghadapi masalah, kamu akan jumpai maklumat
terkini pada laman web Cleona dan di GitHub. Oleh kerana Cleona ialah
sebuah projek teragih, tiada sokongan pelanggan klasik -- tetapi sebuah
komuniti aktif yang suka membantu.

---

*Manual ini menerangkan Cleona Chat versi 4.2. Fungsi tertentu
boleh berubah atau berkembang dalam versi lebih baharu.*