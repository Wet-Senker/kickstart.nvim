# Texttools cheatsheet

## Neovim leaders

| Leader       | Actie                                                              |
|--------------|--------------------------------------------------------------------|
| <leader>am   | Metadata genereren (krant + web)                                   |
| <leader>ac   | Metadata + kalenderitem — bewerkbare ## Kalender sectie            |
| <leader>ao   | Tekstcheck: spelling/grammatica; twijfel → ## Suggesties onderaan  |
| <leader>at   | Tussenkopjes + streamer (geen streamer als er al een > staat)      |
| <leader>ar   | Herschrijven; fotocredit verhuist vóór === ARTIKEL ===             |
| <leader>af   | Facebook-post genereren — bewerkbare ## Facebook sectie            |
| <leader>aw   | Versturen; bij eventteksten: eerst controleren, nogmaals publiceren|
| <leader>ap   | Ad-hoc rewrite: typ *** + instructie, buffer wordt vervangen       |
| <leader>ag   | AI gesprek: typ *** + vraag, antwoord verschijnt eronder           |
| <leader>ah   | Codes invoegen via zoeklijst                                       |
| <leader>a?   | Deze cheatsheet                                                    |
| <leader>kt   | Rubriektemplate invoegen (Raadspraat, 112, etc.)                   |
| <leader>kr   | Raadspraat: reminders / overzicht / artikel maken                   |
| <leader>ko   | Ondernemen in Kampen: idem, acht columnisten                        |

Rubriekmenu (<leader>kr = Raadspraat, <leader>ko = Ondernemen):
  Reminders       de rotatie; ▶ = deze week, ○/✓ = verzendstatus, s = wisselen
  Overzicht       planning voor één deelnemer of iedereen tegelijk
  Artikel maken   foto + template (zaten voorheen onder <leader>kt)
In de mailbuffer: <leader>aw = Apple Mail, c = kopiëren, ? = toetsen
  c geeft bij een reminder de hele mail, bij een overzicht alleen de planning

Ook vanuit de terminal:
  raadspraat-reminder overzicht [fractie] | pbcopy
  ondernemen-reminder overzicht [naam]    | pbcopy

