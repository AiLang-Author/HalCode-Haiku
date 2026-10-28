---
name: haiku-beapi-interface
description: BeAPI Interface Kit — BWindow, BView, BControl, menus, lists, scroll views, and the layout system. Load when building Haiku OS GUIs, drawing custom views, handling mouse/keyboard input, or laying out widgets. Use whenever Haiku, BeOS, BeAPI, BWindow, BView, BControl, BButton, BTextView, BListView, BMenuBar, Interface Kit, GUI, UI, layout, drawing, or widgets is mentioned.
---

# BeAPI Interface Kit

## SYNOPSIS

```cpp
#include <Application.h>
#include <Window.h>
#include <View.h>
#include <Button.h>
#include <LayoutBuilder.h>
```

The Interface Kit provides all UI classes. Every visible element is a **BView** inside a **BWindow**. BWindow owns a lock and a message loop (it inherits BLooper). The app_server composites drawing.

---

## BWindow

### Construction

```cpp
BWindow(BRect frame, const char *title, window_type type, uint32 flags,
        uint32 workspace = B_CURRENT_WORKSPACE)
BWindow(BRect frame, const char *title, window_look look, window_feel feel,
        uint32 flags, uint32 workspace = B_CURRENT_WORKSPACE)
```

| window_type | Shorthand for look+feel |
|---|---|
| `B_TITLED_WINDOW` | Title bar, close/zoom, normal feel |
| `B_DOCUMENT_WINDOW` | Title bar, resize knob, normal feel |
| `B_MODAL_WINDOW` | No title bar, modal app feel |
| `B_FLOATING_WINDOW` | Small title bar, floating app feel |
| `B_BORDERED_WINDOW` | Plain border, no title bar |

Common flags: `B_NOT_RESIZABLE`, `B_NOT_ZOOMABLE`, `B_NOT_CLOSABLE`, `B_NOT_MINIMIZABLE`, `B_QUIT_ON_WINDOW_CLOSE`, `B_AUTO_UPDATE_SIZE_LIMITS`.

### Lifecycle

```cpp
void Show()                         // makes window visible, starts message loop
void Hide()
virtual void Quit()                 // closes window, deletes it (call from window thread)
virtual bool QuitRequested()        // return true to allow Quit; override for save-on-close
```

**RULE:** Call `PostMessage(B_QUIT_REQUESTED)` from outside the window thread, not `Quit()` directly.

### Locking

```cpp
bool Lock()        // blocks until acquired; REQUIRED before touching views from non-window thread
void Unlock()
```

Every BView operation must happen while the parent window is locked. The window thread auto-locks during hook calls (MessageReceived, Draw, etc.).

### View management

```cpp
void AddChild(BView *child, BView *before = NULL)
bool RemoveChild(BView *child)
BView* FindView(const char *viewName) const
BView* CurrentFocus() const
```

### Positioning

```cpp
void MoveTo(float x, float y)
void ResizeTo(float width, float height)
void CenterOnScreen()
void SetSizeLimits(float minW, float maxW, float minH, float maxH)
```

### Event hooks

```cpp
virtual void MessageReceived(BMessage *message)
virtual void FrameMoved(BPoint newPosition)
virtual void FrameResized(float newWidth, float newHeight)
virtual void WindowActivated(bool focus)
virtual void MenusBeginning()       // called before menus open — update menu state here
```

### Layout integration

```cpp
void SetLayout(BLayout *layout)      // switches window to layout mode
BLayout* GetLayout() const
```

When a layout is set, `B_AUTO_UPDATE_SIZE_LIMITS` should be in the window flags.

---

## BView

### Construction

```cpp
// Traditional (manual positioning):
BView(BRect frame, const char *name, uint32 resizingMode, uint32 flags)

// Layout-aware (Haiku):
BView(const char *name, uint32 flags, BLayout *layout = NULL)
```

### Resizing modes (traditional)

