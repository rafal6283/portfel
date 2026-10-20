# Portfel

Prywatna aplikacja na Androida i iPhone'a (Flutter) do śledzenia zysków i strat z walut, złota, srebra i lokat. Dane są tylko na telefonie.

## Co potrafi

- **Transakcje** kupna i sprzedaży z dowolną datą wstecz – 11 walut, złoto i srebro (w gramach lub uncjach), prowizje, notatki, znacznik „do sprawdzenia”.
- **Wynik metodą FIFO**: zrealizowany ze sprzedaży i niezrealizowany po bieżącym kursie, osobno dla każdego aktywa.
- **Kursy na żywo**: średnie NBP (tabela A), cena złota NBP za 1 g, srebro ze spotu USD (gold-api.com) × kurs NBP. Odświeżanie przy starcie i przeciągnięciem w dół. Każdy kurs można ustawić ręcznie.
- **Kurs NBP z dnia transakcji** podpowiadany w formularzu (przycisk „Użyj”).
- **Lokaty**: trwające z odsetkami narosłymi do dziś (po 19% podatku), zakończone z wynikiem z wypłaty albo z odsetek i podatku, lokaty bez wyniku osobno.
- **Gotówka**: złotówki i waluty (sejf, portfel, konto), wyceniane po kursie NBP.
- **Nieruchomości**: cena zakupu z kosztami, szacowana wartość dziś albo sprzedaż, dochód z najmu – zysk/strata i wynik r/r.
- **Kopia zapasowa** w pliku `.json` (import scala wpisy po id) – też do przeniesienia danych między telefonami.
- **Logowanie** (jak w Teczce Zdrowia): PIN, wzór, blokada ekranu telefonu, opcjonalnie odcisk palca / twarz; PIN sprawdzany bez zatwierdzania, przerwa po 5 błędnych próbach, zapomniany kod – odblokowanie blokadą telefonu. Kod zapisany tylko jako solony skrót SHA-256.

## Instalacja

Każdy push na `main` buduje aplikację w GitHub Actions i publikuje ją w zakładce **Releases**:

- **Android** – `portfel.apk`: pobierz na telefonie i zainstaluj. Kolejne wersje instalują się jako aktualizacja (stały klucz), dane zostają.
- **iPhone** – `portfel.ipa` (niepodpisany): zainstaluj z komputera przez [Sideloadly](https://sideloadly.io) lub AltStore swoim Apple ID. Przy darmowym koncie aplikację trzeba odświeżać co 7 dni (dane zostają).

Pierwsze uruchomienie: **Ustawienia → Importuj kopię** i wskaż plik `portfel-dane.json`.

## Struktura

- `lib/models.dart` – transakcje, lokaty, kursy (JSON zachowuje nieznane pola)
- `lib/calc.dart` – FIFO i wynik lokat (czysty Dart, testy w `test/calc_test.dart`)
- `lib/rates.dart` – pobieranie kursów NBP i srebra
- `lib/store.dart` – stan aplikacji, zapis do pliku, import/eksport
- `lib/ui/` – ekrany

Plik z danymi osobistymi (`portfel-dane*.json`) jest w `.gitignore` i nie trafia do repo.

Wycena nie uwzględnia spreadu kantoru ani marży monet. Aplikacja nie jest rozliczeniem podatkowym.
