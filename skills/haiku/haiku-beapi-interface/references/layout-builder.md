# BLayoutBuilder Reference

## Table of Contents

1. [Overview](#overview)
2. [BLayoutBuilder::Group](#group)
3. [BLayoutBuilder::Grid](#grid)
4. [BLayoutBuilder::Split](#split)
5. [Nesting Builders](#nesting)
6. [Sizing and Alignment](#sizing)
7. [Complete Example](#complete-example)

---

## Overview

`BLayoutBuilder` provides a fluent API for constructing layout hierarchies. Builders nest
via `AddGroup()` / `AddGrid()` / `AddSplit()` and return to the parent with `End()`.

**Window setup:** pass the window pointer as first arg — the builder creates the root layout
and calls `SetLayout()` automatically.

```cpp
#include <LayoutBuilder.h>
```

All spacing/inset values accept these constants:

| Constant | Meaning |
|---|---|
| `B_USE_DEFAULT_SPACING` | Standard gap between widgets |
| `B_USE_SMALL_SPACING` | Tighter gap |
| `B_USE_BIG_SPACING` | Wider gap |
| `B_USE_WINDOW_INSETS` | Standard window edge padding (for SetInsets) |
| `B_USE_SMALL_INSETS` | Tighter window edge padding |
| `B_USE_BIG_INSETS` | Wider window edge padding |

---

## BLayoutBuilder::Group {#group}

Arranges children in a horizontal or vertical line.

### Constructors

```cpp
// Create layout on a window (calls window->SetLayout()):
BLayoutBuilder::Group<>(window, B_VERTICAL, B_USE_DEFAULT_SPACING)

// Create layout on an existing view:
BLayoutBuilder::Group<>(view, B_HORIZONTAL, B_USE_DEFAULT_SPACING)

// Standalone (attach later):
BLayoutBuilder::Group<>(B_VERTICAL, B_USE_DEFAULT_SPACING)
```

### Adding children

```cpp
.Add(BView *view)                    // default weight
.Add(BView *view, float weight)     // weight controls stretch proportion
.Add(BLayoutItem *item)
.Add(BLayoutItem *item, float weight)
```

### Spacing helpers

```cpp
.AddGlue(float weight = 1.0f)       // flexible empty space (like a spring)
.AddStrut(float size)                // fixed empty space in pixels
```

### Insets

```cpp
.SetInsets(float left, float top, float right, float bottom)
.SetInsets(float horizontal, float vertical)
.SetInsets(float all)
```

### Example: vertical toolbar

```cpp
BLayoutBuilder::Group<>(this, B_VERTICAL)
    .SetInsets(B_USE_WINDOW_INSETS)
    .Add(fMenuBar)
    .Add(fToolBar)
    .Add(fContentView, 1.0f)    // stretches to fill
    .Add(fStatusBar);
```

---

## BLayoutBuilder::Grid {#grid}

Arranges children in a row/column grid. Cells are addressed by column and row index.

### Constructors

```cpp
BLayoutBuilder::Grid<>(window, B_USE_DEFAULT_SPACING, B_USE_DEFAULT_SPACING)
BLayoutBuilder::Grid<>(view, float horizontal, float vertical)
BLayoutBuilder::Grid<>(float horizontal = B_USE_DEFAULT_SPACING,
                       float vertical = B_USE_DEFAULT_SPACING)
```

### Adding children

```cpp
.Add(BView *view, int32 column, int32 row)
.Add(BView *view, int32 column, int32 row, int32 columnCount, int32 rowCount)
.Add(BLayoutItem *item, int32 column, int32 row)
.Add(BLayoutItem *item, int32 column, int32 row, int32 columnCount, int32 rowCount)
```

### Column/row weight

```cpp
.SetColumnWeight(int32 column, float weight)
.SetRowWeight(int32 row, float weight)
```

### Example: form layout

```cpp
BLayoutBuilder::Grid<>(this, B_USE_DEFAULT_SPACING, B_USE_SMALL_SPACING)
    .SetInsets(B_USE_WINDOW_INSETS)
    .Add(new BStringView("", "Name:"),  0, 0)
    .Add(fNameControl,                  1, 0)
    .Add(new BStringView("", "Email:"), 0, 1)
    .Add(fEmailControl,                 1, 1)
    .Add(new BStringView("", "Phone:"), 0, 2)
    .Add(fPhoneControl,                 1, 2);
```

---

## BLayoutBuilder::Split {#split}

Creates a resizable split view (like a pane divider).

### Constructors

```cpp
BLayoutBuilder::Split<>(window, B_HORIZONTAL, B_USE_DEFAULT_SPACING)
BLayoutBuilder::Split<>(view, orientation, float spacing)
BLayoutBuilder::Split<>(orientation = B_HORIZONTAL, float spacing = B_USE_DEFAULT_SPACING)
```

### Adding children

```cpp
.Add(BView *view)
.Add(BView *view, float weight)
.Add(BLayoutItem *item)
.Add(BLayoutItem *item, float weight)
```

### Collapsible

```cpp
.SetCollapsible(bool collapsible)
.SetCollapsible(int32 index, bool collapsible)
```

### Example: editor with sidebar

```cpp
BLayoutBuilder::Split<>(this, B_HORIZONTAL)
    .Add(fSidebarScrollView, 0.3f)
    .Add(fEditorView, 0.7f);
```

---

## Nesting Builders {#nesting}

Call `AddGroup()`, `AddGrid()`, or `AddSplit()` to push a nested builder. Call `End()` to
return to the parent.

```cpp
BLayoutBuilder::Group<>(window, B_VERTICAL)
    .SetInsets(B_USE_WINDOW_INSETS)
    .Add(fMenuBar)
    .AddSplit(B_HORIZONTAL, B_USE_DEFAULT_SPACING)       // push split builder
        .Add(fSidebar, 0.25f)
        .AddGroup(B_VERTICAL, B_USE_SMALL_SPACING)       // push group inside split
            .Add(fToolBar)
            .Add(fCanvas, 1.0f)
        .End()                                            // pop back to split
    .End()                                                // pop back to root group
    .Add(fStatusBar);
```

**Nest signatures:**

```cpp
// From Group:
.AddGroup(orientation, float spacing = B_USE_DEFAULT_SPACING, float weight = 1.0f)
.AddGrid(float hSpacing = ..., float vSpacing = ..., float weight = 1.0f)
.AddSplit(orientation, float spacing = ..., float weight = 1.0f)

// From Grid:
.AddGroup(orientation, int32 column, int32 row,
          int32 columnCount = 1, int32 rowCount = 1)
.AddGrid(float hSpacing, float vSpacing,
         int32 column, int32 row, int32 columnCount = 1, int32 rowCount = 1)
```

---

## Sizing and Alignment {#sizing}

Override automatic sizing on any builder:

```cpp
.SetExplicitMinSize(BSize(200, 100))
.SetExplicitMaxSize(BSize(B_SIZE_UNLIMITED, 50))
.SetExplicitPreferredSize(BSize(400, 300))
.SetExplicitAlignment(BAlignment(B_ALIGN_CENTER, B_ALIGN_MIDDLE))
```

For individual views, call the same methods directly:

```cpp
fButton->SetExplicitMinSize(BSize(100, B_SIZE_UNSET));
fTextView->SetExplicitMaxSize(BSize(B_SIZE_UNLIMITED, B_SIZE_UNLIMITED));
```

**Size constants:**

| Constant | Meaning |
|---|---|
| `B_SIZE_UNSET` | No constraint (use intrinsic size) |
| `B_SIZE_UNLIMITED` | Allow unlimited growth |

---

## Complete Example {#complete-example}

A mail-client-style window: menu bar, horizontal split (folder list | message list + preview),
and a status bar.

```cpp
#include <Application.h>
#include <Window.h>
#include <MenuBar.h>
#include <Menu.h>
#include <MenuItem.h>
#include <ListView.h>
#include <ScrollView.h>
#include <TextView.h>
#include <StringView.h>
#include <LayoutBuilder.h>

enum {
    MSG_FOLDER_SELECTED = 'fsel',
    MSG_MESSAGE_SELECTED = 'msel',
};

class MailWindow : public BWindow {
public:
    MailWindow()
        : BWindow(BRect(100, 100, 800, 600), "Mail",
                  B_DOCUMENT_WINDOW,
                  B_AUTO_UPDATE_SIZE_LIMITS | B_QUIT_ON_WINDOW_CLOSE)
    {
        // Menu bar
        BMenuBar *menuBar = new BMenuBar("menubar");
        BMenu *fileMenu = new BMenu("File");
        fileMenu->AddItem(new BMenuItem("Quit",
            new BMessage(B_QUIT_REQUESTED), 'Q'));
        menuBar->AddItem(fileMenu);

        // Folder list (scrollable)
        fFolderList = new BListView("folders");
        fFolderList->SetSelectionMessage(new BMessage(MSG_FOLDER_SELECTED));
        BScrollView *folderScroll = new BScrollView("folderScroll",
            fFolderList, 0, false, true);

        // Message list (scrollable)
        fMessageList = new BListView("messages");
        fMessageList->SetSelectionMessage(new BMessage(MSG_MESSAGE_SELECTED));
        BScrollView *messageScroll = new BScrollView("messageScroll",
            fMessageList, 0, false, true);

        // Preview pane
        fPreview = new BTextView("preview");
        fPreview->MakeEditable(false);
        BScrollView *previewScroll = new BScrollView("previewScroll",
            fPreview, 0, false, true);

        // Status bar
        fStatus = new BStringView("status", "0 messages");

        // Layout
        BLayoutBuilder::Group<>(this, B_VERTICAL, 0)
            .Add(menuBar)
            .AddSplit(B_HORIZONTAL, B_USE_DEFAULT_SPACING)
                .Add(folderScroll, 0.2f)
                .AddSplit(B_VERTICAL, B_USE_DEFAULT_SPACING)
                    .Add(messageScroll, 0.4f)
                    .Add(previewScroll, 0.6f)
                .End()
            .End()
            .AddGroup(B_HORIZONTAL)
                .SetInsets(B_USE_SMALL_INSETS)
                .Add(fStatus)
                .AddGlue()
            .End();
    }

    void MessageReceived(BMessage *msg) override {
        switch (msg->what) {
        case MSG_FOLDER_SELECTED:
            // load messages for selected folder
            break;
        case MSG_MESSAGE_SELECTED:
            // show message in preview
            break;
        default:
            BWindow::MessageReceived(msg);
        }
    }

private:
    BListView   *fFolderList;
    BListView   *fMessageList;
    BTextView   *fPreview;
    BStringView *fStatus;
};
```

### AddChild vs Layout

- **Layout mode:** Use `BLayoutBuilder` and `Add()`. Do NOT mix `AddChild()` with layout — the layout
  owns child management.
- **Traditional mode:** Use `AddChild()` with explicit BRect frames and resizing modes. No layout
  builders.
- **Exception:** `BMenuBar` can be added via the layout builder even though it is traditionally added
  with `AddChild()`.
