# IJsseldelta: herstel en onderzoek — 20 oktober 2026

## Uitgevoerde correcties

- Escape in invoervelden wisselt alleen naar Normal, ook bij herhaald drukken.
  Annuleren/uitstellen gebeurt daar met Ctrl-C. Keuzelijsten behouden hun
  afzonderlijke Escape-beleid. Een regressie met een lopende, gemockte AI-taak
  bewijst dat Escape geen kill of vervolgcallback veroorzaakt; expliciet
  `<leader>aq` / `:AICancel` werkt wel en negeert late uitvoer.
- Fidget zegt nu `afgerond` in plaats van `beëindigd`. Dat is het einde van de
  verwerking, geen bewijs dat tekst is toegepast of een publicatie is geslaagd.
  Uitkomsten staan bij het artikel; de voortgang blijft acht seconden staan.
- De onverklaarde `Aandacht nodig`-toevoeging aan de statusbalk is verwijderd.
  Uitleg staat boven de artikelgrens, de historie opent via `<leader>kl`.
- Verzendbewaking vergelijkt de volledige bron inclusief agenda, foto en
  workflowmetadata. Alleen expliciete `Melding:`-regels vóór de artikelgrens
  zijn presentatieruis. Datumgoedkeuring levert een expliciete vóór/na-transitie:
  alleen als de vóór-revisie overeenkomt met de gestagede bron schuift de
  verwachting mee. Echte eerdere/latere edits blijven beschermd.
- De datumcontrole beschermt nu ook enkele aanhalingstekens. De slogan
  ‘Niemand vogelvrij. Vandaag de boer. Morgen jij’ is geen relatieve
  publicatiedatum en blijft ook bij krantconversie letterlijk behouden.
- Het bestaande uitvoerplan voor lezersnieuws gaat mee naar een herstelbuffer
  én in de herstel-sidecar. Heropenen na een editorherstart verliest dat plan
  niet. Herstelkeuzes gebruiken nu de asynchrone centrale keuzelaag; herhaald
  `aw` start geen tweede vraag of verzending. Ongeldige uitvoernamen blokkeren.
- Herkende, al getemplate kopij wordt niet opnieuw gewikkeld. Ontbrekende
  bestaande templatevelden en de exportopdracht worden uit dezelfde definitie
  hersteld; een aanwezige werktitel en expliciete bestemming blijven staan.
  Voor de Natuurvereniging is de bestaande standaard `z - NATUURVERENIGING`.
- De gedeelde Python-herkenning herkent een auteursnaam met de exacte
  verenigingswebsite, zoals Martijn van der Heide. Dit blijft een voorstel met
  bevestiging. Alleen de naam van de vereniging, een losse URL of een ander
  domein maakt een persbericht niet tot een column.
- De fotodoelen omvatten nu ook `calendar.variant_article_ids`: editiegebonden
  agenda-items krijgen hun hoofdfoto. Een tweede/derde mediapass hergebruikt de
  upload en de duurzame koppelstatus. Web/krant krijgen nog steeds alle foto's.

## Wat de bestaande bestanden en logs bewijzen

De eerste columnpoging (`20261020-161133`) bevat nog de z-werktitel. In de
latere import (`20261020-161854`) ontbreken zowel die technische rubriekgegevens
als `rubriek: column`. Daardoor bouwt metadata een generieke `x - 3`-werktitel.
Het precieze verliesmoment tussen die twee imports is niet gelogd; een
gebruikersbewerking of één specifieke oorzaak is dus niet bewezen.

Bij de latere import eindigt de eerste verzendpoging om 16.20 uur met een
herstelconflict. De hervatting om 16.22 uur registreert een geslaagde
publicatie en foto-upload/-koppeling. De herstelmarker bevat `completed=true`;
artikel en foto bestaan in het archief. De oude werkbuffer mag daarom niet
als nieuw artikel worden verzonden. Het ontbreken van de lezersnieuwsexport
is afzonderlijk verklaard: het uitvoerplan werd niet overgenomen bij het
openen van het herstelbestand. Een Pubble-succes bewijst niet dat die lokale
export is uitgevoerd.

Alle tijden hierboven zijn Europe/Amsterdam. Tijdens het oorspronkelijke
onderzoek zijn geen live AI-/CMS-calls gedaan. De latere expliciet gevraagde
afronding heeft gericht herstel uitgevoerd, zoals hieronder vastgelegd.

## Bestaande column en laatste UI-restpunten hersteld

Na de opdracht om ook al het resterende werk af te ronden:

- Krantartikel **110969**, webartikel **376911**, gedeelde publicatie
  **426405**: werktitel wordt nu op beide kanalen
  `z - NATUURVERENIGING Boeren en natuur 20-10-26`. Het krantdossier is `z`.
  Voor en na de gerichte PUT is de identiteit gecontroleerd. Hashvergelijking
  bevestigt behoud van tekst, kop, foto, serialisatie en planning; bij web ook
  socials en online-status. Geen create, herpublicatie of fotowijziging.
- De lokale export staat in `~/Desktop/44_lezersnieuws/` als
  `1.column_natuurvereniging.txt` en `1.column_natuurvereniging.jpg`.
  De tekst komt uit het gepubliceerde archief, zonder archiefkop/weblinkblok en
  zonder Facebook-sectie. De foto is inhoudelijk identiek aan de bijbehorende
  archieffoto. Het bronartikel blijft intact, ook een bestaande onjuiste
  geneste auteurslink wordt niet stil herschreven. De gedeelde herstelactie
  weigert afwijkende bestaande uitvoer en ongerelateerde foto's.
