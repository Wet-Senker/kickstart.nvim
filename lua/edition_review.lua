local M = {}

local config = {}
local review_buffers = {}

local STATUS_LABELS = {
  approved = "goedgekeurd",
  review = "controleren",
  stale = "verouderd",
}

local function notify(message, level)
  if config.notify then
    config.notify(message, level)
  else
    vim.notify(message, level)
  end
end

local function buffer_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local function markdown_lines(markdown)
  local normalized = (markdown or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  normalized = normalized:gsub("\n$", "")
  if normalized == "" then return {} end
  return vim.split(normalized, "\n", { plain = true })
end

local function source_buffer(target_buf)
  local target = target_buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(target) then return nil end
  local source = vim.b[target].edition_source_buf
  if type(source) == "number" and vim.api.nvim_buf_is_valid(source) then
    return source
  end
  return target
end

local function review_entry(review_buf)
  if not review_buf or not vim.api.nvim_buf_is_valid(review_buf) then return nil end
  local source = vim.b[review_buf].edition_source_buf
  local code = vim.b[review_buf].edition_code
  if type(source) ~= "number" or not vim.api.nvim_buf_is_valid(source)
      or type(code) ~= "string" or code == "" then
    return nil
  end
  return source, code
end

local function names_by_code(codes, names)
  local result = {}
  for index, code in ipairs(codes or {}) do
    result[code] = type(names) == "table" and names[index] or code
  end
  return result
end

local function decode_result(result)
  if not result or result.code ~= 0 then
    local message = vim.trim((result and result.stderr) or "")
    return nil, message ~= "" and message or "Editieversieactie mislukt."
  end
  local ok, decoded = pcall(vim.json.decode, result.stdout or "")
  if not ok or type(decoded) ~= "table" or decoded.contract_version ~= 1 then
    return nil, "Editieversieactie gaf geen geldig resultaat."
  end
  return decoded, nil
end

local function default_runner(source_buf, action, payload, done)
  local ok, encoded = pcall(vim.json.encode, payload)
  if not ok then
    done(false, nil, "Editieversie-invoer kon niet als JSON worden opgebouwd.")
    return
  end
  if config.start_job then config.start_job(source_buf) end
  local started, start_error = pcall(vim.system,
    { config.python, "-m", "texttools.edition_versions_cli", action },
    { text = true, stdin = encoded },
    function(result)
      vim.schedule(function()
        local decoded, err = decode_result(result)
        done(decoded ~= nil, decoded, err)
        if config.finish_job then config.finish_job(source_buf) end
      end)
    end
  )
  if not started then
    vim.schedule(function()
      done(false, nil, "Editieversieactie kon niet starten: " .. tostring(start_error))
      if config.finish_job then config.finish_job(source_buf) end
    end)
  end
end

local function run_action(source_buf, action, payload, done)
  local runner = M._runner or default_runner
  runner(source_buf, action, payload, done)
end

local function set_source_markdown(source_buf, markdown, expected_tick)
  if not vim.api.nvim_buf_is_valid(source_buf) then
    return false, "De bronbuffer bestaat niet meer."
  end
  if expected_tick
      and vim.api.nvim_buf_get_changedtick(source_buf) ~= expected_tick then
    return false, "De bronbuffer veranderde tijdens de actie; het late resultaat is niet toegepast."
  end
  vim.api.nvim_buf_set_lines(
    source_buf,
    0,
    -1,
    false,
    markdown_lines(markdown)
  )
  return true, nil
end

local function persist_source(source_buf)
  local name = vim.api.nvim_buf_get_name(source_buf)
  if name == "" or vim.bo[source_buf].buftype ~= "" then
    return false, "De bronbuffer heeft nog geen bestandsnaam; sla hem zelf op."
  end
  local ok, err = pcall(vim.api.nvim_buf_call, source_buf, function()
    vim.cmd("silent write")
  end)
  if not ok then
    return false, "Bronartikel opslaan mislukt: " .. tostring(err)
  end
  return true, nil
end

local function review_name(source_buf, variant, modified)
  local source_name = vim.api.nvim_buf_get_name(source_buf)
  source_name = source_name ~= "" and vim.fs.basename(source_name) or "onopgeslagen artikel"
  local status = modified and "gewijzigd" or (STATUS_LABELS[variant.status] or variant.status)
  return string.format(
    "[Krantversie %s · %s · bron %d] %s",
    variant.code,
    status,
    source_buf,
    source_name
  )
end

local function set_review_name(review_buf, variant)
  if not vim.api.nvim_buf_is_valid(review_buf) then return end
  local source = vim.b[review_buf].edition_source_buf
  if type(source) ~= "number" or not vim.api.nvim_buf_is_valid(source) then return end
  local desired = review_name(source, variant, vim.bo[review_buf].modified)
  if vim.api.nvim_buf_get_name(review_buf) == desired then return end
  pcall(vim.api.nvim_buf_set_name, review_buf, desired)
end

local function remove_review_reference(review_buf)
  for source, entries in pairs(review_buffers) do
    for code, candidate in pairs(entries) do
      if candidate == review_buf then entries[code] = nil end
    end
    if next(entries) == nil then review_buffers[source] = nil end
  end
end

local function configure_review_buffer(review_buf)
  vim.bo[review_buf].buftype = "acwrite"
  vim.bo[review_buf].bufhidden = "hide"
  vim.bo[review_buf].swapfile = false
  vim.bo[review_buf].filetype = "markdown"

  local group = vim.api.nvim_create_augroup(
    "TexttoolsEditionReview" .. review_buf,
    { clear = true }
  )
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = review_buf,
    callback = function() M.sync(review_buf, false) end,
  })
  vim.api.nvim_create_autocmd("BufModifiedSet", {
    group = group,
    buffer = review_buf,
    callback = function()
      local variant = vim.b[review_buf].edition_variant
      if type(variant) == "table" then set_review_name(review_buf, variant) end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = review_buf,
    once = true,
    callback = function() remove_review_reference(review_buf) end,
  })

  vim.keymap.set("n", "<leader>aG", function() M.approve(review_buf) end, {
    buffer = review_buf,
    desc = "Huidige krantversie opslaan en goedkeuren",
  })
  vim.keymap.set("n", "<leader>aV", function() M.show(review_buf) end, {
    buffer = review_buf,
    desc = "Overzicht van krantversies openen",
  })
  vim.keymap.set("n", "<leader>aw", function()
    local source = source_buffer(review_buf)
    if vim.bo[review_buf].modified then
      vim.notify(
        "Deze krantversie heeft onopgeslagen wijzigingen. Gebruik eerst :w en keur haar goed.",
        vim.log.levels.ERROR
      )
      return
    end
    if config.send and source then config.send(source) end
  end, {
    buffer = review_buf,
    desc = "Bronartikel met alle goedgekeurde krantversies verzenden",
  })
