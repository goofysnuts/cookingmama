# Kochbuch (iOS)

iPhone-App für das selbst gehostete **Kochbuch** auf dem NAS (`Y:\cookbook`). Der Docker-Container
liefert nur noch die API (`/api/v1`), die Oberfläche ist diese SwiftUI-App. iOS 17+.

## Funktionen

- **Start:** Begrüßung und ein zufälliges Rezept passend zur aktuellen Essenszeit („Anderer Vorschlag“
  würfelt neu), weitere passende Rezepte, Favoriten für die Mahlzeit, „Zuletzt gekocht“
- **Rezepte:** startet mit den Kategorien (Kacheln mit Anzahl), Suche über alle Rezepte (Titel, Zutat,
  Kategorie, #tag), Zufallsrezept, Filter innerhalb einer Kategorie (Art, Ernährung, Mahlzeit, Favoriten),
  eigene Kategorien anlegen (Admins benennen um/löschen)
- **Was habe ich da?:** Zutaten eingeben (mit oder ohne Menge) und passende Rezepte bekommen – komplett
  kochbare zuerst, sonst mit Liste der fehlenden Zutaten. Grundzutaten (Salz, Pfeffer, Wasser, Zucker, Öl)
  zählen auf Wunsch als vorhanden. Die Liste bleibt auf dem iPhone gespeichert.
- **Rezeptdetail:** Fotos, Portionsrechner, Zutaten mit Alternativen, abhakbare Schritte mit Zutatenmengen,
  Backangaben, Nährwerte, Bewertungen/Kommentare, Favorit, „Auf die Einkaufsliste“ (Zutaten auswählen,
  Menge passend zur Portionenzahl), „Heute gekocht/gebacken“
- **Rezept-Editor:** Kategorie, Koch-/Backrezept, Mahlzeiten, Tags, Fotos (Mediathek/Kamera), Zutaten mit
  Einheit, Einstufung, Hinweis, Alternative und Vorteig, Schritte mit Zutatenmengen, Stehzeiten, Nährwerte
- **Automatisch:** Fotos/PDFs eines Rezepts hochladen → Claude erstellt es („Erstelle meine Kochbuch-Rezepte“)
- **Einkaufsliste:** gemeinsam für alle, Einträge mit Vorschlägen, gleiche Zutaten werden zusammengezählt, Teilen
- **Mitteilungen:** Stehzeit vorbei, Einkaufslisten-Erinnerung, neue Bewertungen, Kontoanfragen (Admins) –
  je Kategorie abschaltbar (Mehr → Mitteilungen). Tippen auf eine Mitteilung öffnet das Rezept.
- **Mehr:** Benachrichtigungen, Favoriten, Konto (Ernährung, Essenszeiten, Einkaufserinnerung, Passwort)
- **Admin:** Kontoanfragen freigeben, Nutzer anlegen/Rollen/Passwort/Löschen, Datenbank-Backup

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