- De resterende interactieve ja/nee- en persoonskeuzes zijn aangesloten op
  dezelfde asynchrone overlay. Oude beslisstappen draaien via expliciete
  coroutine-adapters; geen editor-wachtlus. Bronbinding en late-keuzebewaking
  gelden ook voor de echte verzend- en resetroute. Hoofdthread, timer en
  achtergrondwerk blijven doorlopen. Details staan in `NOTIFICATIES.md`.

Dit eenmalige herstel gebruikte twee gerichte bestaande-artikel-PUTs plus
verificatie-GETs en lokale bestandsexport; geen AI of nieuwe foto-upload.

## Waarom de versie voor De Kop algemeen werd

Onderzocht: `20261020-155403`, bronkopie vóór verzending van 16.06 uur, de
veilige uitvoeringslog en de werkelijke CLI-/promptopbouw. Geen promptwijziging.

1. De deterministische strategie vindt Kampen voor B en Vollenhove/Paasloo
   voor K, en adviseert gerichte varianten. De oorspronkelijke bron bevat dus
   wel degelijk bruikbare informatie over het lezersgebied van De Kop.
2. Voor K geeft het programma Nieuwsbode de Kop, het lezersgebied
   Steenwijkerland en omliggende kernen, en de gevonden bronplaatsen mee.
   De hele originele tekst gaat mee; de lokale achtergrond is niet eerst
   weggeknipt. Een onjuiste editiecode verklaart het probleem niet.
3. De log toont twee gerichte AI-calls om 15.56 uur en daarna één
   `krantversie_algemeen`-call. De eerste K-call duurt circa 5,5 seconden;
   de algemene terugval circa 16 seconden. In deze codeflow volgt die extra
   algemene taak op afwijzing van een lokale invalshoek. Dat verklaart de
   algemene Kampen-opening beter dan de veronderstelling dat nooit een aparte
   versie is aangevraagd. De feitelijke afwijsuitvoer is niet bewaard.
4. De gebruikte calls hebben `gpt-5.6-terra`, reasoning `medium` en het schema
   `article_edit_plan_v1`. De log telt ongeveer 25–26 duizend instructietekens
   voor de gerichte calls en 20 duizend voor de algemene terugval. Dit is geen
   proef met uitsluitend de korte, door Nick aangeleverde prompt.

De lokale opdracht gaat nadrukkelijk over personen, bijdragen en activiteiten.
De extra afwijsmogelijkheid benadrukt concrete betrokkenheid. Bij deze bron
ligt de relevantie voor K juist in het **onderwerp/landschap** van een lezing
die fysiek in Kampen plaatsvindt. Het is aannemelijk dat dit onderscheid te
weinig gewicht kreeg. De behoudende/automatische bewerkopdracht voegt bovendien
een bronbeoordeling en bewerkingsplan toe. Dat kan andere afwegingen geven dan
een directe journalistieke herschrijfopdracht. Dit zijn verklaringshypothesen,
geen bewezen uitspraak over de interne redenering van het model.

Nicks voorgestelde nadruk op het landschap is logisch: benoem vroeg dat de
lezing over de Kop van Overijssel gaat en behoud Kampen als feitelijke
bijeenkomstlocatie. Neem niet blind alle formuleringen over: `Steenwijk` en
`de Woldberg bij Steenwijk` staan niet letterlijk in deze oorspronkelijke bron.
Die concrete toevoegingen vallen buiten het huidige bronfeitencontract.

Een eventuele vervolgaanpassing vraagt eerst een kleine offline evaluatieset
met onderwerp-/landschapsrelevantie, terloopse plaatsvermeldingen en de eerdere
muzikanten-/deelnemersgevallen. Geen algemene versoepeling van feitenbehoud of
automatische wijziging van het model op basis van één voorbeeld. Een live
vergelijking kost extra AI-calls en is hier niet uitgevoerd.

## Kosten, compatibiliteit en bediening

Geen extra AI-calls, uploads, subprocessen, wachttijden of periodieke scans.
Revisies gebruiken een begrensd aantal lineaire buffervergelijkingen per
verzendpoging, niet per toetsaanslag. De herstel-sidecar krijgt een optioneel
client-uitvoerplan binnen versie 1; oude markers blijven geldig. De bestaande
templatecatalogus wordt hergebruikt, niet gekopieerd naar een tweede tabel.
De gedeelde Python-kern blijft eigenaar van herkenning en fotodoelen.

Prestatie-impact: grotendeels neutraal; niet apart gebenchmarkt. Bewuste extra
HTTP-koppeling: één per eerder vergeten editiegebonden agenda-ID, zonder
nieuwe foto-upload. Daarna voorkomt bestaande idempotentie dubbele koppelingen.

De Lua-wijzigingen gelden in een nieuw gestarte Neovim-sessie. Herstart pas
wanneer de lopende taken zijn afgerond; de huidige sessie wordt niet op afstand
herladen of beëindigd.

Verificatie na alle correcties: 140/140 NeoVim-testbestanden en 2988 Python-
tests geslaagd. Beide repositories slagen voor `git diff --check`.
