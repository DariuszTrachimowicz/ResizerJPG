# Resizer JPG | Digital Xperts

Pomoc: kliknij ikone **znaku zapytania w kolku** w naglowku programu. Otwiera ten plik README w Notatniku, lokalnie i bez internetu. Link **GPLv3 - bez gwarancji** w stopce otwiera pelny tekst LICENSE. Mozesz tez otworzyc oba pliki bezposrednio z folderu programu.

Wersja **2.2.0**. Tworca: **Dariusz Trachimowicz**. [Digital Xperts](https://d-x.pl/).

Przenosny program Windows do przygotowywania zdjec JPG/JPEG. Natywny interfejs WPF, bez dodatkowych bibliotek. Przetwarzanie jest lokalne; internet jest potrzebny tylko do aktualizacji.

[Najnowsza paczka](https://github.com/DariuszTrachimowicz/ResizerJPG/releases/latest) | [Repozytorium](https://github.com/DariuszTrachimowicz/ResizerJPG)

## Uruchomienie

Rozpakuj **cala paczke ZIP** do jednego folderu. Kliknij `Uruchom Resizer JPG.vbs` lub utworz skrot przez `Utworz skrot z ikona.vbs`. Po przeniesieniu programu utworz skrot ponownie. Uruchamiacz pracuje z ukryta konsola.

Wymagania: Windows 10/11, Windows PowerShell 5.1, WPF i Windows Script Host. Polityka organizacji blokujaca VBS lub PowerShell moze zablokowac uruchamiacz.

## Makalu Sklep

Domyslny profil **Makalu Sklep** przygotowuje zdjecia do sklepu online:

- pion **1920 x 2880 px**, poziom **2880 x 1920 px**,
- automatyczna orientacja z uwzglednieniem EXIF,
- zachowanie calego zdjecia z bialym tlem,
- jakosc JPG **85** i **72 DPI** w obu osiach.

Zmiana parametrow przelacza profil na wlasny. Wybor `Makalu Sklep` przywraca domyslne ustawienia. Formaty 2:3 / 3:2 profilu Makalu sa niezalezne od dodatkowych trybow 9:16 i 16:9.

## Praca ze zdjeciami

Po lewej jest kolejka konkretnych zdjec, grupowana wedlug folderow zrodlowych. Grupy mozna zwijac; kazde zdjecie ma miniature, nazwe, informacje o wymiarach i checkbox eksportu. W centrum jest podglad z paskiem miniatur (filmstrip), a po prawej ustawienia eksportu z domyslnym profilem Makalu Sklep. Staly dolny pasek zawiera cel zapisu, przykladowa nazwe pliku, licznik zaznaczonych zdjec, eksport, status, dziennik i otwieranie wyniku. Stopka z autorem i wersja pozostaje widoczna.

1. Dodaj folder lub pliki JPG/JPEG do kolejki. Mozesz tez przeciagnac kilka plikow/folderow na okno lub skrot. Skanowanie i tworzenie miniatur odbywa sie w tle; opcja `Podfoldery` jest domyslnie wlaczona.
2. Kliknij zdjecie w kolejce lub filmstripie, aby je podejrzec. Strzalki przechodza po zdjeciach calej kolejki, nie tylko jednego folderu. `Oryginal / Wynik` przelacza widok przed i po przetwarzaniu.
3. Checkbox przy zdjeciu decyduje tylko o jego eksporcie. Wybor zdjecia do podgladu jest niezalezny: mozna podejrzec zdjecie odznaczone, a jego klikniecie nie zaznacza go do eksportu. Checkbox nad kolejka zaznacza lub odznacza wszystkie zdjecia. Usuniecie zdjecia z kolejki i `Wyczysc` nie usuwaja plikow z dysku.
4. W prawym panelu ustaw profil, orientacje, dopasowanie i jakosc JPG. DPI, presety oraz szerokosc/wysokosc sa w sekcji `Zaawansowane`.
5. Kliknij `Eksportuj N zdjec`, aby zapisac tylko zaznaczone pozycje. Eksport pracuje w tle. `Zatrzymaj` zglasza kooperacyjne zatrzymanie skanowania lub eksportu; nie przerywa zapisu biezacego zdjecia. Zamkniecie okna podczas tej pracy rowniez czeka na jej bezpieczne zakonczenie. Dziennik zawiera szczegoly i bledy.
6. `Otworz wynik` otwiera folder wynikowy, a przy kilku folderach pozwala wybrac jeden z menu.

### Przeciaganie folderow i plikow

**Cale glowne okno przyjmuje upuszczane foldery i pliki JPG/JPEG. Nie ma osobnego pola do wrzucania plikow.** Najpierw zamknij nakladki `Aktualizacje` lub `Dziennik` przyciskiem X albo klawiszem `Esc`. Podczas przeciagania poprawnych plikow lub folderow obszar podgladu podswietla sie na niebiesko. Eksport i pobieranie aktualizacji blokuja przyjmowanie nowych zrodel; poczekaj na koniec tej pracy.

Po skanowaniu foldery tworza zwijane grupy w lewej kolejce, a w nich widac poszczegolne zdjecia z checkboxami wyboru do eksportu. Samo wskazanie miniatury zmienia podglad, nie checkbox.

Jakosc JPG 85 jest ustawieniem domyslnym. Nizsza jakosc zwykle zmniejsza rozmiar pliku kosztem szczegolow, wyzsza zwykle zwieksza rozmiar. Porownaj `Oryginal` i `Wynik` przed eksportem.

### Podglad i zoom

`Wynik` pokazuje finalny JPG wygenerowany do pliku tymczasowego przez ten sam silnik co eksport, w dokladnych wymiarach oraz z wybrana orientacja, dopasowaniem, jakoscia JPG i DPI. Obraz nie jest dodatkowo zmniejszany przed wyswietleniem; plik tymczasowy jest usuwany po odczycie. Nie jest to odczyt wczesniej wyeksportowanego pliku, lecz wynik dla biezacych ustawien.

`Oryginal` uwzglednia EXIF i jest pomniejszany do maksymalnie **2048 px na dluzszym boku**, bez powiekszania mniejszych zdjec. Wyswietlane wymiary oryginalu opisuja zdjecie zrodlowe, nie pomniejszony obraz podgladu.

Zoom **100% oznacza dopasowanie do obszaru podgladu**, nie skale pikselowa 1:1. Zakres **100-400%** powieksza widok wzgledem tego dopasowania. Dostepne sa suwak, przyciski powiekszania/pomniejszania, `Ctrl` + kolko myszy i przycisk dopasowania; wybor innego zdjecia przywraca 100%.

Generowanie podgladu odbywa sie w tle. Zmiana jakosci suwakiem zleca odswiezenie juz podczas przesuwania, z opoznieniem 120 ms laczacym szybkie zmiany. Zmiany profilu, orientacji, presetu i dopasowania rowniez odswiezaja podglad; pola liczbowe zatwierdzaja zmiany po opuszczeniu pola. Nieaktualne wyniki podgladu sa pomijane.

Domyslnie zdjecia trafiaja do `resize` obok zrodel. `produkt.jpg` staje sie `produkt_R.jpg`. Przy kolizji powstaje `produkt_R_1.jpg`. Oryginaly pozostaja zachowane.

Wspolny folder wybiera ikona folderu przy `Cel zapisu`; ikona przywracania wraca do domyslnego zapisu. Struktura podfolderow jest zachowywana wzgledem folderu zrodlowego. Skanowanie pomija podfoldery `resize`, wybrany wspolny folder wynikowy i dowiazania katalogowe; nakladajace sie zrodla nie duplikuja zdjec w kolejce. Jawnie dodany plik z `resize` moze trafic do kolejki.

## Aktualizacje GitHub

Panel `Aktualizacje` sprawdza stabilne wydania `DariuszTrachimowicz/ResizerJPG`. Domyslnie sprawdzanie dziala przy uruchomieniu, w tle; mozna je wylaczyc.

Przy nowszej wersji wybierz `Pobierz i zainstaluj`. Program pobiera ZIP z GitHub Releases, sprawdza SHA-256 paczki, manifest, pliki i wersje, zamyka sie i uruchamia po instalacji. Logowanie do GitHuba nie jest wymagane.

Instalator zmienia tylko pliki programu. Kopia trafia do `_updates/backup-*`; przy bledzie kopiowania przywracane sa poprzednie pliki. Stan instalacji jest w `_updates/status.json`. Zdjecia i pliki uzytkownika pozostaja zachowane.

Ustawienia oraz pobrane paczki sa w `%LOCALAPPDATA%\DigitalXperts\ResizerJPG`. Program nie wysyla zdjec na serwer. Zapytania o aktualizacje trafiaja do GitHuba.

## Polecenia

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ResizerJPG.ps1 -InputFolder "C:\Zdjecia" -MakaluSklep
powershell -NoProfile -ExecutionPolicy Bypass -File .\ResizerJPG.ps1 -InputFolder "C:\Zdjecia\produkt.jpg" -MakaluSklep
```

Alias `-OnlineStore` nadal dziala. Wlasne ustawienia: `-AspectRatio "9:16" -Width 1080 -Height 1920 -Mode Pad -Quality 85 -Dpi 72`.

## Rozwiazywanie problemow

- Brak reakcji na upuszczenie: zamknij nakladki, poczekaj na zakonczenie eksportu lub pobierania i sprawdz, czy przeciagasz folder albo JPG/JPEG. Uzyj tez `Dodaj folder` lub `Dodaj pliki`.
- Windows moze blokowac przeciaganie miedzy Eksploratorem a programem uruchomionym z innymi uprawnieniami. Uruchom oba normalnie, na tym samym poziomie uprawnien; nie uruchamiaj Resizera jako administrator tylko po to, aby dodac zdjecia.
- Brak zdjec po skanowaniu: sprawdz rozszerzenia i opcje `Podfoldery`. Foldery wynikowe sa pomijane zgodnie z opisem powyzej.
- Blad zapisu: sprawdz dostep do folderu docelowego, wolne miejsce i szczegoly w `Dziennik`. Oryginaly nie sa nadpisywane.
- Pomoc lub licencja nie otwiera sie: sprawdz komunikat statusu i obecnosc README.md oraz LICENSE w folderze programu. Rozpakuj kompletna paczke; gdy Notatnik jest niedostepny, odczytaj te pliki innym edytorem tekstu.

## Licencja GPLv3

Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts.

Od wersji **2.2.0** program jest wolnym oprogramowaniem na licencji **GNU General Public License, wylacznie wersja 3** (**SPDX: GPL-3.0-only**). Nie oznacza to zmiany licencji starszych wydan wstecz. Mozesz uzywac, kopiowac, modyfikowac i rozpowszechniac program zgodnie z warunkami GPLv3, w tym obowiazkami dotyczacymi udostepnienia odpowiedniego kodu zrodlowego przy rozpowszechnianiu.

Program jest udostepniany **BEZ JAKIEJKOLWIEK GWARANCJI**, w tym dorozumianej gwarancji przydatnosci handlowej lub do okreslonego celu. Pelne warunki zawiera dolaczony [LICENSE](LICENSE), dostepny takze przez link w stopce programu.

[Pelny kod zrodlowy programu i historia wersji](https://github.com/DariuszTrachimowicz/ResizerJPG). Skladniki zewnetrzne zachowuja swoje licencje i oznaczenia w [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt).

## Wydawanie

`AppInfo.json` jest zrodlem wersji i adresu repozytorium. `Build-Portable.ps1` buduje folder przenosny, ZIP, manifest i plik SHA-256. Tag `vX.Y.Z` zgodny z metadanymi uruchamia testy i workflow wydania.

Testy w `tests`: `Test-Resizer.ps1`, `Test-Queue.ps1`, `Test-UIModels.ps1`, `Test-WindowLayout.ps1`, `Test-Launcher.ps1`, `Test-Updates.ps1`, `Test-PortableCompatibility.ps1`, `Test-Icons.ps1` i `Test-HelpLicense.ps1`. Lokalny test GUI: `powershell -Sta -NoProfile -File .\tests\Test-WpfUI.ps1`. CI sprawdza silnik, kolejke, modele, strukture ukladu, ikony, pomoc/licencje, paczke i instalator; nie zastepuje recznego testu interfejsu ani fizycznego przeciagania z Eksploratora.

Logo pochodzi z projektu Digital Xperts, zgodnie z poleceniem wlasciciela. Ikona programu jest wielorozmiarowa wersja logo. Ikony kontrolek: Lucide (ISC/MIT); licencje w `THIRD-PARTY-NOTICES.txt`.
