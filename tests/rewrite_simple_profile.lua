-- De echte Python CLI met alleen de AI gemockt: ook een oude auto-client
-- krijgt in het nieuwe profiel rechtstreeks artikeltekst, geen JSON-plan.
vim.env.TEXTTOOLS_WRITING_PROFILE = 'eenvoudig-20261021'
local source = 'Lezing over de Kop\n\nKAMPEN - Een fotograaf vertelt over Weerribben-Wieden.\n\nDe lezing begint om 19.30 uur.'
local stub = [=[
from unittest.mock import patch
from texttools.ai_cli import main
def writer(**kw):
    assert 'output_format' not in kw
    assert 'source_hash' not in kw['instructions']
    assert 'Nieuwsbode de Kop' in kw['instructions']
    assert 'onderwerp, landschap' in kw['instructions']
    assert 'KAMPEN - Een fotograaf' in kw['text']
    return kw['text'].replace('KAMPEN - Een fotograaf vertelt over Weerribben-Wieden.',
        '**KAMPEN - Een fotograaf vertelt over Weerribben-Wieden.**')
with patch('texttools.ai_cli.run_ai_edit', side_effect=writer) as call:
    main()
    assert call.call_count == 1
]=]
local result = vim.system({ require('texttools_commands').bin('python'), '-c', stub,
  'krantversie', '--edition', 'K', '--edit-mode', 'auto' },
  { text = true, stdin = source }):wait(5000)
assert(result.code == 0, result.stderr)
assert(result.stdout:find('**KAMPEN -', 1, true))
local normalized = require('ai_text')._normalized_edition_variant(result.stdout)
assert(normalized, 'de nieuwe artikeluitvoer past niet in krantreview')
print('rewrite simple profile: OK')
