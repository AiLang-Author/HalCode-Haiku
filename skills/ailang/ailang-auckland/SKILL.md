---
name: ailang-auckland
description: Auckland UI layout engine and simplified HTML GUI for Ailang-Self-Hosting Display. Use when working on Library.Auckland*, AucklandBind, AucklandEvent, config/*.html app markup, AppHost, TextRegion draw paths, or widget tags (button, textfield, input, docview, scroll, canvas, etc.).
---

# Auckland Display UI

Load **`ailang/ailang-dev`** first for general AILANG syntax (6-arg ABI, StoreValue, flattened expressions).

Inventory (may be stale — prefer sources): `/home/bob/Ailang-Self-Hosting-/docs/display/AUCKLAND_INVENTORY.md`.

---

## Pipeline

```
config/foo.html
  → HTMLParse (AST)
  → AucklandBind (AKParse_File / AKParse_String)
  → Auckland (AK_Solve + AK_Draw)
  → WinManager content surface
```

Entry point for apps: `AppHost_Open(html_file, action_cb)` in `Librarys/Library.AppHost.ailang`.

---

## File Map — Read Before Writing

| Task | Read first |
|------|------------|
| New widget draw | `UI/Library.Auckland.ailang` → `AK_DrawNode` |
| New HTML attr/tag | `UI/Library.AucklandBind.ailang` → `AKBind_ApplyAttr`, `AKBind_TagNameToAKTag1`/`2` |
| Input/events | `UI/Library.AucklandEvent.ailang` → `AK_HitWalk`, `AK_EventMouse`, `AK_IsHittable` |
| Text rendering | `UI/Library.TextRegion.ailang` |
| App from HTML | `Librarys/Library.AppHost.ailang` |
| Example markup | `config/settings.html`, `config/notepad.html` |

Core paths (repo root `Ailang-Self-Hosting-`):
- `Librarys/Display/UI/Library.Auckland.ailang`
- `Librarys/Display/UI/Library.AucklandBind.ailang`
- `Librarys/Display/UI/Library.AucklandEvent.ailang`

---

## AKContext Rules

- Always pass `ctx: LinkagePool.AKContext` — use `ctx@field` or accessor functions (`AK_GetDesignW`, etc.).
- Nodes: `AK_CreateNode(ctx, tag)` → `AK_AddChild(ctx, parent, child)` → `AK_SetRoot(ctx, root)`.
- Fields via `AK_Get(ctx, node, AKF.*)` / `AK_Set` and `AK_ExtraGet` / `AK_ExtraSet`.
- Render: `AK_Draw(ctx, canvas, canvas_w, canvas_h)` calls solve then draw.
- Mark dirty after dynamic changes: `AK_Set(ctx, node, AKF.DIRTY, 1)`.
- Lookup: `AK_FindById(ctx, id_str)` exists in `Library.Auckland.ailang` (DJB2 hash, node index or -1).

---

## Widget Status

**Working (drawn):** `window`, `group`, `panel`, `button`, `label`, `separator`, `checkbox`, `textfield`, `input` (AKTag 23), `docview` (AKTag 24), `scroll` (draw path + clip/offset/scrollbars), `spacer` (layout only).

**Stubs (tag exists, no/full draw):** `tabs`, `tab`, `text`, `display`, `radio`, `slider`, `progress`, `image`, `canvas`, `theme`. `flow` is parsed, not laid out.

Do not assume stubbed tags work — verify `AK_DrawNode` has an `EqualTo(tag, AKTag.X)` block.

---

## Canonical Patterns

### Bind a color attribute (AucklandBind)

Attrs are split: `AKBind_ApplyLayout` / `ApplySize` / `ApplyStyle` / `ApplyWindow` / `ApplyTextWidget` / `ApplyInput` / `ApplyDocViewAttr`. Tag names: `AKBind_TagNameToAKTag` → `TagNameToAKTag1` then `2`.

```
cmp_bg = StringCompare(attr_name, "bg")
IfCondition EqualTo(cmp_bg, 0) ThenBlock: {
    bgc = AKBind_ParseColor(attr_val)
    AK_ExtraSet(ctx, ak_node, AKExtra.COLOR_BG, bgc)
    ReturnValue(0)
}
```

Colors: `#RGB`, `#RRGGBB`, `#RRGGBBAA` → `TVG_PackColor` / packed BGRA.

### Draw a filled widget (Auckland)

Use **`AK_FillRect`**, not `Draw_Pix_FillRect` (that is the clip wrapper's callee).

```
IfCondition EqualTo(tag, AKTag.BUTTON) ThenBlock: {
    bg = AK_ExtraGet(ctx, node, AKExtra.COLOR_BG)
    IfCondition EqualTo(bg, 0) ThenBlock: { bg = Theme.ak_btn_bg }
    AK_FillRect(ctx, sx, sy, sw, sh, bg)
    // ... border, TextRegion label, state handling ...
}
```

Use `Theme.*` and `UIScale.*` defaults — not hardcoded pixels.

### Button state handling

States: `AKState.NORMAL`, `HOVER`, `PRESSED`, `DISABLED`. Set via `AK_SetState` in AucklandEvent. Lighten/darken BGRA channels for hover/press (see existing BUTTON block).

### Text label

```
tr = AK_ExtraGet(ctx, node, AKExtra.TR_HANDLE)
IfCondition LessThan(tr, 0) ThenBlock: {
    tr = TextRegion_Create(canvas, sx, sy, sw, sh)
    AK_ExtraSet(ctx, node, AKExtra.TR_HANDLE, tr)
}
TextRegion_SetRect(tr, sx, sy, sw, sh)
TextRegion_SetColor(tr, fg)
TextRegion_Render(tr, sp, sl)
```

### HTML app window root

```html
<window title="My App" design-w="640" design-h="480" toolbar="about">
  <group layout="vbox" gap="8" padding="8" bg="#0E1730">
    <button label="OK" action="app.ok" height="28"/>
  </group>
</window>
```

Toolbar modes: `none`, `about`, `file`, `full`, `browser`. Optional `addressbar="true"`.

---

## Layout

| `layout` | Status |
|----------|--------|
| `vbox` | measure + layout + grow |
| `hbox` | measure + layout + grow |
| `grid` | measure + layout (`cols` attr) |
| `flow` | parsed only — **not implemented** |

Sizing attrs in bind: `width`, `height`, `min-w`, `min-h`, `max-w`, `max-h`, `grow`, `shrink`, `gap`, `padding`, `pad-t/r/b/l`, `cols`, `align`.

**Not wired:** `justify` (constants exist in `AKJustify`).

Scale: design-space values → `AK_Scale(ctx, val)` at layout/draw time.

---

## Events & Actions

- Mouse: `AK_EventMouse(ctx, mx, my, ev, data)` — **5 args**. `AKMouseEv.MOVE/DOWN/UP/WHEEL`. Wheel uses `data`.
- Click on hittable node → `AK_FireAction` → `action` string → `ctx@action_cb` via `CallIndirect`.
- Hittable (`AK_IsHittable`): `button`, `checkbox`, `textfield`, `input`, `docview`, `scroll`, plus `label`, `text`, `radio`, `slider`, `canvas`, `display`. Requires `AKFlags.ENABLED`.
- Keyboard: `AK_EventKey` → focused `TEXTFIELD` + `INPUT` + `DOCVIEW` (`DocView_Key`). Fallback walks for first TEXTFIELD.

---

## Known Gaps (expansion backlog)

1. Draw stubs: `image`, `canvas`, `radio`, `slider`, `progress`, `text`, `display`, `tabs`
2. `justify` + `flow` layout
3. Per-node `font-size` (parsed, not used in draw)
4. Auckland calls `SynColor_Line` without explicit `LibraryImport.Display.UI.SyntaxColor`
5. AucklandBind is compile-time HTML→tree, not live data binding

Priority: image/canvas → form controls → justify/flow → tabs.

---

## Workflow Checklist

Before editing Auckland code:

1. `Skills read ailang/ailang-dev`
2. `Skills read ailang/ailang-auckland` (this file)
3. Prefer live sources over the inventory markdown
4. Read 2 existing functions in the same file — match style exactly
5. After edits: `analyzer.x <abs-path-to-entry.ailang>`

---

## Imports Reference

```
LibraryImport.Display.UI.Auckland
LibraryImport.Display.UI.AucklandBind
LibraryImport.Display.UI.AucklandEvent
LibraryImport.Display.UI.TextRegion
LibraryImport.Display.Content.HTMLParse
LibraryImport.Display.Theme.UITheme
LibraryImport.Display.Theme.UIScale
LibraryImport.TextBuffer
```

Render deps (via Auckland): `DSurface`, `DDrawPixel`, `SurfaceBlit`, `Fonts`, `VIF`.

---

## Anti-Patterns

- Do not use C/Python control flow — use `IfCondition`/`ThenBlock`/`ElseBlock`, `WhileLoop`.
- Do not pass more than 6 args to `SystemCall`.
- Do not add `LibraryImport` without checking the link graph (SysDisplay pulls the full tree).
- Do not implement a new HTML tag without: `AKTag` (if new), `AKBind_TagNameToAKTag1`/`2`, `AKBind_ApplyAttr` split handlers, `AK_DrawNode` case, and optionally `AK_HitWalk` + `AK_MeasureNode`.
- Do not call `Draw_Pix_FillRect` from widget draw — use `AK_FillRect`.

Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. SCSL.
