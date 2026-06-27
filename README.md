# texttools

Personal editorial text tools for moving source text into Neovim, generating article metadata, and sending content to Pubble.

This project is intentionally small and modular. The core logic lives in Python. Local automation tools such as Keyboard Maestro or Neovim only orchestrate the workflow.

## Purpose

`texttools` started as clipboard and text-cleanup tooling, but now contains several small subsystems that can be combined as needed:

- text cleanup
- AI rewriting
- newspaper metadata generation
- calendar metadata generation
- Pubble newspaper/web draft creation
- Pubble media upload and linking

The design goal is that each subsystem can stand on its own, while one workflow can combine them.

## Current modules

### `cleantext`

Cleans copied text before it is pasted into Neovim.

### `aitext`

Runs AI rewriting prompts on text.

### `articlemeta`

Generates YAML frontmatter for articles.

Current frontmatter areas include:

- `newspaper`
- `web`
- `media`
- `send`
- `calendar` when calendar mode is enabled

Typical usage:

```bash
articlemeta < article.md
articlemeta --calendar < article.md
```

### `pubble-send`

Creates linked Pubble newspaper and web drafts from one Markdown article file.

Current behavior:

- creates newspaper draft first
- forwards that draft to web
- writes returned IDs back into the Markdown file when `--write-ids` is used
- creates a calendar draft too when a ready calendar block is present and enabled in the file

Typical usage:

```bash
pubble-send article.md --create --write-ids
```

### `pubble-media`

Uploads images from the Pubble dropzone and links them to available targets in the article file.

Current targets:

- newspaper article
- internet article
- calendar article

Typical usage:

```bash
pubble-media article.md --upload --json
```

## Current editorial workflow

Typical personal workflow:

```text
Clipboard/source text
→ cleantext or AI rewrite
→ article in Neovim
→ articlemeta or articlemeta --calendar
→ pubble-send --create --write-ids
→ pubble-media --upload
```

In Neovim this currently maps roughly to:

- add newspaper metadata
- add calendar metadata and text
- send content to Pubble

## Dropzone for images

Current image dropzone:

```text
~/Desktop/Pubble Inbox
```

Images should be placed directly in that folder.

Used subfolders:

```text
~/Desktop/Pubble Inbox/used
~/Desktop/Pubble Inbox/error
```

Supported image extensions:

- `.jpg`
- `.jpeg`
- `.png`
- `.webp`
- `.heic`

## Installation on a different computer

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
pip install pytest
```

## Test suite

Run all tests:

```bash
pytest -q
```

Run a focused subset, for example:

```bash
pytest tests/test_article_meta_frontmatter