Evenement-vervolgplaatsingen (artikel met ## Kalender + toekomstige datum):
  na datumkeuze maximaal twee vragen: korte versie op T-10? dagreminder(s)?
  bij ja: eerste <leader>aw toont ## Korte versie / ## Dagreminder in de buffer
  controleer/bewerk; tweede <leader>aw maakt hoofdartikel + foto + vervolgen
  Pubble opent pas wanneer alles klaar en gearchiveerd is (ook Facebooktekst)
  bij twee keer nee publiceert de eerste <leader>aw het gewone artikel direct
  "groot evenement" = jouw actuele vinkje; er is geen los event memory
  vervolgversies blijven gekoppeld en hergebruiken categorie + hoofdafbeelding
  Ook vanuit de terminal: pubble-event opties/teksten/plaats

Fotobijschriften Ondernemen komen uit personen.md in de fotomap:
  ~/krant-fotos/ondernemen_in_kampen/personen.md   (iCloud, niet in git)
  naam:      exact zoals hij in de krant moet staan (mét hoofdletters)
  functie:   \n geeft een echte regelovergang; " breekt de frontmatter

---

## Controlecodes boven de artikelgrens

`pv` plaatst `=== ARTIKEL ===` automatisch. Zet codes daarboven; de kop staat
eronder. `<leader>ah` kiest en plaatst codes op de juiste plek.

  editie: B          of SW, ST, Z, D, K, all, overijssel, flevoland
  prio: 2            1=moet mee  2=mag mee  3=rest(standaard)  4=nood
  rubriek: 112       112-bericht (categorie 112 op krant én web); de kop gebruikt
                      de eerste bekende plaats uit de tekst, anders alleen `112:`;
                      op de web verwijst
                     de slotregel naar de knoppen, in print naar het mailadres
  rubriek: column    column: krant + web krijgen een reactie-uitnodiging
                     (krant via mailadres, web via de link eronder). De
                     column-templates zetten dit zelf via de vlag
                     column = true in krant.lua
  week: 29           publicatieweek overschrijven (x = geen deadline)
  week: 30, 31       meerdere mogelijke weken; beide komen in de werktitel
  b: Bijschrift      globaal bijschrift (alle foto's)
  c: Fotograaf       globale credit
  b1: Bijschrift 1   bijschrift specifiek voor foto 1
  c1: Fotograaf 1
  b2: Bijschrift 2   bijschrift specifiek voor foto 2
  c2: Fotograaf 2
  calendar: x        kalenderitem meenemen
  facebook: x        Facebook-post genereren (AI)
  web: draft         webartikel als concept, niet direct publiceren

  === ARTIKEL ===    niet zelf typen of verplaatsen

  Artikelkop

Alternatief voor fotocredit/bijschrift:

  Bijschrift: tekst
  Foto: naam fotograaf

`f:` is ongeldig. Bij `<leader>aw` wordt iedere niet-lege regel boven de grens
gevalideerd voordat AI of Pubble wordt aangeroepen. AI-rewrites ontvangen
alleen de tekst onder de grens. `***` is geen artikelgrens maar hoort alleen
bij de inline AI-prompt- en gespreksleaders.

---

## Alleen pubble-batch (in .meta of bovenaan document)

  rewrite: x         herschrijven naar krantenstijl (AI)
  facebook_tekst:    eigen tekst als Facebook-post
  prefix: sport      voorvoegsel voor de werktitel

---

## Kalender (leader ac of handmatig)

  ## Kalender

  Titel: Naam evenement
  Datum: 2026-07-23
  Einddatum: 2026-07-31     (alleen bij meerdaags evenement, anders weglaten)
  Herhaling: wekelijks      (of: maandelijks / maandelijks laatste)
  Herhaal tot: 2026-08-27   (verplicht bij Herhaling)
  Tijd: 20:00
  Eindtijd: 22:00
  Locatie: Naam locatie
  Adres: Straatnaam 1
  Stad: Plaatsnaam

  Korte omschrijving. Geen datum/tijd/locatie herhalen.

  Tijd mag ook als 19.30 / 19u30 / 20 uur — wordt genormaliseerd naar HH:MM.
  Een datum in het verleden geeft een waarschuwing bij het versturen.

  Herhaling: de weekdag volgt uit Datum, dus "elke donderdag" = Datum op een
  donderdag + Herhaling: wekelijks. Bij maandelijks zet je de positie erachter
  ("maandelijks laatste" / "maandelijks tweede"): die is NIET uit de datum af
  te leiden, want de 4e woensdag is vaak ook de laatste. Einddatum en
  Herhaling sluiten elkaar uit.

---

## Markdown opmaak (website)

  Eerste alinea      automatisch vet
  **tekst**          vet
  *tekst*            cursief
  > "citaat"         QUOTE-blok
  [tekst](url)       hyperlink

  Print: bold/italic gestript, > quote blijft op zijn plek als "STREAMER: quote"

  Streamer zelf plaatsen: zet "> 'citaat'" op de gewenste regel.
  <leader>at genereert er alleen een als je er nog geen hebt (AI kiest de
  tekst; de plaatsing is automatisch rond het inhoudelijke midden, nooit
  direct na de lead/eerste tekstalinea).

  ## Suggesties (van <leader>ao) hoef je nooit op te ruimen:
  pubble-send stript die sectie automatisch bij verzenden.

  Slotregel per artikeltype (automatisch bij verzenden): op de website
  reageer je via de knoppen onder het artikel, in de krant via het mailadres.
  - gewoon nieuws: alleen op de website "Spot jij iets dat niet klopt? ...
    Meld het hieronder."
  - column (rubriek: column): krant + web een reactie-uitnodiging
  - 112: web verwijst naar de knoppen, krant naar het mailadres
  - Raadspraat/Ondernemen: houden hun eigen slotregel

---

## Edities

  B            brugnieuws (standaard)
  SW           deswollenaer
  ST           destadskoerier
  Z            zeewolde
  D            dedrontenaar
  K            De Kop van Overijssel
  all          alle edities
  overijssel   B, SW, ST, K
  flevoland    D, Z

Plaatsenscan: pubble-places leest het clipboard (of stdin/bestand) en toont
per krant de gevonden plaatsnamen — snelle check of een artikel voor ons
interessant is. Alleen treffers met hoofdletter tellen.

e:-regel na <leader>ar: zodra het artikel herschreven is (en er dus een
dateline staat) vult het systeem bovenaan een e:-regel in:
  e: D, SUGGESTIE, SW
De kranten vóór SUGGESTIE zijn de bestemming (uit de dateline); daarachter
staan de suggesties van de plaatsenscan (kranten die de tekst wél noemt).
Wil je een suggestie meesturen, zet hem dan vóór SUGGESTIE (of haal het
woord SUGGESTIE weg). Bij <leader>aw gaat alleen wat vóór SUGGESTIE staat mee.

---

## pubble-batch

Bestanden in: ~/Desktop/Pubble Inbox/pubble-batch/

Controlecodes bovenaan het document (voor de kop), in artikel.meta naast het
document, of in default.meta voor de hele map.
default.meta wordt automatisch aangemaakt bij de eerste run.

Prioriteit: bovenaan artikel > artikel.meta > default.meta

Foto's op bestandsnaam:  artikel.jpg, artikel2.jpg, artikel3.jpg
event_reminder: x maakt kalender + hoofdartikel + één openingsdagreminder
automatisch in dezelfde run; geen Neovim-controlepauze en geen T-10/reeks.
Na verwerking: alles met datum-prefix naar ~/Documents/Pubble Archief/JJJJ/MM/
Archief zoeken: <leader>pa op bestand, <leader>ps door volledige inhoud
Het archiefpad mag een symlink naar een cloudmap zijn; TEXTTOOLS_ARCHIVE_DIR
stelt een alternatief pad in voor zowel Python als de Neovimzoekers.

---

## Mislukte verzending? Gewoon opnieuw versturen

pubble-send schrijft elk Pubble-ID direct terug in de frontmatter.
Een rerun slaat edities met een ID over en maakt alleen de ontbrekende aan —
geen duplicaten. Exit code 1 + waarschuwing = artikel staat mogelijk nog
offline in het CMS, even controleren.
