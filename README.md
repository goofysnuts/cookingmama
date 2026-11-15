# Kochbuch (iOS)

iPhone-App für das selbst gehostete **Kochbuch** auf dem NAS (`Y:\cookbook`). Der Docker-Container
liefert nur noch die API (`/api/v1`), die Oberfläche ist diese SwiftUI-App. iOS 17+.

## Funktionen

- **Start:** Begrüßung, Vorschläge passend zur Tageszeit, Ernährung und Vorrat („Sofort kochbar“ oder
  „Auch mit fehlenden Zutaten“), Favoriten für die aktuelle Mahlzeit, Hinweise auf Rezepte mit langer
  Stehzeit, „Zuletzt gekocht“
- **Rezepte:** Suche (Titel, Zutat, #tag), Filter (Art, Ernährung, Mahlzeit, Favoriten), Zufallsrezept
- **Rezeptdetail:** Fotos, Portionsrechner, Zutaten mit Vorratsstatus und Alternativen, abhakbare Schritte
  mit Zutatenmengen, Backangaben, Nährwerte, Bewertungen/Kommentare, Favorit, „Gekocht/Gebacken“ bucht den
  Vorrat ab (Alternative wählbar), fehlende Zutaten per Telegram
- **Stehzeiten:** Wird ein Schritt abgehakt, auf den eine Stehzeit folgt, plant die App eine lokale
  Benachrichtigung (funktioniert auch ohne kostenpflichtigen Apple-Account). Telegram-Hinweise kommen
  wie bisher vom Server.
- **Rezept-Editor:** Koch-/Backrezept, Mahlzeiten, Tags, Fotos (Mediathek/Kamera), Zutaten mit Einheit,
  Einstufung, Hinweis, Alternative und Vorteig, Schritte mit Zutatenmengen, Stehzeit-Schritte,
  Backschritt, Stehzeit-Planung, Nährwerte
- **Automatisch:** Fotos/PDFs eines Rezepts hochladen → Claude erstellt es („Erstelle meine Kochbuch-Rezepte“)
- **Vorrat:** Haushalt wechseln, Bestand/Mindestbestand/Nachkaufmenge/Kauf-Einheit, Foto, schnelles
  Auffüllen per Wischen, knappe Zutaten auf die Einkaufsliste
- **Einkaufsliste:** Einträge mit Vorschlägen, Abhaken bucht in den Vorrat, Telegram-Versand, Teilen
- **Mehr:** Benachrichtigungen (inkl. Haushalts-Einladungen), Favoriten, Konto (Ernährung, Essenszeiten,
  Telegram, Einkaufserinnerung, Passwort), Haushalte (einladen, umbenennen, verlassen)
- **Admin:** Kontoanfragen freigeben, Nutzer anlegen/Rollen/Passwort/Löschen, alle Haushalte verwalten,
  Telegram-Bot-Token, Datenbank-Backup

## Bauen ohne Mac (GitHub Actions + Sideloadly)

1. Auf GitHub ein **öffentliches** Repository anlegen (z. B. `goofysnuts/kochbuch-ios`), damit die
   macOS-Builds kostenlos sind, und diesen Ordner hochladen.
2. Unter **Actions → Build unsigned IPA** läuft der Build bei jedem Push. XcodeGen erzeugt dabei aus
   `project.yml` das Xcode-Projekt.
3. Die fertige `Kochbuch-…-unsigned.ipa` unter **Artifacts** herunterladen und mit **Sideloadly** und
   deiner Apple-ID aufs iPhone installieren. Mit kostenloser Apple-ID läuft die App 7 Tage und muss dann
   neu signiert werden (Sideloadly kann das automatisch).

## Erste Schritte

Serveradresse eingeben (`http://192.168.30.145:5000`), „Verbindung prüfen“, mit dem bisherigen
Kochbuch-Konto anmelden. Unterwegs funktioniert die App, wenn das iPhone per VPN (z. B. Tailscale) im
Heimnetz ist.

## Projektstruktur

```
project.yml           XcodeGen-Projektdefinition
Kochbuch/App          App-Einstieg, Tabs
Kochbuch/Core         API-Client, Modelle, Keychain, App-Zustand, lokale Benachrichtigungen
Kochbuch/Views        Start, Rezepte, Detail, Editor, Vorrat, Einkauf, Automatisch, Mehr, Admin
```