| Constant | Meaning |
|---|---|
| `B_FOLLOW_NONE` | Fixed position |
| `B_FOLLOW_ALL_SIDES` | Stretch with parent |
| `B_FOLLOW_LEFT_RIGHT` | Stretch horizontally |
| `B_FOLLOW_TOP_BOTTOM` | Stretch vertically |
| `B_FOLLOW_LEFT \| B_FOLLOW_TOP` | Anchor top-left (default) |

### Flags

| Flag | Purpose |
|---|---|
| `B_WILL_DRAW` | View implements Draw() — **required** for custom drawing |
| `B_PULSE_NEEDED` | Receive Pulse() at window's pulse rate |
| `B_FRAME_EVENTS` | Receive FrameMoved()/FrameResized() |
| `B_NAVIGABLE` | Reachable via Tab key navigation |
| `B_FULL_UPDATE_ON_RESIZE` | Entire view redrawn on resize, not just new area |
| `B_DRAW_ON_CHILDREN` | DrawAfterChildren() is called |

### Drawing lifecycle

**CRITICAL:** Never call `Draw()` directly. The app_server calls it. To trigger a redraw:

```cpp
void Invalidate()                    // marks entire bounds dirty
void Invalidate(BRect invalRect)     // marks specific rect dirty
```

The app_server coalesces dirty rects and calls:

```cpp
virtual void Draw(BRect updateRect)  // called by app_server — draw here
```

Drawing state:

```cpp
void SetHighColor(rgb_color color)   // foreground color
void SetLowColor(rgb_color color)    // background / pattern fill color
void SetViewColor(rgb_color color)   // auto-erase color (set B_TRANSPARENT_COLOR to disable)
void SetFont(const BFont *font, uint32 mask = B_FONT_ALL)
void SetPenSize(float size)
```

Primitives:

```cpp
void StrokeLine(BPoint start, BPoint end, pattern p = B_SOLID_HIGH)
void StrokeRect(BRect rect, pattern p = B_SOLID_HIGH)
void FillRect(BRect rect, pattern p = B_SOLID_HIGH)
void FillRoundRect(BRect rect, float xRadius, float yRadius, pattern p = B_SOLID_HIGH)
void StrokeEllipse(BPoint center, float xRadius, float yRadius, pattern p = B_SOLID_HIGH)
void FillEllipse(BRect rect, pattern p = B_SOLID_HIGH)
void DrawString(const char *string, BPoint location, escapement_delta *delta = NULL)
void DrawBitmap(const BBitmap *bitmap, BPoint where)
void DrawBitmap(const BBitmap *bitmap, BRect destRect)
```

### Coordinate system

`Bounds()` returns the view's local rectangle (scrolling shifts its origin).
`Frame()` returns the view's rectangle in its parent's coordinates.
`ConvertToScreen()`/`ConvertFromScreen()` convert to/from screen coordinates.

### Attachment hooks

```cpp
virtual void AttachedToWindow()      // view is now in a window — set targets, configure here
virtual void DetachedFromWindow()
virtual void AllAttached()           // all children also attached
virtual void AllDetached()
```

**AttachedToWindow()** is the right place to call `SetTarget()` on child controls, because `Window()` returns non-NULL here.

### Input events

```cpp
virtual void MouseDown(BPoint where)        // where is in view coordinates
virtual void MouseUp(BPoint where)
virtual void MouseMoved(BPoint where, uint32 code, const BMessage *dragMessage)
virtual void KeyDown(const char *bytes, int32 numBytes)
virtual void KeyUp(const char *bytes, int32 numBytes)
void GetMouse(BPoint *location, uint32 *buttons, bool checkQueue = true)
void MakeFocus(bool focus = true)
```

Mouse tracking: call `SetMouseEventMask(B_POINTER_EVENTS, B_LOCK_WINDOW_FOCUS)` inside MouseDown() to receive MouseMoved/MouseUp even when the cursor leaves the view.

### Scrolling

```cpp
void ScrollTo(float x, float y)
void ScrollBy(float dh, float dv)
```

### Hierarchy

