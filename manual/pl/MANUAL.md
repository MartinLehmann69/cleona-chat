# Cleona Chat -- Podręcznik użytkownika

Wersja 4.2 | Stan na listopad 2026

---

## Spis treści

1. [Czym jest Cleona Chat?](#1-czym-jest-cleona-chat)
2. [Pierwsze kroki](#2-pierwsze-kroki)
3. [Kontakty](#3-kontakty)
4. [Wiadomości](#4-wiadomości)
5. [Grupy](#5-grupy)
6. [Kanały publiczne](#6-kanały-publiczne)
7. [Połączenia](#7-połączenia)
8. [Kalendarz](#8-kalendarz)
9. [Ankiety](#9-ankiety)
10. [Wiele tożsamości](#10-wiele-tożsamości)
11. [Wiele urządzeń](#11-wiele-urządzeń)
12. [Odzyskiwanie](#12-odzyskiwanie)
13. [Ustawienia](#13-ustawienia)
14. [Bezpieczeństwo](#14-bezpieczeństwo)
15. [Aktualizacje oprogramowania](#15-aktualizacje-oprogramowania)
16. [Najczęściej zadawane pytania](#16-najczęściej-zadawane-pytania)

---
## 1. Czym jest Cleona Chat?

### Twój komunikator, Twoje dane

Cleona Chat to komunikator, który działa całkowicie bez centralnego serwera.
Twoje wiadomości wędrują z Twojego urządzenia do urządzenia rozmówcy --
bez pośrednictwa siedziby firmy, bez chmury, bez centrum danych. Gdzie po
drodze pomaga inne urządzenie, przekazuje tylko zaszyfrowane pakiety.
Żadna firma nie może odczytać, przechować ani przekazać Twoich wiadomości,
ponieważ po prostu żadna firma nie znajduje się pomiędzy.

### Brak konta, brak numeru telefonu

W Cleonie nie potrzebujesz ani numeru telefonu, ani adresu e-mail, aby się
zalogować. Twoja tożsamość składa się z pary kluczy kryptograficznych,
która przy pierwszym uruchomieniu jest automatycznie generowana na Twoim
urządzeniu. To oznacza: nikt nie może Cię wytropić po numerze telefonu ani
adresie e-mail, chyba że sam podasz swoje dane kontaktowe.

### Szyfrowanie odporne na przyszłość

Cleona korzysta z tzw. szyfrowania postkwantowego. To znaczy: nawet
przyszłe komputery kwantowe nie zdołają złamać Twoich wiadomości. Nie
musisz rozumieć szczegółów -- ważne jest tylko, że Twoja komunikacja jest
chroniona najlepiej, jak pozwala na to obecny stan techniki.

### Jak to działa bez serwera?

Sieć Cleony składa się wyłącznie z urządzeń jej użytkowników. Każde
urządzenie jest węzłem, żaden węzeł nie jest ważniejszy od innego, a każdy
zna tylko swoich sąsiadów. Cztery rzeczy czynią tę sieć wyjątkową:

- **Brak stałego punktu.** W aplikacji nie widnieje żaden adres serwera, a
  sieć nie zależy od żadnego pojedynczego węzła. Nie ma nic, co można by
  wyłączyć, aby wyłączyć Cletonę.
- **Natychmiast.** Twoja wiadomość rusza w momencie, w którym ją
  wysyłasz. Nie czeka na żaden takt ani na nic innego.
- **Maskowanie z boku.** Twoje urządzenie stale wysyła małe pakiety
  maskujące, aby z zewnątrz nie było widać, kiedy naprawdę piszesz. Żadna
  wiadomość od tego nie zależy -- maskowanie działa tylko obok.
- **Kody zamiast nazw.** Ktoś przekazujący wiadomość widzi tylko kod,
  który zmienia się każdego dnia. W normalnym przypadku żaden z nich nie
  zna jednocześnie nadawcy i odbiorcy; wyjątki opisano w rozdziale 14.

**Trzy drogi, wszystkie naraz.** Gdy wysyłasz wiadomość, Cleona nie
próbuje jednej drogi po drugiej, lecz wszystkie pasujące naraz. Gdy tylko
rozmówca potwierdzi odbiór, pozostałe zostają przerwane.

1. **W tej samej sieci:** Jeśli jesteście w tej samej sieci Wi-Fi,
   wiadomość idzie bezpośrednio.
2. **Przez stałych sąsiadów:** W internecie Twoje urządzenie przekazuje
   wiadomość swojemu stałemu sąsiadowi. Ten przekazuje ją stałym sąsiadom
   Twojego rozmówcy (do trzech naraz), a jeden z nich ją dostarcza.
3. **Skrzynka:** Jeśli rozmówca jest offline, Cleona zostawia wiadomość
   zaszyfrowaną u trzech sąsiadów. Pozostaje tam do 7 dni. Gdy rozmówca
   znów będzie online, ją odbierze.

**Jak wejść do sieci?** W aplikacji nie widnieje żaden adres serwera. Swój
punkt wejścia otrzymujesz od swojego pierwszego kontaktu: jego zaproszenie
zawiera adresy, dzięki którym Twoje urządzenie znajduje swoich pierwszych
sąsiadów. W tej samej sieci Wi-Fi urządzenia Cleony znajdują się też
same. Od tego momentu Twoje urządzenie uczy się od każdego sąsiada
kolejnych.

### Platformy

Cleona jest dostępna na Androida, iOS, macOS, Linuksa i Windows. Na
komputerach i na Androidzie wiadomości i połączenia docierają w ciągu
kilku sekund. Na iPhonie obowiązuje to, dopóki aplikacja jest otwarta.
Gdy nie jest, iOS budzi ją tylko od czasu do czasu i to krótko; kiedy,
decyduje iOS. Cleona pobiera wtedy wszystko, co zostało zapisane dla
Ciebie, i pokazuje powiadomienie z liczbą na ikonie aplikacji. Połączenia
nie docierają na iPhone'a z zamkniętą aplikacją. To reguła Apple'a, a nie
błąd w Cleonie.

---

## 2. Pierwsze kroki

### Instalacja aplikacji

**Android:**
1. Pobierz plik APK ze strony Cleony lub z GitHub Releases.
2. Otwórz plik na swoim telefonie. W razie potrzeby zezwól na instalację
   z nieznanych źródeł (Android zapyta Cię automatycznie).
3. Stuknij „Instaluj" i poczekaj, aż instalacja się zakończy.

**iOS:**
1. Otwórz link zaproszenia TestFlight na swoim iPhonie.
2. Stuknij „Instaluj". TestFlight to oficjalna metoda Apple do
   dystrybuowania aplikacji beta.
3. Po instalacji znajdziesz Cletonę na ekranie głównym.

**macOS:**
1. Pobierz plik DMG ze strony Cleony lub z GitHub Releases.
2. Otwórz DMG i przeciągnij Cletonę do folderu Programy.
3. Przy pierwszym uruchomieniu macOS może zapytać, czy chcesz otworzyć
   aplikację zidentyfikowanego dewelopera -- potwierdź to.

**Linux (Ubuntu/Debian):**
1. Pobierz plik .deb ze strony Cleony lub z GitHub Releases.
2. Zainstaluj dwuklikiem lub w terminalu: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Uruchom Cletonę z menu aplikacji lub w terminalu wpisując `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Pobierz plik .rpm ze strony Cleony lub z GitHub Releases.
2. Zainstaluj poleceniem: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Uruchom Cletonę z menu aplikacji lub w terminalu wpisując `cleona-chat-beta`.

**Linux (wszystkie dystrybucje -- AppImage):**
1. Pobierz plik .AppImage ze strony Cleony lub z GitHub Releases.
2. Nadaj plikowi uprawnienie do wykonywania: prawy przycisk, właściwości,
   wykonywalny, lub w terminalu: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Uruchom dwuklikiem lub w terminalu: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Nazwy pakietów dotyczą bety, która jest obecnie jedyną opublikowaną
wersją; nazywają się `cleona-chat-beta`.

**Windows:**
1. Pobierz instalator ze strony Cleony lub z GitHub Releases.
2. Uruchom plik instalacyjny i postępuj zgodnie z instrukcjami.
3. Uruchom Cletonę z menu Start lub ze skrótu na pulpicie.

### Tworzenie tożsamości

Przy pierwszym uruchomieniu Cleona automatycznie tworzy dla Ciebie nową
tożsamość. Możesz nadać sobie nazwę wyświetlaną -- to imię, które widzą
Twoje kontakty. Tę nazwę można zmienić w dowolnym momencie.

### Zapisanie frazy seed -- najważniejsza rzecz w ogóle

Po utworzeniu Twojej tożsamości Cleona pokazuje Ci 24 słowa. To jest Twoja
**fraza seed** -- Twój osobisty klucz odzyskiwania.

**Zapisz te 24 słowa na papierze i przechowuj je bezpiecznie.**

Dlaczego to jest tak ważne?

- Jeśli Twój telefon się zepsuje, zgubi lub zostanie skradziony, możesz
  za pomocą tych 24 słów przywrócić całą swoją tożsamość na nowym
  urządzeniu.
- Bez frazy seed nie ma drogi powrotnej. Nie ma przycisku „zapomniane
  hasło" ani supportu, który mógłby Ci oddać konto -- bo nie ma w ogóle
  żadnego konta na serwerze. Nawet Twoje kontakty nie mogą przywrócić
  Twojej tożsamości, niezależnie od tego, ilu ich jest. Drugie urządzenie
  z tą samą tożsamością pojawi się w późniejszej wersji (patrz rozdział 11).
- Nigdy nie podawaj frazy seed innym. Kto zna te słowa, może wydawać się
  za Ciebie.

24 słowa znajdziesz później w ustawieniach w sekcji „Kopia zapasowa" ->
„Pokaż frazę odzyskiwania", gdybyś chciał(a) je jeszcze raz odczytać. Na
Androidzie potwierdzasz to swoją blokadą ekranu.

### Dodanie pierwszego kontaktu

Aby porozmawiać z kimś, musisz najpierw dodać tę osobę jako kontakt. Jest
na to kilka dróg -- wszystkie zostaną wyjaśnione w kolejnym rozdziale.

---

## 3. Kontakty

### Twoje zaproszenie

Kontakty w Cleonie powstają wyłącznie za pośrednictwem zaproszenia. Twoje
zaproszenie jest dostępne od pierwszego uruchomienia -- nawet bez
internetu i zanim Twoje urządzenie w ogóle znajdzie jakiegoś sąsiada.
Znajdziesz je na stronie szczegółów swojej tożsamości (stuknij w swoją
nazwę na górnym pasku).

Zaproszenie występuje w dwóch formach, które zawierają dokładnie to samo:

- jako **kod QR**, gdy Twój rozmówca stoi obok Ciebie, oraz
- jako **linia tekstowa**, którą wysyłasz e-mailem, SMS-em lub przez inny
  komunikator.

Zaproszenie nie zawiera numeru telefonu ani nazwy z jakiegoś katalogu.
Zawiera Twoje klucze publiczne i adresy, przez które Twój rozmówca
dosięga Ciebie i Twoich sąsiadów. Dla kogoś, kto świeżo instaluje Cletonę,
Twoje zaproszenie jest więc również wejściem do sieci.

### Skanowanie kodu QR (zalecane)

Gdy spotykacie się osobiście:

1. Pokazujesz rozmówcy kod QR swojego zaproszenia.
2. Twój rozmówca stuknięciem w przycisk plusa wybiera „Skanuj kod QR" i
   kieruje kamerę na Twój ekran. Działa to także z kamerką internetową
   komputera.
3. Żądanie trafia do Ciebie i jest **przyjmowane automatycznie** -- bo
   przecież sam przed chwilą pokazałeś kod.

Kod QR jest ważny tylko raz: pierwsze ważne żądanie zostaje przyjęte,
potem zaproszenie jest zużyte. Kod QR to najbezpieczniejsza metoda,
ponieważ przy niej dokładnie wiecie, z kim wymieniacie kontakt.

### NFC (zbliżenie telefonów)

Jeśli oba urządzenia obsługują NFC:

1. Otwórzcie u obu funkcję dodawania kontaktu.
2. Zbliżcie swoje telefony tyłami do siebie.
3. Zaproszenie zostaje przesłane i automatycznie przyjęte.

NFC oferuje, podobnie jak kod QR, wysokie bezpieczeństwo, ponieważ
wymiana działa tylko wtedy, gdy stoicie fizycznie obok siebie.

### Wysłanie linii tekstowej

Gdy nie możecie się spotkać:

1. Otwórz swoje zaproszenie i skopiuj linię tekstową.
2. Wyślij ją osobie, która ma Cię dodać -- mailem, SMS-em lub przez inny
   komunikator.
3. Ta osoba wkleja linię w Cleonie w oknie dodawania kontaktu.
4. Żądanie pojawia się u Ciebie w zakładce **„Żądania"**. Tutaj **nie
   jest** przyjmowane automatycznie: decydujesz sam, bo nie wiesz, kto po
   drodze jeszcze odczytał linię.

### Przyjmowanie żądań kontaktu

Przychodzące żądanie nie tworzy jeszcze kontaktu. Zadaje Ci pytanie i
pojawia się w zakładce **„Żądania"**. Widzisz tam nazwę i poziom
weryfikacji oraz możesz wybrać:

- **Przyjmij** -- dopiero teraz osoba staje się Twoim kontaktem.
- **Odrzuć** -- żądanie zostaje odrzucone.
- **Zablokuj** -- osoba nie może wysyłać Ci dalszych żądań.

### Nigdy nie używaj jako stałego sąsiada

W menu kontaktu znajdziesz przełącznik **„Nigdy nie używaj jako stałego
sąsiada"** (domyślnie: wyłączony). Gdy jest włączony, ten kontakt nie
przekazuje dla Ciebie wiadomości i dlatego nie wie też, kiedy wysyłasz
lub odbierasz wiadomości. Jest to przewidziane na wypadek, gdy grozi Ci
niebezpieczeństwo ze własnego otoczenia.

Od nieznajomych (niebędących ani Twoim kontaktem, ani członkiem wspólnej
grupy) Cleona nie przepuszcza niczego poza takim żądaniem --
żadnej wiadomości, żadnego połączenia, żadnego pliku. A samo żądanie
trafia tylko wtedy, gdy nadawca rozwiąże wcześniej drobne zadanie
obliczeniowe. To czyni masowy spam kosztowny.

### Poziomy weryfikacji

Cleona pokazuje Ci, jak pewnie potwierdzona jest tożsamość kontaktu:

| Poziom | Znaczenie |
|-------|-----------|
| Niezweryfikowany | Jesteście połączeni, ale nic nie potwierdza, że naprawdę kryje się za tym właściwa osoba. |
| Widziany | Wymiana kluczy zakończyła się powodzeniem, możecie komunikować się zaszyfrowanie. |
| Zweryfikowany | Spotkaliście się osobiście i połączyliście przez skanowanie aparatem lub NFC. |
| Zaufany | Oznaczyłeś ten kontakt wyraźnie jako godny zaufania. |

„Zweryfikowany" istnieje tylko dla wymiany osobistej. Zaproszenie,
które przyszło przez czat lub mailem, nigdy nie osiąga tego poziomu --
nawet jeśli zawiera te same dane.

Jeśli klucze kontaktu zmienią się bez zapowiedzi, Cleona cofa go do
„Niezweryfikowany". To chroni Cię przed sytuacją, w której ktoś
niepostrzeżenie podszywa się pod Twój kontakt.

---
## 4. Wiadomości

### Wysyłanie i odbieranie tekstu

Wpisz po prostu swoją wiadomość w polu wprowadzania na dole i naciśnij
Enter lub przycisk wysyłania. Twoja wiadomość jest automatycznie
szyfrowana, zanim opuści Twoje urządzenie.

Przychodzące wiadomości pojawiają się w historii czatu.

### Co oznaczają znaczki przy Twojej wiadomości

| Znaczek | Znaczenie |
|---------|-----------|
| Zegarek | Wiadomość jest utworzona, ale jeszcze żadna droga jej nie zaniosła. |
| Jeden ptaszek | Wiadomość jest w drodze. Dotyczy to też czasu, gdy czeka na rozmówcę w skrzynce. |
| Dwa ptaszki | Dostarczona: urządzenie rozmówcy potwierdziło odbiór. |
| Znak ostrzeżenia | Przez 14 dni żadna droga nie zaniosła wiadomości. Stuknij, aby wysłać ją ponownie. |

**Offline to nie błąd.** Jeśli rozmówca jest nieosiągalny, wiadomość
pozostaje przy jednym ptaszku, dopóki nie zostanie odebrana -- nie jest
stracona. Jeśli samo Twoje urządzenie nie ma połączenia, wiadomość
pozostaje przy zegarku i rusza sama, gdy tylko znów będzie droga. Znak
ostrzeżenia pojawia się dopiero wtedy, gdy przez 14 dni nie znalazła
żadnej drogi; wtedy możesz wysłać ją ponownie.

Dotyczy to także iPhone'a z zamkniętą aplikacją: wiadomość czeka w
skrzynce, aż iOS krótko obudzi aplikację lub aż Twój rozmówca ją otworzy.
To może potrwać dłużej niż na innych urządzeniach.

Dwa ptaszki są tylko wtedy, gdy sam odbiorca potwierdzi odbiór. To
potwierdzenie jest zaszyfrowane i podpisane -- nikt po drodze nie może go
sfałszować, aby wmówić Ci dostarczenie.

### Wysyłanie obrazów, wideo i plików

Masz kilka możliwości:

- **Ikona spinacza** w polu wprowadzania: stuknij ją, aby wybrać plik,
  obraz lub wideo z galerii lub systemu plików.
- **Przeciągnij i upuść** (desktop): przeciągnij plik po prostu do okna
  czatu.
- **Wklej ze schowka** (desktop): skopiuj obraz i wklej go w czacie.

Małe pliki (poniżej 256 KB) wędrują bezpośrednio z wiadomością. Większe
pliki są dzielone na kawałki i wyposażane w korekcję błędów, tak że
pojedyncze zagubione fragmenty nic nie psują. Jeśli jesteście obaj online,
są przesyłane strumieniowo przez sąsiada; w przeciwnym razie są
odkładane na urządzeniach stale osiągalnych, dopóki rozmówca ich nie
odbierze.

Od 256 KB Cleona pyta Cię przy każdym pliku, zanim go wyśle: duży plik nie
może wyruszyć drogą Twoich wiadomości. Jego treść pozostaje zaszyfrowana,
a Twój rozmówca nie poznaje Twojego adresu internetowego. Sam transfer
jest jednak z zewnątrz widoczny jako zdarzenie, a obce urządzenie, które
go przekazuje lub przechowuje, widzi, kto wysyła, a kto pobiera. Twoja
zgoda dotyczy tylko tego jednego pliku.

### Wiadomości głosowe

1. Przytrzymaj przycisk mikrofonu w polu wprowadzania.
2. Wymów swoją wiadomość.
3. Puść przycisk, aby wysłać wiadomość.

Jeśli na Twoim urządzeniu jest włączone rozpoznawanie mowy (patrz
ustawienia), Twoja wiadomość głosowa jest automatycznie transkrybowana na
tekst. Twój rozmówca widzi wtedy zarówno nagranie, jak i transkrybowany
tekst.

### Odpowiadanie na wiadomości (cytowanie)

Aby odpowiedzieć na konkretną wiadomość:

1. Otwórz menu trzech kropek obok wiadomości.
2. Wybierz „Odpowiedz".
3. Nad polem wprowadzania pojawia się baner z cytowaną wiadomością.
4. Napisz swoją odpowiedź i wyślij ją.

Cytowana wiadomość jest wyświetlana w Twojej odpowiedzi, tak że powiązanie
jest jasne.

### Edytowanie i usuwanie wiadomości

- **Edytuj:** menu trzech kropek wiadomości, następnie „Edytuj". Zmień
  tekst i wyślij go ponownie. Twój rozmówca widzi, że wiadomość była
  edytowana. Edycja jest możliwa w ciągu 15 minut od wysłania.
- **Usuń:** menu trzech kropek wiadomości, następnie „Usuń". Wiadomość
  zostaje usunięta u Ciebie i u rozmówcy. Możesz usuwać swoje własne
  wiadomości w dowolnym momencie -- nie ma okna czasowego na usuwanie.

### Reakcje emoji

Zamiast pisać odpowiedź, możesz zareagować na wiadomość emoji:

1. Otwórz menu trzech kropek lub przytrzymaj wiadomość długo.
2. Wybierz emoji z szybkiego wyboru lub otwórz wybór emoji dla pełnej
   palety.
3. Twoja reakcja pojawia się pod wiadomością.

### Kopiowanie tekstu

Przez menu trzech kropek wiadomości możesz skopiować tekst wiadomości do
schowka.

### Wyszukiwanie wiadomości

W górnej części okna czatu znajdziesz funkcję wyszukiwania. Wpisz
wyszukiwane hasło, a Cleona pokaże Ci wszystkie trafienia w bieżącym
czacie. Strzałkami możesz przeskakiwać między trafieniami.

Na stronie startowej jest dodatkowo filtr wyszukiwania obejmujący wszystkie
zakładki, którym możesz przeszukać wszystkie rozmowy pod kątem hasła.

### Podgląd linku

Gdy wysyłasz link, Cleona automatycznie generuje podgląd (tytuł, opis,
obrazek podglądowy). Ten podgląd jest tworzony na Twoim urządzeniu i
dołączany do wiadomości -- Twój rozmówca nie musi z tego powodu
nawiązywać połączenia z linkowaną stroną.

To, co robi stuknięcie w otrzymany link, ustawiasz w ustawieniach w sekcji
„Otwieranie linków": „Normalnie", „Prywatne okno, jeśli to możliwe" (tam,
gdzie urządzenie nie potrafi otworzyć prywatnego okna, link otwiera się
normalnie) lub „Pytaj za każdym razem".

---

## 5. Grupy

### Tworzenie grupy

1. Przejdź do zakładki „Grupy".
2. Stuknij w przycisk plusa.
3. Nadaj grupie nazwę.
4. Wybierz kontakty, które chcesz zaprosić.
5. Stuknij „Utwórz".

Zaproszone kontakty otrzymują powiadomienie i mogą dołączyć do grupy.

### Jak chronione są wiadomości grupowe

W grupie liczącej do 16 członków Cleona wysyła każdą wiadomość do każdego
członka osobno -- każdorazowo zaszyfrowaną tylko dla tego członka, tak
jakbyś każdemu napisał osobną wiadomość. Ptaszki przy wiadomości grupowej
pokazują stan członka, u którego wiadomość jest najmniej zaawansowana.

Gdy grupa rozrośnie się ponad 16 członków, używa wspólnego klucza. Zmienia
się on każdego dnia i jest losowany na nowo, gdy jakiś członek wyjdzie lub
zostanie usunięty; nowy członek czyta dopiero od chwili dołączenia.
Ptaszki nie pokazują tam już stanu każdego członka, lecz to, że wiadomość
została złożona w sieci. Gdy grupa spadnie do 12 lub mniej członków,
wraca do wysyłki pojedynczej.

### Obrazy w grupach i kanałach

W ustawieniach grupy lub kanału ustalasz opcją „Zawsze wczytuj obrazy",
czy obrazy mają być wczytywane od razu, czy dopiero, gdy w któryś
stukniesz.

### Zapraszanie członków

Także po utworzeniu możesz zaprosić kolejne kontakty:

1. Otwórz informacje o grupie (menu trzech kropek w przeglądzie grup lub
   górny pasek w czacie grupowym).
2. Stuknij „Zaproś".
3. Wybierz kontakty, które chcesz dodać.

### Role

Każda grupa ma trzy role:

- **Właściciel (Owner):** Ma pełną kontrolę. Może dodawać i usuwać
  członków, mianować administratorów i zarządzać grupą. Właściciel może
  też przekazać swój status innemu członkowi.
- **Admin:** Może usuwać członków i pomagać w zarządzaniu.
- **Członek:** Może czytać i pisać wiadomości.

### Opuszczanie grupy

1. Otwórz menu trzech kropek w przeglądzie grup.
2. Wybierz „Opuść".
3. Potwierdź swoją decyzję.

Gdy opuszczasz grupę, Twoje dotychczasowe wiadomości pozostają widoczne
dla pozostałych członków.

---

## 6. Kanały publiczne

### Czym są kanały?

Kanały to publiczne fora dyskusyjne wewnątrz sieci Cleony. W przeciwieństwie
do grup tutaj każdy może czytać, bez konieczności bycia zaproszonym. Tylko
właściciel i administratorzy mogą publikować wpisy -- subskrybenci tylko
czytają.

### Znajdowanie kanałów i dołączanie

1. Przejdź do zakładki „Kanały".
2. Otwórz zakładkę „Szukaj".
3. Przeszukaj dostępne kanały według nazwy lub tematu.
4. Stuknij w kanał, a następnie w „Subskrybuj".

Kanały można filtrować według języka. Niektóre kanały są oznaczone jako
„Nieodpowiednie dla nieletnich" -- są widoczne tylko wtedy, gdy w swoim
profilu potwierdzisz, że masz ponad 18 lat.

### Tworzenie własnego kanału

1. Przejdź do zakładki „Kanały".
2. Stuknij w przycisk plusa.
3. Wpisz nazwę kanału (musi być unikalna w całej sieci).
4. Wybierz język oraz to, czy kanał ma być publiczny, czy prywatny.
5. Opcjonalnie: dodaj opis i obraz.
6. Stuknij „Utwórz".

Przy kanałach publicznych możesz ustalić, czy treść ma być sklasyfikowana
jako „Nieodpowiednia dla nieletnich".

### Zgłaszanie treści

Jeśli w publicznym kanale zauważysz nieodpowiednie treści, możesz je
zgłosić. Cleona korzysta z zdecentralizowanego systemu moderacji: zgłoszenia
są oceniane przez losowo wybranych członków sieci (rodzaj „ławy
przysięgłych"). Gdy stwierdzi się naruszenie, kanał otrzymuje
ostrzeżenie. Przy powtarzających się naruszeniach jest degradowany w
indeksie wyszukiwania lub blokowany.

### Kanały systemowe

Cleona ma dwa wbudowane kanały systemowe:

- **Bug Log:** Gdy Cleona rozpozna błąd, pyta Cię, czy chcesz wysłać
  zgłoszenie błędu; wcześniej widzisz dokładnie, co zostanie opublikowane.
  Te raporty trafiają do kanału Bug Log, gdzie mogą być oglądane przez
  społeczność. Raport nie zawiera nazwy ani treści Twoich rozmów, lecz
  pseudonim. W becie podaje dodatkowo Twój identyfikator (User-ID), aby
  deweloperzy mogli dopytać. Możesz też ręcznie wysłać raport z logów
  (z oknem podglądu i wyraźną zgodą).
- **Feature Requests:** Tutaj użytkownicy mogą zgłaszać życzenia
  funkcjonalne i głosować na istniejące propozycje. Propozycje są
  sortowane według głosów.

Każdy komputer trzyma do 25 MB na każdy kanał systemowy, każdy telefon
do 5 MB; gdy się zapełni, jako pierwsze odchodzi najstarsze -- nigdy to,
co sam już widziałeś.

---
## 7. Połączenia

### Rozpoczęcie połączenia głosowego

1. Otwórz czat z kontaktem, który chcesz zadzwonić.
2. Stuknij ikonę telefonu na górnym pasku.
3. Poczekaj, aż rozmówca odbierze połączenie.

Podczas rozmowy widzisz oś czasu, czas trwania rozmowy i masz dostęp do
wyciszenia oraz głośnika.

Aby rozłączyć się, stuknij czerwony przycisk rozłączenia.

Jeśli widzisz „Niedostępny", urządzenie Twojego rozmówcy jest w tej
chwili nieosiągalne, na przykład iPhone z zamkniętą aplikacją. Napisz
zamiast tego wiadomość.

### Rozpoczęcie połączenia wideo

1. Otwórz czat z kontaktem.
2. Stuknij ikonę kamery na górnym pasku.
3. Twój obraz wideo pojawia się w małym oknie, obraz rozmówcy w dużym
   obszarze.

Podczas rozmowy możesz przełączać się między przednią a tylną kamerą.

### Połączenia przychodzące

Gdy ktoś do Ciebie dzwoni, pojawia się okno powiadomienia z nazwą
dzwoniącego. Możesz:

- **Odbierz** -- rozmowa się rozpoczyna.
- **Odrzuć** -- dzwoniący zostaje powiadomiony.

Jeśli jesteś właśnie w rozmowie, nowe połączenie nie dzwoni; dostajesz
zamiast tego wiadomość „Nieodebrane połączenie". To samo dotyczy
połączenia grupowego, którego nie odebrałeś -- wiadomość stoi wtedy w
czacie grupowym.

Jeśli ktoś dzwoni na jedną z Twoich tożsamości, która właśnie nie jest
wyświetlana, telefon dzwoni mimo to; ekran połączenia mówi, która z
Twoich tożsamości jest wywoływana.

Na iPhone dzwoni tylko przy otwartej aplikacji. Kto dzwoni do Ciebie, gdy
aplikacja jest zamknięta, po 10 sekundach widzi „Niedostępny". Gdy tylko
otworzysz aplikację, znajdziesz wiadomość o nieodebranym połączeniu.

### Połączenia grupowe

Możesz również prowadzić połączenia grupowe, w których jednocześnie
uczestniczy kilka osób. Połączenie jest organizowane przez inteligentne
drzewo przekazywania, tak że nie każdy uczestnik musi być bezpośrednio
połączony z każdym innym. Wszystkie rozmowy są stale szyfrowane.

Każdy członek grupy może rozpocząć połączenie grupowe. Dwaj uczestnicy,
którzy nie są swoimi kontaktami, nigdy nie widzą adresu internetowego
drugiego: ich dźwięk i obraz idą przez uczestnika, który z oboma ma
kontakt. Jeśli takiego nie ma, dwójka nie jest połączona, a kafelek mówi
„Brak wspólnego kontaktu w rozmowie". Gdy przekazanie jest przeciążone,
dźwięk zostaje, a wideo dla tej pary odpada.

### Szyfrowanie przy połączeniach

Wszystkie połączenia są szyfrowane jednorazowymi kluczami, które istnieją
tylko przez czas trwania rozmowy. Po rozłączeniu te klucze są natychmiast
usuwane. Nikt nie może odszyfrować dawnej rozmowy po fakcie.

Szczerze mówiąc: połączenia przebiegają, gdzie tylko możliwe, bezpośrednio
między urządzeniami, bo już małe opóźnienie przeszkadza w mówieniu. W
przeciwieństwie do wiadomości Twój dostawca internetu może więc przy
połączeniu zobaczyć, z jakim adresem internetowym jesteś połączony. Tego,
co mówicie, nie widzi.

Przy połączeniu Twój kontakt widzi też Twój adres internetowy. Jeśli nie
chcesz tego przy którymś kontakcie, wyłącz w jego menu „Zezwalaj na
połączenia" (domyślnie: włączone). Jeśli wyłączysz to później, adres,
który już widział, pozostaje mu znany.

---

## 8. Kalendarz

Cleona zawiera wbudowany kalendarz, który działa zaszyfrowany i całkowicie
zdecentralizowanie -- bez usługi chmurowej.

### Widoki

Kalendarz oferuje pięć widoków: dzień, tydzień, miesiąc, rok oraz widok
zadań. Przełączaj się między nimi przez zakładki na górze ekranu
kalendarza.

### Tworzenie wydarzeń

Stuknij w przedział czasu lub użyj przycisku dodawania, aby utworzyć nowe
wydarzenie. Możesz podać tytuł, datę, godzinę, miejsce i notatki. Wydarzenia
są przechowywane zaszyfrowane na Twoim urządzeniu.

### Wydarzenia cykliczne

Wydarzenia mogą powtarzać się codziennie, co tydzień, co miesiąc lub co
rok. Możesz dostosować wzorzec (np. co drugi wtorek, każdego pierwszego
miesiąca) i ustalić datę końcową lub liczbę powtórzeń.

### Zapraszanie kontaktów

Podczas tworzenia lub edytowania wydarzenia możesz zaprosić swoje kontakty
Cleony. Otrzymują one zaszyfrowane zaproszenie kalendarzowe i mogą
odpowiedzieć: potwierdzić, odmówić lub „może". Zmiany w wydarzeniu są
automatycznie wysyłane do wszystkich zaproszonych.

### Wskazanie wolny/zajęty

Możesz udostępniać kontaktom swoją dostępność, nie ujawniając szczegółów
wydarzenia. Są trzy poziomy ochrony prywatności: pełne szczegóły, tylko
bloki czasowe lub ukryte. Możesz ustawić standard i nadpisać go dla
każdego kontaktu.

### Przypomnienia

Wydarzenia mogą mieć przypomnienia, które przed rozpoczęciem wydarzenia
wywołują powiadomienie systemowe. Przypomnienia możesz w razie potrzeby
odroczyć.

### Zewnętrzna synchronizacja kalendarza

Cleona może synchronizować się z zewnętrznymi usługami kalendarza:

- **CalDAV** -- Połącz się z dowolnym serwerem zgodnym z CalDAV
  (Nextcloud, Radicale itd.).
- **Kalendarz Google** -- Synchronizacja przez Google Calendar API z
  bezpiecznym uwierzytelnianiem OAuth2.
- **Lokalny serwer CalDAV** -- Cleona może uruchomić lokalny serwer
  CalDAV na Twoim urządzeniu, tak aby aplikacje kalendarza na desktopie
  (Thunderbird, Outlook, Kalendarz Apple, Evolution) mogły
  synchronizować się z Twoim kalendarzem Cleony.
- **Systemowy kalendarz Androida** -- Wydarzenia z Cleony mogą być
  przenoszone do wbudowanej aplikacji kalendarza na Twoim urządzeniu
  Android.
- **Pliki ICS** -- Importuj i eksportuj wydarzenia w standardowym
  formacie iCalendar.

### Eksport do PDF

Możesz wydrukować lub wyeksportować każdy widok kalendarza (dzień,
tydzień, miesiąc, rok) jako dokument PDF.

---

## 9. Ankiety

Możesz tworzyć ankiety w każdym czacie lub grupie, aby zbierać opinie lub
planować terminy.

### Typy ankiet

Cleona obsługuje pięć rodzajów ankiet:

- **Wybór pojedynczy** -- uczestnicy wybierają jedną opcję.
- **Wybór wielokrotny** -- uczestnicy mogą wybrać kilka opcji.
- **Ankieta terminowa** -- Znajdź termin, który pasuje wszystkim. Każdy
  uczestnik oznacza terminy jako dostępne, może, niedostępne.
- **Skala** -- Oceń coś na skali liczbowej (np. od 1 do 5).
- **Tekst swobodny** -- uczestnicy piszą własną odpowiedź.

### Tworzenie ankiety

Otwórz czat i stuknij ikonę ankiety (lub użyj menu załączników). Wybierz
typ ankiety, sformułuj swoje pytanie i opcje, i wyślij ankietę. Pojawia się
ona jako wiadomość w czacie.

### Głosowanie

Stuknij w ankietę, aby oddać swój głos. Możesz w dowolnym momencie zmienić
swój głos lub go wycofać.

### Anonimowe głosowanie

Ankiety mogą być skonfigurowane do anonimowego głosowania. Gdy
włączone, głosy są kryptograficznie anonimowe -- nikt, nawet twórca
ankiety, nie może zobaczyć, kto za co głosował. Liczba głosów pozostaje
mimo to widoczna.

### Ankieta terminowa do kalendarza

Gdy ankieta terminowa się zakończy, zwycięski termin może być jednym
stuknięciem zamieniony bezpośrednio w wpis kalendarzowy.

---
## 10. Wiele tożsamości

### Po co wiele tożsamości?

Wyobraź sobie, że chcesz oddzielić życie zawodowe od prywatnego -- podobnie
jak dwoma różnymi numerami telefonu, ale bez drugiego telefonu. W Cleonie
możesz używać wielu tożsamości na jednym urządzeniu. Każda tożsamość ma
własną nazwę, własne zdjęcie profilowe, własne kontakty i własne rozmowy.

### Tworzenie nowej tożsamości

1. Na górnym pasku widzisz swoją bieżącą tożsamość jako zakładkę.
2. Stuknij w znak plusa (+) po prawej stronie swoich zakładek
   tożsamości.
3. Wpisz nazwę dla nowej tożsamości.
4. Gotowe -- nowa tożsamość jest od razu aktywna.

### Przełączanie między tożsamościami

Stuknij po prostu w zakładkę tożsamości na górnym pasku. Przełączenie jest
natychmiastowe -- bez czasu oczekiwania, bez przeładowywania.

### Wszystkie działają jednocześnie

Ważna rzecz: wszystkie Twoje tożsamości są aktywne jednocześnie. Nawet
gdy jesteś aktualnie wyświetlany jako „Zawodowa", Twoja tożsamość
„Prywatna" nadal odbiera wiadomości. Nie ominie Cię nic, niezależnie od
tego, którą tożsamość masz właśnie wybraną.

### Strona szczegółów tożsamości

Gdy stukniesz w zakładkę swojej aktualnie aktywnej tożsamości, otwiera się
strona szczegółów. Tutaj możesz:

- Wyświetlić swój kod QR dla kontaktów.
- Zmienić lub usunąć swoje zdjęcie profilowe.
- Dodać opis profilu.
- Zmienić swoją nazwę wyświetlaną.
- Wybrać motyw (skórę) dla tej tożsamości.
- Usunąć tożsamość, jeśli jej już nie potrzebujesz.

### Usuwanie tożsamości

Gdy usuniesz tożsamość, Twoje kontakty zostają o tym powiadomione.
Tożsamość i wszystkie należące do niej dane są usuwane z Twojego
urządzenia. Ten proces jest nieodwracalny.

---

## 11. Wiele urządzeń

### Jedna tożsamość, jedno urządzenie -- na razie

Tożsamość działa dziś na jednym urządzeniu. Drugie urządzenie dla tej samej
tożsamości pojawi się w późniejszej wersji; w ustawieniach w sekcji
„Urządzenia" -> „Zarządzaj urządzeniami" opcja „Sparuj kolejne urządzenie"
stoi dlatego jeszcze jako „Jeszcze niedostępne".

Gdy się pojawi, będzie tak: Wszystkie urządzenia są równorzędne, nie ma
urządzenia głównego. Kolejne urządzenie ustawiasz swoimi 24 słowami, a
jedno z Twoich dotychczasowych urządzeń wyraża zgodę. Maksymalnie 5
urządzeń.

Jeśli dziś podasz swoje 24 słowa na nowym urządzeniu, robisz przeprowadzkę:
Tożsamość zostaje przywrócona na nowe urządzenie, a Twoje dotychczasowe
urządzenie usuwa ją następnie u siebie (patrz rozdział 12).

Na wielu urządzeniach możesz dziś używać różnych tożsamości (rozdział 10).

### Rotacja kluczy tożsamości

Jeśli podejrzewasz, że ktoś wszedł w posiadanie Twoich kluczy, możesz pod
„Zarządzaj urządzeniami" -> „Rotacja kluczy" wygenerować nowe klucze.
Twoje kontakty zostają powiadomione, Twoje otwarte zaproszenia zostają
odwołane. Ważne: Potem same 24 słowa odtwarzają już tylko stare klucze.
Utwórz dlatego bezpośrednio potem nowy pakiet odzyskiwania; przywrócić
możesz się wtedy już tylko razem z tym pakietem.

---

## 12. Odzyskiwanie

### Użycie frazy seed

Jeśli zgubisz swoje urządzenie lub konfigurujesz nowe:

1. Zainstaluj Cletonę na nowym urządzeniu.
2. Wybierz przy uruchomieniu „Odzyskaj".
3. Wpisz swoje 24 słowa.
4. Cleona odtwarza z nich wszystkie Twoje tożsamości -- z tymi samymi
   kluczami co wcześniej. Dla Twoich kontaktów jesteś tą samą osobą.

### Co wraca -- a co nie

Twoja tożsamość tkwi w 24 słowach, Twoje kontakty i historia rozmów nie.
Wraca Twój dostęp do sieci przez **pakiet odzyskiwania**: Twoje
urządzenie odkłada w sieci mały, zaszyfrowany pakiet. Tylko Twoje 24
słowa mogą go znaleźć i otworzyć. W środku jest to, czego Twoje nowe
urządzenie potrzebuje, aby ponownie dosięgnąć swoich kontaktów, i to, co
leżało w międzyczasie w sieci dla Ciebie. Nie musi przy tym żaden kontakt
być online.

Dotychczasowej historii czatu przywracanie nie zwraca.

Pakiet odzyskiwania żyje 7 dni i Twoje urządzenie odnawia go, dopóki
działa; w ustawieniach widzisz, do kiedy obowiązuje. Jeśli żadne z Twoich
urządzeń nie działało dłużej niż 7 dni, wygasł. Wtedy 24 słowa odtwarzają
Twoją tożsamość mimo wszystko, ale swoje kontakty musisz zaprosić na nowo;
to, co leżało w międzyczasie w sieci dla Ciebie, jest stracone.

### Przywracanie to przeprowadzka

Gdy Twoje dotychczasowe urządzenie później stwierdzi, że tożsamość została
przywrócona gdzie indziej, usuwa ją u siebie -- razem z jej historią.
Dlatego: Kto ma Twoje 24 słowa, może w ten sposób zabrać Twoją tożsamość
z Twojego urządzenia. Dopóki wszystkie kontakty nie wrócą, aplikacja Ci o
tym przypomina; opcją „Zakończ i odnów klucze" kończysz przywracanie sam.

### Czego nikt nie może odzyskać

To jest ważne, dlatego mówimy to wyraźnie:

- **Nikt poza Tobą nie może odzyskać Twojej tożsamości.** Nie deweloper,
  nie support, a także nie Twoje kontakty -- niezależnie od tego, ilu
  ich jest. Nie ma klucza uniwersalnego ani części Twojego klucza, która
  byłaby gdzieś złożona u innych.
- **Jeśli zgubiłeś 24 słowa i nie masz już żadnego urządzenia, Twoja
  tożsamość jest stracona.** Pozostaje tylko założyć nową i ponownie
  zaprosić swoje kontakty.

Najlepsza ochrona: Zapisz 24 słowa na papierze i przechowuj je bezpiecznie.

---
## 13. Ustawienia

Do ustawień dotrzesz przez ikonę zębatki w prawym górnym rogu.

### Powiadomienia i dzwonki

- Wybierz spośród sześciu różnych dzwonków dla połączeń przychodzących.
- Ustaw dźwięk wiadomości.
- Na urządzeniach z Androidem możesz dodatkowo włączyć lub wyłączyć
  wibracje.
- **„Wycisz wszystko"** nie pozwala na tym urządzeniu żadnej wiadomości
  dzwonić, wibrować ani się odzywać -- dla wszystkich tożsamości.
  Połączenia dzwonią dalej.
- **„Godziny ciszy"** ustalasz dla każdej tożsamości z od/do. W tym
  czasie żadna wiadomość tej tożsamości nie dzwoni, nie wibruje i nie
  odzywa się; wiadomości dochodzą mimo to.
- **„Powiadomienia bez treści"** (domyślnie: wyłączone) pokazują tylko, że
  przyszła wiadomość, zaproszenie lub przypomnienie -- bez nadawcy, nazwy
  i tekstu. Połączenia pokazują nadal nazwę.
- To, co przyjdzie zaraz po uruchomieniu, zgłasza Cleona w jednym
  zbiorczym powiadomieniu („5 nowych wiadomości w 2 rozmowach"); wszystko
  późniejsze pojedynczo. Stuknięcie w powiadomienie o wiadomości otwiera
  rozmowę, także w innej tożsamości.

### Motywy (skóry)

Cleona oferuje dziesięć różnych motywów: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold i Contrast. Motyw Contrast spełnia
najwyższy poziom dostępności (WCAG AAA) i jest szczególnie czytelny przy
ograniczonej ostrości wzroku.

Każda tożsamość może mieć swój własny motyw. Motyw zmieniasz na stronie
szczegółów tożsamości (stuknij w aktywną zakładkę tożsamości).

Dodatkowo możesz w ustawieniach w sekcji „Wygląd" przełączać się między
jasnym, ciemnym i motywem systemowym.

### Zmiana języka

Cleona jest dostępna w 34 językach, w tym w językach z pisownią od prawej
do lewej (np. arabski, hebrajski). Zmień język w ustawieniach w sekcji
„Język".

### Archiwizacja multimediów

Jeśli masz w domu pamięć sieciową (NAS) lub udostępniony folder, Cleona
może automatycznie archiwizować tam Twoje multimedia. Obsługiwane są SMB,
SFTP, FTPS i WebDAV.

Tak działa magazynowanie stopniowane:
- Pierwsze 30 dni: wszystko zostaje na Twoim urządzeniu.
- Po 30 dniach: na urządzeniu zostaje obrazek podglądowy, oryginał jest
  archiwizowany.
- Po 90 dniach: na urządzeniu zostaje tylko mały obrazek podglądowy.
- Po roku: zostaje tylko znacznik zastępczy, oryginał leży bezpiecznie
  w archiwum.

W dowolnym momencie możesz stuknąć w zarchiwizowany nośnik, aby go
odzyskać -- pod warunkiem, że jesteś połączony ze swoją siecią domową.
Szczególnie ważne multimedia można przypiąć, tak aby nigdy nie były
archiwizowane.

W sekcji „Budżet pamięci" ustalasz, ile MB multimediów zostaje na
urządzeniu (domyślnie: 100 MB na telefonie, 2 GB na komputerze). Gdy się
zapełni, najpierw archiwizowane jest najstarsze nieprzypięte medium.
Oryginał jest usuwany tylko wtedy, gdy bezpiecznie leży w archiwum --
wiadomości tekstowe są zawsze zachowywane.

### Transkrypcja wiadomości głosowych

Gdy włączone, Twoje wiadomości głosowe są lokalnie na Twoim urządzeniu
zamieniane na tekst (modelem open-source Whisper). Transkrybowany tekst
jest wysyłany wraz z nagraniem do rozmówcy. Transkrypcja odbywa się
całkowicie na Twoim urządzeniu -- żadne dane nie trafiają do zewnętrznych
usług.

To, który model (tiny, base, small) zostanie pobrany, ustawiasz raz dla
urządzenia; język (automatycznie lub stały) dla każdej tożsamości.

### Auto-pobieranie

Możesz ustawić, od jakiego rozmiaru multimedia mają być automatycznie
pobierane. Możesz np. pozwolić automatycznie ładować obrazy, ale przy
dużych wideo decydować ręcznie.

### Urządzenia

W sekcji „Urządzenia" -> „Zarządzaj urządzeniami" widzisz to urządzenie.
Parowanie kolejnego urządzenia pojawi się w późniejszej wersji (rozdział 11).

### Sieć

Cleona nie potrzebuje ustawień sieciowych, aby działać. Są trzy
przełączniki sieciowe:

- **Przekierowanie portu na routerze** (domyślnie: włączone). Cleona prosi
  Twój własny router, aby otworzył dla Cleony port. Jeśli się uda,
  Twoje urządzenie jest dla innych lepiej osiągalne i pomaga sieci.
  Cleona rozmawia przy tym tylko z Twoim routerem, nie z internetem.
- **Publiczne wpisy adresowe** (domyślnie: włączone). Gdy Twoje
  urządzenie ma jeszcze zbyt mało sąsiadów, zagląda do publicznego
  katalogu (Nostr) za kolejnymi punktami wejścia, a gdy samo jest dobrze
  osiągalne, wpisuje się tam. Wpis zawiera adres, żadnej nazwy i żadnego
  kontaktu. Wyłączysz go, Twoje urządzenie znajdzie sąsiadów tylko przez
  zaproszenia, sieć lokalną i sąsiadów, których już zna.
- **Mniej pakietów maskujących w Wi-Fi** (domyślnie: wyłączone). W Wi-Fi
  lub na kablu możesz wyłączyć puste pakiety maskujące. Wtedy jest tam
  jednak znów widać, kiedy piszesz. W sieci komórkowej tego przełącznika
  nie ma -- tam Cleona i tak wysyła tylko jeden pakiet maskujący na
  minutę.

Ruchu maskującego jako całości nie da się wyłączyć. To jest celowe: tylko
gdy działa zawsze, aktywność Twojego urządzenia nic nie mówi o tym, czy
właśnie piszesz.

Nad trzema przełącznikami znajduje się **tryb oszczędzania danych**: w
sieci komórkowej Cleona go podpowiada, ale nigdy nie włącza go sama.
Oszczędza dane, ale Twoje urządzenie jest od zewnątrz łatwiejsze do
rozpoznania.

Pod nim znajduje się opcja **„Pamięć podręczna dla mediów innych osób"**: Twoje
urządzenie trzyma zaszyfrowane części mediów innych osób do 7 dni, aby
dotarły do swoich odbiorców (domyślnie: 100 MB na telefonie, 1 GB na
komputerze). Mniejszy rozmiar uwalnia miejsce od razu -- najpierw
najstarsze części.

---

## 14. Bezpieczeństwo

### Co oznacza szyfrowanie postkwantowe?

Dzisiejsze szyfrowanie opiera się na problemach matematycznych, które dla
zwykłych komputerów są ekstremalnie trudne do rozwiązania. Komputery
kwantowe mogłyby niektóre z tych problemów w przyszłości szybko rozwiązać.
Szyfrowanie postkwantowe stosuje dodatkowe metody, które oprą się też
komputerom kwantowym.

Cleona łączy oba podejścia: klasyczne szyfrowanie dla niezawodności i
metody postkwantowe dla odporności na przyszłość. Tak jesteś chroniony
jednocześnie przed dzisiejszymi i przyszłymi zagrożeniami.

Dla każdej pojedynczej wiadomości generowany jest własny klucz. Nawet
gdyby atakujący złamał klucz jednej wiadomości, nie mógłby odczytać żadnej
innej.

### Dlaczego brak serwera jest bezpieczniejszy

W zwykłych komunikatorach Twoje wiadomości wędrują przez serwery
dostawcy. Nawet jeśli są tam szyfrowane: dostawca ma dostęp do metadanych
(kto komunikuje się kiedy z kim, jak często, skąd) i w określonych
okolicznościach musi je wydać na polecenie sądu.

W Cleonie nie ma takiego centralnego punktu. Nie ma miejsca, w którym
zbierałyby się wszystkie metadane, ani katalogu, w którym można by
sprawdzić, kim jesteś lub kogo znasz.

### Kto widzi, że piszesz z kimś?

Szyfrowanie chroni to, **co** piszesz. Równie ważne jest, aby żaden
pojedynczy obserwator nie dowiedział się, **z kim** i **kiedy** piszesz.
O to Cleona dba tak:

- **W internecie nigdy bezpośrednio.** Gdyby Twoje urządzenie wysłało
  wiadomość bezpośrednio na adres internetowy rozmówcy, Twój dostawca
  mógłby zobaczyć, z kim piszesz. Dlatego wiadomość w internecie idzie
  zawsze przez Waszych stałych sąsiadów: Twojego i rozmówcy.
- **Sąsiedzi, którym ufasz.** Twoi stali sąsiedzi są, gdzie tylko
  możliwe, urządzeniami Twoich własnych kontaktów -- do trzech, które
  akurat są osiągalne z zewnątrz. Gdy jeden odpadnie, wchodzi inny
  kontakt. Kontaktu nie da się kupić serwerami; dowolny węzeł w sieci
  tak. Gdy nie masz jeszcze żadnego osiągalnego kontaktu, Cleona bierze
  innego sąsiada. Twoje zaproszenie nigdy nie wymienia żadnego z Twoich
  kontaktów, tak by nikt przez nie nie dowiedział się o adresie znajomego.
- **Kody zamiast nazw.** Sąsiedzi nie widzą nazw ani identyfikatorów,
  lecz tylko kod. Obowiązuje on dokładnie dla Was obu, w jednym
  kierunku, przez jeden dzień -- następnego dnia jest inny. Twój sąsiad
  wie, skąd pakiet pochodzi, ale nie wie, dokąd ostatecznie zmierza.
  Sąsiad rozmówcy wie, dokąd zmierza, ale nie skąd pochodził. W normalnym
  przypadku nikt po drodze nie widzi obu końców.
- **Ruch maskujący.** Twoje urządzenie stale, w nieregularnych
  odstępach, wysyła do swoich sąsiadów pakiety maskujące. Są tak samo
  duże jak prawdziwe pakiety, idą tym samym portem i z zewnątrz nie
  różnią się od nich. Czy właśnie pisze człowiek, czy urządzenie tylko
  działa, nie da się rozpoznać. Twoje wiadomości nigdy nie czekają na
  ruch maskujący -- ruszają od razu, on działa tylko obok.

**Koszt ruchu maskującego:** W Wi-Fi około 13 MB dziennie. W sieci
komórkowej Cleona wysyła tylko jeden pakiet maskujący na minutę, to około
1,7 MB dziennie. Powodem ograniczenia w sieci komórkowej nie jest ilość
danych, lecz bateria: każdy pakiet wybudza modem radiowy.

**Czego Cleona nie może ukryć** -- szczerze mówiąc:

- Żaden **pojedynczy** obserwator nie widzi, kto pisze z kim -- ani Twój
  dostawca, ani węzły po drodze. Kto jednak **obserwuje oba końce
  jednocześnie**, np. państwo obserwujące Twój i rozmówcy przyłącz lub
  obstawiające obu sąsiadów, może w czasie przyporządkować: paket
  wychodzi u Ciebie, chwilę później paket wchodzi u rozmówcy.
  Powtórzone wystarczająco często, daje to powiązanie.
- Ruch maskujący utrudnia to przyporządkowanie, ale go nie zapobiega.
  Ukrywa pojedyncze wiadomości, nie ilość: kto bardzo dużo wysyła,
  zwiększa całkowity ruch swojego urządzenia.
- Kontakt, który jest Twoim stałym sąsiadem, dowiaduje się, **kiedy** i
  **ile** wysyłasz i odbierasz -- nie z kim i nie co. Gdy grozi
  niebezpieczeństwo z Twojego własnego otoczenia, możesz wyłączyć każdego
  kontaktu (patrz rozdział 3, „Nigdy nie używaj jako stałego sąsiada").
- Gdy dwójka nowych użytkowników ma tylko tego samego jednego sąsiada,
  ich wiadomość idzie dokładnie przez ten węzeł i widzi on oba końce.
  Gdy tylko jeden z nich ma kolejnych sąsiadów, to się kończy.
- Twoje zaproszenie zawiera Twoje adresy internetowe. Kto ma linię
  tekstową, widzi, gdzie jesteś online -- podawaj ją tylko ludziom,
  którym to ufasz.
- Sąsiad przekazujący widzi, że dwa kody wymieniają pakiety -- nie kto
  za nimi stoi i nie co jest w środku.
- Sygnał trwającego połączenia może, gdy pierwszy sąsiad akurat nie
  odpowiada, pójść przez węzeł, który widzi oba końce; dowiaduje się, że
  rozmawiacie ze sobą.
- Duży plik, na który się zgodziłeś, jest widoczny dla komputera, który go
  przekazuje lub przechowuje, na obu końcach (patrz rozdział 4).
- Przy połączeniach ochrona przed dostawcą nie obowiązuje, a Twój kontakt
  widzi Twój adres internetowy (patrz rozdział 7).

### Co się dzieje, gdy rozmówca jest offline?

1. Cleona uruchamia wszystkie pasujące drogi jednocześnie: w tej samej
   sieci Wi-Fi bezpośrednio, w internecie przez dwóch sąsiadów -- oraz
   dodatkowo skrzynkę.
2. Dla skrzynki Cleona zostawia zaszyfrowaną wiadomość u trzech sąsiadów.
   Gdy dwóch potwierdzi odbiór, uznaje się ją za złożoną.
3. Cleona wybiera do tego sąsiadów, u których rozmówca też zagląda --
   najpierw sąsiada, którego wymienia jego zaproszenie.
4. Wiadomość czeka tam do 7 dni. Gdy rozmówca wróci, ją odbiera i
   potwierdza Ci odbiór. Dopiero wtedy widzisz dwa ptaszki.

Skrzynkę może opróżnić tylko Twój rozmówca: odbieranie i usuwanie działa
tylko z kluczem, który posiada tylko on, a usuwanie następuje dopiero,
gdy potwierdzi odbiór. Sąsiedzi widzą tylko zaszyfrowane pakiety pod
wartościem, który zmienia się każdego dnia.

### Obcy nie przechodzą

Od kogoś, kto nie jest ani Twoim kontaktem, ani członkiem wspólnej grupy,
Cleona przyjmuje dokładnie dwie rzeczy: pytanie o Twoje klucze publiczne,
dopóki jedno z Twoich zaproszeń jest otwarte, oraz żądanie kontaktu.
Żądanie musi nosić ważne zaproszenie od Ciebie, a nadawca musi wcześniej
rozwiązać zadanie obliczeniowe. Wszystko inne -- wiadomości, połączenia,
pliki -- jest odrzucane, zanim w ogóle dotrze do aplikacji. Kto ma tylko
Twoją wydrukowaną wizytówkę, nie może Cię więc po prostu zadzwonić. Członek
wspólnej grupy dosięga Cię tylko w tej grupie -- z wiadomościami grupowymi
i połączeniami grupowymi, nigdy pojedynczo.

### Antycenzura

Cleona jest tak zbudowana, że trudno ją zablokować:

- **Brak serwera, brak stałego adresu.** W aplikacji nie widnieje adres,
  który można by zablokować, a sieć nie zależy od żadnego pojedynczego
  węzła.
- **Brak stałego portu.** Każde urządzenie przy pierwszym uruchomieniu
  wybiera losowy port. Nie ma znanej numeracji portów, po której można by
  rozpoznać ruch Cleony.
- **Jak dane losowe.** Nawiązywanie połączenia między dwoma urządzeniami
  jest tak zakodowane, że nie odróżnia się od danych losowych.
- **Wiele wejść.** Każde zaproszenie, każdy sąsiad i każde urządzenie w
  tej samej sieci Wi-Fi to możliwa droga z powrotem do sieci.

### Bezpieczne przechowywanie kluczy

Na wspieranych platformach Cleona przechowuje Twoje klucze
szyfrujące w bezpiecznym pęku kluczy systemu operacyjnego (Android
Keystore, iOS Keychain, macOS Keychain). Gdzie dostępne, oferuje to
ochronę wspieraną sprzętowo dla Twoich kluczy.

### Szyfrowanie bazy danych

Twoje wiadomości i rozmowy leżą w zaszyfrowanej bazie danych -- osobnej
dla każdej tożsamości, każda z własnym kluczem. Zaszyfrowana jest nie
tylko sama baza danych, ale też jej pliki tymczasowe; nic nie jest
zapisywane na dysk bez szyfrowania, nawet krótkotrwale. Ustawienia,
kontakty i multimedia również są przechowywane zaszyfrowane.

Klucze są wyprowadzane z Twoich 24 słów i istnieją tylko na Twoim
urządzeniu. Nawet ktoś, kto wejdzie w posiadanie Twojego urządzenia i
odczyta dane, znajdzie bez tych kluczy tylko nieczytelne dane.

Nieszyfrowane jest to tylko tam, gdzie sam wyprowadzasz treści z Cleony:
- gdy zapisujesz plik z czatu na swoje urządzenie,
- gdy przyciskiem zrzutu ekranu kładziesz obraz do swoich obrazów,
- gdy udostępniasz coś innej aplikacji,
- gdy konfigurujesz archiwizację multimediów (rozdział 13):
  zarchiwizowane oryginały leżą nieszyfrowane na Twojej pamięci
  sieciowej w domu, abyś mógł je tam otworzyć także bez Cleony,
- gdy przenosisz wydarzenia do systemowego kalendarza Androida: mogą je
  tam czytać inne aplikacje z dostępem do kalendarza.

To, co tak wyszło na zewnątrz, nie jest usuwane razem z wiadomością i nie
traci ważności razem z nią.

### Ochrona na ekranie

Na Androidzie, Windows i macOS Cleona nie pozwala innym aplikacjom na
nagrywanie ekranu. Potrzebujesz obrazu, sięgnij po przycisk zrzutu
ekranu na górnym pasku: kładzie obraz do Twoich obrazów -- nieszyfrowany.
W rozmowie, w której przekazywanie dalej nie jest dozwolone, zrzutu
ekranu nie ma.

---

## 15. Aktualizacje oprogramowania

### Jak otrzymuję aktualizacje?

Cleona może być aktualizowana różnymi drogami. Celem jest, abyś mógł
otrzymywać aktualizacje także wtedy, gdy pojedyncze kanały dystrybucji
zawiodą lub zostaną zablokowane:

1. **App Store / Play Store:** Gdy tylko Cleona tam się pojawi i
   zainstalujesz ją przez sklep, otrzymujesz aktualizacje jak zwykle
   przez sklep. Na iPhonie aktualizacje przychodzą przez TestFlight.
2. **GitHub Releases:** Na stronie GitHub projektu znajdziesz podpisane
   pakiety instalacyjne dla wszystkich platform.
3. **Aktualizacje przez sieć:** Cleona może pobrać aktualizację
   bezpośrednio przez sieć -- bez serwera pobierania. Nowa wersja jest
   podzielona na kawałki z korekcją błędów, które rozpraszają się w sieci;
   część z nich podróżuje nawet razem z ruchem maskującym. Twoje
   urządzenie zbiera wystarczająco kawałków i składa aktualizację.
   Przesyłane jest zwykle tylko zmiana -- kilka MB zamiast całej
   aplikacji. Dotyczy to Linuksa, Windows i Androida; pod macOS nowe
   wersje pobierasz ze strony lub z GitHuba.
4. **Linki zaproszeniowe:** Możesz tworzyć linki zaproszeniowe, które
   zawierają wszystko, czego nowy użytkownik potrzebuje, aby
   zainstalować Cletonę i połączyć się z siecią.
5. **Transfer fizyczny:** W środowiskach bez internetu możesz przekazać
   Cletonę innym przez pamięć USB lub w sieci lokalnej.

### Jak przebiega aktualizacja

1. Cleona zbiera kawałki nowej aktualizacji automatycznie w tle i składa
   je.
2. Dopiero gdy aktualizacja jest **kompletna**, a jej **podpis
   sprawdzony**, Cleona oferuje Ci ją. Nie dostajesz więc nigdy
   niedokończonej ani niesprawdzonej aktualizacji.
3. Gdy stukniesz „Instaluj", instalacja rozpoczyna się bez dalszego
   pytania. Na Androidzie system pokazuje dodatkowo swój dialog
   instalacji.

Starsze wersje nie są oferowane -- aktualizacja idzie zawsze tylko do
przodu. Jeśli wersja jest tak stara, że nie potrafi już współpracować z
siecią, Cleona pokazuje to wyraźnie i prosi Cię o aktualizację.

### Sprawdzanie podpisu

Każda aktualizacja jest dwukrotnie podpisana: metodą klasyczną i
postkwantową. Cleona sprawdza automatycznie oba podpisy. Tak jest
zapewnione, że akceptowane są tylko aktualizacje od oficjalnego dewelopera
-- nawet gdy aktualizacja przyszła przez sieć od obcych urządzeń.
Aktualizacja nigdy nie powstaje automatycznie z rozwoju, lecz tylko gdy
deweloper podpisze ją ręcznie.

---
## 16. Najczęściej zadawane pytania

### „Czy mogę używać Cleony bez internetu?"

Cleona potrzebuje połączenia sieciowego, ale niekoniecznie internetu:
w tej samej sieci Wi-Fi urządzenia Cleony znajdują się same i mogą pisać
do siebie całkowicie bez dostępu do internetu. Być jednocześnie online
z rozmówcą nie musisz: gdy jest offline, wiadomość czeka do 7 dni w
skrzynce u trzech sąsiadów, aż ją odbierze.

### „Co, jeśli zgubię swoją frazę seed?"

Dopóki działa jeszcze jakieś urządzenie z Twoją tożsamością, nic nie jest
stracone -- po prostu piszesz tam dalej. Na urządzeniu, na którym
założyłeś tożsamość, możesz zwykle ponownie odczytać 24 słowa (patrz
rozdział 2). Nie polegaj na tym: Ponowna instalacja usuwa tę kopię, a na
Androidzie niszczy ją także usunięcie lub zmiana blokady ekranu. Jeśli nie
masz ani słów, ani urządzenia, nie ma drogi powrotnej -- także nie przez
swoje kontakty, dewelopera ani kogokolwiek innego. Dlatego tak ważne jest
bezpieczne przechowanie 24 słów.

### „Czy ktoś może podsłuchiwać moje wiadomości?"

Nie. Każda wiadomość jest szyfrowana jednorazowym kluczem, który obowiązuje
tylko dla tej jednej wiadomości. Tylko Ty i Twój rozmówca możecie
odszyfrować wiadomość. Nie ma centralnego serwera, nie ma klucza
uniwersalnego i nie ma dostępu dla dewelopera. Nawet gdy jakieś urządzenie
po drodze przekazuje wiadomość, widzi tylko zaszyfrowaną breję danych i
kod. Twój sąsiad wie, że pakiet pochodzi od Ciebie, ale nie wie, do kogo
idzie; sąsiad Twojego rozmówcy wie, do kogo idzie, ale nie od kogo.

### „Dlaczego nie potrzebuję numeru telefonu?"

Ponieważ Twoja tożsamość jest czysto kryptograficzna. Zamiast numeru
telefonu czy adresu e-mail powiązanego z Twoim prawdziwym nazwiskiem,
identyfikuje Cię para kluczy wygenerowana na Twoim urządzeniu. Kontakty
dodajesz przez kod QR, NFC lub linię tekstową swojego zaproszenia -- nie
przez książkę telefoniczną. To oznacza
więcej prywatności, bo Twoje konto komunikatora nie jest związane z Twoją
rzeczywistą tożsamością.

### „Jak znajdę ludzi w Cleonie?"

Cleona celowo nie ma wyszukiwania kontaktów po numerze telefonu ani
nazwie -- to byłby problem dla prywatności. Zamiast tego wymieniasz
zaproszenia bezpośrednio: przez kod QR, NFC lub jako linię tekstową inną
drogą. To jak wymiana wizytówek zamiast zaglądania do książki
telefonicznej.

### „Czy Cleona działa też za granicą?"

Tak. Dopóki masz połączenie z internetem, Cleona działa wszędzie na
świecie. Ponieważ nie ma centralnego serwera ani stałego adresu, usługi
nie da się po prostu wyłączyć dla poszczególnych krajów. Jak Cleona
utrudnia blokady, opisano w rozdziale „Bezpieczeństwo" w sekcji
„Antycenzura". Kraj, który blokuje na granicy każdy nieznany ruch, może
jednak także zatrzymać Cletonę.

### „Czy Cleona jest darmowa?"

Tak. Cleona jest darmowa i użyteczna bez reklam. Ponieważ nie ma
centralnego serwera, nie powstają też koszty serwerowe dla prowadzenia. W
ustawieniach w sekcji „Wesprzyj Cleona" -> „Wesprzyj" możesz dobrowolnie
wesprzeć rozwój.

### „Moja wiadomość ma tylko jeden ptaszek -- co to znaczy?"

Wiadomość jest w drodze, ale rozmówca jeszcze nie potwierdził odbioru --
najczęściej dlatego, że jest właśnie offline. To nie jest błąd: wiadomość
czeka do 7 dni w skrzynce. Gdy ją odbierze, widzisz dwa ptaszki. Zegarek
oznacza, że jeszcze żadna droga nie zaniosła wiadomości -- ruszy sama, gdy
tylko jakaś droga się pojawi; znak ostrzeżenia, że przez 14 dni nie
znalazła żadnej drogi i możesz wysłać ją ponownie.

### „Dlaczego wiadomości przychodzą z opóźnieniem na moim iPhonie?"

iOS nie pozwala aplikacjom stale działać w tle. Cleona jest wybudzana
tylko od czasu do czasu i to krótko; kiedy, decyduje iOS. Pobiera wtedy
wszystko. Gdy tylko otworzysz aplikację, Cleona pobiera to, co zostało
zapisane dla Ciebie.

### „Czy mogę przejść z WhatsApp do Cleony?"

Tak, ale nie możesz przenieść swoich czatów z WhatsApp. Cleona i WhatsApp
to fundamentalnie różne systemy. Musisz dodać swoje kontakty w Cleonie
pojedynczo. Najprościej idzie to, gdy wyślesz linię tekstową swojego
zaproszenia do swoich kontaktów. Każde żądanie, które tak dotrze,
potwierdzisz sam w „Żądaniach".

### „Czy mogę używać Cleony na wielu urządzeniach jednocześnie?"

Jeszcze nie. Drugie urządzenie dla tej samej tożsamości pojawi się w
późniejszej wersji (rozdział 11). Na wielu urządzeniach możesz dziś
używać różnych tożsamości.

### „Jak otrzymuję aktualizacje, gdy App Store jest zablokowany?"

Cleona może pobierać aktualizacje bezpośrednio przez sieć, bez
polegania na sklepie z aplikacjami, stronie internetowej czy serwerze
pobierania. Jeśli jakieś inne urządzenie w sieci ma najnowszą wersję,
Twoje urządzenie może pobrać stamtąd aktualizację. Autentyczność jest
sprawdzana przez podpis cyfrowy dewelopera. Alternatywnie kontakt może
przekazać Ci aplikację przez link zaproszeniowy lub pamięć USB. Więcej o
tym w rozdziale „Aktualizacje oprogramowania".

---

## Pomoc i kontakt

Jeśli masz pytania lub napotkasz problem, aktualne informacje znajdziesz na
stronie Cleony i na GitHub. Ponieważ Cleona to projekt zdecentralizowany,
nie ma klasycznego supportu dla klientów -- ale aktywną społeczność, która
chętnie pomaga.

---

*Ten podręcznik opisuje Cleona Chat w wersji 4.2. Pojedyncze funkcje mogą
się w nowszych wersjach zmieniać lub rozszerzać.