# Texttools cheatsheet

## Neovim leaders

| Leader       | Actie                                                              |
|--------------|--------------------------------------------------------------------|
| <leader>am   | Metadata genereren (krant + web)                                   |
| <leader>ac   | Metadata + kalenderitem — bewerkbare ## Kalender sectie            |
| <leader>ao   | Tekstcheck: spelling/grammatica; twijfel → ## Suggesties onderaan  |
| <leader>at   | Tussenkopjes + streamer (geen streamer als er al een > staat)      |
| <leader>ar   | Herschrijven naar krantenartikel (AI)                              |
| <leader>af   | Facebook-post genereren — bewerkbare ## Facebook sectie            |
| <leader>aw   | Versturen naar Pubble                                              |
| <leader>ap   | Ad-hoc rewrite: typ *** + instructie, buffer wordt vervangen       |
| <leader>ag   | AI gesprek: typ *** + vraag, antwoord verschijnt eronder           |
| <leader>ah   | Codes invoegen via zoeklijst                                       |
| <leader>ak   | Verdachte tekens scannen (U+FFFD, control chars)                   |
| <leader>a?   | Deze cheatsheet                                                    |
| <leader>kt   | Rubriektemplate invoegen (Raadspraat, 112, etc.)                   |
| <leader>kr   | Raadspraat-reminders: ▶ = deze week, ○/✓ = status; ? = toetsen     |

Planning naar een fractie sturen:  raadspraat-reminder overzicht [partij]
  bijv. `raadspraat-reminder overzicht vvd | pbcopy`

---

## Controlecodes bovenaan artikel

Werken in beide workflows (leader aw én pubble-batch):

  editie: B          of SW, ST, Z, D, K, all, overijssel, flevoland
  prio: 2            1=moet mee  2=mag mee  3=rest(standaard)  4=nood
  rubriek: 112       112-bericht (articleCategoryId 24)
  week: 29           uiterste publicatieweek overschrijven (x = geen deadline)
  b: Bijschrift      globaal bijschrift (alle foto's)
  c: Fotograaf       globale credit
  b1: Bijschrift 1   bijschrift specifiek voor foto 1
  c1: Fotograaf 1
  b2: Bijschrift 2   bijschrift specifiek voor foto 2
  c2: Fotograaf 2
  calendar: x        kalenderitem meenemen
  facebook: x        Facebook-post genereren (AI)
  web: draft         webartikel als concept, niet direct publiceren

Alternatief (herkend in eerste 4 regels van de body):

  Bijschrift: tekst
  Foto: naam fotograaf

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
  tekst, de plaatsing — midden van het artikel — is automatisch).

  ## Suggesties (van <leader>ao) hoef je nooit op te ruimen:
  pubble-send stript die sectie automatisch bij verzenden.

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
interessant is. Alleen treffers met hoofdletter tellen. Bij <leader>aw zie
je dezelfde scan als "Tekst noemt ook: ..." — suggestie, stuurt niet;
zelf e: toevoegen als je erheen wilt.

---

## pubble-batch

Bestanden in: ~/Desktop/Pubble Inbox/pubble-batch/

Controlecodes bovenaan het document (voor de kop), in artikel.meta naast het
document, of in default.meta voor de hele map.
default.meta wordt automatisch aangemaakt bij de eerste run.

Prioriteit: bovenaan artikel > artikel.meta > default.meta

Foto's op bestandsnaam:  artikel.jpg, artikel2.jpg, artikel3.jpg
Na verwerking: alles met datum-prefix naar published-archive/

---

## Mislukte verzending? Gewoon opnieuw versturen

pubble-send schrijft elk Pubble-ID direct terug in de frontmatter.
Een rerun slaat edities met een ID over en maakt alleen de ontbrekende aan —
geen duplicaten. Exit code 1 + waarschuwing = artikel staat mogelijk nog
offline in het CMS, even controleren.
