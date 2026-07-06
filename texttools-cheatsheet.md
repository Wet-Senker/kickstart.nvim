# Texttools cheatsheet

## Neovim leaders

| Leader       | Actie                                                              |
|--------------|--------------------------------------------------------------------|
| <leader>am   | Metadata genereren (krant + web)                                   |
| <leader>ac   | Metadata + kalenderitem — bewerkbare ## Kalender sectie            |
| <leader>ao   | Opmaken: spellcheck, tussenkopjes, lead bold, streamer, oordeel    |
| <leader>ar   | Herschrijven naar krantenartikel (AI)                              |
| <leader>af   | Facebook-post genereren — bewerkbare ## Facebook sectie            |
| <leader>aw   | Versturen naar Pubble                                              |
| <leader>ap   | Ad-hoc rewrite: typ *** + instructie, buffer wordt vervangen       |
| <leader>ag   | AI gesprek: typ *** + vraag, antwoord verschijnt eronder           |
| <leader>ah   | Codes invoegen via zoeklijst                                       |
| <leader>a?   | Deze cheatsheet                                                    |
| <leader>kt   | Rubriektemplate invoegen (Raadspraat, 112, etc.)                   |

---

## Controlecodes bovenaan artikel

Werken in beide workflows (leader aw én pubble-batch):

  editie: B          of SW, ST, Z, D, K, all, overijssel, flevoland
  prio: 2            1=moet mee  2=mag mee  3=rest(standaard)  4=nood
  b: Bijschrift      globaal bijschrift (alle foto's)
  c: Fotograaf       globale credit
  b1: Bijschrift 1   bijschrift specifiek voor foto 1
  c1: Fotograaf 1
  b2: Bijschrift 2   bijschrift specifiek voor foto 2
  c2: Fotograaf 2

Alternatief (herkend in eerste 4 regels van de body):

  Bijschrift: tekst
  Foto: naam fotograaf

---

## Alleen pubble-batch (in .meta of bovenaan document)

  rewrite: x         herschrijven naar krantenstijl (AI)
  calendar: x        kalenderitem aanmaken
  facebook: x        Facebook-post genereren (AI)
  facebook_tekst:    eigen tekst als Facebook-post

---

## Kalender (leader ac of handmatig)

  ## Kalender

  Titel: Naam evenement
  Datum: 2026-07-23
  Tijd: 20:00
  Eindtijd: 22:00
  Locatie: Naam locatie
  Adres: Straatnaam 1
  Stad: Plaatsnaam

  Korte omschrijving. Geen datum/tijd/locatie herhalen.

---

## Markdown opmaak (website)

  Eerste alinea      automatisch vet
  **tekst**          vet
  *tekst*            cursief
  > "citaat"         QUOTE-blok
  [tekst](url)       hyperlink

  Print: bold/italic gestript, > quote wordt STREAMER - - -

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

---

## pubble-batch

Bestanden in: ~/Desktop/Pubble Inbox/articles/

Controlecodes bovenaan het document (voor de kop) of in default.meta voor de hele map.
default.meta wordt automatisch aangemaakt bij de eerste run.

Prioriteit: bovenaan artikel > default.meta

Foto's op bestandsnaam:  artikel.jpg, artikel2.jpg, artikel3.jpg
