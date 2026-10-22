--!nonstrict
-- Workspace HUD: mango's nine workspaces as a 3x3 grid of equal-size cards,
-- each listing its windows (icon, app, title). Arrow keys move the selection and
-- Enter views it; a click or 1-9 also views a workspace; click a window to
-- focus it; drag a window's icon onto another card to move it there. Window
-- data comes from mmsg each time the panel opens.

local COLUMNS = 3
local WORKSPACES = 9
local MAX_ROWS = 4 -- windows listed per card before "+N more"
local CARD_WIDTH = 320
local CARD_HEIGHT = 210
local DRAG_TYPE = "mango-window"

local workspaces = nil -- index -> { windows = {...} }, nil while loading
local visible = {} -- workspace indexes shown, in grid order
local selected = 1 -- position in `visible`
local active = nil
local iconCache = {}

local function mmsg(...)
  noctalia.runAsync({ "mmsg", ... })
end

local function iconFor(appid)
  if iconCache[appid] == nil then
    iconCache[appid] = noctalia.appIconPath(appid, 32)
      or noctalia.appIconPath(string.lower(appid), 32)
      or false
  end
  return iconCache[appid] or nil
end

local function appName(appid)
  local short = appid:match("([^.]+)$") or appid -- org.gnome.Nautilus -> Nautilus
  return short:sub(1, 1):upper() .. short:sub(2)
end

local function viewWorkspace(index)
  mmsg("dispatch", "view," .. index .. ",0")
  panel.close()
end

local render

local function load()
  noctalia.runAsync({ "sh", "-c", "mmsg get all-clients; echo; mmsg get all-tags" }, function(result)
    local clientsJson, tagsJson = (result.stdout or ""):match("^(.-)\n(.*)$")
    local clients = noctalia.json.decode(clientsJson or "")
    local tags = noctalia.json.decode(tagsJson or "")

    local list = {}
    for i = 1, WORKSPACES do
      list[i] = { windows = {} }
    end
    for _, c in ipairs((type(clients) == "table" and clients.clients) or {}) do
      if not c.is_scratchpad then
        for _, t in ipairs(c.tags or {}) do
          if list[t] then
            table.insert(list[t].windows, { id = c.id, appid = c.appid or "", title = c.title or "", focused = c.is_focused })
          end
        end
      end
    end
    active = nil
    for _, mon in ipairs((type(tags) == "table" and tags.all_tags) or {}) do
      for _, t in ipairs(mon.tags or {}) do
        if t.is_active and active == nil then active = t.index end
      end
    end
    workspaces = list

    -- Keep the selection on the same workspace across reloads (e.g. after a
    -- drop); otherwise start on the current one.
    local keep = visible[selected]
    visible = {}
    for i = 1, WORKSPACES do
      table.insert(visible, i)
    end
    selected = 1
    for pos, index in ipairs(visible) do
      if index == (keep or active) then selected = pos end
    end
    render()
  end, 3000)
end

local function windowRow(win)
  local path = iconFor(win.appid)
  local icon = path and ui.image({ path = path, width = 22, height = 22, fit = "contain" })
    or ui.glyph({ name = "app-window", size = 20, color = "on_surface_variant" })
  return ui.row({
    key = "win-" .. win.id,
    gap = 10,
    align = "center",
    paddingH = 6,
    paddingV = 4,
    radius = 8,
    fill = win.focused and "primary/0.18" or nil,
    onClick = function()
      mmsg("dispatch", "focusid", "client," .. win.id)
      panel.close()
    end,
  }, {
    -- The icon is the drag handle; the ghost shows the whole row.
    ui.dragSource({
      key = "drag-" .. win.id,
      dragType = DRAG_TYPE,
      payload = tostring(win.id),
      previewAncestor = 1,
      width = 24,
      height = 24,
      align = "center",
      justify = "center",
      tooltip = "Drag to another workspace",
    }, { icon }),
    ui.column({ flexGrow = 1, gap = 0 }, {
      ui.label({ text = appName(win.appid), fontWeight = "medium", color = "on_surface", maxLines = 1 }),
      ui.label({ text = win.title, fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
    }),
  })
end

local function card(index, isSelected)
  local ws = workspaces[index]
  local isActive = index == active
  local rows = {
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = tostring(index), fontSize = 18, fontWeight = "bold", color = isActive and "primary" or "on_surface" }),
      ui.spacer({ flexGrow = 1 }),
      ui.label({
        text = #ws.windows == 0 and "" or (#ws.windows == 1 and "1 window" or (#ws.windows .. " windows")),
        fontSize = 11,
        color = "on_surface_variant",
      }),
    }),
  }
  for i, win in ipairs(ws.windows) do
    if i > MAX_ROWS then
      table.insert(rows, ui.label({ text = "+" .. (#ws.windows - MAX_ROWS) .. " more", fontSize = 11, color = "on_surface_variant" }))
      break
    end
    table.insert(rows, windowRow(win))
  end
  if #ws.windows == 0 then
    table.insert(rows, ui.label({ text = "Empty", color = "on_surface_variant", opacity = 0.6 }))
  end

  -- Selection (arrow keys) gets the strong outline; the current workspace a tint.
  return ui.dropZone({
    key = "ws-" .. index,
    accepts = { DRAG_TYPE },
    value = tostring(index),
    onDrop = function(payload, value)
      mmsg("dispatch", "tagsilent," .. value, "client," .. payload)
      load()
    end,
    width = CARD_WIDTH,
    height = CARD_HEIGHT,
    radius = 16,
    fill = isActive and "primary/0.12" or "surface_variant/0.35",
    border = isSelected and "primary" or "outline/0.3",
    borderWidth = isSelected and 3 or 1,
  }, {
    ui.column({
      flexGrow = 1,
      gap = 4,
      padding = 12,
      onClick = function() viewWorkspace(index) end,
    }, rows),
  })
end

function render()
  if workspaces == nil then
    panel.render(ui.column({ flexGrow = 1, align = "center", justify = "center" }, {
      ui.label({ text = "Loading workspaces…", color = "on_surface_variant" }),
    }))
    return
  end
  if #visible == 0 then
    panel.render(ui.column({ flexGrow = 1, align = "center", justify = "center" }, {
      ui.label({ text = "No open windows", color = "on_surface_variant" }),
    }))
    return
  end
  local gridRows = {}
  for first = 1, #visible, COLUMNS do
    local cards = {}
    for pos = first, math.min(first + COLUMNS - 1, #visible) do
      table.insert(cards, card(visible[pos], pos == selected))
    end
    table.insert(gridRows, ui.row({ gap = 12, justify = "center" }, cards))
  end
  panel.render(ui.column({ flexGrow = 1, gap = 12, padding = 4, justify = "center" }, gridRows))
end

local MOVES = { Left = -1, Right = 1, Up = -COLUMNS, Down = COLUMNS }

function onOpen(_context)
  workspaces = nil
  render()
  load()
end

function onKey(chord, pressed)
  if not pressed then return end
  local index = tonumber(chord)
  if index then
    viewWorkspace(index)
  elseif chord == "Return" or chord == "KP_Enter" then
    if visible[selected] then viewWorkspace(visible[selected]) end
  elseif MOVES[chord] and #visible > 0 then
    local target = selected + MOVES[chord]
    if target >= 1 and target <= #visible then
      selected = target
      render()
    end
  end
end
