# Zmiany

## 2.2.0 - 2026-10-01

- Pomoc pod ikona znaku zapytania w naglowku: lokalny README otwierany w Notatniku bez blokowania interfejsu. Instrukcje importu, przeciagania, eksportu, podgladu i rozwiazywania problemow.
- Link GPLv3 z informacja o braku gwarancji w stopce; pelny LICENSE otwierany lokalnie. Od tej wersji program na licencji GPL-3.0-only, z oznaczeniami praw autorskich i dostepem do kodu zrodlowego.
- Poprawiona konwersja niezaleznych sciezek SVG Lucide: kompletne X zamykania paneli oraz poprawne ikony pobierania i obrazu. Zachowane zamykanie kliknieciem/Esc i przywracanie fokusu.

## 2.1.0 - 2026-10-01

- Uklad z wybranej makiety: kolejka zdjec po lewej, centralny podglad i filmstrip, ustawienia Makalu Sklep po prawej oraz staly dolny pasek i stopka.
- Konkretne zdjecia zamiast listy zrodel: zwijane grupy folderow, miniatury, checkboxy eksportu, zaznaczanie wszystkich i usuwanie pozycji bez usuwania plikow z dysku.
- Wybor zdjecia do podgladu niezalezny od checkboxa eksportu; filmstrip i strzalki nawigacji obejmuja cala kolejke.
- Podglad Wynik z finalnego JPG generowanego tym samym silnikiem co eksport, w dokladnych wymiarach, orientacji, dopasowaniu, jakosci i DPI. Oryginal uwzglednia EXIF i ma maksymalnie 2048 px na dluzszym boku.
- Zoom 100-400% wzgledem dopasowania do obszaru podgladu: 100% to dopasowanie, nie 1:1. Suwak, przyciski, Ctrl + kolko myszy i przywracanie dopasowania.
- Skanowanie, miniatury, podglad i eksport w tle. Suwak jakosci odswieza podglad podczas zmiany z opoznieniem 120 ms; nieaktualne wyniki sa pomijane.
- Kooperacyjne zatrzymanie skanowania i eksportu; biezace zdjecie konczy przetwarzanie przed zatrzymaniem. Zamkniecie okna podczas pracy czeka na jej zakonczenie.
- Eksport tylko zaznaczonych zdjec, liczniki, postep i dziennik; wybor folderu wynikowego z menu przy wielu folderach. Zachowane ustawienia Makalu, ochrona oryginalow i aktualizacje GitHub.
- Dopasowanie podgladu po zmniejszeniu okna; obsluga fokusu podgladu i blednych pol, kopiowalne sciezki, trwaly stan zatrzymywania oraz ponowne dodawanie usunietych pozycji kolejki.

## 2.0.0 - 2026-10-01

- Nowy interfejs WPF i domyslny profil Makalu Sklep.
- Logo Digital Xperts, ikona programu, link d-x.pl i wersja w stopce.
- Podglad oryginalu/wyniku i nawigacja po zdjeciach w folderze.
- GitHub Releases: sprawdzanie w tle, pobranie i instalacja aktualizacji.
- SHA-256 paczki i plikow, kontrola ZIP, kopia poprzedniej wersji i przywracanie przy bledzie kopiowania.
- Zachowane 1920 x 2880 / 2880 x 1920, JPG 85, 72 DPI, folder resize i suffix _R.
