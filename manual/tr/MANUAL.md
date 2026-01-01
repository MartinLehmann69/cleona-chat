# Cleona Chat -- Kullanım Kılavuzu

Version 3.1.125 | Temmuz 2026

---

## İçindekiler

1. [Cleona Chat Nedir?](#1-cleona-chat-nedir)
2. [İlk Adımlar](#2-ilk-adimlar)
3. [Kişiler](#3-kisiler)
4. [Mesajlar](#4-mesajlar)
5. [Gruplar](#5-gruplar)
6. [Herkese Açık Kanallar](#6-herkese-acik-kanallar)
7. [Aramalar](#7-aramalar)
8. [Takvim](#8-takvim)
9. [Anketler](#9-anketler)
10. [Birden Fazla Kimlik](#10-birden-fazla-kimlik)
11. [Çoklu Cihaz](#11-coklu-cihaz)
12. [Kurtarma](#12-kurtarma)
13. [Ayarlar](#13-ayarlar)
14. [Güvenlik](#14-guvenlik)
15. [Yazılım Güncellemeleri](#15-yazilim-guncellemeleri)
16. [Sıkça Sorulan Sorular](#16-sikca-sorulan-sorular)

---

## 1. Cleona Chat Nedir?

### Senin mesajlaşma uygulaman, senin verilerin

Cleona Chat, merkezi bir sunucu olmadan tamamen çalışan bir mesajlaşma uygulamasıdır. Mesajların, doğrudan senin cihazından karşındakinin cihazına gider -- bir şirket merkezinden, buluttan ya da veri merkezinden geçmeden. Hiçbir şirket mesajlarını okuyamaz, saklayamaz ya da paylaşamaz, çünkü aranda hiçbir şirket yoktur.

### Hesap yok, telefon numarası yok

Cleona'da giriş yapmak için ne bir telefon numarasına ne de bir e-posta adresine ihtiyacın var. Kimliğin, ilk açılışta cihazında otomatik olarak oluşturulan kriptografik bir anahtar çiftinden oluşur. Bu şu anlama gelir: sen kendi iletişim bilgilerini paylaşmadıkça, kimse seni telefon numaran veya e-posta adresin üzerinden bulamaz.

### Geleceğe hazır şifreleme

Cleona, kuantum sonrası şifreleme (post-quantum) adı verilen bir yöntem kullanır. Bu, gelecekteki kuantum bilgisayarların bile mesajlarını çözemeyeceği anlamına gelir. Ayrıntıları anlaman gerekmiyor -- önemli olan, iletişiminin güncel teknolojiye göre mümkün olan en iyi şekilde korunmasıdır.

### Sunucu olmadan nasıl çalışır?

Sen ve kişilerinin birlikte bir ağ oluşturduğunu düşün. Her cihaz, mesajların iletilmesine yardımcı olur. Karşındaki kişi o an çevrimiçiyse, mesaj doğrudan ona gider. Karşındaki kişi çevrimdışıysa, ortak kişileriniz mesajı geçici olarak saklar ve alıcı tekrar çevrimiçi olur olmaz teslim eder. Yani kişilerin aynı zamanda senin ağındır.

### Platformlar

Cleona; Android, iOS, macOS, Linux ve Windows için kullanılabilir.

---

## 2. İlk Adımlar

### Uygulamayı yükleme

**Android:**
1. APK dosyasını Cleona web sitesinden veya GitHub Releases üzerinden indir.
2. Dosyayı telefonunda aç. Gerekirse, bilinmeyen kaynaklardan yüklemeye izin ver (Android bunu otomatik olarak sorar).
3. "Yükle"ye dokun ve kurulum tamamlanana kadar bekle.

**iOS:**
1. TestFlight davet bağlantısını iPhone'unda aç.
2. "Yükle"ye dokun. TestFlight, Apple'ın beta uygulamaları dağıtmak için kullandığı resmi yöntemdir.
3. Kurulumdan sonra Cleona'yı ana ekranında bulabilirsin.

**macOS:**
1. DMG dosyasını Cleona web sitesinden veya GitHub Releases üzerinden indir.
2. DMG dosyasını aç ve Cleona'yı Uygulamalar klasörüne sürükle.
3. İlk açılışta macOS, tanımlı bir geliştiricinin uygulamasını açmak isteyip istemediğini sorabilir -- bunu onayla.

**Linux (Ubuntu/Debian):**
1. .deb dosyasını Cleona web sitesinden veya GitHub Releases üzerinden indir.
2. Çift tıklayarak veya terminalde şu komutla yükle: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Cleona'yı uygulama menüsünden veya terminalde `cleona-chat` komutuyla başlat.

**Linux (Fedora/openSUSE):**
1. .rpm dosyasını Cleona web sitesinden veya GitHub Releases üzerinden indir.
2. Şu komutla yükle: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Cleona'yı uygulama menüsünden veya terminalde `cleona-chat` komutuyla başlat.

**Linux (tüm dağıtımlar -- AppImage):**
1. .AppImage dosyasını Cleona web sitesinden veya GitHub Releases üzerinden indir.
2. Dosyayı çalıştırılabilir yap: sağ tık, Özellikler, Çalıştırılabilir, veya terminalde: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Çift tıklayarak veya terminalde şu komutla başlat: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Kurulum dosyasını Cleona web sitesinden veya GitHub Releases üzerinden indir.
2. Kurulum dosyasını çalıştır ve talimatları takip et.
3. Cleona'yı Başlat menüsünden veya masaüstü kısayolundan başlat.

### Kimlik oluşturma

İlk açılışta Cleona senin için otomatik olarak yeni bir kimlik oluşturur. Kendine bir görünen ad verebilirsin -- bu, kişilerinin göreceği isimdir. Bu isim istediğin zaman değiştirilebilir.

### Seed-Phrase'i yazıya dökmek -- her şeyden daha önemlisi

Kimliğini oluşturduktan sonra Cleona sana 24 kelime gösterir. Bu senin **Seed-Phrase**'in -- kişisel kurtarma anahtarındır.

**Bu 24 kelimeyi kağıda yaz ve güvenli bir yerde sakla.**

Bu neden bu kadar önemli?

- Telefonun bozulursa, kaybolursa veya çalınırsa, bu 24 kelime ile tüm kimliğini yeni bir cihazda geri yükleyebilirsin.
- Seed-Phrase olmadan geri dönüş yoktur. "Şifremi unuttum" düğmesi ve sana hesabını geri verebilecek bir destek ekibi yoktur -- çünkü zaten bir sunucuda hesap diye bir şey yoktur.
- Seed-Phrase'i asla başkalarıyla paylaşma. Bu kelimeleri bilen biri, senin yerine geçebilir.

Seed-Phrase'ini daha sonra tekrar görmek istersen, Ayarlar içinde "Güvenlik" bölümünde de bulabilirsin.

### İlk kişiyi ekleme

Biriyle sohbet edebilmek için önce o kişiyi kişi olarak eklemen gerekir. Bunun için birden fazla yöntem vardır -- hepsi bir sonraki bölümde açıklanmaktadır.

---

## 3. Kişiler

### QR-Code tarama (önerilen)

Bir kişi eklemenin en kolay yolu:

1. Karşındaki kişi kendi kimlik detay sayfasını açar (üst çubukta kendi adına dokunarak) ve sana QR-Code'unu gösterir.
2. Artı düğmesine dokun ve "QR-Code tara"yı seç.
3. Telefonunu karşındakinin QR-Code'una doğru tut.
4. Kişi isteği otomatik olarak gönderilir. Karşındaki kişi bunu kabul eder etmez birbirinize yazabilirsiniz.

Şahsen buluştuğunuzda QR-Code en güvenli yöntemdir, çünkü kiminle kişi bilgisi paylaştığını tam olarak bilirsin.

### NFC (telefonları birbirine değdirme)

Her iki cihaz da NFC destekliyorsa:

1. İkiniz de Kişi Ekle özelliğini açın.
2. Telefonlarınızı sırt sırta birbirine değdirin.
3. Kişi bilgileri otomatik olarak değiş tokuş edilir.

NFC, QR-Code gibi yüksek bir güvenlik sunar, çünkü bu değiş tokuş sadece fiziksel olarak yan yana durduğunuzda çalışır.

### Bağlantı paylaşma (cleona:// URI)

Kişi bağlantını e-posta, SMS veya başka bir mesajlaşma uygulaması üzerinden de gönderebilirsin:

1. Kimlik detay sayfanı aç.
2. cleona:// bağlantını kopyala.
3. Bağlantıyı seni eklemesini istediğin kişiye gönder.
4. Diğer kişi bağlantıyı açar veya Kişi Ekle diyaloğuna yapıştırır.

Dikkat: Bu yöntemde, bağlantının iletim yolunda değiştirilmediğine güvenirsin. Özellikle hassas kişiler için QR-Code veya NFC kullanmanı öneririz.

### Kişi isteklerini kabul etme

Biri sana bir kişi isteği gönderdiğinde, bu istek gelen kutunda görünür (alt çubuktaki son sekme). Orada şunları yapabilirsin:

- **Kabul et** -- kişi, kişi listene eklenir.
- **Reddet** -- istek silinir.
- **Engelle** -- kişi sana artık istek gönderemez.

### Doğrulama seviyeleri

Cleona, bir kişinin kimliğinin ne kadar güvenli şekilde onaylandığını sana gösterir:

| Seviye | Anlamı |
|-------|-----------|
| Bilinmiyor | Sadece Node-ID veya bir bağlantı aldın. |
| Görüldü | Anahtar değişimi başarılı oldu, şifreli iletişim kurabilirsiniz. |
| Doğrulandı | Şahsen buluştunuz ve QR-Code veya NFC ile doğruladınız. |
| Güvenilir | Bu kişiyi açıkça güvenilir olarak işaretledin. |

Seviye ne kadar yüksekse, gerçekten doğru kişiyle konuştuğundan o kadar emin olabilirsin.

---

## 4. Mesajlar

### Metin gönderme ve alma

Mesajını alttaki giriş alanına yaz ve Enter'a veya Gönder düğmesine bas. Mesajın, cihazından çıkmadan önce otomatik olarak şifrelenir.

Gelen mesajlar sohbet geçmişinde görünür. Bir onay işareti, mesajının teslim edilip edilmediğini gösterir.

### Resim, video ve dosya gönderme

Birkaç seçeneğin var:

- **Ataç simgesi** giriş alanında: Galerinden veya dosya sisteminden bir dosya, resim veya video seçmek için buna dokun.
- **Sürükle bırak** (masaüstü): Bir dosyayı doğrudan sohbet penceresine sürükle.
- **Panodan yapıştırma** (masaüstü): Bir resmi kopyala ve sohbette yapıştır.

Küçük dosyalar (256 KB altı) doğrudan gönderilir. Daha büyük dosyalar iki aşamalı bir yöntemle iletilir: önce dosya duyurulur, sonra parçalar halinde iletilir.

### Sesli mesajlar

1. Giriş alanındaki mikrofon düğmesini basılı tut.
2. Mesajını söyle.
3. Mesajı göndermek için düğmeyi bırak.

Cihazında konuşma tanıma etkinleştirilmişse (Ayarlar'a bak), sesli mesajın otomatik olarak metne dönüştürülür. Karşındaki kişi hem kaydı hem de metne dökülmüş halini görür.

### Mesajlara yanıt verme (alıntılama)

Belirli bir mesaja yanıt vermek için:

1. Mesajın yanındaki üç nokta menüsünü aç.
2. "Yanıtla"yı seç.
3. Giriş alanının üzerinde, alıntılanan mesajla birlikte bir banner belirir.
4. Yanıtını yaz ve gönder.

Alıntılanan mesaj, yanıtında gösterilir, böylece hangi mesaja atıfta bulunduğun net olur.

### Mesajları düzenleme ve silme

- **Düzenleme:** Mesajın üç nokta menüsü, ardından "Düzenle". Metni değiştir ve tekrar gönder. Karşındaki kişi mesajın düzenlendiğini görür. Düzenleme, gönderimden sonra 15 dakika içinde mümkündür.
- **Silme:** Mesajın üç nokta menüsü, ardından "Sil". Mesaj hem sende hem de karşındaki kişide kaldırılır. Kendi mesajlarını istediğin zaman silebilirsin -- silme için bir zaman sınırı yoktur.

### Emoji tepkileri

Bir yanıt yazmak yerine bir mesaja emoji ile tepki verebilirsin:

1. Üç nokta menüsünü aç veya mesaja uzun bas.
2. Hızlı seçimden bir emoji seç veya tam seçenekler için emoji seçiciyi aç.
3. Tepkin mesajın altında görünür.

### Metin kopyalama

Bir mesajın üç nokta menüsü üzerinden mesaj metnini panoya kopyalayabilirsin.

### Mesajlarda arama

Sohbet penceresinin üst kısmında arama işlevini bulursun. Bir arama terimi gir, Cleona sana mevcut sohbetteki tüm sonuçları gösterir. Ok tuşlarıyla sonuçlar arasında ileri geri gidebilirsin.

Ana ekranda ayrıca, tüm sohbetleri bir terime göre aramanı sağlayan sekmeler arası bir arama filtresi bulunur.

### Bağlantı önizlemesi

Bir bağlantı gönderdiğinde Cleona otomatik olarak bir önizleme oluşturur (başlık, açıklama, önizleme görseli). Bu önizleme senin cihazında oluşturulur ve birlikte gönderilir -- karşındaki kişinin bunun için bağlantılı web sitesine bağlantı kurması gerekmez.

Aldığın bir bağlantıya dokunduğunda, onu normal tarayıcıda mı, gizli modda mı yoksa hiç açmak istemediğin sorulur.

---

## 5. Gruplar

### Grup oluşturma

1. "Gruplar" sekmesine geç.
2. Artı düğmesine dokun.
3. Gruba bir isim ver.
4. Davet etmek istediğin kişileri seç.
5. "Oluştur"a dokun.

Davet edilen kişiler bir bildirim alır ve gruba katılabilir.

### Üye davet etme

Oluşturulduktan sonra da yeni kişiler davet edebilirsin:

1. Grup bilgisini aç (grup genel görünümünde üç nokta menüsü veya grup sohbetinde üst çubuk).
2. "Davet et"e dokun.
3. Eklemek istediğin kişileri seç.

### Roller

Her grupta üç rol vardır:

- **Sahip (Owner):** Tam kontrole sahiptir. Üye ekleyip çıkarabilir, admin atayabilir ve grubu yönetebilir. Sahip, durumunu başka bir üyeye de devredebilir.
- **Admin:** Üyeleri çıkarabilir ve yönetime yardımcı olabilir.
- **Üye:** Mesaj okuyabilir ve yazabilir.

### Gruptan ayrılma

1. Grup genel görünümünde üç nokta menüsünü aç.
2. "Ayrıl"ı seç.
3. Kararını onayla.

Bir gruptan ayrıldığında, önceki mesajların diğer üyeler için görünür kalmaya devam eder.

---

## 6. Herkese Açık Kanallar

### Kanallar nedir?

Kanallar, Cleona ağı içindeki herkese açık tartışma forumlarıdır. Gruplardan farklı olarak burada herkes davet edilmeye gerek kalmadan okuyabilir. Sadece sahip ve adminler içerik yayınlayabilir -- aboneler ise sadece okur.

### Kanal bulma ve katılma

1. "Kanallar" sekmesine geç.
2. "Arama" sekmesini aç.
3. Mevcut kanalları isme veya konuya göre ara.
4. Bir kanala dokun ve ardından "Abone ol"a dokun.

Kanallar dile göre filtrelenebilir. Bazı kanallar "18 yaş altına uygun değil" olarak işaretlenmiştir -- bunlar sadece profilinde 18 yaşından büyük olduğunu onayladığında görünür.

### Kendi kanalını oluşturma

1. "Kanallar" sekmesine geç.
2. Artı düğmesine dokun.
3. Bir kanal adı gir (ağın tamamında benzersiz olmalı).
4. Dili seç ve kanalın herkese açık mı özel mi olacağını belirle.
5. İsteğe bağlı: Bir açıklama ve görsel ekle.
6. "Oluştur"a dokun.

Herkese açık kanallarda, içeriğin "18 yaş altına uygun değil" olarak sınıflandırılıp sınıflandırılmayacağını belirleyebilirsin.

### İçerik bildirme

Herkese açık bir kanalda uygunsuz içerik fark edersen, bunu bildirebilirsin. Cleona merkezi olmayan bir moderasyon sistemi kullanır: bildirimler, ağdan rastgele seçilen üyeler tarafından değerlendirilir (bir tür "jüri"). Bir ihlal tespit edilirse kanal bir uyarı alır. Tekrarlanan ihlallerde kanal arama dizininde geriletilir veya kapatılır.

### Sistem kanalları

Cleona'da iki adet yerleşik sistem kanalı bulunur:

- **Bug Log:** Cleona bir hata tespit ettiğinde, anonimleştirilmiş bir hata raporu göndermek isteyip istemediğini sorar. Bu raporlar Bug Log kanalına düşer ve topluluk tarafından görüntülenebilir. Hiçbir kişisel veri iletilmez -- sadece teknik hata açıklamaları. Manuel olarak da bir log raporu gönderebilirsin (önizleme diyaloğu ve açık onay ile).
- **Feature Requests:** Burada kullanıcılar özellik talepleri sunabilir ve mevcut önerilere oy verebilir. Öneriler oylara göre sıralanır.

Her iki sistem kanalının da 25 MB boyut sınırı vardır ve jüri moderasyon sistemi tarafından denetlenir.

---

## 7. Aramalar

### Sesli arama başlatma

1. Aramak istediğin kişiyle sohbeti aç.
2. Üst çubuktaki telefon simgesine dokun.
3. Karşındaki kişinin aramayı kabul etmesini bekle.

Görüşme sırasında bir zaman çizelgesi, görüşme süresi görürsün ve sessize alma ile hoparlöre erişimin olur.

Kapatmak için kırmızı kapatma düğmesine dokun.

### Görüntülü arama başlatma

1. Kişiyle sohbeti aç.
2. Üst çubuktaki kamera simgesine dokun.
3. Senin görüntün küçük bir pencerede, karşındakinin görüntüsü ise büyük alanda görünür.

Görüşme sırasında ön ve arka kamera arasında geçiş yapabilirsin.

### Gelen aramalar

Biri seni aradığında, arayanın adıyla birlikte bir bildirim penceresi belirir. Şunları yapabilirsin:

- **Kabul et** -- görüşme başlar.
- **Reddet** -- arayan bilgilendirilir.

Zaten bir görüşmedeysen, yeni bir arama otomatik olarak reddedilir.

### Grup aramaları

Birden fazla kişinin aynı anda katıldığı grup aramaları da yapabilirsin. Arama, akıllı bir yönlendirme ağacı üzerinden organize edilir, böylece her katılımcının diğer herkesle doğrudan bağlantılı olması gerekmez. Tüm görüşmeler uçtan uca şifrelidir.

### Aramalarda şifreleme

Tüm aramalar, sadece görüşme süresince var olan tek seferlik anahtarlarla şifrelenir. Kapatıldıktan sonra bu anahtarlar hemen silinir. Kimse geçmiş bir görüşmeyi sonradan çözemez.

---

## 8. Takvim

Cleona, şifreli ve tamamen merkezi olmayan şekilde çalışan yerleşik bir takvim içerir -- bulut hizmeti olmadan.

### Görünümler

Takvim beş görünüm sunar: Gün, Hafta, Ay, Yıl ve bir Görevler görünümü. Takvim ekranının üst kısmındaki sekmelerle aralarında geçiş yapabilirsin.

### Etkinlik oluşturma

Yeni bir etkinlik oluşturmak için bir zaman dilimine dokun veya Ekle düğmesini kullan. Başlık, tarih, saat, konum ve notlar girebilirsin. Etkinlikler cihazında şifreli olarak saklanır.

### Tekrarlayan etkinlikler

Etkinlikler günlük, haftalık, aylık veya yıllık olarak tekrarlanabilir. Deseni özelleştirebilirsin (örn. her ikinci Salı, ayın her ilk günü) ve bir bitiş tarihi veya tekrar sayısı belirleyebilirsin.

### Kişileri davet etme

Bir etkinlik oluştururken veya düzenlerken Cleona kişilerini davet edebilirsin. Onlar şifreli bir takvim daveti alır ve Katılıyorum, Katılmıyorum veya Belki ile yanıt verebilir. Etkinlikteki değişiklikler otomatik olarak tüm davetlilere gönderilir.

### Müsait/Meşgul gösterimi

Etkinlik ayrıntılarını paylaşmadan müsaitlik durumunu kişilerinle paylaşabilirsin. Üç gizlilik seviyesi vardır: tam ayrıntılar, sadece zaman blokları veya gizli. Bir varsayılan belirleyebilir ve bunu kişi bazında geçersiz kılabilirsin.

### Hatırlatıcılar

Etkinliklerin, etkinlik başlamadan önce bir sistem bildirimi tetikleyen hatırlatıcıları olabilir. Hatırlatıcıları gerektiğinde erteleyebilirsin.

### Harici takvim senkronizasyonu

Cleona harici takvim hizmetleriyle senkronize olabilir:

- **CalDAV** -- CalDAV uyumlu herhangi bir sunucuya bağlan (Nextcloud, Radicale vb.).
- **Google Takvim** -- Google Calendar API üzerinden güvenli OAuth2 kimlik doğrulamasıyla senkronizasyon.
- **Yerel CalDAV sunucusu** -- Cleona, cihazında yerel bir CalDAV sunucusu başlatabilir, böylece masaüstü takvim uygulamaları (Thunderbird, Outlook, Apple Takvim, Evolution) Cleona takvininle senkronize olabilir.
- **Android sistem takvimi** -- Cleona'daki etkinlikler, Android cihazının yerleşik takvim uygulamasına aktarılabilir.
- **ICS dosyaları** -- Etkinlikleri standart iCalendar formatında içe ve dışa aktar.

### PDF dışa aktarma

Her takvim görünümünü (Gün, Hafta, Ay, Yıl) PDF belgesi olarak yazdırabilir veya dışa aktarabilirsin.

---

## 9. Anketler

Görüş toplamak veya bir tarih planlamak için her sohbette veya grupta anket oluşturabilirsin.

### Anket türleri

Cleona beş tür anketi destekler:

- **Tekli seçim** -- Katılımcılar bir seçenek seçer.
- **Çoklu seçim** -- Katılımcılar birden fazla seçenek seçebilir.
- **Tarih anketi** -- Herkese uyan bir tarih bul. Her katılımcı tarihleri müsait, belki veya müsait değil olarak işaretler.
- **Ölçek** -- Bir şeyi sayısal bir ölçekte değerlendir (örn. 1 ile 5 arası).
- **Serbest metin** -- Katılımcılar kendi yanıtlarını yazar.

### Anket oluşturma

Bir sohbet aç ve anket simgesine dokun (veya ek menüsünü kullan). Anket türünü seç, sorunu ve seçeneklerini oluştur ve anketi gönder. Anket, sohbette bir mesaj olarak görünür.

### Oy verme

Oyunu vermek için bir ankete dokun. Oyunu istediğin zaman değiştirebilir veya geri çekebilirsin.

### Anonim oylama

Anketler anonim oylama için yapılandırılabilir. Etkinleştirildiğinde, oylar kriptografik olarak anonimdir -- anket oluşturucusu dahil kimse kimin neye oy verdiğini göremez. Oy sayısı yine de görünür kalır.

### Tarih anketinden takvime

Bir tarih anketi tamamlandığında, kazanan tarih tek bir dokunuşla doğrudan bir takvim girdisine dönüştürülebilir.

---

## 10. Birden Fazla Kimlik

### Neden birden fazla kimlik?

İş hayatını ve özel hayatını ayırmak istediğini düşün -- iki farklı telefon numarasına sahip olmak gibi, ama ikinci bir telefon olmadan. Cleona'da tek bir cihazda birden fazla kimlik kullanabilirsin. Her kimliğin kendine ait bir adı, profil resmi, kişileri ve sohbetleri vardır.

### Yeni kimlik oluşturma

1. Üst çubukta mevcut kimliğini bir sekme olarak görürsün.
2. Kimlik sekmelerinin sağındaki artı işaretine (+) dokun.
3. Yeni kimlik için bir isim gir.
4. Bu kadar -- yeni kimlik hemen etkin hale gelir.

### Kimlikler arasında geçiş yapma

Üst çubuktaki kimlik sekmesine dokunman yeterli. Geçiş anında olur -- bekleme yok, yeniden yükleme yok.

### Hepsi aynı anda çalışır

Önemli bir nokta: tüm kimliklerin aynı anda etkindir. "İş" olarak görünsen bile, "Özel" kimliğin mesaj almaya devam eder. Hangi kimliği seçmiş olursan ol, hiçbir şeyi kaçırmazsın.

### Kimlik detay sayfası

O an etkin olan kimliğinin sekmesine dokunduğunda detay sayfası açılır. Burada şunları yapabilirsin:

- Kişiler için QR-Code'unu göster.
- Profil resmini değiştir veya kaldır.
- Bir profil açıklaması ekle.
- Görünen adını değiştir.
- Bu kimlik için bir tasarım (skin) seç.
- Artık ihtiyacın yoksa kimliği sil.

### Kimlik silme

Bir kimliği sildiğinde, kişilerin bu konuda bilgilendirilir. Kimlik ve buna ait tüm veriler cihazından kaldırılır. Bu işlem geri alınamaz.

---

## 11. Çoklu Cihaz

### Cleona'yı birden fazla cihazda kullanma

Aynı kimliği aynı anda 5 cihaza kadar kullanabilirsin. Bir cihaz birincildir (Seed-Phrase'i taşır) ve diğer cihazlar buna bağlanır.

### Yeni cihaz bağlama

1. Birincil cihazında Ayarlar'ı aç.
2. "Bağlı Cihazlar"a git.
3. "Yeni Cihaz Bağla"yı seç.
4. Yeni cihaza Cleona'yı yükle ve başlangıçta "Mevcut Cihaza Bağlan"ı seç.
5. Birincil cihazında gösterilen eşleştirme QR-Code'unu tara veya eşleştirme bağlantısını kullan.

Bağlı cihaz, birincil cihazdan bir delegasyon sertifikası alır. Bağlı bir cihazdan gönderilen mesajlar, delege edilmiş bir anahtarla kriptografik olarak imzalanır, böylece kişiler mesajın gerçekten senin kimliğinden geldiğini doğrulayabilir.

### Nasıl çalışır

- Birincil cihaz Seed-Phrase'ini ve ana anahtarlarını taşır.
- Bağlı cihazlar türetilmiş imza anahtarları ve bir delegasyon sertifikası alır -- Seed-Phrase'in kendisini asla almazlar.
- Tüm cihazlar aynı kimliği ve kişileri paylaşır. Mesajlar tüm cihazlara ulaşır.
- Delegasyon sertifikaları süresi dolmadan önce otomatik olarak yenilenir.

### Cihaz yönetimi

Tüm bağlı cihazlarını, durumlarını ve son etkinliklerini görmek için Ayarlar'ı aç ve "Bağlı Cihazlar"a git. Kaybolması veya çalınması durumunda bağlı bir cihazı istediğin zaman iptal edebilirsin.

### Acil durum anahtar rotasyonu

Bir cihazın ele geçirildiğinden şüpheleniyorsan acil durum anahtar rotasyonu başlatabilirsin. Bu sırada yeni anahtarlar üretilir ve rotasyonun diğer cihazlarının çoğunluğu tarafından onaylanması gerekir. Bu, çalınmış tek bir cihazın tek başına anahtar rotasyonu yapmasını engeller.

---

## 12. Kurtarma

### Seed-Phrase kullanma

Cihazını kaybedersen veya yeni bir cihaz kurarsan:

1. Cleona'yı yeni cihaza yükle.
2. Başlangıçta "Geri Yükle"yi seç.
3. 24 kelimeni gir.
4. Cleona kimliğini geri yükler ve otomatik olarak önceki kişilerinle iletişime geçer.
5. Kişilerin, kişi bilgilerin, grup üyeliklerin ve mesaj geçmişinle yanıt verir.

Geri yükleme üç adımda gerçekleşir:
- Önce kişilerin ve grupların geri döner.
- Sonra her sohbetten son 50 mesaj.
- En son da tam mesaj geçmişi.

Geri yüklemenin çalışması için kişilerinden yalnızca birinin çevrimiçi olması yeterlidir.

### Guardian Recovery (Güvenilir kişiler)

En fazla beş güvenilir kişiyi "Guardian" olarak belirleyebilirsin. Bu sırada kurtarma anahtarın beş parçaya bölünür ve her Guardian bir parça alır. Kimliğini geri yüklemek için beş parçadan üçü yeterlidir.

Bu şu anlama gelir: Seed-Phrase'ini kaybetmiş olsan bile, Guardian'larından üçü birlikte hesabını geri yükleyebilir. Hiçbir tek Guardian tek başına verilerine erişemez -- her zaman en az üçü gereklidir.

Guardian'ları şu şekilde kurarsın:
1. Ayarlar'ı aç.
2. "Güvenlik"e git.
3. "Guardian Recovery"yi seç.
4. Beş güvenilir kişi seç.

### Kişilerin neden yedeğin olduğu

Geleneksel mesajlaşma uygulamalarında verilerin sağlayıcının sunucularında bulunur. Cleona'da sunucu yoktur -- ama bu rolü kişilerin üstlenir. Bir mesaj gönderdiğinde, alıcının o an çevrimdışı olma ihtimaline karşı ortak kişileriniz şifreli bir kopya saklar. Bir geri yükleme sırasında kişilerin sana verilerini geri verir.

Bu şu anlama gelir: Ne kadar çok aktif kişin varsa, yedeğin o kadar güvenilir olur. Düzenli olarak çevrimiçi olan bir kişi, başarılı bir geri yükleme için yeterlidir.

---

## 13. Ayarlar

Ayarlara sağ üst köşedeki dişli simgesi üzerinden ulaşabilirsin.

### Bildirimler ve zil sesleri

- Gelen aramalar için altı farklı zil sesinden birini seç.
- Bir mesaj sesi ayarla.
- Android cihazlarda ayrıca titreşimi açıp kapatabilirsin.

### Tasarımlar (Skinler)

Cleona on farklı tasarım sunar: Teal, Ocean, Sunset, Forest, Amethyst, Fire, Storm, Slate, Gold ve Contrast. Contrast tasarımı en yüksek erişilebilirlik seviyesini (WCAG AAA) karşılar ve görme güçlüğü olan kullanıcılar için özellikle okunaklıdır.

Her kimlik kendi tasarımına sahip olabilir. Tasarımı kimlik detay sayfasında değiştirirsin (etkin kimlik sekmesine dokunarak).

Ayrıca Ayarlar'da "Görünüm" altında açık, koyu ve sistem teması arasında geçiş yapabilirsin.

### Dili değiştirme

Cleona, aralarında sağdan sola yazılan diller de (örn. Arapça, İbranice) bulunan 33 dilde kullanılabilir. Dili Ayarlar'da "Dil" altında değiştir.

### Depolama sınırı

Cleona'nın cihazında ne kadar depolama alanı kullanabileceğini belirleyebilirsin (100 MB ile 2 GB arası). Sınıra ulaşıldığında eski medyalar otomatik olarak dışa aktarılır veya silinir -- metin mesajları her zaman korunur.

### Medya arşivleme

Evinde bir ağ depolama cihazın (NAS) veya paylaşılan bir klasörün varsa, Cleona medyalarını otomatik olarak oraya aktarabilir. SMB, SFTP, FTPS ve WebDAV desteklenir.

Kademeli depolama şu şekilde çalışır:
- İlk 30 gün: Her şey cihazında kalır.
- 30 günden sonra: Bir önizleme görseli cihazda kalır, orijinal arşivlenir.
- 90 günden sonra: Cihazda sadece küçük bir önizleme görseli kalır.
- Bir yıldan sonra: Sadece bir yer tutucu kalır, orijinal güvenli bir şekilde arşivde tutulur.

Ev ağına bağlıysan, arşivlenmiş bir medyayı geri getirmek için istediğin zaman ona dokunabilirsin. Özellikle önemli medyaları, hiçbir zaman dışa aktarılmaması için sabitleyebilirsin.

### Sesli mesajlar için transkripsiyon

Etkinleştirildiğinde, sesli mesajların yerel olarak cihazında metne dönüştürülür (açık kaynaklı Whisper modeliyle). Metne dökülen metin, kayıtla birlikte karşındaki kişiye gönderilir. Transkripsiyon tamamen cihazında gerçekleşir -- hiçbir veri harici hizmetlere gitmez.

### Otomatik indirme

Medyaların hangi boyuttan itibaren otomatik olarak indirileceğini ayarlayabilirsin. Örneğin resimlerin otomatik yüklenmesine izin verirken büyük videolarda manuel karar verebilirsin.

### Bağlı cihazlar

Bağlı cihazlarını Ayarlar'ın bu bölümünde yönetebilirsin. Ayrıntılar için Çoklu Cihaz bölümüne bak.

---

## 14. Güvenlik

### Kuantum sonrası şifreleme ne anlama gelir?

Günümüzün şifrelemesi, normal bilgisayarlar için çözülmesi son derece zor olan matematiksel problemlere dayanır. Kuantum bilgisayarlar gelecekte bu problemlerden bazılarını hızlı bir şekilde çözebilir. Kuantum sonrası şifreleme, kuantum bilgisayarlara da dayanıklı ek yöntemler kullanır.

Cleona her iki yaklaşımı birleştirir: güvenilirlik için klasik şifreleme ve geleceğe hazırlık için kuantum sonrası yöntemler. Böylece hem bugünün hem de geleceğin tehditlerine karşı aynı anda korunmuş olursun.

Her bir mesaj için ayrı bir anahtar üretilir. Bir saldırgan bir mesajın anahtarını kırsa bile, bununla başka bir mesajı okuyamaz.

### Sunucusuz olmanın neden daha güvenli olduğu

Geleneksel mesajlaşma uygulamalarında mesajların sağlayıcının sunucuları üzerinden geçer. Orada şifreli olsalar bile: sağlayıcı meta verilere erişebilir (kim ne zaman kiminle, ne sıklıkta, nereden iletişim kuruyor) ve bunları gerektiğinde mahkeme kararıyla teslim etmek zorunda kalabilir.

Cleona'da böyle merkezi bir nokta yoktur. Mesajların doğrudan cihazdan cihaza gider. Tüm meta verilerin bir araya geldiği bir yer yoktur. Kimse tek bir veri noktasından iletişim davranışını yeniden oluşturamaz.

### Çevrimdışıyken ne olur?

Bir mesaj gönderdiğinde ve alıcı çevrimdışıysa:

1. Cleona önce mesajı doğrudan teslim etmeye çalışır.
2. Bu işe yaramazsa, mesaj ortak kişiler üzerinden iletilir.
3. Aynı zamanda mesaj, şifreli parçalar halinde ağdaki birden fazla düğüme dağıtılır (10 parçadan oluşan ve resmi bir araya getirmek için 7'sinin yeterli olduğu bir bulmaca gibi).
4. Mesaj en fazla 7 gün boyunca saklanır.

Alıcı tekrar çevrimiçi olur olmaz mesajlar teslim edilir. Mesajın ulaştığında bir onay alırsın.

### Sansüre karşı direnç

Ağın standart bağlantı yöntemini (UDP) engelliyorsa, Cleona otomatik olarak tespit edilmesi ve engellenmesi daha zor olan alternatif bir iletim yöntemine (TLS) geçer. Bu, hiçbir yapılandırma gerektirmeden şeffaf bir şekilde gerçekleşir.

### Güvenli anahtar depolama

Desteklenen platformlarda Cleona, şifreleme anahtarlarını işletim sisteminin güvenli anahtar deposunda saklar (Android Keystore, iOS Keychain, macOS Keychain). Mevcut olduğu yerde bu, anahtarların için donanım destekli koruma sağlar.

### Veritabanı şifreleme

Tüm mesajların, kişilerin ve ayarların cihazında şifreli olarak saklanır. Biri dosya sistemine erişim sağlasa bile, kriptografik anahtarın olmadan hiçbir şey okuyamaz. Bu anahtar kimliğinden türetilir ve sadece cihazında var olur.

### Kapalı ağ

Cleona kapalı bir ağ olarak çalışır. Her ağ paketi kimlik doğrulamalıdır, böylece ağa yalnızca meşru Cleona cihazları katılabilir. Bu, dışarıdakilerin sahte mesajlar sokmasını veya ağ trafiğini dinlemesini engeller.

---

## 15. Yazılım Güncellemeleri

### Güncellemeleri nasıl alırım?

Cleona farklı yollarla güncellenebilir. Amaç, bazı dağıtım kanalları devre dışı kalsa veya engellense bile güncellemeleri alabilmendir:

1. **App Store / Play Store:** Cleona'yı bir App Store üzerinden yüklediysen, güncellemeleri her zamanki gibi mağaza üzerinden alırsın.
2. **GitHub Releases:** Projenin GitHub sayfasında tüm platformlar için imzalı kurulum paketleri bulabilirsin.
3. **Ağ içi güncellemeler (In-Network-Updates):** Ağındaki başka bir Cleona kullanıcısında zaten en yeni sürüm varsa, Cleona güncellemeyi harici bir sunucu olmadan doğrudan P2P ağı üzerinden alabilir. Bu sırada yeni sürüm hata düzeltmeli parçalara ayrılır ve birden fazla düğüme dağıtılır. Cihazın yeterli parça toplar ve güncellemeyi bir araya getirir. Gerçekliği, geliştiricinin Ed25519 imzasıyla doğrulanır.
4. **Davet bağlantıları:** Yeni bir kullanıcının Cleona'yı yüklemesi ve ağa bağlanması için ihtiyaç duyduğu her şeyi içeren davet bağlantıları oluşturabilirsin.
5. **Fiziksel aktarım:** İnternetsiz ortamlarda Cleona'yı USB bellek ile veya yerel ağ üzerinden başkalarına aktarabilirsin.

### Güncelleme bildirimi

Yeni bir güncelleme mevcut olduğunda Cleona sana ana ekranda bir bildirim gösterir. Güncelleme ağ üzerinden de mevcutsa (In-Network-Update), onu doğrudan ağdan indirme seçeneğin olur.

### İkili (Binary) dağıtım

Varsayılan olarak cihazın, güncellemeleri ağdaki diğer kullanıcılara iletmeye yardımcı olur. Bunu istemiyorsan bu özelliği Ayarlar'da "Ağ" altında devre dışı bırakabilirsin. Güncelleme parçaları için depolama kullanımı sınırlıdır (mobil cihazlarda 5 MB, masaüstü cihazlarda 20 MB) ve düzenli olarak temizlenir.

### İmza doğrulama

Her güncelleme kriptografik olarak imzalanır. Cleona, bir güncelleme yüklenmeden önce imzayı otomatik olarak kontrol eder. Böylece güncelleme P2P ağı üzerinden alınmış olsa bile, yalnızca resmi geliştiriciden gelen güncellemelerin kabul edilmesi sağlanır.

---

## 16. Sıkça Sorulan Sorular

### "Cleona'yı internetsiz kullanabilir miyim?"

Hayır, Cleona mesaj gönderip almak için bir ağ bağlantısına ihtiyaç duyar. Ancak karşındaki kişiyle aynı anda çevrimiçi olman gerekmez: alıcı çevrimdışıyken gönderilen mesajlar geçici olarak saklanır ve her iki taraf da tekrar bağlandığında otomatik olarak teslim edilir. Yerel ağda (örn. aynı WLAN içinde) internet erişimi olmadan da birbirinizle iletişim kurabilirsiniz.

### "Seed-Phrase'imi kaybedersem ne olur?"

Guardian'lar kurmuşsan, beş güvenilir kişiden üçü birlikte erişimini geri yükleyebilir. Guardian'lar ve Seed-Phrase olmadan, kimliğini geri almanın maalesef bir yolu yoktur. Bu yüzden 24 kelimeyi güvenli bir şekilde saklamak bu kadar önemlidir.

### "Biri mesajlarımı okuyabilir mi?"

Hayır. Her mesaj, yalnızca o mesaj için geçerli olan tek seferlik bir anahtarla şifrelenir. Mesajı yalnızca sen ve karşındaki kişi çözebilir. Merkezi bir sunucu, bir genel anahtar veya geliştirici için bir erişim yolu yoktur. Bir cihaz iletim yolunda mesajı iletse bile, sadece şifreli bir veri yığını görür.

### "Neden telefon numarasına ihtiyacım yok?"

Çünkü kimliğin tamamen kriptografiktir. Gerçek adınla ilişkilendirilmiş bir telefon numarası veya e-posta adresi yerine, cihazında oluşturulan bir anahtar çifti seni tanımlar. Kişileri telefon rehberi üzerinden değil, QR-Code, NFC veya bağlantı yoluyla eklersin. Bu, mesajlaşma hesabının gerçek kimliğine bağlı olmaması nedeniyle daha fazla gizlilik sağlar.

### "Cleona'da insanları nasıl bulurum?"

Cleona bilinçli olarak telefon numarasına veya isme göre kişi aramaya sahip değildir -- bu bir gizlilik sorunu olurdu. Bunun yerine kişi bilgilerini doğrudan değiş tokuş edersin: QR-Code, NFC, cleona:// bağlantısı veya herkese açık kanallar üzerinden. Bu, telefon rehberine bakmak yerine kartvizit değiş tokuş etmek gibidir.

### "Cleona yurt dışında da çalışır mı?"

Evet. Bir internet bağlantın olduğu sürece Cleona dünyanın her yerinde çalışır. Merkezi bir sunucu olmadığı için hizmet belirli ülkeler için de engellenemez. Cleona ayrıca sansüre karşı bir yedek yönteme sahiptir: normal bağlantı (UDP) engellendiğinde, Cleona otomatik olarak tespit edilmesi ve engellenmesi daha zor olan alternatif bir iletim yöntemine (TLS) geçer.

### "Cleona ücretsiz mi?"

Evet. Cleona ücretsiz ve reklamsız kullanılabilir. Merkezi bir sunucu olmadığı için işletim için sunucu maliyeti de oluşmaz. Uygulamada "Bağış" altında, geliştirmeyi gönüllü olarak destekleme imkanı bulursun.

### "Mesajımda bir saat simgesi var -- bu ne anlama gelir?"

Bu, mesajın henüz teslim edilmediği anlamına gelir. Karşındaki kişi muhtemelen şu anda çevrimdışıdır. Mesaj teslim edildiğinde simge değişir. Mesajlar teslimat için en fazla 7 gün boyunca saklanır.

### "WhatsApp'tan Cleona'ya geçebilir miyim?"

Evet, ama WhatsApp sohbetlerini aktaramazsın. Cleona ve WhatsApp tamamen farklı sistemlerdir. Kişilerini Cleona'ya tek tek eklemen gerekir. En kolay yol, cleona:// bağlantını bir WhatsApp grubuna paylaşıp diğerlerinden seni orada eklemelerini istemektir.

### "Cleona'yı birden fazla cihazda aynı anda kullanabilir miyim?"

Evet. Aynı kimlikle 5 cihaza kadar bağlayabilirsin. Bir cihaz birincildir (Seed-Phrase'i taşır) ve diğer cihazlar güvenli bir eşleştirme süreci üzerinden bağlanır. Tüm cihazlar aynı kimliği, kişileri ve sohbetleri paylaşır. Ayrıntılar için Çoklu Cihaz bölümüne bak.

### "App Store engellenmişse güncellemeleri nasıl alırım?"

Cleona, bir App Store'a, web sitesine veya indirme sunucusuna bağımlı olmadan güncellemeleri doğrudan P2P ağı üzerinden alabilir. Ağdaki başka bir kullanıcıda en yeni sürüm varsa, cihazın güncellemeyi oradan yükleyebilir. Gerçekliği, geliştiricinin dijital imzasıyla doğrulanır. Alternatif olarak bir kişin sana uygulamayı bir davet bağlantısı veya USB bellek ile aktarabilir. Daha fazla bilgi için "Yazılım Güncellemeleri" bölümüne bak.

---

## Yardım ve İletişim

Sorularınız varsa veya bir sorunla karşılaşırsanız, güncel bilgileri Cleona web sitesinde ve GitHub'da bulabilirsin. Cleona merkezi olmayan bir proje olduğu için klasik bir müşteri desteği yoktur -- ama yardımcı olmaktan mutluluk duyan aktif bir topluluk vardır.

---

*Bu kılavuz Cleona Chat sürüm 3.1.125'i açıklamaktadır. Bazı özellikler daha yeni sürümlerde değişebilir veya genişleyebilir.*