end

local function refresh_review_buffers(source_buf, workspace, options)
  options = options or {}
  local entries = review_buffers[source_buf] or {}
  review_buffers[source_buf] = entries
  local present = {}
  local ordered = {}

  for _, variant in ipairs(workspace.variants or {}) do
    present[variant.code] = true
    local review_buf = entries[variant.code]
    if not review_buf or not vim.api.nvim_buf_is_valid(review_buf) then
      review_buf = vim.api.nvim_create_buf(true, true)
      entries[variant.code] = review_buf
      vim.b[review_buf].edition_source_buf = source_buf
      vim.b[review_buf].edition_code = variant.code
      configure_review_buffer(review_buf)
    end

    local may_replace = options.force == true or not vim.bo[review_buf].modified
    if may_replace then
      vim.api.nvim_buf_set_lines(
        review_buf,
        0,
        -1,
        false,
        markdown_lines(variant.content)
      )
      vim.bo[review_buf].modified = false
    end
    vim.b[review_buf].edition_variant = variant
    set_review_name(review_buf, variant)
    table.insert(ordered, review_buf)
  end

  for code, review_buf in pairs(entries) do
    if not present[code] then
      entries[code] = nil
      if vim.api.nvim_buf_is_valid(review_buf) and not vim.bo[review_buf].modified then
        pcall(vim.api.nvim_buf_delete, review_buf, { force = true })
      end
    end
  end
  vim.b[source_buf].edition_workspace_ready = workspace.ready == true
  vim.b[source_buf].edition_workspace_source_stale = workspace.source_stale == true
  return ordered
end

local function next_pending_buffer(source_buf, workspace, current_code)
  local entries = review_buffers[source_buf] or {}
  local found_current = false
  for _, variant in ipairs(workspace.variants or {}) do
    if variant.code == current_code then
      found_current = true
    elseif found_current and variant.status ~= "approved" then
      return entries[variant.code]
    end
  end
  for _, variant in ipairs(workspace.variants or {}) do
    if variant.status ~= "approved" and variant.code ~= current_code then
      return entries[variant.code]
    end
  end
  return nil
end

