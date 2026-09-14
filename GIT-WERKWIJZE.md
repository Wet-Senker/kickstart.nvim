# Git-werkwijze — twee banen: `master` (werk/test) en `stabiel` (vangnet)

Deze repo wordt live gebruikt: de checkout ís productie (bij nvim leest de editor
rechtstreeks uit `~/.config/nvim`; bij texttools draait `pip install -e .` op de
werkmap). Daarom houden we twee branches met een bewuste rolverdeling.

## De twee branches

| Branch | Rol | Wie schrijft erop |
|---|---|---|
| **`master`** | De **bewegende werk-/testbaan**. Hier landt alle dagelijkse ontwikkeling. Mag tijdelijk kapot zijn. | Nick + Codex + AI-assistenten |
| **`stabiel`** | Het **bekend-goede terugvalpunt**. Beweegt alleen vooruit naar een master-commit die Nick heeft getest en goedgekeurd. | Alleen via "promoveren" (zie onder) |

> Let op: dit is bewust omgekeerd aan de conventie. Normaal is de default-branch
> (`master`) de stabiele; hier is `master` juist de test-branch, omdat Nick er de
> hele dag op werkt en test. `stabiel` is het vangnet.

## Dagelijks werken
Gewoon op `master` blijven en committen/pushen zoals altijd. Niets verandert aan
de dagelijkse flow. CI (`.github/workflows/ci.yml`) draait de tests bij elke push.

## Een goede staat vastleggen (promoveren naar `stabiel`)
Wanneer `master` een tijd goed draait én je het getest hebt:

```bash
git checkout master
git pull --ff-only
git branch -f stabiel master     # verplaats stabiel naar de huidige (goede) master
git push origin stabiel
```

`stabiel` wijst nu naar exact die goedgekeurde commit. Geen merge, geen conflicten.

## Terugvallen als `master` stuk is
Twee opties:

**A. Even doorwerken op de goede versie** (zonder master te wijzigen):
```bash
git checkout stabiel     # je checkout draait nu de bekend-goede versie
# ... werk door / gebruik het programma ...
git checkout master      # terug naar de werkbaan zodra master gerepareerd is
```

**B. Master terugzetten naar het vangnet** (gooit de kapotte master-commits weg —
alleen doen als je die echt niet wilt bewaren):
```bash
git checkout master
git reset --hard stabiel
git push --force-with-lease origin master
```
Twijfel je? Kies A, of maak eerst een backup-branch: `git branch backup-master master`.

## Regels voor AI-assistenten en Codex
- Commit dagelijks werk op **`master`**, niet op `stabiel`.
- Raak **`stabiel` nooit** automatisch aan; promoveren doet Nick bewust.
- Draai vóór een commit de tests (`python -m pytest tests/ -q` voor texttools;
  de headless nvim-tests onder `tests/` voor de nvim-repo).
- Na een pull met nieuwe entry points: `pip install -e .` opnieuw (texttools).
- Altijd `git status` vóór edits — er wordt parallel op meerdere machines gewerkt;
  commit niet in andermans niet-gecommitte werk.

## Opruimen
Volledig gemergede feature-branches (`git rev-list --count master..<branch>` = 0)
mogen weg: `git push origin --delete <branch>`. Branches die nog commits vóór
lopen op master eerst bekijken; niet blind verwijderen.
