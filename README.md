# Resizer JPG | Digital Xperts

Wersja **2.0.0**. Tworca: **Dariusz Trachimowicz**. [Digital Xperts](https://d-x.pl/).

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

1. Dodaj folder lub pliki JPG w panelu zrodel. Mozesz tez przeciagnac kilka plikow/folderow na okno lub skrot.
2. Wybierz zrodlo. Strzalki pod podgladem przegladaja zdjecia folderu; `Oryginal / Wynik` pokazuje obraz przed i po dopasowaniu.
3. W panelu eksportu ustaw profil, orientacje, dopasowanie, jakosc i DPI. Presety oraz szerokosc/wysokosc sa pod `Rozmiar niestandardowy`.
4. Kliknij `Eksportuj JPG`. Zatrzymanie konczy prace po biezacym zdjeciu. Dziennik zawiera szczegoly i bledy.
5. `Otworz wynik` otwiera foldery wynikowe.

Podglad wyniku jest pomniejszony do maksymalnie 1000 px, nie jest podgladem 1:1 finalnego JPG. Suwak odswieza go po puszczeniu myszy; pole rozmiaru po zatwierdzeniu.

Domyslnie zdjecia trafiaja do `resize` obok zrodel. `produkt.jpg` staje sie `produkt_R.jpg`. Przy kolizji powstaje `produkt_R_1.jpg`. Oryginaly pozostaja zachowane.

Wspolny folder wybiera ikona folderu w wierszu `Zapis`; ikona przywracania wraca do domyslnego zapisu. Podfoldery sa opcjonalne, ich struktura jest zachowywana. Foldery `resize` i nakladajace sie zrodla nie sa ponownie przetwarzane.

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

## Wydawanie

`AppInfo.json` jest zrodlem wersji i adresu repozytorium. `Build-Portable.ps1` buduje folder przenosny, ZIP, manifest i plik SHA-256. Tag `vX.Y.Z` zgodny z metadanymi uruchamia testy i workflow wydania.

Testy: `powershell -Sta -NoProfile -File .\tests\Test-Resizer.ps1 -Ui`, `Test-Launcher.ps1` i `Test-Updates.ps1`. GUI jest sprawdzane lokalnie przez zdarzenia kontrolek i rendery w dwoch rozmiarach. CI sprawdza silnik, paczke i instalator; nie zastepuje recznego testu interfejsu.

Logo pochodzi z projektu Digital Xperts, zgodnie z poleceniem wlasciciela. Ikona programu jest wielorozmiarowa wersja logo. Ikony kontrolek: Lucide (ISC/MIT); licencje w `THIRD-PARTY-NOTICES.txt`.