function M.create_workspace(source_buf, expected_source, codes, names, variants, done)
  if not vim.api.nvim_buf_is_valid(source_buf) then
    if done then done(false) end
    return
  end
  local function attempt(retries_left)
    local source_tick = vim.api.nvim_buf_get_changedtick(source_buf)
    run_action(source_buf, "create", {
      markdown = buffer_text(source_buf),
      expected_source = expected_source,
      editions = codes,
      names = names_by_code(codes, names),
      variants = variants,
    }, function(ok, result, err)
      if not ok then
        notify(err or "Krantversies konden niet worden opgeslagen.", vim.log.levels.ERROR)
        if done then done(false) end
        return
      end
      if vim.api.nvim_buf_get_changedtick(source_buf) ~= source_tick
          and retries_left > 0 then
        attempt(retries_left - 1)
        return
      end
      local applied, apply_err = set_source_markdown(
        source_buf,
        result.markdown,
        source_tick
      )
      if not applied then
        notify(apply_err, vim.log.levels.ERROR)
        if done then done(false) end
        return
      end
      local buffers = refresh_review_buffers(source_buf, result.workspace, { force = true })
      if buffers[1] and vim.api.nvim_buf_is_valid(buffers[1]) then
        vim.api.nvim_set_current_buf(buffers[1])
      end
      notify(
        "Aparte krantversies staan in eigen buffers. Controleer elke tekst en keur goed met <leader>aG.",
        vim.log.levels.INFO
      )
      if done then done(true, result.workspace) end
    end)
  end
  attempt(1)
end

function M.sync(review_buf, approve, done)
  local source_buf, code = review_entry(review_buf)
  if not source_buf then
    vim.notify("Dit is geen actieve krantversiebuffer.", vim.log.levels.ERROR)
    if done then done(false) end
    return
  end
  if vim.b[review_buf].edition_sync_in_progress then
    notify("Deze krantversie wordt al gesynchroniseerd.", vim.log.levels.INFO)
    if done then done(false) end
    return
  end
  vim.b[review_buf].edition_sync_in_progress = true
  local review_tick = vim.api.nvim_buf_get_changedtick(review_buf)
  local content = buffer_text(review_buf)
  local function finish(ok)
    vim.b[review_buf].edition_sync_in_progress = false
    if done then done(ok) end
  end
  local function attempt(retries_left)
    local source_tick = vim.api.nvim_buf_get_changedtick(source_buf)
    run_action(source_buf, "update", {
      markdown = buffer_text(source_buf),
      edition = code,
      content = content,
      approve = approve == true,
    }, function(ok, result, err)
      if not ok then
        notify(err or "Krantversie synchroniseren mislukt.", vim.log.levels.ERROR)
        finish(false)
        return
      end
      if not vim.api.nvim_buf_is_valid(review_buf)
          or vim.api.nvim_buf_get_changedtick(review_buf) ~= review_tick then
        notify(
          "De krantversiebuffer veranderde tijdens het opslaan; het late resultaat is niet toegepast.",
          vim.log.levels.ERROR
        )
        finish(false)
        return
      end
      if vim.api.nvim_buf_get_changedtick(source_buf) ~= source_tick
          and retries_left > 0 then
        attempt(retries_left - 1)
        return
      end
      local applied, apply_err = set_source_markdown(source_buf, result.markdown, source_tick)
      if not applied then
        notify(apply_err, vim.log.levels.ERROR)
        finish(false)
        return
      end
      vim.bo[review_buf].modified = false
      refresh_review_buffers(source_buf, result.workspace)
      local saved, save_err = persist_source(source_buf)
      if not saved then notify(save_err, vim.log.levels.WARN) end

      if approve then
        if result.workspace.ready then
          notify("Alle krantversies zijn goedgekeurd en verzendklaar.", vim.log.levels.INFO)
        else
          notify("Krantversie " .. code .. " is goedgekeurd.", vim.log.levels.INFO)
          local next_buf = next_pending_buffer(source_buf, result.workspace, code)
          if next_buf and vim.api.nvim_buf_is_valid(next_buf) then
            vim.api.nvim_set_current_buf(next_buf)
          end
        end
      else
        notify(
          "Krantversie " .. code .. " is opgeslagen en moet nog worden goedgekeurd.",
          vim.log.levels.INFO
        )
      end
      vim.b[review_buf].edition_sync_in_progress = false
      if done then done(true, result.workspace) end
    end)
  end
  attempt(1)
end

function M.approve(target_buf)
  local review_buf = target_buf or vim.api.nvim_get_current_buf()
  if not review_entry(review_buf) then
    vim.notify(
      "Open eerst een krantversiebuffer met :Krantversies.",
      vim.log.levels.ERROR
    )
    return
  end
  M.sync(review_buf, true)
end

