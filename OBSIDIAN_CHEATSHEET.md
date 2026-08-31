# Obsidian in Neovim — cheat sheet

Vault: `~/Obsidian/Obsidian`. De `<leader>o…`-toetsen hieronder werken **alleen
in een notitie binnen de vault** (buffer-lokaal); de drie globale onderaan
werken overal.

## In een notitie (buffer-lokaal)

| Toets | Commando | Doet |
|-------|----------|------|
| `<cr>` | smart action | Context-afhankelijk op wat onder de cursor staat: **link** → volgen · **checkbox** → togglen · **kopregel** → sectie in-/uitvouwen (overschrijft de normale Enter, alleen in vault-notities) |
| `gf` | volg link | Link onder cursor openen |
| `<leader>ch` | toggle checkbox | `- [ ]` ⇄ `- [x]` |
| `<leader>oo` | ObsidianOpen | Huidige notitie in de **Obsidian-app** openen |
| `<leader>ob` | ObsidianBacklinks | Wie **linkt naar** deze notitie |
| `<leader>os` | ObsidianSearch | **Full-text** zoeken door de hele vault |
| `<leader>oT` | ObsidianTags | Zoeken/bladeren door **tags** (`#tag`) |
| `<leader>or` | ObsidianRename | Notitie hernoemen **+ alle `[[links]]` bijwerken** |
| `<leader>oc` | ObsidianTOC | **Inhoudsopgave** van de huidige notitie |

## Overal bruikbaar (globaal)

| Toets | Commando | Doet |
|-------|----------|------|
| `<leader>oq` | ObsidianQuickSwitch | Snel naar een notitie springen op naam |
| `<leader>on` | ObsidianNew | **Nieuwe** notitie |
| `<leader>ot` | ObsidianToday | **Daily note** van vandaag |

## Ezelsbruggetje

- **Binnen een notitie navigeren** → `oc` (inhoud)
- **Tussen notities** → `ob` (backlinks) · `os` (zoeken) · `oT` (tags) · `oq` (springen)
- **Beheer** → `or` (hernoemen mét linkherstel) · `on` (nieuw) · `oo` (in app)
