# Cleona Chat -- Kullanım Kılavuzu

Version 4.2 | Kasım 2026 itibarıyla

---

## İçindekiler

1. [Cleona Chat nedir?](#1-cleona-chat-nedir)
2. [İlk adımlar](#2-i̇lk-adımlar)
3. [Kişiler](#3-kişiler)
4. [Mesajlar](#4-mesajlar)
5. [Gruplar](#5-gruplar)
6. [Herkese açık kanallar](#6-herkese-açık-kanallar)
7. [Aramalar](#7-aramalar)
8. [Takvim](#8-takvim)
9. [Anketler](#9-anketler)
10. [Birden çok kimlik](#10-birden-çok-kimlik)
11. [Birden fazla cihaz](#11-birden-fazla-cihaz)
12. [Kurtarma](#12-kurtarma)
13. [Ayarlar](#13-ayarlar)
14. [Güvenlik](#14-güvenlik)
15. [Yazılım güncellemeleri](#15-yazılım-güncellemeleri)
16. [Sıkça sorulan sorular](#16-sıkça-sorulan-sorular)

---

## 1. Cleona Chat nedir?

### Senin mesajlaşman, senin verilerin

Cleona Chat, tamamen merkezi sunucu olmadan çalışan bir mesajlaşma uygulamasıdır.
Mesajların kendi cihazından karşı tarafın cihazına gider -- bir şirket
merkezinden, buluttan veya veri merkezinden geçmeden. Yol üzerinde başka bir
cihaz yardımcı olursa, yalnızca şifrelenmiş paketleri iletir. Hiçbir şirket
mesajlarını okuyamaz, depolayamaz veya başkasına veremez, çünkü araya giren bir
şirket yoktur.

### Hesap yok, telefon numarası yok

Cleona'da kaydolmak için bir telefon numarasına da e-posta adresine de ihtiyacın
yok. Kimliğin, ilk başlatmada cihazında otomatik olarak oluşturulan bir
kriptografik anahtar çiftinden oluşur. Bunun anlamı: Kimse seni telefon numaran
veya e-posta adresin üzerinden bulamaz, tabii kendi iletişim bilgilerini kendin
paylaşmadıkça.

### Geleceğe güvenli şifreleme

Cleona, sözde post-quantum şifreleme kullanır. Yani: Geleceğin kuantum
bilgisayarları bile mesajlarını kıramaz. Ayrıntıları anlamak zorunda değilsin --
tek önemli olan, iletişinin mevcut teknolojinin durumuna göre olabildiğince iyi
korunması.

### Sunucu olmadan nasıl çalışıyor?

Cleona'nın ağı yalnızca kullanıcılarının cihazlarından oluşur. Her cihaz bir
düğümdür, hiçbir düğüm diğerinden daha önemli değildir ve her biri yalnızca kendi
komşularını bilir. Dört şey bu ağı özel yapar:

- **Sabit bir nokta yok.** Uygulamada bir sunucu adresi yoktur ve ağ hiçbir tek
  düğüme bağlı değildir. Cleona'yı kapatmak için kapatılabilecek bir şey yoktur.
- **Anında.** Mesajın, onu gönderdiğin an yola çıkar. Hiçbir ritme ve başka hiçbir
  şeye beklemez.
- **Yandan gizleme.** Cihazın, dışarıdan ne zaman gerçekten yazdığının
  anlaşılmaması için sürekli küçük gizleme paketleri gönderir. Hiçbir mesaj buna
  bağlı değildir -- gizleme yalnızca yanında çalışır.
- **Adlar yerine kodlar.** Bir mesajı ileten kişi yalnızca her gün değişen bir kod
  görür. Normal durumda içlerinden hiçbiri göndereni ve alıcıyı aynı anda bilmez;
  istisnalar 14. bölümde yer alır.

**Üç yol, hepsi aynı anda.** Bir mesaj gönderdiğinde Cleona yol yol denemez, uygun
olanların hepsini birden dener. Karşı taraf alımı onaylar onaylamaz diğerleri
iptal edilir.

1. **Aynı ağda:** Aynı Wi-Fi'deyseniz mesaj doğrudan karşıya gider.
2. **Sabit komşular üzerinden:** İnternette cihazın mesajı kendi sabit komşusuna
   verir. O da onu karşı tarafın sabit komşularına (aynı anda en fazla üçüne)
   iletir ve bunlardan biri teslim eder.
3. **Posta kutusu:** Karşı taraf çevrimdışıysa, Cleona mesajı üç komşuda
   şifrelenmiş olarak bırakır. Orada en fazla 7 gün kalır. Karşı taraf yeniden
   çevrimiçi olunca onu alır.

**Ağa nasıl girersin?** Uygulamada bir sunucu adresi yoktur. Giriş noktanı ilk
kişinden alırsın: Daveti, cihazının ilk komşularını bulacağı adresleri içerir.
Aynı Wi-Fi'de Cleona cihazları kendiliklerinden de birbirlerini bulur. O andan
itibaren cihazın her komşuyla birlikte diğerlerini de tanır.

### Platformlar

Cleona; Android, iOS, macOS, Linux ve Windows için kullanılabilir. Bilgisayarlarda
ve Android'de mesajlar ve aramalar saniyeler içinde ulaşır. iPhone'da bu, uygulama
açıkken geçerlidir. Uygulama açık değilken, iOS onu yalnızca ara ara kısa
süreliğine uyandırır; ne zaman olacağına iOS karar verir. Cleona o zaman senin
için saklanan her şeyi alır ve uygulama simgesinde sayı içeren bir bildirim
gösterir. Aramalar, uygulaması açık olmayan bir iPhone'a ulaşmaz. Bu, Apple'ın
kuralıdır, Cleona'nın bir hatası değildir.

---

## 2. İlk adımlar

### Uygulamayı yükle

**Android:**
1. APK dosyasını Cleona web sitesinden veya GitHub Releases'ten indir.
2. Dosyayı telefonunda aç. Gerekirse bilinmeyen kaynaklardan yüklemeye izin ver
   (Android seni otomatik olarak sorar).
3. "Yükle"ye dokun ve kurulum bitene kadar bekle.

**iOS:**
1. iPhone'unda TestFlight davet bağlantısını aç.
2. "Yükle"ye dokun. TestFlight, Apple'ın beta uygulamalarını dağıtmanın resmi
   yoludur.
3. Kurulumdan sonra Cleona'yı ana ekranında bulursun.

**macOS:**
1. DMG dosyasını Cleona web sitesinden veya GitHub Releases'ten indir.
2. DMG'yi aç ve Cleona'yı Uygulamalar klasörüne sürükle.
3. İlk başlatmada macOS, tanımlı bir geliştiricinin uygulamasını açmak isteyip
   istemediğini sorabilir -- bunu onayla.

**Linux (Ubuntu/Debian):**
1. .deb dosyasını Cleona web sitesinden veya GitHub Releases'ten indir.
2. Çift tıklayarak veya terminalde kur: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Cleona'yı uygulama menüsünden veya terminalde `cleona-chat-beta` ile başlat.

**Linux (Fedora/openSUSE):**
1. .rpm dosyasını Cleona web sitesinden veya GitHub Releases'ten indir.
2. Şununla kur: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Cleona'yı uygulama menüsünden veya terminalde `cleona-chat-beta` ile başlat.

**Linux (tüm dağıtımlar -- AppImage):**
1. .AppImage dosyasını Cleona web sitesinden veya GitHub Releases'ten indir.
2. Dosyayı çalıştırılabilir yap: sağ tık, özellikler, çalıştırılabilir, ya da
   terminalde: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Çift tıklayarak ya da terminalde başlat: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Paket adları beta içindir -- şu anda yayımlanan tek sürüm odur; adları
`cleona-chat-beta`'dır.

**Windows:**
1. Yükleyiciyi Cleona web sitesinden veya GitHub Releases'ten indir.
2. Kurulum dosyasını çalıştır ve yönergeleri izle.
3. Cleona'yı Başlat menüsünden veya masaüstü kısayolundan başlat.

### Kimlik oluştur

İlk başlatmada Cleona senin için otomatik olarak yeni bir kimlik oluşturur.
Kendine bir görünen ad verebilirsin -- bu, kişilerinin gördüğü addır. Bu ad
istediğin zaman değiştirilebilir.

### Seed ifadesini yaz -- hepsinden en önemlisi

Kimliğini oluşturduktan sonra Cleona sana 24 söz gösterir. Bu senin **seed
ifaden** -- kişisel kurtarma anahtarın.

**Bu 24 sözü kağıda yaz ve güvenli bir şekilde sakla.**

Neden bu kadar önemli?

- Telefonun bozulursa, kaybolursa veya çalınırsa, bu 24 sözle tüm kimliğini yeni
  bir cihazda geri yükleyebilirsin.
- Seed ifadesi olmadan geri dönüş yolu yoktur. "Parolamı unuttum" düğmesi ve sana
  hesabını geri verebilecek bir destek yoktur -- çünkü sunucuda hiç hesap
  yoktur. Kişilerin de -- kaç tane olursa olsun -- kimliğini geri yükleyemez. Aynı
  kimliğe sahip ikinci bir cihaz sonraki bir sürümde gelecek (11. bölüme bak).
- Seed ifadesini asla başkalarına verme. Bu sözleri bilen biri senin adına
  hareket edebilir.

24 sözü daha sonra, yeniden okumak istersen, ayarlarda "Yedekleme" -> "Kurtarma
ifadesini göster" altında bulursun. Android'de bunun için ekran kilidinle
onaylarsın.

### İlk kişiyi ekle

Biriyle sohbet etmek için o kişiyi önce kişi olarak eklemen gerekir. Bunun için
birkaç yol vardır -- hepsi bir sonraki bölümde açıklanır.

---

## 3. Kişiler

### Senin davetin

Cleona'da kişiler yalnızca bir davetle oluşur. Davetin ilk başlatmadan beri
oradadır -- internetsiz ve cihazın henüz bir komşu bulmamış olsa bile. Onu kimlik
ayrıntı sayfanda bulursun (üst çubuktaki kendi adına dokun).

Davet, tam olarak aynı şeyi içeren iki biçimde gelir:

- karşı taraf yanında duruyorsa **QR kod** olarak, ve
- e-posta, SMS veya başka bir mesajlaşma uygulaması üzerinden gönderdiğin **metin
  satırı** olarak.

Davet bir telefon numarası ve bir dizindeki ad içermez. Açık anahtarlarını ve
karşı tarafın seni ve komşularına hangi adreslerden ulaşacağını içerir. Cleona'yı
yeni yüklemiş biri için davetin bu yüzden ağa giriş noktasıdır.

### QR kod tara (önerilir)

Yüz yüze görüşürseniz:

1. Karşı tarafa davetinin QR kodunu gösterirsin.
2. Karşı taraf artı düğmesine dokunur, "QR kod tara"yı seçer ve kamerayı ekranına
   tutar. Bu, bir bilgisayarın web kamerasıyla da çalışır.
3. İstek sana gelir ve **otomatik kabul edilir** -- çünkü kodu az önce kendin
   gösterdin.

Bir QR kod yalnızca bir kez geçerlidir: İlk geçerli istek kabul edilir, sonrasında
davet tükenir. QR kod en güvenli yöntemdir, çünkü bunu yaparken kişi alışverişini
tam olarak kiminle yaptığınızı bilirsiniz.

### NFC (telefonları birbirine tutun)

Her iki cihaz da NFC destekliyorsa:

1. İkiniz de kişi ekleme işlevini açın.
2. Telefonlarınızı arka arkaya birbirine tutun.
3. Davet aktarılır ve otomatik kabul edilir.

NFC, QR kod gibi yüksek güvenlik sunar, çünkü alışveriş yalnızca fiziksel olarak
yan yana durduğunuzda çalışır.

### Metin satırı gönder

Görüşemiyorsanız:

1. Davetini aç ve metin satırını kopyala.
2. Onu seni ekleyecek kişiye gönder -- e-posta, SMS veya başka bir mesajlaşma
   uygulamasıyla.
3. Diğer kişi satırı Cleona'da kişi ekleme iletişim kutusuna yapıştırır.
4. İstek senin tarafında **"İstekler"** altında görünür. Burada **otomatik kabul
   edilmez**: Kendin karar verirsin, çünkü satırı yol boyunca kimin daha okuduğunu
   bilemezsin.

### Kişi isteklerini kabul et

Gelen bir istek henüz bir kişi oluşturmaz. Sana bir soru sorar ve **"İstekler"**
sekmesinde görünür. Orada adı ve doğrulama düzeyini görür ve seçebilirsin:

- **Kabul et** -- ancak şimdi kişi, senin kişin olur.
- **Reddet** -- istek atılır.
- **Engelle** -- kişi sana başka istek gönderemez.

### Asla sabit komşu olarak kullanma

Bir kişinin menüsünde **"Asla sabit komşu olarak kullanma"** düğmesini bulursun
(varsayılan: kapalı). Açık olduğunda, bu kişi senin için mesaj iletmez ve bu
yüzden ne zaman mesaj gönderdiğini veya aldığını da öğrenmez. Bu, tehlikenin kendi
çevrenden gelmesi durumu için düşünülmüştür.

Tanınmayanlardan (kişi de, ortak bir grubun üyesi de olmayanlardan) Cleona,
böyle bir istek dışında hiçbir şeyi içeri sokmaz -- mesaj, arama, dosya yok. Ve
istek bile yalnızca gönderen önceden küçük bir hesaplama
görevini çözdüyse gelir. Bu, toplu spamı pahalı yapar.

### Doğrulama düzeyleri

Cleona sana bir kişinin kimliğinin ne kadar güvenle doğrulandığını gösterir:

| Düzey | Anlamı |
|-------|-----------|
| Doğrulanmamış | Bağlantısınız, ama arkasında gerçekten doğru kişinin olduğunu hiçbir şey doğrulamaz. |
| Görüldü | Anahtar alışverişi başarılı oldu, şifreli iletişim kurabilirsiniz. |
| Doğrulandı | Yüz yüze buluştunuz ve kamera taraması ya da NFC ile bağlandınız. |
| Güvenilir | Bu kişiyi açıkça güvenilir olarak işaretledin. |

"Doğrulandı" yalnızca yüz yüze alışveriş için vardır. Bir sohbet üzerinden veya
e-postayla gelen davet bu düzeye hiçbir zaman ulaşamaz -- aynı verileri içerse bile.

Bir kişinin anahtarları haber vermeden değişirse, Cleona onu "Doğrulanmamış"a
sıfırlar. Bu, birinin fark edilmeden senin kişin gibi davranmasından seni korur.

---
## 4. Mesajlar

### Metin gönder ve al

Mesajını sadece alttaki giriş alanına yaz ve Enter'a veya gönder düğmesine bas.
Mesajın cihazını terk etmeden önce otomatik olarak şifrelenir.

Gelen mesajlar sohbet geçmişinde görünür.

### Mesajındaki işaretler ne anlama gelir

| İşaret | Anlamı |
|---------|-----------|
| Saat | Mesaj oluşturuldu, ama henüz hiçbir yol onu taşımadı. |
| Bir tik | Mesaj yolda. Bu, karşı tarafını posta kutusunda beklerken de geçerlidir. |
| İki tik | Teslim edildi: Karşı tarafın cihazı alımı onayladı. |
| Uyarı işareti | 14 gün boyunca hiçbir yol mesajı taşıyamadı. Yeniden göndermek için ona dokun. |

**Çevrimdışı bir hata değildir.** Karşı tarafın ulaşılabilir değilse, mesaj
alınana kadar bir tikte kalır -- kaybolmamıştır. Cihazının kendisinin bağlantısı
yoksa, mesaj saatte kalır ve bir yol yeniden var olur olmaz kendiliğinden yola
çıkar. Uyarı işareti, 14 gün boyunca hiçbir yol bulamadığında görünür; ancak o
zaman onu yeniden gönderebilirsin.

Bu, uygulaması açık olmayan bir iPhone için de geçerlidir: Mesaj, iOS uygulamayı
kısa süreliğine uyandırana ya da karşı taraf onu açana kadar posta kutusunda
bekler. Bu, diğer cihazlara göre daha uzun sürebilir.

İki tik yalnızca alıcı kendisi alımı onayladığında vardır. Bu alındı onayı
şifrelidir ve imzalıdır -- yolda hiçkimse sana sahte bir teslim göstermek için onu
sahteleştiremez.

### Resim, video ve dosya gönder

Birkaç seçeneğin var:

- Giriş alanındaki **ataş simgesi**: Galerinden veya dosya sisteminden bir dosya,
  resim veya video seçmek için ona dokun.
- **Sürükle ve bırak** (masaüstü): Bir dosyayı sohbet penceresine sürükle.
- **Panodan yapıştır** (masaüstü): Bir resmi kopyala ve sohbete yapıştır.

Küçük dosyalar (256 KB altı) doğrudan mesajın içinde yolculuk eder. Daha büyük
dosyalar parçalara bölünür ve bir hata düzeltmesiyle donatılır, böylece tek tek
kaybolan parçaların bir önemi olmaz. İkiniz de çevrimiçiyse bir komşu üzerinden
akıtılır; değilse, karşı tarafın onları alana kadar sürekli ulaşılabilir
cihazlarda bırakılır.

256 KB'dan itibaren Cleona, her dosya için gönderilmeden önce sana sorar: Büyük
bir dosya, mesajlarının yolunu alamaz. İçeriği şifreli kalır ve karşı tarafın
internet adresini öğrenmez. Ama aktarım dışarıdan bir olay olarak görünür ve onu
ileten ya da saklayan yabancı bir cihaz, kimin yüklediğini ve kimin aldığını
görür. Onayın yalnızca o tek dosya için geçerlidir.

### Sesli mesajlar

1. Giriş alanındaki mikrofon düğmesine basılı tut.
2. Mesajını söyle.
3. Mesajı göndermek için düğmeyi bırak.

Cihazında konuşma tanıma etkinse (ayarlara bak), sesli mesajın otomatik olarak
metne çevrilir. Karşı tarafın hem kaydı hem de çevrilmiş metni görür.

### Mesajları yanıtla (alıntı)

Belirli bir mesajı yanıtlamak için:

1. Mesajın yanındaki üç nokta menüsünü aç.
2. "Yanıtla"yı seç.
3. Giriş alanının üstünde alıntılanan mesajı içeren bir banner görünür.
4. Yanıtını yaz ve gönder.

Alıntılanan mesaj yanıtında gösterilir, böylece ilişki açıktır.

### Mesajları düzenle ve sil

- **Düzenle:** Mesajın üç nokta menüsü, sonra "Düzenle". Metni değiştir ve yeniden
  gönder. Karşı tarafın mesajın düzenlendiğini görür. Düzenleme, gönderdikten
  sonra 15 dakika içindedir.
- **Sil:** Mesajın üç nokta menüsü, sonra "Sil". Mesaj sende ve karşı tarafında
  kaldırılır. Kendi mesajlarını istediğin zaman silebilirsin -- silme için bir
  zaman penceresi yoktur.

### Emoji tepkileri

Bir yanıt yazmak yerine, bir mesaja bir emojiyle tepki verebilirsin:

1. Üç nokta menüsünü aç ya da mesaja uzun bas.
2. Hızlı seçimden bir emoji seç ya da tam seçim için emoji seçicisini aç.
3. Tepkin mesajın altında görünür.

### Metni kopyala

Bir mesajın üç nokta menüsü üzerinden mesaj metnini panoya
kopyalayabilirsin.

### Mesajları ara

Sohbet penceresinin üst kenarında arama işlevini bulursun. Bir arama terimi gir ve
Cleona sana geçerli sohbetteki tüm eşleşmeleri gösterir. Ok tuşlarıyla eşleşmeler
arasında ileri-geri atlayabilirsin.

Başlangıç sayfasında ayrıca tüm konuşmaları bir terime göre arayabileceğin
sekmeler arası bir arama süzgeci vardır.

### Bağlantı önizlemesi

Bir bağlantı gönderdiğinde Cleona otomatik olarak bir önizleme (başlık,
açıklama, önizleme resmi) oluşturur. Bu önizlemeyi cihazın oluşturur ve birlikte
gönderir -- karşı tarafın bunun için bağlantılı web sitesine bağlantı kurması
gerekmez.

Aldığın bir bağlantıya dokunmanın ne yapacağını ayarlarda "Bağlantıları aç"
altında ayarlarsın: "Normal", "Gizli pencereyi tercih et" (cihazın gizli
pencere açamadığı yerde bağlantı normal açılır) ya da "Her seferinde sor".

---

## 5. Gruplar

### Grup oluştur

1. "Gruplar" sekmesine geç.
2. Artı düğmesine dokun.
3. Gruba bir ad ver.
4. Davet etmek istediğin kişileri seç.
5. "Oluştur"a dokun.

Davet edilen kişiler bir bildirim alır ve gruba katılabilir.

### Grup mesajları nasıl korunur

En fazla 16 üyeli bir grupta Cleona her mesajı her üyeye tek tek gönderir --
her biri yalnızca o üye için şifrelenir, tıpkı her birine ayrı bir mesaj yazmışsın
gibi. Bir grup mesajındaki tikler, en az ilerlemiş olan üyenin durumunu gösterir.

Grup 16 üyeyi aşarsa, ortak bir anahtar kullanır. Bu anahtar her gün değişir ve
bir üye ayrıldığında ya da kaldırıldığında yeniden oluşturulur; yeni bir üye
yalnızca katıldığı andan itibaren okur. Orada tikler artık her üyenin durumunu
değil, mesajın ağda bulunduğunu gösterir. Grup 12 ya da daha az üyeye düşerse,
tek tek gönderime geri döner.

### Gruplarda ve kanallarda görseller

Bir grubun ya da kanalın ayarlarında "Görselleri her zaman yükle" ile
görsellerin hemen mi yükleneceğini yoksa birine doktuğunda mı yükleneceğini
belirlersin.

### Üye davet et

Oluşturduktan sonra da başka kişileri davet edebilirsin:

1. Grup bilgisini aç (grup genel bakışındaki üç nokta menüsü ya da grup
   sohbetindeki üst çubuk).
2. "Davet et"e dokun.
3. Eklemek istediğin kişileri seç.

### Roller

Her grubun üç rolü vardır:

- **Sahip (Owner):** Tam kontrole sahiptir. Üye ekleyip kaldırabilir, yöneticiler
  atayabilir ve grubu yönetebilir. Sahip, durumunu başka bir üyeye de
  devredebilir.
- **Yönetici:** Üye kaldırabilir ve yönetime yardım edebilir.
- **Üye:** Mesaj okuyup yazabilir.

### Gruptan ayrıl

1. Grup genel bakışındaki üç nokta menüsünü aç.
2. "Ayrıl"ı seç.
3. Kararını onayla.

Bir gruptan ayrıldığında, önceki mesajların diğer üyeler için görünür kalır.

---

## 6. Herkese açık kanallar

### Kanallar nedir?

Kanallar, Cleona ağı içindeki herkese açık tartışma forumlarıdır. Grupların
aksine burada davet edilmeden herkes okuyabilir. Yalnızca sahip ve yöneticiler
gönderi yayımlayabilir -- aboneler okur.

### Kanal bul ve katıl

1. "Kanallar" sekmesine geç.
2. "Arama" sekmesini aç.
3. Kullanılabilir kanalları ad veya konuya göre ara.
4. Bir kanala dokun ve sonra "Abone ol"a dokun.

Kanallar dile göre süzülebilir. Bazı kanallar "Reşit olmayanlar için uygun değil"
olarak işaretlidir -- bunlar yalnızca profilinde 18 yaşın üzerinde olduğunu
onayladıysan görünür.

### Kendi kanalını oluştur

1. "Kanallar" sekmesine geç.
2. Artı düğmesine dokun.
3. Bir kanal adı gir (tüm ağda benzersiz olmalıdır).
4. Dili ve kanalın herkese açık mı yoksa özel mi olacağını seç.
5. İsteğe bağlı: bir açıklama ve resim ekle.
6. "Oluştur"a dokun.

Herkese açık kanallarda içeriğin "Reşit olmayanlar için uygun değil" olarak
sınıflandırılıp sınıflandırılmayacağını belirleyebilirsin.

### İçerik bildir

Herkese açık bir kanalda uygunsuz içerik fark edersen bunu bildirebilirsin.
Cleona merkeziyetsiz bir moderasyon sistemi kullanır: Bildirimler ağdan rastgele
seçilen üyeler tarafından değerlendirilir (bir tür "jüri"). İhlal bulunursa kanal
bir uyarı alır. Yinelenen ihlallerde arama dizininde düşürülür ya da engellenir.

### Sistem kanalları

Cleona'nın iki yerleşik sistem kanalı vardır:

- **Bug Log:** Cleona bir hata algıladığında, bir hata raporu göndermek isteyip
  istemediğini sana sorar; önce neyin yayımlanacağını tam olarak görürsün. Bu
  raporlar, topluluk tarafından incelenebileceği Bug Log kanalına düşer. Bir
  rapor ad ve konuşmalarının içeriğini taşımaz, yalnızca bir rumuz taşır. Betada
  ayrıca geliştiricilerin soru sorabilmesi için kullanıcı kimliğini (User-ID)
  belirtir. El ile de bir günlük raporu gönderebilirsin (önizleme iletişim kutusu
  ve açık onayla).
- **Feature Requests:** Burada kullanıcılar işlev istekleri gönderebilir ve var
  olan önerilere oy verebilir. Öneriler oylara göre sıralanır.

Her bilgisayar sistem kanalı başına 25 MB'a kadar, her telefon 5 MB'a kadar
tutar; alan dolunca önce en eskisi gider -- senin çoktan görmüş oldukların asla.

---
## 7. Aramalar

### Sesli arama başlat

1. Aramak istediğin kişinin sohbetini aç.
2. Üst çubuktaki telefon simgesine dokun.
3. Karşı tarafın aramayı kabul etmesini bekle.

Görüşme sırasında bir zaman çizelgesi, görüşme süresi görürsün ve sessize alma
ile hoparlöre erişebilirsin.

Kapatmak için kırmızı kapat düğmesine dokun.

"Ulaşılamıyor" görürsen, karşı tarafın cihazına şu anda ulaşılamıyordur; örneğin
uygulaması açık olmayan bir iPhone. Bunun yerine bir mesaj yaz.

### Görüntülü arama başlat

1. Kişinin sohbetini aç.
2. Üst çubuktaki kamera simgesine dokun.
3. Görüntün küçük bir pencerede, karşı tarafın görüntüsü büyük alanda görünür.

Görüşme sırasında ön ve arka kamera arasında geçiş yapabilirsin.

### Gelen aramalar

Biri seni aradığında, arayanın adını içeren bir bildirim penceresi görünür.
Şunları yapabilirsin:

- **Kabul et** -- görüşme başlar.
- **Reddet** -- arayana bildirilir.

Şu an bir görüşmedeysen, yeni bir arama çalmaz; bunun yerine "Cevapsız arama"
mesajı alırsın. Aynı şey, kabul etmediğin bir grup araması için de geçerlidir --
mesaj o zaman grup sohbetinde durur.

Biri şu an görüntülenmeyen kimliklerinden birini ararsa, telefon yine de çalar;
arama ekranı, kimliklerinden hangisinin arandığını belirtir.

iPhone'da yalnızca uygulama açıkken çalar. Uygulama açık değilken seni arayan kişi
10 saniye sonra "Ulaşılamıyor" görür. Uygulamayı açar açmaz cevapsız arama
mesajını bulursun.

### Grup aramaları

Birkaç kişinin aynı anda katıldığı grup aramaları da yapabilirsin. Arama, akıllı
bir iletme ağacı üzerinden düzenlenir, böylece her katılımcının her diğerine
doğrudan bağlanması gerekmez. Tüm görüşmeler baştan sona şifrelidir.

Her grup üyesi bir grup araması başlatabilir. Birbirinin kişisi olmayan iki
katılımcı, diğerinin internet adresini asla görmez: Sesleri ve görüntüleri,
ikisiyle de kişi olan bir katılımcı üzerinden yürür. Böyle biri yoksa, ikisi
bağlanmaz ve kutucuk "Görüşmede ortak kişi yok" der. Bir iletme hattı doluysa
ses kalır ve bu çift için video düşer.

### Aramalarda şifreleme

Tüm aramalar yalnızca görüşme süresince var olan tek kullanımlık anahtarlarla
şifrelenir. Kapatınca bu anahtarlar hemen silinir. Hiçkimse geçmiş bir görüşmeyi
sonradan şifresini çözemez.

Açıkçası: aramalar, mümkün olduğunca cihazlar arasında doğrudan yürür, çünkü
konuşurken bile küçük bir gecikme rahatsız eder. Mesajların aksine, bu yüzden
internet sağlayıcın bir arama sırasında hangi internet adresine bağlı olduğunu
görebilir. Ne söylediğinizi göremez.

Bir aramada kişin de internet adresini görür. Bunu bir kişide istemiyorsan, onun
menüsünde "Aramalara izin ver"i kapat (varsayılan: açık). Daha sonra kapatırsan,
kişinin zaten görmüş olduğu bir adres onda bilinen olarak kalır.

---

## 8. Takvim

Cleona, şifreli ve tamamen merkeziyetsiz çalışan -- bulut hizmeti olmayan --
yerleşik bir takvim içerir.

### Görünümler

Takvim beş görünüm sunar: gün, hafta, ay, yıl ve bir görevler görünümü. Takvim
ekranının üst kenarındaki sekmeler üzerinden aralarında geçiş yap.

### Randevu oluştur

Bir zaman dilimine dokun ya da yeni bir randevu oluşturmak için ekle düğmesini
kullan. Başlık, tarih, saat, yer ve notlar girebilirsin. Randevular cihazında
şifreli olarak depolanır.

### Yinelenen randevular

Randevular günlük, haftalık, aylık veya yıllık yinelenebilir. Düzeni
uyarlayabilirsin (ör. her ikinci Salı, her ayın biri) ve bir bitiş tarihi ya da
yineleme sayısı belirleyebilirsin.

### Kişi davet et

Bir randevu oluştururken ya da düzenlerken Cleona kişilerini davet edebilirsin.
Onlar şifreli bir takvim daveti alır ve evet, hayır veya belki yanıt verebilir.
Randevudaki değişiklikler otomatik olarak tüm davetlilere gönderilir.

### Müsait/meşgul görünümü

Kullanılabilirliğini kişilerle, randevu ayrıntılarını açıklamadan
paylaşabilirsin. Üç gizlilik düzeyi vardır: tam ayrıntı, yalnızca zaman blokları
ya da gizli. Bir varsayılan belirleyebilir ve onu kişi bazında geçersiz
kılabilirsin.

### Hatırlatıcılar

Randevular, randevu başlamadan önce bir sistem bildirimi tetikleyen
hatırlatıcılara sahip olabilir. Gerekirse hatırlatıcıları erteleyebilirsin.

### Dış takvim eşitleme

Cleona, dış takvim hizmetleriyle eşitleyebilir:

- **CalDAV** -- Herhangi bir CalDAV uyumlu sunucuya bağlan (Nextcloud, Radicale
  vb.).
- **Google Takvim** -- Güvenli OAuth2 kimlik doğrulamasıyla Google Calendar API
  üzerinden eşitleme.
- **Yerel CalDAV sunucusu** -- Cleona, cihazında yerel bir CalDAV sunucusu
  başlatabilir, böylece masaüstü takvim uygulamaları (Thunderbird, Outlook, Apple
  Takvim, Evolution) Cleona takvimle eşitleyebilir.
- **Android sistem takvimi** -- Cleona'daki randevular, Android cihazının yerleşik
  takvim uygulamasına aktarılabilir.
- **ICS dosyaları** -- Randevuları standart iCalendar biçiminde içe ve dışa
  aktar.

### PDF dışa aktarma

Her takvim görünümünü (gün, hafta, ay, yıl) bir PDF belgesi olarak
yazdırabilir ya da dışa aktarabilirsin.

---

## 9. Anketler

Görüş toplamak ya da tarih planlamak için her sohbette veya her grupta anket
oluşturabilirsin.

### Anket türleri

Cleona beş anket türünü destekler:

- **Tek seçim** -- katılımcılar bir seçenek seçer.
- **Çoklu seçim** -- katılımcılar birkaç seçenek seçebilir.
- **Tarih anketi** -- Herkese uygun bir tarih bul. Her katılımcı tarihleri
  müsait, belki veya müsait değil olarak işaretler.
- **Ölçek** -- Bir şeyi sayısal bir ölçeğe göre değerlendir (ör. 1'den 5'e).
- **Serbest metin** -- katılımcılar kendi yanıtlarını yazar.

### Anket oluştur

Bir sohbet aç ve anket simgesine dokun (ya da ek menüsünü kullan). Anket türünü
seç, sorunu ve seçenekleri ifade et ve anketi gönder. Sohbette bir mesaj olarak
görünür.

### Oy ver

Oy vermek için bir ankete dokun. Oyunu istediğin zaman değiştirebilir veya geri
çekebilirsin.

### Anonim oylama

Anketler anonim oylama için yapılandırılabilir. Etkinleştirildiğinde oylar
kriptografik olarak anonimdir -- hiçkimse, anket oluşturucu bile, neye kimin oy
verdiğini göremez. Yine de oy sayısı görünür kalır.

### Tarih anketini takvime

Bir tarih anketi bittiğinde, kazanan tarih bir dokunuşla doğrudan bir takvim
girdisine dönüştürülebilir.

---
## 10. Birden çok kimlik

### Neden birden çok kimlik?

Düşün: iş yaşamını ve özel yaşamını ayırmak istiyorsun -- iki farklı telefon
numarasıyla benzer, ama ikinci bir telefon olmadan. Cleona'da tek bir cihazda
birden çok kimlik kullanabilirsin. Her kimliğin kendi adı, kendi profil resmi,
kendi kişileri ve kendi konuşmaları vardır.

### Yeni kimlik oluştur

1. Üst çubukta geçerli kimliğini sekme olarak görürsün.
2. Kimlik sekmelerinin sağındaki artı işaretine (+) dokun.
3. Yeni kimlik için bir ad gir.
4. Hazır -- yeni kimlik hemen etkin.

### Kimlikler arasında geçiş yap

Üst çubuktaki kimlik sekmesine dokun. Geçiş anlıktır -- bekleme süresi yok,
yeniden yükleme yok.

### Hepsi aynı anda yürür

Önemli bir nokta: tüm kimliklerin aynı anda etkindir. Şu an "İş" olarak
görünsen bile "Özel" kimliğin mesaj almaya devam eder. Hangi kimliği seçmiş
olursan ol, hiçbir şeyi kaçırmazsın.

### Kimlik ayrıntı sayfası

Şu an etkin olan kimliğinin sekmesine dokunduğunda ayrıntı sayfası açılır. Burada
şunları yapabilirsin:

- Kişiler için QR kodunu göster.
- Profil resmini değiştir veya kaldır.
- Bir profil açıklaması ekle.
- Görünen adını değiştir.
- Bu kimlik için bir tasarım (skin) seç.
- Artık gerekmiyorsa kimliği sil.

### Kimliği sil

Bir kimliği sildiğinde, kişilerin bundan haberdar edilir. Kimlik ve ilişkili tüm
veriler cihazından kaldırılır. Bu işlem geri alınamaz.

---

## 11. Birden fazla cihaz

### Bir kimlik, bir cihaz -- şimdilik

Bir kimlik bugün tek bir cihazda çalışır. Aynı kimlik için ikinci bir cihaz
sonraki bir sürümde gelecek; ayarlarda "Cihazlar" -> "Cihazları yönet" altında
"Başka bir cihaz eşleştir" bu yüzden hâlâ "Henüz kullanılamıyor" olarak durur.

Geldiğinde şunlar geçerli olacak: Tüm cihazlar eşit haklı olacak, bir ana cihaz
olmayacak. Başka bir cihazı 24 sözünle kuracaksın ve şimdiye kadarki
cihazlarından biri onaylayacak. En fazla 5 cihaz.

Bugün yeni bir cihazda 24 sözünü girersen taşınmış olursun: Kimlik yeni cihaza
geri yüklenir ve şimdiye kadarki cihaz onu daha sonra kendinden siler
(12. bölüme bak).

Birden fazla cihazda bugün farklı kimlikler kullanabilirsin (10. bölüm).

### Kimliği yeniden anahtarla

Birinin anahtarlarına ulaştığını sanıyorsan, "Cihazları yönet" -> "Anahtarları
döndür" altında yeni anahtarlar oluşturabilirsin. Kişilerin haberdar edilir, açık
davetlerin geri alınır. Önemli: Ondan sonra 24 söz tek başına yalnızca eski
anahtarları geri getirir. Bu yüzden hemen ardından yeni bir kurtarma paketi
oluştur; geri yüklemeyi ancak bu paketle birlikte yapabilirsin.

---

## 12. Kurtarma

### Seed ifadesini kullan

Cihazını kaybedersen ya da yeni bir tane kurarsan:

1. Yeni cihaza Cleona'yı yükle.
2. Başlangıçta "Geri yükle"yi seç.
3. 24 sözünü gir.
4. Cleona onlardan tüm kimliklerini yeniden oluşturur -- önceki gibi aynı
   anahtarlarla. Kişilerin için aynı insansın.

### Geri gelen -- ve gelmeyen

Kimliğin 24 sözün içindedir, kişilerin ve geçmişin değil. Ağ erişimin **Kurtarma
paketi** üzerinden geri gelir: Cihazın ağa küçük, şifreli bir paket bırakır.
Onu yalnızca 24 sözün bulup açabilir. İçinde, yeni cihazının kişilerine yeniden
ulaşmak için neye ihtiyaç duyduğu ve bu arada senin için ağda neyin durduğu
yazar. Bunun için hiçbir kişinin çevrimiçi olması gerekmez.

Bir geri yükleme, şimdiye kadarki sohbet geçmişini geri getirmez.

Kurtarma paketi 7 gün yaşar ve cihazın çalıştığı sürece yenilenir; ayarlarda ne
zamana kadar geçerli olduğunu görürsün. Cihazlarından hiçbiri 7 günden uzun
süredir çalışmadıysa, süresi dolmuş demektir. O zaman da 24 söz kimliğini yine
geri getirir, ama kişilerini yeniden davet etmen gerekir; bu arada senin için
ağda duran şeyler kaybolmuştur.

### Geri yüklemek taşınmak demektir

Şimdiye kadarki cihazın daha sonra kimliğin başka bir yerde geri yüklendiğini
fark ederse, onu -- geçmişiyle birlikte -- kendinden siler. Bu yüzden: 24
sözüne sahip olan biri, kimliğini bu yolla cihazından alabilir. Tüm kişiler
yeniden gelene kadar uygulama seni hatırlatır; "Tamamla ve anahtarları yenile"
ile geri yüklemeyi kendin bitirirsin.

### Hiçbir kişinin geri yükleyemeyeceği şey

Bu önemlidir, ve bu yüzden açıkça söylüyoruz:

- **Senden başka hiçkimse kimliğini geri yükleyemez.** Geliştirici de değil, bir
  destek de değil, kişilerin de değil -- kaç tane olursa olsun. Bir ana anahtar
  ve başkalarına bırakılmış anahtarının bir parçası yoktur.
- **24 sözü kaybettiysen ve hiç cihazın kalmadıysa, kimliğin kaybolmuştur.** O
  zaman tek seçenek yeni bir tane oluşturmak ve kişilerini yeniden davet
  etmektir.

En iyi koruma: 24 sözü kağıda yaz ve güvenli bir şekilde sakla.

---
## 13. Ayarlar

Ayarlara sağ üst köşedeki dişli simgesinden ulaşırsın.

### Bildirimler ve zil sesleri

- Gelen aramalar için altı farklı zil sesinden seç.
- Bir mesaj sesi ayarla.
- Android cihazlarda ayrıca titreşimi etkinleştirebilir veya devre dışı
  bırakabilirsin.
- **"Her şeyi sessize al"**: Bu cihazda hiçbir mesaj artık çalmaz, titreşmez ya
  da kendini bildirmez -- tüm kimlikler için. Aramalar çalmaya devam eder.
- **"Sessiz saatler"**: Bunları kimlik başına Başlangıç/Bitiş ile belirlersin.
  Bu sürede bu kimliğin hiçbir mesajı çalmaz, titreşmez ve kendini bildirmez;
  mesajlar yine de ulaşır.
- **"İçeriksiz bildirimler"** (varsayılan: kapalı): Yalnızca bir mesaj, davet ya
  da hatırlatıcının geldiğini gösterir -- gönderen, ad ve metin olmadan. Aramalar
  adı göstermeye devam eder.
- Başlangıçtan sonra birden gelen her şeyi Cleona bir toplu bildirimle bildirir
  ("2 konuşmada 5 yeni mesaj"); sonrasını tek tek bildirir. Bir mesaj
  bildirimine dokunmak konuşmayı açar -- başka bir kimlikte olsa bile.

### Tasarımlar (skin)

Cleona on farklı tasarım sunar: Teal, Ocean, Sunset, Forest, Amethyst, Fire,
Storm, Slate, Gold ve Contrast. Contrast tasarımı en yüksek erişilebilirlik
düzeyini (WCAG AAA) karşılar ve sınırlı görmeyle özellikle iyi okunur.

Her kimliğin kendi tasarımı olabilir. Tasarımı kimlik ayrıntı sayfasında
değiştirirsin (etkin kimlik sekmesine dokun).

Ek olarak, ayarlarda "Görünüm" altında açık, koyu ve sistem teması arasında geçiş
yapabilirsin.

### Dili değiştir

Cleona 34 dilde kullanılabilir, buna sağdan-sola yazılan diller de dahildir (ör.
Arapça, İbranice). Dili ayarlarda "Dil" altında değiştir.

### Medya arşivleme

Evde bir ağ deposu (NAS) ya da paylaşılan bir klasörün varsa, Cleona medyanı
otomatik olarak oraya taşıyabilir. SMB, SFTP, FTPS ve WebDAV desteklenir.

Kademeli depolama şöyle çalışır:
- İlk 30 gün: her şey cihazında kalır.
- 30 gün sonra: cihazda bir önizleme resmi kalır, özgün hali arşivlenir.
- 90 gün sonra: cihazda yalnızca küçük bir önizleme resmi kalır.
- Bir yıl sonra: yalnızca bir yer tutucu kalır, özgün hali güvenle arşivde yatar.

Arşivlenmiş bir medyaya, geri getirmek için istediğin zaman
dokunabilirsin -- ev ağına bağlı olduğun varsayımıyla. Özellikle önemli medyalar,
hiç dışa taşınmamaları için sabitlenebilir.

"Depolama bütçesi" altında, cihazda kaç MB medyanın kalacağını belirlersin
(varsayılan: telefonda 100 MB, bilgisayarda 2 GB). Alan dolunca, sabitlenmemiş en
eski medya önce arşivlenir. Bir özgün hâl yalnızca arşivde güvenle durduğunda
silinir -- metin mesajları her zaman korunur.

### Sesli mesajlar için metne çevirme

Etkinleştirildiğinde, sesli mesajların cihazında yerel olarak metne çevrilir (açık
kaynak modeli Whisper ile). Çevrilmiş metin, kayıtla birlikte karşı tarafına
gönderilir. Metne çevirme tamamen cihazında olur -- hiçbir veri dış hizmetlere
gitmez.

Hangi modelin (tiny, base, small) indirileceğini cihaz için bir kez ayarlarsın;
dili (otomatik ya da sabit) kimlik başına ayarlarsın.

### Otomatik indirme

Medyanın hangi boyuttan itibaren otomatik indirileceğini ayarlayabilirsin. Böylece
örneğin resimleri otomatik yükletebilir, ama büyük videolarda el ile karar
verebilirsin.

### Cihazlar

"Cihazlar" -> "Cihazları yönet" altında bu cihazı görürsün. Başka bir cihaz
eşleştirmek sonraki bir sürümde gelecek (11. bölüm).

### Ağ

Cleona'nın çalışması için ağ ayarlarına gerek yoktur. Üç ağ düğmesi vardır:

- **Yönlendiricide port açma** (varsayılan: açık). Cleona, kendi yönlendiricinden
  Cleona için bir kapı açmasını ister. Bu işlerse, cihazın başkaları için daha iyi
  ulaşılabilir olur ve ağa yardım eder. Cleona bu sırada yalnızca yönlendiricinle
  konuşur, internetle değil.
- **Herkese açık adres girdileri** (varsayılan: açık). Cihazının hâlâ çok az
  komşusu varsa, daha fazla giriş noktası için herkese açık bir dizine (Nostr)
  bakar ve kendisi de iyi ulaşılabilirse oraya kendini girer. Girdi bir adres
  içerir, ad ve kişi içermez. Kapatırsan, cihazın komşuları yalnızca davetler,
  yerel ağ ve hâlâ bildiği komşular üzerinden bulur.
- **Wi-Fi'de daha az gizleme paketi** (varsayılan: kapalı). Wi-Fi'de ya da
  kabloda boş gizleme paketlerini kapatabilirsin. Ama o zaman ne zaman yazdığın
  yine görünür olur. Mobil veride böyle bir düğme yoktur -- orada Cleona zaten
  yalnızca dakikada bir gizleme paketi gönderir.

Gizleme trafiğinin tamamı kapatılamaz. Bu bilerek böyledir: yalnızca hep
çalıştığında cihazının etkinliği, şu an yazıp yazmadığın hakkında hiçbir şey
söylemez.

Üç düğmenin üstünde **veri tasarrufu modu** durur: Mobil veride Cleona onu
önerir, ama asla kendi kendine açmaz. Veri tasarrufu sağlar, buna karşılık
cihazın dışarıdan daha kolay tanınır hale gelir.

Onun altında **"Başkalarının medyası için önbellek"** ayarını yaparsın: Cihazın,
başkalarının medyalarının şifreli parçalarını, alıcılarına ulaşsınlar diye 7 güne
kadar tutar (varsayılan: telefonda 100 MB, bilgisayarda 1 GB). Daha küçük bir
boyut, alanı hemen boşaltır -- önce en eski parçalar.

---

## 14. Güvenlik

### Post-quantum şifreleme ne demektir?

Günümüz şifrelemesi, normal bilgisayarlar için çözülmesi son derece zor olan
matematiksel problemlere dayanır. Kuantum bilgisayarlar gelecekte bu
sorunlardan bazılarını hızla çözebilir. Post-quantum şifreleme, kuantum
bilgisayarlara da dayanan ek yöntemler kullanır.

Cleona her iki yaklaşımı birleştirir: güvenilirlik için klasik şifreleme ve
geleceğe güvenlik için post-quantum yöntemleri. Böylece bugünün ve geleceğin
tehditlerine aynı anda karşı korunursun.

Her tekil mesaj için ayrı bir anahtar oluşturulur. Bir saldırgan bir mesajın
anahtarını kırmış olsa bile, onunla başka hiçbir mesajı okuyamaz.

### Neden sunucu olmaması daha güvenli

Geleneksel mesajlaşma uygulamalarında mesajların sağlayıcının sunucularından geçer.
Orada şifreli olsalar bile: sağlayıcı, üst verilere (kim, ne zaman, kiminle, ne
sıklıkta, nereden iletişim kuruyor) erişebilir ve bunları bir mahkeme kararıyla
vermek zorunda kalabilir.

Cleona'da böyle merkezi bir nokta yoktur. Tüm üst verilerin toplandığı bir yer ve
kim olduğunu ya da kimi tanıdığını bakabileceğin bir dizin yoktur.

### Kim, biriyle yazıştığını görür?

Şifreleme, **neyi** yazdığını korur. En az bunun kadar önemli olan, **tek bir
gözlemcinin** **kiminle** ve **ne zaman** yazdığını öğrenmemesidir. Cleona bunu
şöyle sağlar:

- **İnternette asla doğrudan.** Cihazın bir mesajı doğrudan karşı tarafın internet
  adresine gönderseydi, sağlayıcın kiminle yazıştığını görebilirdi. Bu yüzden
  internette bir mesaj her zaman sabit komşularınız üzerinden gider: senin ve
  karşı tarafın.
- **Güvendiğin komşular.** Sabit komşuların, mümkün olduğunca, kendi kişilerinin
  cihazlarıdır -- dışarıdan şu an ulaşılabilen en fazla üçü. Biri düşerse, başka
  bir kişi sıraya girer. Bir kişi sunucularla satın alınamaz; ağda rasgele bir
  düğüm olabilir. Henüz ulaşılabilir kişin yoksa, Cleona başka bir komşu alır.
  Davetin, kişilerinden hiçbirini hiçbir zaman ad göstermez, böylece hiç kimse
  onlar üzerinden bir arkadaşının adresini öğrenemez.
- **Adlar yerine kodlar.** Komşular ad ve tanıtıcı görmez, yalnızca bir kod görür.
  O, tam ikiniz için, tek yönde, tek bir gün için geçerlidir -- ertesi gün başka
  bir tanedir. Komşun paketin nereden geldiğini bilir, ama sonunda nereye
  gittiğini bilmez. Karşı tarafının komşusu nereye gittiğini bilir, ama nereden
  geldiğini bilmez. Normal durumda yolda hiç kimse her iki ucu görmez.
- **Gizleme trafiği.** Cihazın, düzensiz aralıklarla, komşularına sürekli gizleme
  paketleri gönderir. Onlar gerçek paketler kadar büyüktür, aynı porttan gider ve
  dışarıdan onlardan ayırt edilemezler. Şu an bir insan yazıyor mu yoksa cihaz
  yalnızca çalışıyor mu, bundan anlaşılamaz. Mesajların asla gizleme trafiğini
  beklemez -- hemen yola çıkarlar, o yalnızca yanında yürür.

**Gizleme trafiğinin maliyeti:** Wi-Fi'de günde yaklaşık 13 MB. Mobil veride
Cleona yalnızca dakikada bir gizleme paketi gönderir, bu da günde yaklaşık 1,7 MB
yapar. Mobil veride yavaşlamanın nedeni veri miktarı değil, bataryadır: her paket
radyo modemini uyandırır.

**Cleona'nın gizleyemediği** -- açıkçası:

- Hiçbir **tek** gözlemci kimin kimle yazdığını görmez -- ne sağlayıcın ne de
  yoldaki düğümler. Ama **her iki ucu aynı anda** izleyen, örneğin senin
  bağlantını ve karşı tarafınkini izleyen ya da her iki komşuyu da kuran bir
  devlet, zaman içinde eşleştirebilir: sende paket çıkar, kısa süre sonra karşı
  tarafında paket girer. Yeterince sık yinelenirse, bu bir bağ kurar.
- Gizleme trafiği bu eşleştirmeyi zorlaştırır ama engellemez. Tekil mesajları
  gizler, miktarı gizlemez: çok gönderen, cihazının toplam trafiğini artırır.
- Sabit komşun olan bir kişi, **ne zaman** ve **ne kadar** gönderip aldığını
  öğrenir -- kiminle ve ne olduğunu değil. Tehlike kendi çevrenden geliyorsa, her
  kişiyi bundan çıkarabilirsin (3. bölüme bak, "Asla sabit komşu olarak
  kullanma").
- İki yeni kullanıcının yalnızca aynı tek komşusu varsa, mesajları tam bu düğüm
  üzerinden yürür ve o her iki ucu görür. İkisinden biri başka komşular edindiği
  an bu biter.
- Davetin internet adreslerini içerir. Metin satırına sahip olan, nerede
  çevrimiçi olduğunu görür -- onu yalnızca buna güvendiğin insanlara ver.
- İleten bir komşu, iki kodun paket alışverişi yaptığını görür -- arkasında kim
  olduğunu ve içinde ne olduğunu değil.
- Devam eden bir aramanın sinyali, ilk komşu o anda yanıt vermezse, her iki ucu
  gören bir düğümden geçebilir; o da sizin birlikte telefonlaştığınızı öğrenir.
- Onay verdiğin büyük bir dosyayı, onu ileten ya da saklayan bilgisayar her iki
  uçta görür (4. bölüme bak).
- Aramalarda sağlayıcıya karşı koruma geçerli değildir ve kişin internet adresini
  görür (7. bölüme bak).

### Karşı tarafın çevrimdışıyken ne olur?

1. Cleona tüm uygun yolları aynı anda başlatır: aynı Wi-Fi'de doğrudan, internette
   iki komşu üzerinden -- ve ek olarak posta kutusu.
2. Posta kutusu için Cleona şifreli mesajı üç komşuda bırakır. İkisi alımı
   onaylar onaylamaz, bırakılmış sayılır.
3. Cleona bunun için, karşı tarafının da baktığı komşuları yeğler -- önce
   davetinin adını söylediği komşuyu.
4. Mesaj orada en fazla 7 gün bekler. Karşı tarafın döndüğünde onu alır ve sana
   alımı onaylar. Ancak o zaman iki tik görürsün.

Posta kutusunu yalnızca karşı tarafın boşaltabilir: alma ve silme yalnızca
yalnızca onun sahip olduğu bir anahtarla olur ve silme, ancak alımı onayladıktan
sonra yapılır. Komşular yalnızca her gün değişen bir değerin altında şifreli
paketler görür.

### Yabancılar içeri geçemez

Cleona, kişin de ortak bir grubun üyesi de olmayan birinden tam iki şeyi
kabul eder: davetlerinden biri hâlâ
açıksa açık anahtarların için sorulan soru ve bir kişi isteği. İstek, senden
geçerli bir davet taşımalıdır ve gönderen önceden bir hesaplama görevini çözmüş
olmalıdır. Başka her şey -- mesajlar, aramalar, dosyalar -- uygulamaya ulaşmadan
önce atılır. Böylece yalnızca basılı kartvizitine sahip olan seni kolayca
arayamaz. Ortak bir grubun bir üyesi sana yalnızca bu grup içinde ulaşır -- grup
mesajlarıyla ve grup aramalarıyla, asla tek tek değil.

### Anti-sansür

Cleona, engellemesi zor olacak şekilde yapılmıştır:

- **Sunucu yok, sabit adres yok.** Uygulamada engellenebilecek bir adres yoktur ve
  ağ hiçbir tek düğüme bağlı değildir.
- **Sabit port yok.** Her cihaz ilk başlatmada rastgele bir port seçer. Cleona
  trafiğini tanıyabileceğin bilinen bir port numarası yoktur.
- **Rastgele veri gibi.** İki cihaz arasındaki bağlantı kurulumu, rastgele
  veriden ayırt edilemeyecek şekilde kodlanmıştır.
- **Çok sayıda giriş.** Her davet, her komşu ve aynı Wi-Fi'deki her cihaz, ağa
  geri dönüş için olası bir yoldur.

### Güvenli anahtar depolama

Desteklenen platformlarda Cleona, şifreleme anahtarlarını işletim sisteminin
güvenli anahtarlığında (Android Keystore, iOS Keychain, macOS Keychain) depolar.
Bulunabildiği yerde bu, anahtarların için donanım destekli koruma sunar.

### Veritabanı şifrelemesi

Mesajların ve konuşmaların şifreli bir veritabanında yatar -- her kimlik için
ayrı biri, her biri kendi anahtarıyla. Yalnızca veritabanının kendisi değil, ara
dosyaları da şifrelidir; hiçbir şey, kısaca bile olsa, diske şifresiz yazılmaz.
Ayarlar, kişiler ve medya da şifreli depolanır.

Anahtarlar 24 sözünden türetilir ve yalnızca cihazında vardır. Cihazını ele
geçiren ve verileri okuyan biri bile, bu anahtarlar olmadan yalnızca okunamaz
veriler bulur.

Şifresiz olması yalnızca, içeriği kendin Cleona'dan dışarı çıkardığında söz
konusudur:
- bir dosyayı bir sohbetten cihazına kaydettiğinde,
- ekran görüntüsü düğmesiyle bir resmi Galerine koyduğunda,
- bir şeyi başka bir uygulamaya paylaştığında,
- medya arşivlemeyi kurduğunda (13. bölüm): arşivlenmiş özgün haller, onları
  orada Cleona'sız da açabilmen için evdeki ağ depolamanda şifresiz yatar,
- randevuları Android sistem takvimine yansıttığında: orada takvim erişimi olan
  başka uygulamalar onları okuyabilir.

Bu şekilde dışarı çıkmış olan şeyler, mesajla birlikte silinmez ve onunla
birlikte süresi dolmaz.

### Ekranda koruma

Android, Windows ve macOS'ta Cleona, başka uygulamaların ekran kaydı almasına
izin vermez. Bir görüntüye ihtiyacın varsa, üst çubuktaki ekran görüntüsü
düğmesini kullan: O, resmi Galerine koyar -- şifresiz. Yönlendirmenin kabul
edilmediği bir konuşmada ekran görüntüsü yoktur.

---
## 15. Yazılım güncellemeleri

### Güncellemeleri nasıl alırım?

Cleona çeşitli yollarla güncellenebilir. Amaç, tek tek dağıtım kanalları
çöktüğünde ya da engellendiğinde bile güncellemeleri alabilmenizdir:

1. **App Store / Play Store:** Cleona orada göründüğünde ve onu bir mağaza
   üzerinden kurduğun zaman, güncellemeleri her zamanki gibi mağaza üzerinden
   alırsın. iPhone'da güncellemeler TestFlight üzerinden gelir.
2. **GitHub Releases:** Projenin GitHub sayfasında tüm platformlar için imzalı
   kurulum paketleri bulursun.
3. **Ağ üzerinden güncellemeler:** Cleona bir güncellemeyi doğrudan ağ üzerinden
   alabilir -- bir indirme sunucusu olmadan. Yeni sürüm, ağda yayılan hata
   düzeltmeli parçalara bölünür; bir kısmı hatta gizleme trafiğiyle birlikte
   yolculuk eder. Cihazın yeterince parça toplar ve güncellemeyi bir araya
   getirir. Aktarılan şey çoğunlukla yalnızca değişikliktir -- tüm uygulama
   yerine birkaç MB. Bu, Linux, Windows ve Android için geçerlidir; macOS'ta
   yeni sürümleri web sitesinden ya da GitHub'dan indirirsin.
4. **Davet bağlantıları:** Cleona'yı yüklemek ve ağa bağlanmak için yeni bir
   kullanıcının ihtiyaç duyduğu her şeyi içeren davet bağlantıları
   oluşturabilirsin.
5. **Fiziksel aktarım:** İnternet olmayan ortamlarda Cleona'yı bir USB bellekle
   ya da yerel ağ üzerinden başkalarına geçirebilirsin.

### Bir güncelleme nasıl yürür

1. Cleona yeni bir güncellemenin parçalarını arka planda otomatik toplar ve bir
   araya getirir.
2. Yalnızca güncelleme **eksiksiz** olduğunda ve **imzası denetlendiğinde** Cleona
   onu sana sunar. Böylece sana hiçbir zaman yarım ya da denetlenmemiş bir
   güncelleme sunulmaz.
3. "Yükle"ye dokunduğunda, kurulum başka soru sorulmadan başlar. Android'de
   ayrıca sistem kendi kurulum iletişim kutusunu gösterir.

Eski sürümler sunulmaz -- bir güncelleme her zaman yalnızca ileri gider. Bir
sürüm ağla artık birlikte çalışamayacak kadar eskiyse, Cleona bunu açıkça gösterir
ve güncellemen için sana rica eder.

### İmza denetimi

Her güncelleme iki kez imzalanır: bir klasik ve bir post-quantum yöntemiyle.
Cleona her iki imzayı da otomatik denetler. Böylece yalnızca resmi
geliştiriciden güncellemelerin kabul edildiği güvence altına alınır -- güncelleme
ağ üzerinden yabancı cihazlardan gelmiş olsa bile. Bir güncelleme hiçbir zaman
geliştirmeden otomatik oluşmaz, yalnızca geliştirici elle imzaladığında oluşur.

---

## 16. Sıkça sorulan sorular

### "Cleona'yı internetsiz kullanabilir miyim?"

Cleona bir ağ bağlantısına ihtiyaç duyar, ama mutlaka internete değil: aynı
Wi-Fi'de Cleona cihazları kendiliklerinden birbirini bulur ve tamamen internet
erişimi olmadan birbiriyle yazışabilir. Karşı tarafınla aynı anda çevrimiçi olman
gerekmez: o çevrimdışıysa, mesaj onu alana kadar üç komşudaki posta kutusunda en
fazla 7 gün bekler.

### "Seed ifademi kaybedersem ne olur?"

Kimliğin olan bir cihaz hâlâ çalıştığı sürece hiçbir şey kaybolmamıştır -- orada
yalnızca yazmaya devam edersin. Kimliği oluşturduğun cihazda 24 sözü çoğunlukla
yeniden okuyabilirsin (2. bölüme bak). Buna güvenme: Yeni bir kurulum bu
kopyayı kaldırır ve Android'de ekran kilidini kaldırmak ya da değiştirmek de onu
yok eder. Ne sözlerin ne de bir cihazın varsa, geri dönüş yolu yoktur --
kişilerin, geliştirici ya da başka herhangi biri üzerinden de değil. Bu yüzden
24 sözü güvenli bir şekilde saklamak bu kadar önemlidir.

### "Birisi mesajlarımı okuyabilir mi?"

Hayır. Her mesaj, yalnızca bu tek mesaj için geçerli olan tek kullanımlık bir
anahtarla şifrelenir. Yalnızca sen ve karşı tarafın mesajın şifresini çözebilir.
Merkezi sunucu, ana anahtar ve geliştirici için erişim yoktur. Taşıma yolunda bir
cihaz mesajı iletse bile, yalnızca şifreli veri yığını ve bir kod görür. Komşun
paketin senden geldiğini bilir, ama kime gittiğini bilmez; karşı tarafının
komşusu kime gittiğini bilir, ama kimden geldiğini bilmez.

### "Neden telefon numarasına ihtiyacım yok?"

Çünkü kimliğin tamamen kriptografiktir. Gerçek adınla bağlı bir telefon numarası
ya da e-posta adresi yerine, cihazında oluşturulmuş bir anahtar çifti seni
tanımlar. Kişileri QR kod, NFC ya da davetinin metin satırıyla eklersin -- bir
telefon rehberi üzerinden değil. Bu, daha fazla gizlilik anlamına gelir, çünkü
mesajlaşma hesabın gerçek kimliğine bağlı değildir.

### "Cleona'da insanları nasıl bulurum?"

Cleona bilinçli olarak telefon numarası ya da ada göre kişi aramaya sahip
değildir -- bu bir gizlilik sorunu olurdu. Bunun yerine davetleri doğrudan
alışveriş edersin: QR kod, NFC ya da başka bir yol üzerinden metin satırı olarak.
Bu, telefon rehberinde bakmak yerine kartvizit alışverişi yapmak gibidir.

### "Cleona yurt dışında da çalışır mı?"

Evet. Bir internet bağlantın olduğu sürece Cleona dünyanın her yerinde çalışır.
Merkezi sunucu ve sabit adres olmadığından, hizmet belli ülkeler için kolayca
kapatılamaz. Cleona'nın engellemeleri nasıl zorlaştırdığı "Güvenlik" bölümünde
"Anti-sansür" altında yer alır. Sınırda her bilinmeyen trafiği engelleyen bir
ülke, Cleona'yı da durdurabilir.

### "Cleona ücretsiz mi?"

Evet. Cleona ücretsizdir ve reklamsız kullanılabilir. Merkezi sunucu
olmadığından, işletme için sunucu maliyetleri de oluşmaz. Ayarlarda "Cleona'yı
destekle" -> "Bağış yap" altında geliştirmeye gönüllü destek olabilirsin.

### "Mesajımın yalnızca bir tiki var -- bu ne anlama gelir?"

Mesaj yolda, ama karşı tarafın alımı henüz onaylamadı -- çoğunlukla şu an
çevrimdışı olduğu için. Bu bir hata değildir: mesaj posta kutusunda en fazla 7
gün bekler. Onu alır almaz iki tik görürsün. Bir saat, henüz hiçbir yolun mesajı taşımadığı anlamına gelir
-- bir yol var olur olmaz kendiliğinden yola çıkar; bir uyarı işareti, 14 gün
boyunca hiçbir yol bulamadığı ve onu yeniden gönderebileceğin anlamına gelir.

### "Mesajlar iPhone'umda neden gecikir?"

iOS, uygulamaların arka planda sürekli çalışmasına izin vermez. Cleona yalnızca
ara ara kısa süreliğine uyandırılır; ne zaman olacağına iOS karar verir. O zaman
her şeyi alır. Uygulamayı açar açmaz Cleona, senin için saklananları alır.

### "WhatsApp'tan Cleona'ya geçebilir miyim?"

Evet, ama WhatsApp sohbetlerini aktaramazsın. Cleona ve WhatsApp temelden farklı
sistemlerdir. Kişilerini Cleona'da tek tek eklemen gerekir. En kolay yolu,
davetinin metin satırını kişilerine göndermektir. Bu şekilde gelen her isteği
"İstekler" altında kendin onaylarsın.

### "Cleona'yı birkaç cihazda aynı anda kullanabilir miyim?"

Henüz hayır. Aynı kimlik için ikinci bir cihaz sonraki bir sürümde gelecek
(11. bölüm). Birden fazla cihazda bugün farklı kimlikler kullanabilirsin.

### "Uygulama mağazası engelliyken güncellemeleri nasıl alırım?"

Cleona, bir uygulama mağazasına, web sitesine ya da indirme sunucusuna bağlı
olmadan güncellemeleri doğrudan ağ üzerinden alabilir. Ağdaki başka bir cihaz en
yeni sürüme sahipse, cihazın güncellemeyi oradan yükleyebilir. Özgünlük,
geliştiricinin dijital imzasıyla denetlenir. Alternatif olarak, bir kişi
uygulamayı sana bir davet bağlantısı ya da USB bellekle geçirebilir. Bunun hakkında
daha fazlası "Yazılım güncellemeleri" bölümünde.

---

## Yardım ve iletişim

Soruların varsa ya da bir soruna çarparsan, güncel bilgileri Cleona web sitesinde
ve GitHub'da bulursun. Cleona merkeziyetsiz bir proje olduğundan, klasik bir
müşteri desteği yoktur -- ama yardıma severlikle yardım eden etkin bir topluluk
vardır.

---

*Bu kılavuz Cleona Chat 4.2 sürümünü açıklar. Tek tek işlevler daha yeni
sürümlerde değişebilir ya da genişleyebilir.*