local function show_selector(source_buf, workspace)
  local entries = review_buffers[source_buf] or {}
  local items = {
    { kind = "source", label = "BRON — gedeelde tekst, wordt niet gepubliceerd" },
  }
  for _, variant in ipairs(workspace.variants or {}) do
    local marker = variant.status == "approved" and "✓"
      or (variant.status == "stale" and "!" or "·")
    table.insert(items, {
      kind = "variant",
      code = variant.code,
      label = string.format(
        "%s %-3s %-22s %s",
        marker,
        variant.code,
        variant.name or variant.code,
        STATUS_LABELS[variant.status] or variant.status
      ),
    })
  end
  vim.ui.select(items, {
    prompt = "Krantversies:",
    format_item = function(item) return item.label end,
  }, function(choice)
    if not choice then return end
    if choice.kind == "source" then
      vim.api.nvim_set_current_buf(source_buf)
      return
    end
    local review_buf = entries[choice.code]
    if review_buf and vim.api.nvim_buf_is_valid(review_buf) then
      vim.api.nvim_set_current_buf(review_buf)
    end
  end)
end

local function migrate_legacy(source_buf)
  if not config.resolve_editions then
    notify("Oude krantversies kunnen niet worden gemigreerd.", vim.log.levels.ERROR)
    return
  end
  if vim.fn.confirm(
      "Dit artikel gebruikt het oude versieformaat. Omzetten naar losse reviewbuffers? Alle versies moeten daarna eenmalig worden goedgekeurd.",
      "&Omzetten\n&Annuleren",
      1
    ) ~= 1 then
    return
  end
  local markdown = buffer_text(source_buf)
  config.resolve_editions(source_buf, markdown, function(resolved)
    if not resolved or type(resolved.editions) ~= "table" then
      notify("Edities voor de oude krantversies konden niet worden bepaald.", vim.log.levels.ERROR)
      return
    end
    local tick = vim.api.nvim_buf_get_changedtick(source_buf)
    run_action(source_buf, "migrate", {
      markdown = markdown,
      editions = resolved.editions,
      names = names_by_code(resolved.editions, resolved.names),
    }, function(ok, result, err)
      if not ok then
        notify(err or "Migreren van oude krantversies mislukt.", vim.log.levels.ERROR)
        return
      end
      local applied, apply_err = set_source_markdown(source_buf, result.markdown, tick)
      if not applied then
        notify(apply_err, vim.log.levels.ERROR)
        return
      end
      refresh_review_buffers(source_buf, result.workspace, { force = true })
      persist_source(source_buf)
      show_selector(source_buf, result.workspace)
    end)
  end)
end

function M.show(target_buf)
  local source_buf = source_buffer(target_buf)
  if not source_buf then return end
  local tick = vim.api.nvim_buf_get_changedtick(source_buf)
  run_action(source_buf, "status", { markdown = buffer_text(source_buf) }, function(ok, result, err)
    if not ok then
      notify(err or "Krantversies konden niet worden gelezen.", vim.log.levels.ERROR)
      return
    end
    if vim.api.nvim_buf_get_changedtick(source_buf) ~= tick then
      notify("De bronbuffer veranderde tijdens het openen van de versies.", vim.log.levels.ERROR)
      return
    end
    if result.legacy then
      if result.has_section then
        migrate_legacy(source_buf)
      else
        notify("Dit artikel heeft geen aparte krantversies.", vim.log.levels.INFO)
      end
      return
    end
    refresh_review_buffers(source_buf, result.workspace)
    show_selector(source_buf, result.workspace)
  end)
end

function M.has_unsaved(source_buf)
  for _, review_buf in pairs(review_buffers[source_buf] or {}) do
    if vim.api.nvim_buf_is_valid(review_buf) and vim.bo[review_buf].modified then
      return true
    end
  end
  return false
end

function M.close(source_buf, force)
  local entries = review_buffers[source_buf]
  if not entries then return true end
  if not force and M.has_unsaved(source_buf) then
    return false
  end
  review_buffers[source_buf] = nil
  for _, review_buf in pairs(entries) do
    if vim.api.nvim_buf_is_valid(review_buf) then
      pcall(vim.api.nvim_buf_delete, review_buf, { force = force == true })
    end
  end
  return true
end

function M.setup(options)
  config = options or {}
  vim.api.nvim_create_user_command("Krantversies", function()
    M.show(vim.api.nvim_get_current_buf())
  end, { desc = "Krantversies en reviewstatus openen", force = true })
  vim.api.nvim_create_user_command("KrantversieGoedkeuren", function()
    M.approve(vim.api.nvim_get_current_buf())
  end, { desc = "Huidige krantversie opslaan en goedkeuren", force = true })
  vim.keymap.set("n", "<leader>aV", function()
    M.show(vim.api.nvim_get_current_buf())
  end, { desc = "Krantversies en reviewstatus openen" })
  return M
end

M._review_buffers = review_buffers
M._refresh_review_buffers = refresh_review_buffers
M._source_buffer = source_buffer

return M