```cpp
void AddChild(BView *child, BView *before = NULL)
bool RemoveChild(BView *child)
BView* Parent() const
BView* ChildAt(int32 index) const
BWindow* Window() const             // NULL until AttachedToWindow()
```

---

## BControl (base for all controls)

Inherits **BView** and **BInvoker**. Sends a BMessage to a target when activated.

```cpp
BControl(const char *name, const char *label, BMessage *message, uint32 flags)
```

```cpp
void SetLabel(const char *string)
const char* Label() const
void SetValue(int32 value)          // B_CONTROL_ON or B_CONTROL_OFF
int32 Value() const
void SetEnabled(bool enabled)
bool IsEnabled() const
status_t Invoke(BMessage *message = NULL)    // send message to target
```

### Common controls

| Class | Purpose | Key detail |
|---|---|---|
| `BButton` | Push button | `SetDefault(true)` for Enter-key activation |
| `BCheckBox` | Toggle on/off | Value toggles between B_CONTROL_ON/OFF |
| `BRadioButton` | Exclusive choice | Auto-deselects siblings in same parent |
| `BTextControl` | Label + single-line text field | `Text()`, `SetText()`, `SetModificationMessage()` |
| `BSlider` | Value slider | `SetRange()`, `SetHashMarks()`, `SetHashMarkCount()` |
| `BStringView` | Static text label | `SetText()`, `SetAlignment()` |
| `BStatusBar` | Progress bar | `Update(float delta, const char *text)`, `Reset()` |
| `BColorControl` | Color picker | `ValueAsColor()`, `SetValue(rgb_color)` |

---

## BListView

```cpp
BListView(const char *name,
          list_view_type type = B_SINGLE_SELECTION_LIST,
          uint32 flags = B_WILL_DRAW | B_FRAME_EVENTS | B_NAVIGABLE)
```

| list_view_type | Behavior |
|---|---|
| `B_SINGLE_SELECTION_LIST` | One item selected at a time |
| `B_MULTIPLE_SELECTION_LIST` | Multiple selection via modifier keys |

```cpp
bool AddItem(BListItem *item)
bool AddItem(BListItem *item, int32 atIndex)
BListItem* RemoveItem(int32 index)
BListItem* ItemAt(int32 index) const
int32 CountItems() const
void Select(int32 index, bool extend = false)
bool IsItemSelected(int32 index) const
int32 CurrentSelection(int32 index = 0) const    // iterate: pass 0, 1, 2... until -1
void SetSelectionMessage(BMessage *message)
void SetInvocationMessage(BMessage *message)     // sent on double-click / Enter
void ScrollToSelection()
void MakeEmpty()
```

**BOutlineListView** adds hierarchy: `AddUnder(BListItem *item, BListItem *superItem)`.

List items are **BStringItem** (simple text) or custom **BListItem** subclasses (override `DrawItem()`).

---

## Menu System

### BMenuBar

```cpp
BMenuBar(const char *name,
         menu_layout layout = B_ITEMS_IN_ROW,
         uint32 flags = B_WILL_DRAW | B_FRAME_EVENTS)
```

Typically set as the window's key menu bar: `window->SetKeyMenuBar(menuBar)`.

### BMenu

```cpp
BMenu(const char *name, menu_layout layout = B_ITEMS_IN_COLUMN)
bool AddItem(BMenuItem *item)
bool AddItem(BMenu *submenu)         // submenu becomes a menu item automatically
bool AddSeparatorItem()
bool RemoveItem(BMenuItem *item)
BMenuItem* FindItem(uint32 command) const
BMenuItem* FindItem(const char *label) const
status_t SetTargetForItems(BHandler *target)
```

### BMenuItem

```cpp
BMenuItem(const char *label, BMessage *message, char shortcut = 0,
          uint32 modifiers = 0)
void SetLabel(const char *label)
const char* Label() const
void SetEnabled(bool enabled)
void SetMarked(bool marked)
bool IsMarked() const
```

### BPopUpMenu

