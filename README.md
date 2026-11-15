# Kochbuch (iOS)

iPhone-App für das selbst gehostete **Kochbuch** auf dem NAS (`Y:\cookbook`). Der Docker-Container
liefert nur noch die API (`/api/v1`), die Oberfläche ist diese SwiftUI-App. iOS 17+.

## Funktionen

- **Start:** Begrüßung, Vorschläge passend zur Tageszeit, Ernährung und Vorrat („Sofort kochbar“ oder
  „Auch mit fehlenden Zutaten“), Favoriten für die aktuelle Mahlzeit, Hinweise auf Rezepte mit langer
  Stehzeit, „Zuletzt gekocht“
- **Rezepte:** Kategorie-Leiste und Schaltfläche „Kategorien“ (Kacheln mit Anzahl, eigene Kategorien anlegen, Admins
  benennen um/löschen), Suche (Titel, Kategorie, Zutat, #tag), Filter (Art, Ernährung, Mahlzeit, Favoriten), Zufallsrezept
- **Rezeptdetail:** Fotos, Portionsrechner, Zutaten mit Vorratsstatus und Alternativen, abhakbare Schritte
  mit Zutatenmengen, Backangaben, Nährwerte, Bewertungen/Kommentare, Favorit, „Gekocht/Gebacken“ bucht den
  Vorrat ab (Alternative wählbar), fehlende Zutaten auf die Einkaufsliste
- **Mitteilungen:** Vorrat knapp, Stehzeit vorbei, Einkaufslisten-Erinnerung, neue Bewertungen,
  Haushalts-Einladungen, Kontoanfragen (Admins) – je Kategorie abschaltbar (Mehr → Mitteilungen).
  Tippen auf eine Mitteilung öffnet das Rezept.
- **Rezept-Editor:** Koch-/Backrezept, Mahlzeiten, Tags, Fotos (Mediathek/Kamera), Zutaten mit Einheit,
  Einstufung, Hinweis, Alternative und Vorteig, Schritte mit Zutatenmengen, Stehzeit-Schritte,
  Backschritt, Stehzeit-Planung, Nährwerte
- **Automatisch:** Fotos/PDFs eines Rezepts hochladen → Claude erstellt es („Erstelle meine Kochbuch-Rezepte“)
- **Vorrat:** Haushalt wechseln, Bestand/Mindestbestand/Nachkaufmenge/Kauf-Einheit, Foto, schnelles
  Auffüllen per Wischen, knappe Zutaten auf die Einkaufsliste
- **Einkaufsliste:** Einträge mit Vorschlägen, Abhaken bucht in den Vorrat, Teilen
- **Mehr:** Benachrichtigungen (inkl. Haushalts-Einladungen), Favoriten, Konto (Ernährung, Essenszeiten,
  Einkaufserinnerung, Passwort), Mitteilungen, Haushalte (einladen, umbenennen, verlassen)
- **Admin:** Kontoanfragen freigeben, Nutzer anlegen/Rollen/Passwort/Löschen, alle Haushalte verwalten,
  Datenbank-Backup

## Wie Mitteilungen ankommen

Mit kostenloser Apple-ID gibt es keinen echten Push über Apple (APNs). Die App holt neue
Benachrichtigungen deshalb selbst ab:

- beim Öffnen und jede Minute, solange sie offen ist,
- im Hintergrund über die iOS-Hintergrundaktualisierung. Wie oft die läuft, bestimmt iOS
  (meist alle 15 Minuten bis einige Stunden, öfter bei häufig genutzten Apps). Dafür muss unter
  Einstellungen → Allgemein → Hintergrundaktualisierung das Kochbuch an sein. Wird die App aus dem
  App-Umschalter weggewischt, gibt es bis zum nächsten Öffnen keinen Hintergrundabruf.
- **Stehzeiten** stellt die App beim Abhaken selbst als Wecker – die kommen immer pünktlich.

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
