# Cleona Chat -- Podręcznik użytkownika

Wersja 3.1.125 | Lipiec 2026

---

## Spis treści

1. [Czym jest Cleona Chat?](#1-czym-jest-cleona-chat)
2. [Pierwsze kroki](#2-pierwsze-kroki)
3. [Kontakty](#3-kontakty)
4. [Wiadomości](#4-wiadomosci)
5. [Grupy](#5-grupy)
6. [Kanały publiczne](#6-kanaly-publiczne)
7. [Połączenia](#7-polaczenia)
8. [Kalendarz](#8-kalendarz)
9. [Ankiety](#9-ankiety)
10. [Wiele tożsamości](#10-wiele-tozsamosci)
11. [Multi-Device](#11-multi-device)
12. [Odzyskiwanie](#12-odzyskiwanie)
13. [Ustawienia](#13-ustawienia)
14. [Bezpieczeństwo](#14-bezpieczenstwo)
15. [Aktualizacje oprogramowania](#15-aktualizacje-oprogramowania)
16. [Najczęściej zadawane pytania](#16-najczesciej-zadawane-pytania)

---

## 1. Czym jest Cleona Chat?

### Twój komunikator, twoje dane

Cleona Chat to komunikator, który działa całkowicie bez centralnego serwera.
Twoje wiadomości trafiają bezpośrednio z twojego urządzenia do urządzenia
rozmówcy -- bez pośrednictwa siedziby firmy, bez chmury, bez centrum danych.
Żadna firma nie może odczytać, zapisać ani przekazać dalej twoich wiadomości,
ponieważ po prostu żadna firma nie stoi pomiędzy wami.

### Brak konta, brak numeru telefonu

W Cleonie nie potrzebujesz ani numeru telefonu, ani adresu e-mail, żeby się
zalogować. Twoja tożsamość składa się z pary kluczy kryptograficznych, która
jest automatycznie generowana na twoim urządzeniu przy pierwszym uruchomieniu.
Oznacza to: nikt nie może cię namierzyć na podstawie numeru telefonu czy
adresu e-mail, chyba że sam(a) udostępnisz swoje dane kontaktowe.

### Szyfrowanie odporne na przyszłość

Cleona korzysta z tzw. szyfrowania postkwantowego. Oznacza to, że nawet
przyszłe komputery kwantowe nie będą w stanie złamać twoich wiadomości. Nie
musisz rozumieć szczegółów technicznych -- ważne jest tylko to, że twoja
komunikacja jest chroniona najlepiej, jak pozwala na to obecny stan techniki.

### Jak to działa bez serwera?

Wyobraź sobie, że ty i twoje kontakty tworzycie wspólnie sieć. Każde
urządzenie pomaga przekazywać wiadomości dalej. Jeśli twój rozmówca jest
akurat online, wiadomość trafia do niego bezpośrednio. Jeśli jest offline,
wspólne kontakty przechowują wiadomość tymczasowo i dostarczają ją, gdy
odbiorca znów będzie dostępny. Twoje kontakty są więc jednocześnie twoją
siecią.

### Platformy

Cleona jest dostępna na Android, iOS, macOS, Linux i Windows.

---

## 2. Pierwsze kroki

### Instalacja aplikacji

**Android:**
1. Pobierz plik APK ze strony Cleona lub z GitHub Releases.
2. Otwórz plik na swoim telefonie. W razie potrzeby zezwól na instalację
   z nieznanych źródeł (Android zapyta cię o to automatycznie).
3. Stuknij "Zainstaluj" i poczekaj, aż instalacja się zakończy.

**iOS:**
1. Otwórz link zaproszenia TestFlight na swoim iPhonie.
2. Stuknij "Zainstaluj". TestFlight to oficjalny sposób firmy Apple na
   dystrybucję aplikacji beta.
3. Po instalacji znajdziesz Cleonę na ekranie głównym.

**macOS:**
1. Pobierz plik DMG ze strony Cleona lub z GitHub Releases.
2. Otwórz DMG i przeciągnij Cleonę do folderu Programy.
3. Przy pierwszym uruchomieniu macOS może zapytać, czy chcesz otworzyć
   aplikację od zidentyfikowanego programisty -- potwierdź to.

**Linux (Ubuntu/Debian):**
1. Pobierz plik .deb ze strony Cleona lub z GitHub Releases.
2. Zainstaluj przez dwuklik lub w terminalu: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Uruchom Cleonę z menu aplikacji lub w terminalu poleceniem `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Pobierz plik .rpm ze strony Cleona lub z GitHub Releases.
2. Zainstaluj poleceniem: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Uruchom Cleonę z menu aplikacji lub w terminalu poleceniem `cleona-chat`.

**Linux (wszystkie dystrybucje -- AppImage):**
1. Pobierz plik .AppImage ze strony Cleona lub z GitHub Releases.
2. Nadaj plikowi uprawnienia do wykonywania: kliknij prawym przyciskiem,
   Właściwości, Wykonywalny, albo w terminalu: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Uruchom przez dwuklik lub w terminalu: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Pobierz instalator ze strony Cleona lub z GitHub Releases.
2. Uruchom plik instalacyjny i postępuj zgodnie z instrukcjami.
3. Uruchom Cleonę z menu Start lub skrótu na pulpicie.

### Tworzenie tożsamości

Przy pierwszym uruchomieniu Cleona automatycznie tworzy dla ciebie nową
tożsamość. Możesz nadać sobie nazwę wyświetlaną -- to imię/nazwa, które widzą
twoje kontakty. Tę nazwę można zmienić w dowolnym momencie.

### Zapisz Seed-Phrase -- najważniejsza rzecz w ogóle

Po utworzeniu tożsamości Cleona wyświetli ci 24 słowa. To twoja
**Seed-Phrase** -- twój osobisty klucz do odzyskiwania.

**Zapisz te 24 słowa na kartce papieru i przechowuj je w bezpiecznym miejscu.**

Dlaczego to takie ważne?

- Jeśli twój telefon się zepsuje, zgubi lub zostanie skradziony, dzięki tym
  24 słowom możesz odtworzyć całą swoją tożsamość na nowym urządzeniu.
- Bez Seed-Phrase nie ma drogi powrotnej. Nie ma przycisku "zapomniałem
  hasła" ani wsparcia, które mogłoby zwrócić ci konto -- ponieważ nie
  istnieje żadne konto na serwerze.
- Nigdy nie udostępniaj Seed-Phrase innym osobom. Kto zna te słowa, może
  podszyć się pod ciebie.

Seed-Phrase znajdziesz później również w ustawieniach w sekcji
"Bezpieczeństwo", jeśli będziesz chciał(a) odczytać ją ponownie.

### Dodawanie pierwszego kontaktu

Żeby z kimś porozmawiać, musisz najpierw dodać tę osobę jako kontakt. Istnieje
kilka sposobów na to -- wszystkie zostały wyjaśnione w następnej sekcji.

---

## 3. Kontakty

### Skanowanie kodu QR (zalecane)

Najprostszy sposób dodania kontaktu:

1. Twój rozmówca otwiera swoją stronę szczegółów tożsamości (stuknięcie we
   własną nazwę na górnym pasku) i pokazuje ci swój kod QR.
2. Stukasz w przycisk plus i wybierasz "Skanuj kod QR".
3. Skieruj telefon na kod QR rozmówcy.
4. Zaproszenie do kontaktów zostaje wysłane automatycznie. Gdy tylko twój
   rozmówca je zaakceptuje, będziecie mogli ze sobą pisać.

Jeśli spotykacie się osobiście, kod QR to najbezpieczniejsza metoda,
ponieważ dokładnie wiesz, z kim wymieniasz się kontaktem.

### NFC (zbliżenie telefonów)

Jeśli oba urządzenia obsługują NFC:

1. Oboje otwórzcie funkcję dodawania kontaktu.
2. Przyłóżcie telefony do siebie tylnymi ściankami.
3. Dane kontaktowe zostaną wymienione automatycznie.

NFC, podobnie jak kod QR, zapewnia wysoki poziom bezpieczeństwa, ponieważ
wymiana działa tylko wtedy, gdy stoicie fizycznie obok siebie.

### Udostępnianie linku (URI cleona://)

Swój link kontaktowy możesz też wysłać przez e-mail, SMS lub inny
komunikator:

1. Otwórz swoją stronę szczegółów tożsamości.
2. Skopiuj swój link cleona://.
3. Wyślij link osobie, która ma cię dodać.
4. Druga osoba otwiera link albo wkleja go w oknie dodawania kontaktu.

Uwaga: przy tej metodzie polegasz na tym, że link nie został zmieniony
podczas przesyłania. W przypadku szczególnie wrażliwych kontaktów zalecamy
kod QR lub NFC.

### Akceptowanie zaproszeń do kontaktów

Gdy ktoś wyśle ci zaproszenie do kontaktów, pojawi się ono w twojej skrzynce
odbiorczej (ostatnia zakładka na dolnym pasku). Możesz tam:

- **Zaakceptować** -- osoba zostanie dodana do twoich kontaktów.
- **Odrzucić** -- zaproszenie zostanie odrzucone.
- **Zablokować** -- osoba nie będzie mogła wysyłać ci kolejnych zaproszeń.

### Poziomy weryfikacji

Cleona pokazuje ci, jak pewnie potwierdzona jest tożsamość danego kontaktu:

| Poziom | Znaczenie |
|-------|-----------|
| Nieznany | Otrzymałeś(-aś) tylko identyfikator węzła (Node-ID) lub link. |
| Widziany | Wymiana kluczy się powiodła, możecie komunikować się w sposób zaszyfrowany. |
| Zweryfikowany | Spotkaliście się osobiście i zweryfikowaliście się przez kod QR lub NFC. |
| Zaufany | Oznaczyłeś(-aś) ten kontakt jawnie jako zaufany. |

Im wyższy poziom, tym większa pewność, że rozmawiasz naprawdę z właściwą
osobą.

---

## 4. Wiadomości

### Wysyłanie i odbieranie tekstu

Po prostu wpisz swoją wiadomość w polu tekstowym na dole i naciśnij Enter lub
przycisk wysyłania. Twoja wiadomość zostaje automatycznie zaszyfrowana,
zanim opuści twoje urządzenie.

Przychodzące wiadomości pojawiają się w historii czatu. Znacznik (haczyk)
pokazuje ci, czy twoja wiadomość została dostarczona.

### Wysyłanie zdjęć, filmów i plików

Masz kilka możliwości:

- **Ikona spinacza** w polu tekstowym: stuknij ją, aby wybrać plik, zdjęcie
  lub film z galerii albo systemu plików.
- **Przeciągnij i upuść** (desktop): po prostu przeciągnij plik do okna
  czatu.
- **Wklejanie ze schowka** (desktop): skopiuj obraz i wklej go w czacie.

Małe pliki (poniżej 256 KB) są wysyłane bezpośrednio. Większe pliki są
przesyłane dwuetapowo: najpierw plik zostaje zapowiedziany, a następnie
przekazany w częściach.

### Wiadomości głosowe

1. Przytrzymaj przycisk mikrofonu w polu tekstowym.
2. Nagraj swoją wiadomość.
3. Puść przycisk, aby wysłać wiadomość.

Jeśli na twoim urządzeniu włączone jest rozpoznawanie mowy (patrz
ustawienia), twoja wiadomość głosowa zostanie automatycznie przepisana na
tekst. Twój rozmówca zobaczy wtedy zarówno nagranie, jak i transkrypcję
tekstową.

### Odpowiadanie na wiadomości (cytowanie)

Aby odpowiedzieć na konkretną wiadomość:

1. Otwórz menu trzech kropek obok wiadomości.
2. Wybierz "Odpowiedz".
3. Nad polem tekstowym pojawi się baner z cytowaną wiadomością.
4. Napisz swoją odpowiedź i wyślij ją.

Cytowana wiadomość jest wyświetlana w twojej odpowiedzi, dzięki czemu
kontekst jest jasny.

### Edytowanie i usuwanie wiadomości

- **Edytowanie:** menu trzech kropek przy wiadomości, następnie "Edytuj".
  Zmień tekst i wyślij go ponownie. Twój rozmówca zobaczy, że wiadomość
  została zedytowana. Edycja jest możliwa w ciągu 15 minut od wysłania.
- **Usuwanie:** menu trzech kropek przy wiadomości, następnie "Usuń".
  Wiadomość zostanie usunięta zarówno u ciebie, jak i u rozmówcy. Swoje
  własne wiadomości możesz usuwać w dowolnym momencie -- nie ma okna
  czasowego na usuwanie.

### Reakcje emoji

Zamiast pisać odpowiedź, możesz zareagować na wiadomość emoji:

1. Otwórz menu trzech kropek albo przytrzymaj wiadomość dłużej.
2. Wybierz emoji z szybkiego wyboru albo otwórz pełny wybór emoji.
3. Twoja reakcja pojawi się pod wiadomością.

### Kopiowanie tekstu

Za pomocą menu trzech kropek przy wiadomości możesz skopiować tekst
wiadomości do schowka.

### Wyszukiwanie wiadomości

Na górze okna czatu znajdziesz funkcję wyszukiwania. Wpisz szukaną frazę,
a Cleona pokaże wszystkie wyniki w bieżącym czacie. Za pomocą strzałek
możesz przechodzić między wynikami.

Na ekranie głównym dostępny jest dodatkowo filtr wyszukiwania obejmujący
wszystkie zakładki, dzięki któremu możesz przeszukać wszystkie rozmowy pod
kątem danego terminu.

### Podgląd linków

Gdy wysyłasz link, Cleona automatycznie generuje podgląd (tytuł, opis,
miniaturkę). Ten podgląd jest tworzony na twoim urządzeniu i wysyłany razem
z linkiem -- twój rozmówca nie musi w tym celu nawiązywać połączenia
z linkowaną stroną.

Gdy stukniesz w otrzymany link, zostaniesz zapytany(-a), czy chcesz go
otworzyć w zwykłej przeglądarce, w trybie incognito, czy wcale.

---

## 5. Grupy

### Tworzenie grupy

1. Przejdź do zakładki "Grupy".
2. Stuknij przycisk plus.
3. Nadaj grupie nazwę.
4. Wybierz kontakty, które chcesz zaprosić.
5. Stuknij "Utwórz".

Zaproszone kontakty otrzymają powiadomienie i będą mogły dołączyć do grupy.

### Zapraszanie członków

Również po utworzeniu grupy możesz zapraszać kolejne kontakty:

1. Otwórz informacje o grupie (menu trzech kropek w widoku grupy lub górny
   pasek w czacie grupowym).
2. Stuknij "Zaproś".
3. Wybierz kontakty, które chcesz dodać.

### Role

Każda grupa ma trzy role:

- **Właściciel (Owner):** ma pełną kontrolę. Może dodawać i usuwać
  członków, mianować adminów i zarządzać grupą. Właściciel może również
  przekazać swój status innemu członkowi.
- **Admin:** może usuwać członków i pomagać w zarządzaniu.
- **Członek:** może czytać i pisać wiadomości.

### Opuszczanie grupy

1. Otwórz menu trzech kropek w widoku grupy.
2. Wybierz "Opuść".
3. Potwierdź swoją decyzję.

Gdy opuścisz grupę, twoje dotychczasowe wiadomości pozostają widoczne dla
pozostałych członków.

---

## 6. Kanały publiczne

### Czym są kanały?

Kanały to publiczne fora dyskusyjne w sieci Cleona. W przeciwieństwie do
grup, każdy może tu czytać bez konieczności bycia zaproszonym. Publikować
posty mogą tylko właściciel i administratorzy -- subskrybenci czytają.

### Wyszukiwanie i dołączanie do kanałów

1. Przejdź do zakładki "Kanały".
2. Otwórz zakładkę "Szukaj".
3. Przeszukaj dostępne kanały według nazwy lub tematu.
4. Stuknij w kanał, a następnie w "Subskrybuj".

Kanały można filtrować według języka. Niektóre kanały są oznaczone jako
"Tylko dla dorosłych" -- są widoczne tylko wtedy, gdy w swoim profilu
potwierdziłeś(-aś), że masz ukończone 18 lat.

### Tworzenie własnego kanału

1. Przejdź do zakładki "Kanały".
2. Stuknij przycisk plus.
3. Wpisz nazwę kanału (musi być unikalna w całej sieci).
4. Wybierz język oraz to, czy kanał ma być publiczny, czy prywatny.
5. Opcjonalnie: dodaj opis i obraz.
6. Stuknij "Utwórz".

W przypadku kanałów publicznych możesz określić, czy treść jest oznaczona
jako "Tylko dla dorosłych".

### Zgłaszanie treści

Jeśli zauważysz nieodpowiednie treści na publicznym kanale, możesz je
zgłosić. Cleona korzysta z zdecentralizowanego systemu moderacji: zgłoszenia
są oceniane przez losowo wybranych członków sieci (rodzaj "ławy
przysięgłych"). Jeśli stwierdzone zostanie naruszenie, kanał otrzymuje
ostrzeżenie. Przy powtarzających się naruszeniach kanał zostaje
zdegradowany w indeksie wyszukiwania lub zablokowany.

### Kanały systemowe

Cleona posiada dwa wbudowane kanały systemowe:

- **Bug Log:** Gdy Cleona wykryje błąd, zapyta cię, czy chcesz wysłać
  zanonimizowany raport o błędzie. Te raporty trafiają na kanał Bug Log,
  gdzie może je przejrzeć społeczność. Nie są przesyłane żadne dane
  osobowe -- tylko techniczny opis błędu. Możesz też ręcznie wysłać raport
  z logu (z oknem podglądu i wyraźną zgodą).
- **Feature Requests:** Tutaj użytkownicy mogą zgłaszać propozycje funkcji
  i głosować na istniejące propozycje. Propozycje są sortowane według
  liczby głosów.

Oba kanały systemowe mają limit rozmiaru 25 MB i są nadzorowane przez system
moderacji jury.

---

## 7. Połączenia

### Rozpoczynanie połączenia głosowego

1. Otwórz czat z kontaktem, do którego chcesz zadzwonić.
2. Stuknij ikonę telefonu na górnym pasku.
3. Poczekaj, aż rozmówca odbierze połączenie.

Podczas rozmowy widzisz licznik czasu trwania rozmowy oraz masz dostęp do
wyciszania i głośnika.

Aby zakończyć połączenie, stuknij czerwony przycisk rozłączenia.

### Rozpoczynanie połączenia wideo

1. Otwórz czat z kontaktem.
2. Stuknij ikonę kamery na górnym pasku.
3. Twój obraz wideo pojawi się w małym oknie, a obraz rozmówcy w dużym
   obszarze.

Podczas rozmowy możesz przełączać się między kamerą przednią a tylną.

### Połączenia przychodzące

Gdy ktoś do ciebie dzwoni, pojawia się okno powiadomienia z nazwą
dzwoniącego. Możesz:

- **Odebrać** -- rozmowa się rozpoczyna.
- **Odrzucić** -- dzwoniący zostaje o tym powiadomiony.

Jeśli jesteś już w trakcie rozmowy, nowe połączenie zostaje automatycznie
odrzucone.

### Połączenia grupowe

Możesz również prowadzić połączenia grupowe, w których jednocześnie
uczestniczy kilka osób. Połączenie jest organizowane za pomocą
inteligentnego drzewa przekazywania, dzięki czemu nie każdy uczestnik musi
być połączony bezpośrednio z każdym innym. Wszystkie rozmowy są w pełni
szyfrowane.

### Szyfrowanie połączeń

Wszystkie połączenia są szyfrowane jednorazowymi kluczami, które istnieją
tylko przez czas trwania rozmowy. Po zakończeniu połączenia klucze te są
natychmiast usuwane. Nikt nie jest w stanie odszyfrować rozmowy
z przeszłości.

---

## 8. Kalendarz

Cleona zawiera wbudowany kalendarz, który działa w sposób zaszyfrowany
i całkowicie zdecentralizowany -- bez usługi chmurowej.

### Widoki

Kalendarz oferuje pięć widoków: dzień, tydzień, miesiąc, rok oraz widok
zadań. Przełączaj się między nimi za pomocą zakładek na górze ekranu
kalendarza.

### Tworzenie wydarzeń

Stuknij w slot czasowy lub użyj przycisku dodawania, aby utworzyć nowe
wydarzenie. Możesz wprowadzić tytuł, datę, godzinę, miejsce i notatki.
Wydarzenia są przechowywane na twoim urządzeniu w postaci zaszyfrowanej.

### Wydarzenia cykliczne

Wydarzenia mogą się powtarzać codziennie, co tydzień, co miesiąc lub co rok.
Możesz dostosować wzorzec (np. co drugi wtorek, każdego pierwszego dnia
miesiąca) oraz ustawić datę zakończenia lub liczbę powtórzeń.

### Zapraszanie kontaktów

Podczas tworzenia lub edycji wydarzenia możesz zaprosić swoje kontakty
z Cleony. Otrzymają one zaszyfrowane zaproszenie do kalendarza i będą mogły
odpowiedzieć "tak", "nie" lub "może". Zmiany w wydarzeniu są automatycznie
wysyłane do wszystkich zaproszonych.

### Wskaźnik wolny/zajęty

Możesz udostępniać swoją dostępność kontaktom bez ujawniania szczegółów
wydarzeń. Istnieją trzy poziomy prywatności: pełne szczegóły, tylko bloki
czasowe lub ukryte. Możesz ustawić wartość domyślną i nadpisać ją
indywidualnie dla poszczególnych kontaktów.

### Przypomnienia

Wydarzenia mogą mieć przypomnienia, które wywołują powiadomienie systemowe
przed rozpoczęciem wydarzenia. W razie potrzeby możesz odłożyć przypomnienie
("drzemka").

### Synchronizacja z zewnętrznym kalendarzem

Cleona może synchronizować się z zewnętrznymi usługami kalendarza:

- **CalDAV** -- połącz się z dowolnym serwerem zgodnym z CalDAV (Nextcloud,
  Radicale itd.).
- **Google Kalendarz** -- synchronizacja przez Google Calendar API
  z bezpiecznym uwierzytelnianiem OAuth2.
- **Lokalny serwer CalDAV** -- Cleona może uruchomić lokalny serwer CalDAV
  na twoim urządzeniu, dzięki czemu aplikacje kalendarza na komputerze
  (Thunderbird, Outlook, Kalendarz Apple, Evolution) mogą synchronizować się
  z twoim kalendarzem Cleona.
- **Kalendarz systemowy Android** -- wydarzenia z Cleony mogą być
  przenoszone do wbudowanej aplikacji kalendarza na urządzeniu z Androidem.
- **Pliki ICS** -- importuj i eksportuj wydarzenia w standardowym formacie
  iCalendar.

### Eksport do PDF

Możesz wydrukować lub wyeksportować dowolny widok kalendarza (dzień,
tydzień, miesiąc, rok) jako dokument PDF.

---

## 9. Ankiety

W każdym czacie lub grupie możesz tworzyć ankiety, aby poznać opinie lub
zaplanować terminy.

### Typy ankiet

Cleona obsługuje pięć rodzajów ankiet:

- **Jednokrotny wybór** -- uczestnicy wybierają jedną opcję.
- **Wielokrotny wybór** -- uczestnicy mogą wybrać kilka opcji.
- **Ankieta terminowa** -- znajdź termin, który pasuje wszystkim. Każdy
  uczestnik oznacza terminy jako dostępne, może być lub niedostępne.
- **Skala** -- oceń coś w skali liczbowej (np. od 1 do 5).
- **Tekst dowolny** -- uczestnicy wpisują własną odpowiedź.

### Tworzenie ankiety

Otwórz czat i stuknij ikonę ankiety (albo skorzystaj z menu załączników).
Wybierz typ ankiety, sformułuj pytanie i opcje odpowiedzi, a następnie
wyślij ankietę. Pojawi się ona jako wiadomość w czacie.

### Głosowanie

Stuknij w ankietę, aby oddać swój głos. Możesz zmienić lub wycofać swój głos
w dowolnym momencie.

### Głosowanie anonimowe

Ankiety mogą być skonfigurowane do anonimowego głosowania. Gdy ta opcja jest
włączona, głosy są kryptograficznie anonimowe -- nikt, nawet twórca ankiety,
nie widzi, kto na co głosował. Liczba głosów pozostaje jednak widoczna.

### Ankieta terminowa w kalendarzu

Po zakończeniu ankiety terminowej zwycięski termin można jednym stuknięciem
przekształcić bezpośrednio w wpis w kalendarzu.

---

## 10. Wiele tożsamości

### Po co wiele tożsamości?

Wyobraź sobie, że chcesz oddzielić życie zawodowe od prywatnego -- podobnie
jak przy dwóch różnych numerach telefonu, ale bez drugiego telefonu.
W Cleonie możesz korzystać z wielu tożsamości na jednym urządzeniu. Każda
tożsamość ma własną nazwę, własne zdjęcie profilowe, własne kontakty
i własne rozmowy.

### Tworzenie nowej tożsamości

1. Na górnym pasku widzisz swoją aktualną tożsamość jako zakładkę.
2. Stuknij znak plus (+) po prawej stronie zakładek tożsamości.
3. Wpisz nazwę nowej tożsamości.
4. Gotowe -- nowa tożsamość jest od razu aktywna.

### Przełączanie między tożsamościami

Po prostu stuknij zakładkę tożsamości na górnym pasku. Przełączenie
następuje natychmiast -- bez czekania, bez ponownego ładowania.

### Wszystkie działają jednocześnie

Ważna informacja: wszystkie twoje tożsamości są aktywne w tym samym czasie.
Nawet gdy jesteś aktualnie widoczny(-a) jako "Zawodowa", twoja tożsamość
"Prywatna" nadal odbiera wiadomości. Niczego nie przegapisz, niezależnie od
tego, którą tożsamość masz aktualnie wybraną.

### Strona szczegółów tożsamości

Gdy stukniesz zakładkę aktualnie aktywnej tożsamości, otworzy się strona
szczegółów. Możesz tutaj:

- Wyświetlić swój kod QR dla kontaktów.
- Zmienić lub usunąć zdjęcie profilowe.
- Dodać opis profilu.
- Zmienić swoją nazwę wyświetlaną.
- Wybrać motyw (skin) dla tej tożsamości.
- Usunąć tożsamość, jeśli już jej nie potrzebujesz.

### Usuwanie tożsamości

Gdy usuniesz tożsamość, twoje kontakty zostaną o tym powiadomione. Tożsamość
oraz wszystkie powiązane z nią dane zostaną usunięte z twojego urządzenia.
Tej operacji nie można cofnąć.

---

## 11. Multi-Device

### Korzystanie z Cleony na wielu urządzeniach

Możesz używać tej samej tożsamości jednocześnie na maksymalnie 5
urządzeniach. Jedno urządzenie jest urządzeniem podstawowym (przechowuje
Seed-Phrase), a kolejne urządzenia są z nim powiązywane.

### Powiązanie nowego urządzenia

1. Otwórz ustawienia na swoim urządzeniu podstawowym.
2. Przejdź do "Powiązane urządzenia".
3. Wybierz "Powiąż nowe urządzenie".
4. Zainstaluj Cleonę na nowym urządzeniu i przy pierwszym uruchomieniu
   wybierz "Powiąż z istniejącym urządzeniem".
5. Zeskanuj kod QR parowania wyświetlony na twoim urządzeniu podstawowym
   albo użyj linku parowania.

Powiązane urządzenie otrzymuje certyfikat delegacji od urządzenia
podstawowego. Wiadomości wysyłane z powiązanego urządzenia są
kryptograficznie podpisywane kluczem delegowanym, dzięki czemu kontakty
mogą zweryfikować, że wiadomość rzeczywiście pochodzi od twojej tożsamości.

### Jak to działa

- Urządzenie podstawowe przechowuje twoją Seed-Phrase oraz klucze główne.
- Powiązane urządzenia otrzymują pochodne klucze podpisu oraz certyfikat
  delegacji -- nigdy nie otrzymują samej Seed-Phrase.
- Wszystkie urządzenia współdzielą tę samą tożsamość i kontakty. Wiadomości
  docierają na wszystkie urządzenia.
- Certyfikaty delegacji są automatycznie odnawiane przed wygaśnięciem.

### Zarządzanie urządzeniami

Otwórz ustawienia i przejdź do "Powiązane urządzenia", aby zobaczyć
wszystkie powiązane urządzenia, ich status oraz ostatnią aktywność. W każdej
chwili możesz odwołać powiązane urządzenie, jeśli zostanie zgubione lub
skradzione.

### Awaryjna rotacja kluczy

Jeśli podejrzewasz, że jakieś urządzenie zostało przejęte, możesz uruchomić
awaryjną rotację kluczy. Generowane są wtedy nowe klucze, a rotacja musi
zostać potwierdzona przez większość pozostałych twoich urządzeń. Zapobiega
to sytuacji, w której pojedyncze skradzione urządzenie mogłoby samodzielnie
dokonać rotacji kluczy.

---

## 12. Odzyskiwanie

### Korzystanie z Seed-Phrase

Jeśli zgubisz urządzenie lub konfigurujesz nowe:

1. Zainstaluj Cleonę na nowym urządzeniu.
2. Przy uruchomieniu wybierz "Odzyskaj".
3. Wpisz swoje 24 słowa.
4. Cleona odtworzy twoją tożsamość i automatycznie skontaktuje się z twoimi
   dotychczasowymi kontaktami.
5. Twoje kontakty odpowiedzą, przesyłając dane kontaktowe, członkostwa
   w grupach oraz historie wiadomości.

Odzyskiwanie odbywa się w trzech krokach:
- Najpierw wracają twoje kontakty i grupy.
- Następnie ostatnie 50 wiadomości z każdej rozmowy.
- Na końcu pełna historia wiadomości.

Wystarczy, że jeden z twoich kontaktów jest online, aby odzyskiwanie się
powiodło.

### Guardian Recovery (osoby zaufane)

Możesz wyznaczyć do pięciu zaufanych osób jako "Guardianów" (opiekunów).
Twój klucz odzyskiwania zostaje wtedy podzielony na pięć części, z których
każdy Guardian otrzymuje jedną. Do odzyskania tożsamości wystarczą trzy
z pięciu części.

Oznacza to: nawet jeśli zgubisz swoją Seed-Phrase, trzej Guardianowie mogą
wspólnie odzyskać twoje konto. Żaden pojedynczy Guardian nie ma dostępu do
twoich danych samodzielnie -- zawsze potrzeba przynajmniej trzech.

Jak skonfigurować Guardianów:
1. Otwórz ustawienia.
2. Przejdź do "Bezpieczeństwo".
3. Wybierz "Guardian Recovery".
4. Wybierz pięć zaufanych kontaktów.

### Dlaczego kontakty są twoją kopią zapasową

W tradycyjnych komunikatorach twoje dane leżą na serwerach dostawcy.
W Cleonie nie ma serwera -- ale tę rolę przejmują twoje kontakty. Gdy
wysyłasz wiadomość, wspólne kontakty przechowują jej zaszyfrowaną kopię na
wypadek, gdyby odbiorca był akurat offline. Podczas odzyskiwania twoje
kontakty zwracają ci twoje dane.

Oznacza to: im więcej masz aktywnych kontaktów, tym bardziej niezawodna jest
twoja kopia zapasowa. Jeden kontakt, który regularnie bywa online, wystarczy
do skutecznego odzyskania danych.

---

## 13. Ustawienia

Ustawienia znajdziesz pod ikoną koła zębatego w prawym górnym rogu.

### Powiadomienia i dzwonki

- Wybierz spośród sześciu różnych dzwonków dla połączeń przychodzących.
- Ustaw dźwięk powiadomienia o wiadomości.
- Na urządzeniach z Androidem możesz dodatkowo włączyć lub wyłączyć
  wibracje.

### Motywy (Skins)

Cleona oferuje dziesięć różnych motywów: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold oraz Contrast. Motyw Contrast spełnia
najwyższy poziom dostępności (WCAG AAA) i jest szczególnie dobrze czytelny
przy ograniczonej sprawności wzroku.

Każda tożsamość może mieć własny motyw. Motyw zmieniasz na stronie
szczegółów tożsamości (stuknięcie w aktywną zakładkę tożsamości).

Dodatkowo w ustawieniach w sekcji "Wygląd" możesz przełączać się między
motywem jasnym, ciemnym a systemowym.

### Zmiana języka

Cleona jest dostępna w 33 językach, w tym w językach zapisywanych od prawej
do lewej (np. arabski, hebrajski). Język zmienisz w ustawieniach w sekcji
"Język".

### Limit pamięci

Możesz określić, ile miejsca na urządzeniu może zajmować Cleona (od 100 MB
do 2 GB). Po osiągnięciu limitu starsze media są automatycznie przenoszone
do archiwum lub usuwane -- wiadomości tekstowe zawsze pozostają zachowane.

### Archiwizacja mediów

Jeśli masz w domu pamięć sieciową (NAS) lub udostępniony folder, Cleona może
automatycznie przenosić tam twoje media. Obsługiwane są SMB, SFTP, FTPS
i WebDAV.

Tak działa stopniowe przechowywanie:
- Pierwsze 30 dni: wszystko pozostaje na twoim urządzeniu.
- Po 30 dniach: na urządzeniu zostaje miniaturka, a oryginał trafia do
  archiwum.
- Po 90 dniach: na urządzeniu pozostaje już tylko mała miniaturka.
- Po roku: pozostaje jedynie symbol zastępczy, a oryginał jest bezpiecznie
  przechowywany w archiwum.

W dowolnym momencie możesz stuknąć zarchiwizowane medium, aby je odzyskać --
pod warunkiem, że jesteś połączony(-a) z siecią domową. Szczególnie ważne
media możesz przypiąć, aby nigdy nie zostały przeniesione do archiwum.

### Transkrypcja wiadomości głosowych

Gdy ta opcja jest włączona, twoje wiadomości głosowe są lokalnie na
urządzeniu zamieniane na tekst (za pomocą modelu open source Whisper).
Przepisany tekst jest wysyłany razem z nagraniem do twojego rozmówcy.
Transkrypcja odbywa się w całości na twoim urządzeniu -- żadne dane nie
trafiają do zewnętrznych usług.

### Automatyczne pobieranie

Możesz ustawić, od jakiego rozmiaru media mają być pobierane automatycznie.
Dzięki temu możesz na przykład automatycznie pobierać zdjęcia, a przy dużych
filmach decydować ręcznie.

### Powiązane urządzenia

Zarządzaj swoimi powiązanymi urządzeniami w tej sekcji ustawień. Szczegóły
znajdziesz w rozdziale Multi-Device.

---

## 14. Bezpieczeństwo

### Co oznacza szyfrowanie postkwantowe?

Dzisiejsze szyfrowanie opiera się na problemach matematycznych, które są
niezwykle trudne do rozwiązania dla zwykłych komputerów. Komputery kwantowe
mogłyby w przyszłości szybko rozwiązać niektóre z tych problemów.
Szyfrowanie postkwantowe wykorzystuje dodatkowe metody, które są odporne
również na komputery kwantowe.

Cleona łączy oba podejścia: klasyczne szyfrowanie zapewniające niezawodność
oraz metody postkwantowe zapewniające odporność na przyszłe zagrożenia.
Dzięki temu jesteś chroniony(-a) jednocześnie przed dzisiejszymi
i przyszłymi zagrożeniami.

Dla każdej pojedynczej wiadomości generowany jest osobny klucz. Nawet gdyby
atakującemu udało się złamać klucz jednej wiadomości, nie mógłby dzięki
temu odczytać żadnej innej wiadomości.

### Dlaczego brak serwera jest bezpieczniejszy

W tradycyjnych komunikatorach twoje wiadomości przechodzą przez serwery
dostawcy. Nawet jeśli są tam zaszyfrowane: dostawca ma dostęp do metadanych
(kto, kiedy, z kim komunikuje się, jak często, skąd) i w pewnych
okolicznościach musi je udostępnić na mocy nakazu sądowego.

W Cleonie nie ma takiego centralnego punktu. Twoje wiadomości podróżują
bezpośrednio z urządzenia do urządzenia. Nie istnieje miejsce, w którym
zbiegałyby się wszystkie metadane. Nikt nie jest w stanie odtworzyć twojego
zachowania komunikacyjnego na podstawie pojedynczego punktu danych.

### Co się dzieje, gdy jesteś offline?

Gdy wysyłasz wiadomość, a odbiorca jest offline:

1. Cleona najpierw próbuje dostarczyć wiadomość bezpośrednio.
2. Jeśli się to nie uda, wiadomość jest przekazywana przez wspólne kontakty.
3. Jednocześnie wiadomość jest dzielona na zaszyfrowane fragmenty
   i rozpraszana po wielu węzłach sieci (podobnie jak puzzle złożone z 10
   elementów, z których wystarczy 7, aby odtworzyć obraz).
4. Wiadomość jest przechowywana przez maksymalnie 7 dni.

Gdy tylko odbiorca ponownie znajdzie się online, wiadomości zostają
dostarczone. Otrzymujesz potwierdzenie, gdy twoja wiadomość dotrze do celu.

### Ochrona przed cenzurą

Jeśli twoja sieć blokuje standardową metodę połączenia (UDP), Cleona
automatycznie przełącza się na alternatywną transmisję (TLS), którą trudniej
wykryć i zablokować. Dzieje się to w sposób przezroczysty -- nie musisz
niczego konfigurować.

### Bezpieczne przechowywanie kluczy

Na obsługiwanych platformach Cleona przechowuje twoje klucze szyfrujące
w bezpiecznym magazynie kluczy systemu operacyjnego (Android Keystore, iOS
Keychain, macOS Keychain). Tam, gdzie to dostępne, zapewnia to sprzętowo
wspieraną ochronę twoich kluczy.

### Szyfrowanie bazy danych

Wszystkie twoje wiadomości, kontakty i ustawienia są przechowywane na
urządzeniu w formie zaszyfrowanej. Nawet gdyby ktoś uzyskał dostęp do
twojego systemu plików, bez twojego klucza kryptograficznego nie mógłby
niczego odczytać. Ten klucz jest wyprowadzany z twojej tożsamości i istnieje
wyłącznie na twoim urządzeniu.

### Sieć zamknięta

Cleona działa jako sieć zamknięta. Każdy pakiet sieciowy jest uwierzytelniany,
dzięki czemu tylko legalne urządzenia z Cleoną mogą uczestniczyć w sieci.
Zapobiega to wprowadzaniu sfałszowanych wiadomości przez osoby z zewnątrz
oraz podsłuchiwaniu ruchu sieciowego.

---

## 15. Aktualizacje oprogramowania

### Jak otrzymywać aktualizacje?

Cleonę można aktualizować na kilka sposobów. Celem jest to, abyś mógł
(mogła) otrzymywać aktualizacje nawet wtedy, gdy poszczególne kanały
dystrybucji zawiodą lub zostaną zablokowane:

1. **App Store / Play Store:** jeśli zainstalowałeś(-aś) Cleonę przez sklep
   z aplikacjami, aktualizacje otrzymujesz jak zwykle przez sklep.
2. **GitHub Releases:** na stronie GitHub projektu znajdziesz podpisane
   pakiety instalacyjne dla wszystkich platform.
3. **Aktualizacje w sieci (In-Network):** jeśli inny użytkownik Cleony
   w twojej sieci ma już najnowszą wersję, Cleona może pobrać aktualizację
   bezpośrednio przez sieć P2P -- bez zewnętrznego serwera. Nowa wersja jest
   dzielona na fragmenty z korekcją błędów i rozpraszana po wielu węzłach.
   Twoje urządzenie zbiera wystarczającą liczbę fragmentów i składa
   aktualizację w całość. Autentyczność jest weryfikowana za pomocą podpisu
   Ed25519 twórcy.
4. **Linki zaproszeń:** możesz tworzyć linki zaproszeń, które zawierają
   wszystko, czego potrzebuje nowy użytkownik, aby zainstalować Cleonę
   i połączyć się z siecią.
5. **Transfer fizyczny:** w środowiskach bez internetu możesz przekazać
   Cleonę innym za pomocą pamięci USB lub w sieci lokalnej.

### Powiadomienie o aktualizacji

Gdy dostępna jest nowa aktualizacja, Cleona wyświetla powiadomienie na
ekranie głównym. Jeśli aktualizacja jest dostępna również przez sieć
(aktualizacja In-Network), masz możliwość pobrania jej bezpośrednio z sieci.

### Dystrybucja plików binarnych

Domyślnie twoje urządzenie pomaga przekazywać aktualizacje innym
użytkownikom sieci. Jeśli tego nie chcesz, możesz wyłączyć tę funkcję
w ustawieniach w sekcji "Sieć". Wykorzystanie pamięci na fragmenty
aktualizacji jest ograniczone (5 MB na urządzeniach mobilnych, 20 MB na
komputerach) i jest regularnie porządkowane.

### Weryfikacja podpisu

Każda aktualizacja jest podpisywana kryptograficznie. Cleona automatycznie
sprawdza podpis przed zainstalowaniem aktualizacji. Dzięki temu akceptowane
są wyłącznie aktualizacje od oficjalnego twórcy -- nawet jeśli aktualizacja
została pobrana przez sieć P2P.

---

## 16. Najczęściej zadawane pytania

### "Czy mogę korzystać z Cleony bez internetu?"

Nie, Cleona potrzebuje połączenia sieciowego, aby wysyłać i odbierać
wiadomości. Nie musisz jednak być online w tym samym czasie co twój
rozmówca: wiadomości wysłane, gdy odbiorca jest offline, są przechowywane
tymczasowo i dostarczane automatycznie, gdy obie strony znów będą
połączone. W sieci lokalnej (np. w tym samym WLAN) możecie komunikować się
ze sobą nawet zupełnie bez dostępu do internetu.

### "Co jeśli zgubię swoją Seed-Phrase?"

Jeśli skonfigurowałeś(-aś) Guardianów, trzy z pięciu zaufanych osób mogą
wspólnie odzyskać twój dostęp. Bez Guardianów i bez Seed-Phrase niestety nie
ma sposobu na odzyskanie tożsamości. Dlatego tak ważne jest bezpieczne
przechowywanie tych 24 słów.

### "Czy ktoś może odczytać moje wiadomości?"

Nie. Każda wiadomość jest szyfrowana jednorazowym kluczem, który obowiązuje
tylko dla tej jednej wiadomości. Tylko ty i twój rozmówca możecie
odszyfrować wiadomość. Nie istnieje centralny serwer, klucz uniwersalny ani
dostęp dla twórcy aplikacji. Nawet jeśli jakieś urządzenie po drodze
przekazuje wiadomość dalej, widzi jedynie zaszyfrowaną kaszę danych.

### "Dlaczego nie potrzebuję numeru telefonu?"

Ponieważ twoja tożsamość jest czysto kryptograficzna. Zamiast numeru
telefonu czy adresu e-mail powiązanego z twoim prawdziwym imieniem
i nazwiskiem, identyfikuje cię para kluczy wygenerowana na twoim
urządzeniu. Kontakty dodajesz przez kod QR, NFC lub link -- nie przez
książkę telefoniczną. Oznacza to większą prywatność, ponieważ twoje konto
w komunikatorze nie jest powiązane z twoją rzeczywistą tożsamością.

### "Jak znajdę ludzi na Cleonie?"

Cleona celowo nie posiada wyszukiwania kontaktów po numerze telefonu czy
imieniu -- byłby to problem z prywatnością. Zamiast tego wymieniasz dane
kontaktowe bezpośrednio: przez kod QR, NFC, link cleona:// lub na kanałach
publicznych. To trochę jak wymiana wizytówek zamiast szukania w książce
telefonicznej.

### "Czy Cleona działa też za granicą?"

Tak. Dopóki masz połączenie z internetem, Cleona działa na całym świecie.
Ponieważ nie ma centralnego serwera, usługa nie może zostać zablokowana dla
konkretnych krajów. Cleona posiada również mechanizm zapasowy chroniący
przed cenzurą: gdy standardowe połączenie (UDP) jest blokowane, Cleona
automatycznie przełącza się na alternatywną transmisję (TLS), którą trudniej
wykryć i zablokować.

### "Czy Cleona jest bezpłatna?"

Tak. Z Cleony można korzystać bezpłatnie i bez reklam. Ponieważ nie ma
centralnego serwera, nie powstają też żadne koszty jego utrzymania.
W aplikacji, w sekcji "Wsparcie", znajdziesz możliwość dobrowolnego wsparcia
finansowego rozwoju projektu.

### "Przy mojej wiadomości widnieje symbol zegara -- co to oznacza?"

Oznacza to, że wiadomość nie została jeszcze dostarczona. Twój rozmówca
prawdopodobnie jest właśnie offline. Gdy tylko wiadomość zostanie
dostarczona, symbol się zmieni. Wiadomości są przechowywane do dostarczenia
przez maksymalnie 7 dni.

### "Czy mogę przenieść się z WhatsAppa na Cleonę?"

Tak, ale nie możesz przenieść swoich czatów z WhatsAppa. Cleona i WhatsApp
to zasadniczo różne systemy. Musisz dodać swoje kontakty w Cleonie
pojedynczo. Najłatwiej zrobić to, publikując swój link cleona:// w grupie na
WhatsAppie i prosząc innych, aby dodali cię tam do kontaktów.

### "Czy mogę korzystać z Cleony na kilku urządzeniach jednocześnie?"

Tak. Możesz powiązać do 5 urządzeń z tą samą tożsamością. Jedno urządzenie
jest podstawowe (przechowuje Seed-Phrase), a kolejne są powiązywane poprzez
bezpieczny proces parowania. Wszystkie urządzenia współdzielą tę samą
tożsamość, kontakty i rozmowy. Szczegóły znajdziesz w rozdziale
Multi-Device.

### "Jak otrzymać aktualizacje, gdy App Store jest zablokowany?"

Cleona może pobierać aktualizacje bezpośrednio przez sieć P2P, bez potrzeby
korzystania z App Store, strony internetowej czy serwera pobierania. Jeśli
inny użytkownik sieci ma najnowszą wersję, twoje urządzenie może pobrać
stamtąd aktualizację. Autentyczność jest weryfikowana za pomocą cyfrowego
podpisu twórcy. Alternatywnie kontakt może przekazać ci aplikację przez link
zaproszenia lub pamięć USB. Więcej informacji w rozdziale "Aktualizacje
oprogramowania".

---

## Pomoc i kontakt

Jeśli masz pytania lub napotkasz problem, aktualne informacje znajdziesz na
stronie Cleona oraz na GitHub. Ponieważ Cleona jest projektem
zdecentralizowanym, nie ma klasycznego wsparcia klienta -- jest za to
aktywna społeczność, która chętnie pomoże.

---

*Ten podręcznik opisuje Cleona Chat w wersji 3.1.125. Poszczególne funkcje
mogą się zmieniać lub rozszerzać w nowszych wersjach.*