```cpp
BPopUpMenu(const char *name, bool radioMode = true,
           bool labelFromMarked = true)
BMenuItem* Go(BPoint where, bool autoInvoke = false,
              bool keepOpen = false, bool async = false)
```

Typical pattern: create in MouseDown(), call `Go(ConvertToScreen(where))`.

---

## BScrollView

Wraps a target view and adds scroll bars.

```cpp
// Layout-aware:
BScrollView(const char *name, BView *target, uint32 flags,
            bool horizontal, bool vertical,
            border_style border = B_FANCY_BORDER)

// Traditional:
BScrollView(const char *name, BView *target,
            uint32 resizingMode = B_FOLLOW_LEFT_TOP, uint32 flags = 0,
            bool horizontal = false, bool vertical = false,
            border_style border = B_FANCY_BORDER)
```

```cpp
BScrollBar* ScrollBar(orientation direction) const   // B_HORIZONTAL or B_VERTICAL
```

**Pattern — scrollable list:**
```cpp
BListView *list = new BListView("list");
BScrollView *scroll = new BScrollView("scroll", list, 0, false, true);
parent->AddChild(scroll);    // add the scroll view, NOT the list view
```

---

## Layout System

Haiku's layout system auto-positions views. Use the `BLayoutBuilder` fluent API.

Read **references/layout-builder.md** for full examples and patterns.

### Quick reference

```cpp
BLayoutBuilder::Group<>(window, B_VERTICAL)
    .SetInsets(B_USE_WINDOW_INSETS)
    .Add(menuBar)
    .AddGroup(B_HORIZONTAL)
        .Add(listScrollView, 1.0f)
        .AddGroup(B_VERTICAL)
            .Add(nameControl)
            .Add(emailControl)
            .AddGlue()
            .Add(saveButton)
        .End()
    .End();
```

Key constants:
- `B_USE_DEFAULT_SPACING` — standard inter-widget gap
- `B_USE_WINDOW_INSETS` — standard window edge padding
- `B_USE_SMALL_SPACING`, `B_USE_BIG_SPACING` — variants

---

## Common Patterns

### Minimal window with layout

```cpp
class MyWindow : public BWindow {
public:
    MyWindow()
        : BWindow(BRect(100, 100, 500, 400), "My App",
                  B_TITLED_WINDOW,
                  B_AUTO_UPDATE_SIZE_LIMITS | B_QUIT_ON_WINDOW_CLOSE)
    {
        BButton *button = new BButton("ok", "OK", new BMessage('okok'));

        BLayoutBuilder::Group<>(this, B_VERTICAL)
            .SetInsets(B_USE_WINDOW_INSETS)
            .Add(button);
    }

    void MessageReceived(BMessage *msg) override {
        switch (msg->what) {
        case 'okok':
            // handle OK
            break;
        default:
            BWindow::MessageReceived(msg);
        }
    }
};
```

### Custom drawing view

```cpp
class MyView : public BView {
public:
    MyView()
        : BView("canvas", B_WILL_DRAW | B_FULL_UPDATE_ON_RESIZE) {}

    void Draw(BRect updateRect) override {
        SetHighColor(0, 120, 200);
        FillRect(Bounds());
        SetHighColor(255, 255, 255);
        DrawString("Hello", BPoint(10, 30));
    }
};
```

### Menu bar setup

```cpp
BMenuBar *menuBar = new BMenuBar("menubar");
BMenu *fileMenu = new BMenu("File");
fileMenu->AddItem(new BMenuItem("Open" B_UTF8_ELLIPSIS,
                  new BMessage('open'), 'O'));
fileMenu->AddSeparatorItem();
fileMenu->AddItem(new BMenuItem("Quit",
                  new BMessage(B_QUIT_REQUESTED), 'Q'));
menuBar->AddItem(fileMenu);
```

### Control target in AttachedToWindow

```cpp
void MyView::AttachedToWindow() {
    fButton->SetTarget(this);      // Window() is now valid
    fListView->SetTarget(this);
}
```
