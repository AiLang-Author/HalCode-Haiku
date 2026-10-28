/* halcode_shell_haiku — native Haiku window for HalCode.
 *
 * The desk (halcode_desk.x) is a Linux ELF. The Haiku Linux bridge
 * runs it. This process is only the window: it blits the desk's
 * framebuffer through app_server and writes the same state files
 * the GTK shell wrote.
 *
 *   meta.bin   int32 width, height, pitch
 *   frame.raw  BGRA, pitch * height
 *   gen.txt    generation; reload the bitmap when it changes
 *   ptr.txt    "d|m|u|w|W x y" in frame pixels (appended)
 *   keys.txt   one command line (replaced)
 *   cmd.txt    "quit"
 *   paste.txt  clipboard text
 *   copy.txt   desk text to publish on the clipboard
 *
 *   g++ -O2 -o halcode_shell_haiku halcode_shell_haiku.cxx -lbe
 *   HALCODE_APP_STATE=/tmp/halcode_app ./halcode_shell_haiku
 *
 * Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.
 */
#ifndef __HAIKU__
#error halcode_shell_haiku.cxx is the Haiku Interface Kit window. Build on Haiku: g++ -O2 -o halcode_shell_haiku halcode_shell_haiku.cxx -lbe
#endif

#include <Alert.h>
#include <Application.h>
#include <Bitmap.h>
#include <Clipboard.h>
#include <Menu.h>
#include <MenuBar.h>
#include <MenuItem.h>
#include <MessageRunner.h>
#include <PopUpMenu.h>
#include <Screen.h>
#include <View.h>
#include <Window.h>

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

enum {
    MSG_POLL = 'poll',
    MSG_QUIT = 'quit',
    MSG_COPY = 'copy',
    MSG_PASTE = 'past',
    MSG_ALL = 'sall',
    MSG_HELP = 'help'
};

static char g_dir[512];
static char path_meta[600], path_frame[600], path_gen[600];
static char path_ptr[600], path_cmd[600], path_keys[600];
static char path_paste[600], path_copy[600];

static void paths_init(const char *dir) {
    snprintf(g_dir, sizeof g_dir, "%s", dir);
    snprintf(path_meta, sizeof path_meta, "%s/meta.bin", dir);
    snprintf(path_frame, sizeof path_frame, "%s/frame.raw", dir);
    snprintf(path_gen, sizeof path_gen, "%s/gen.txt", dir);
    snprintf(path_ptr, sizeof path_ptr, "%s/ptr.txt", dir);
    snprintf(path_cmd, sizeof path_cmd, "%s/cmd.txt", dir);
    snprintf(path_keys, sizeof path_keys, "%s/keys.txt", dir);
    snprintf(path_paste, sizeof path_paste, "%s/paste.txt", dir);
    snprintf(path_copy, sizeof path_copy, "%s/copy.txt", dir);
}

static void write_line(const char *path, const char *s) {
    char tmp[640];
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    FILE *f = fopen(tmp, "w");
    if (!f) return;
    fputs(s, f);
    fputc('\n', f);
    fclose(f);
    rename(tmp, path);
}

static void write_cmd(const char *s) { write_line(path_cmd, s); }

static void write_ptr(const char *kind, int fx, int fy, int fw, int fh) {
    char buf[64];
    struct stat st;
    FILE *pf;
    if (fw < 16) fw = 1100;
    if (fh < 16) fh = 720;
    if (fx < 0) fx = 0;
    if (fy < 0) fy = 0;
    if (fx >= fw) fx = fw - 1;
    if (fy >= fh) fy = fh - 1;
    if (kind[0] == 'm' && stat(path_ptr, &st) == 0 && st.st_size > 400)
        return;
    snprintf(buf, sizeof buf, "%s %d %d\n", kind, fx, fy);
    pf = fopen(path_ptr, "a");
    if (!pf) return;
    fputs(buf, pf);
    fclose(pf);
}

static int read_gen(void) {
    FILE *f = fopen(path_gen, "r");
    int g = -1;
    if (!f) return -1;
    if (fscanf(f, "%d", &g) != 1) g = -1;
    fclose(f);
    return g;
}

static void publish_copy(void) {
    FILE *cf = fopen(path_copy, "rb");
    long sz;
    char *buf;
    if (!cf) return;
    fseek(cf, 0, SEEK_END);
    sz = ftell(cf);
    fseek(cf, 0, SEEK_SET);
    buf = NULL;
    if (sz > 0 && sz < 1024L * 1024L)
        buf = (char *)malloc((size_t)sz + 1);
    if (buf && fread(buf, 1, (size_t)sz, cf) == (size_t)sz) {
        buf[sz] = 0;
        if (be_clipboard->Lock()) {
            be_clipboard->Clear();
            BMessage *data = be_clipboard->Data();
            if (data)
                data->AddData("text/plain", B_MIME_TYPE, buf, (ssize_t)sz);
            be_clipboard->Commit();
            be_clipboard->Unlock();
        }
    }
    free(buf);
    fclose(cf);
    unlink(path_copy);
}

static void do_paste(void) {
    const char *text = NULL;
    ssize_t len = 0;
    if (!be_clipboard->Lock()) return;
    BMessage *data = be_clipboard->Data();
    if (data)
        data->FindData("text/plain", B_MIME_TYPE, (const void **)&text, &len);
    if (text && len > 0) {
        FILE *f = fopen(path_paste, "w");
        if (f) {
            fwrite(text, 1, (size_t)len, f);
            fclose(f);
        }
    }
    be_clipboard->Unlock();
}

class HalView : public BView {
public:
    HalView(BRect frame)
        : BView(frame, "halcode", B_FOLLOW_ALL, B_WILL_DRAW | B_FRAME_EVENTS | B_NAVIGABLE),
          fBitmap(NULL), fW(1100), fH(720), fGen(-1), fTracking(false) {
        SetViewColor(14, 18, 24);
    }

    ~HalView() { delete fBitmap; }

    void Poll() {
        int g = read_gen();
        if (g != fGen)
            LoadFrame();
        publish_copy();
    }

    void Draw(BRect) {
        SetHighColor(14, 18, 24);
        FillRect(Bounds());
        if (!fBitmap) {
            SetHighColor(140, 158, 184);
            DrawString("waiting for the desk frame (meta.bin / frame.raw / gen.txt)",
                       BPoint(24, 40));
            return;
        }
        DrawBitmap(fBitmap, fBitmap->Bounds(), Bounds());
    }

    void MouseDown(BPoint where) {
        MakeFocus(true);
        uint32 buttons = 0;
        GetMouse(&where, &buttons);
        int fx, fy;
        ToFrame(where, &fx, &fy);
        if (buttons & B_SECONDARY_MOUSE_BUTTON) {
            BPopUpMenu menu("edit");
            menu.AddItem(new BMenuItem("Copy", NULL));
            menu.AddItem(new BMenuItem("Paste", NULL));
            BMenuItem *item = menu.Go(ConvertToScreen(where), false);
            if (item && strcmp(item->Label(), "Paste") == 0)
                do_paste();
            else if (item)
                write_line(path_keys, "y");
            return;
        }
        if (!(buttons & B_PRIMARY_MOUSE_BUTTON))
            return;
        fTracking = true;
        write_ptr("d", fx, fy, fW, fH);
        SetMouseEventMask(B_POINTER_EVENTS, B_LOCK_WINDOW_FOCUS);
    }

    void MouseMoved(BPoint where, uint32 transit, const BMessage *msg) {
        (void)transit;
        (void)msg;
        if (!fTracking) return;
        int fx, fy;
        ToFrame(where, &fx, &fy);
        write_ptr("m", fx, fy, fW, fH);
    }

    void MouseUp(BPoint where) {
        if (!fTracking) return;
        int fx, fy;
        fTracking = false;
        ToFrame(where, &fx, &fy);
        write_ptr("u", fx, fy, fW, fH);
    }

    void MessageReceived(BMessage *msg) {
        if (msg->what == B_MOUSE_WHEEL_CHANGED) {
            float dy = 0;
            BPoint where;
            uint32 buttons = 0;
            msg->FindFloat("be:wheel_delta_y", &dy);
            GetMouse(&where, &buttons, false);
            int fx, fy;
            ToFrame(where, &fx, &fy);
            if (dy < 0)
                write_ptr("W", fx, fy, fW, fH);
            else if (dy > 0)
                write_ptr("w", fx, fy, fW, fH);
            return;
        }
        BView::MessageReceived(msg);
    }

    void KeyDown(const char *bytes, int32 numBytes) {
        uint32 mods = modifiers();
        char ch;
        char buf[32];
        if (numBytes < 1) return;
        ch = bytes[0];
        if ((mods & (B_COMMAND_KEY | B_CONTROL_KEY)) && (ch == 'q' || ch == 'Q')) {
            write_cmd("quit");
            be_app->PostMessage(B_QUIT_REQUESTED);
            return;
        }
        if ((mods & (B_COMMAND_KEY | B_CONTROL_KEY)) && (ch == 'v' || ch == 'V')) {
            do_paste();
            return;
        }
        if ((mods & (B_COMMAND_KEY | B_CONTROL_KEY)) && (ch == 'c' || ch == 'C')) {
            write_line(path_keys, "y");
            return;
        }
        if ((mods & (B_COMMAND_KEY | B_CONTROL_KEY)) && (ch == 'a' || ch == 'A')) {
            write_line(path_keys, "a");
            return;
        }
        if (mods & B_SHIFT_KEY) {
            if (ch == B_LEFT_ARROW) { write_line(path_keys, "l"); return; }
            if (ch == B_RIGHT_ARROW) { write_line(path_keys, "m"); return; }
        }
        switch ((unsigned char)ch) {
        case B_RETURN: write_line(path_keys, "r"); return;
        case B_BACKSPACE: write_line(path_keys, "b"); return;
        case B_DELETE: write_line(path_keys, "X"); return;
        case B_LEFT_ARROW: write_line(path_keys, "L"); return;
        case B_RIGHT_ARROW: write_line(path_keys, "R"); return;
        case B_UP_ARROW: write_line(path_keys, "U"); return;
        case B_DOWN_ARROW: write_line(path_keys, "D"); return;
        case B_HOME: write_line(path_keys, "H"); return;
        case B_END: write_line(path_keys, "E"); return;
        case B_TAB: write_line(path_keys, "T"); return;
        case B_ESCAPE: write_line(path_keys, "e"); return;
        default: break;
        }
        if (numBytes == 1 && (unsigned char)ch >= 32 && (unsigned char)ch < 127) {
            snprintf(buf, sizeof buf, "c %u", (unsigned)(unsigned char)ch);
            write_line(path_keys, buf);
            return;
        }
        BView::KeyDown(bytes, numBytes);
    }

private:
    BBitmap *fBitmap;
    int fW, fH, fGen;
    bool fTracking;

    void ToFrame(BPoint where, int *fx, int *fy) {
        BRect b = Bounds();
        float vw = b.Width() + 1;
        float vh = b.Height() + 1;
        if (vw < 1) vw = 1;
        if (vh < 1) vh = 1;
        *fx = (int)(where.x * (float)fW / vw);
        *fy = (int)(where.y * (float)fH / vh);
    }

    bool LoadFrame() {
        FILE *mf = fopen(path_meta, "rb");
        int32_t hdr[3];
        int w, h, pitch;
        size_t sz, got;
        uint8_t *pix;
        FILE *ff;
        if (!mf) return false;
        if (fread(hdr, 4, 3, mf) != 3) {
            fclose(mf);
            return false;
        }
        fclose(mf);
        w = hdr[0];
        h = hdr[1];
        pitch = hdr[2];
        if (w < 16 || h < 16 || pitch < w * 4) return false;
        sz = (size_t)pitch * (size_t)h;
        pix = (uint8_t *)malloc(sz);
        if (!pix) return false;
        ff = fopen(path_frame, "rb");
        if (!ff) {
            free(pix);
            return false;
        }
        got = fread(pix, 1, sz, ff);
        fclose(ff);
        if (got < sz) {
            free(pix);
            return false;
        }
        BBitmap *nb = new BBitmap(BRect(0, 0, w - 1, h - 1), B_RGB32, true);
        if (!nb || !nb->IsValid() || !nb->Bits()) {
            delete nb;
            free(pix);
            return false;
        }
        uint8_t *dst = (uint8_t *)nb->Bits();
        int32 bpr = nb->BytesPerRow();
        int copy = w * 4;
        if (copy > pitch) copy = pitch;
        if (copy > bpr) copy = bpr;
        for (int y = 0; y < h; y++)
            memcpy(dst + (size_t)y * (size_t)bpr,
                   pix + (size_t)y * (size_t)pitch, (size_t)copy);
        free(pix);
        delete fBitmap;
        fBitmap = nb;
        fW = w;
        fH = h;
        fGen = read_gen();
        Invalidate();
        return true;
    }
};

class HalWindow : public BWindow {
public:
    HalWindow(BRect frame)
        : BWindow(frame, "HalCode", B_TITLED_WINDOW, B_QUIT_ON_WINDOW_CLOSE),
          fPoll(NULL) {
        BRect mb = Bounds();
        mb.bottom = mb.top + 18;
        BMenuBar *bar = new BMenuBar(mb, "menu");
        BMenu *file = new BMenu("File");
        file->AddItem(new BMenuItem("Quit", new BMessage(MSG_QUIT), 'Q'));
        bar->AddItem(file);
        BMenu *edit = new BMenu("Edit");
        edit->AddItem(new BMenuItem("Copy", new BMessage(MSG_COPY), 'C'));
        edit->AddItem(new BMenuItem("Paste", new BMessage(MSG_PASTE), 'V'));
        edit->AddItem(new BMenuItem("Select all", new BMessage(MSG_ALL), 'A'));
        bar->AddItem(edit);
        BMenu *help = new BMenu("Help");
        help->AddItem(new BMenuItem("Key map", new BMessage(MSG_HELP)));
        bar->AddItem(help);
        AddChild(bar);

        BRect inner = Bounds();
        inner.top = bar->Bounds().bottom + 1;
        fView = new HalView(inner);
        AddChild(fView);
        fView->MakeFocus(true);
        BMessage poll(MSG_POLL);
        fPoll = new BMessageRunner(BMessenger(this), &poll, 50000);
    }

    ~HalWindow() { delete fPoll; }

    bool QuitRequested() {
        write_cmd("quit");
        be_app->PostMessage(B_QUIT_REQUESTED);
        return true;
    }

    void MessageReceived(BMessage *msg) {
        switch (msg->what) {
        case MSG_POLL:
            if (fView) fView->Poll();
            return;
        case MSG_QUIT:
            write_cmd("quit");
            be_app->PostMessage(B_QUIT_REQUESTED);
            return;
        case MSG_COPY:
            write_line(path_keys, "y");
            return;
        case MSG_PASTE:
            do_paste();
            return;
        case MSG_ALL:
            write_line(path_keys, "a");
            return;
        case MSG_HELP:
            (new BAlert("keymap",
                "Enter sends the line. Backspace, arrows, Home, End, and Tab "
                "go to the desk. Command+C copies, Command+V pastes, "
                "Command+Q quits. The desk draws the chat. This window only "
                "shows its frame.",
                "OK"))->Go();
            return;
        default:
            BWindow::MessageReceived(msg);
        }
    }

private:
    HalView *fView;
    BMessageRunner *fPoll;
};

class HalApp : public BApplication {
public:
    HalApp() : BApplication("application/x-vnd.2paws-HalCode") {}
    void ReadyToRun() {
        BRect screen = BScreen(B_MAIN_SCREEN_ID).Frame();
        float w = 1100, h = 720;
        float x = screen.left + (screen.Width() - w) / 2;
        float y = screen.top + (screen.Height() - h) / 2;
        if (x < 40) x = 40;
        if (y < 40) y = 40;
        HalWindow *win = new HalWindow(BRect(x, y, x + w, y + h));
        win->Show();
    }
};

int main(int argc, char **argv) {
    const char *dir = getenv("HALCODE_APP_STATE");
    if (!dir || !dir[0]) dir = "/tmp/halcode_app";
    if (argc > 1 && argv[1][0]) dir = argv[1];
    paths_init(dir);
    mkdir(dir, 0755);
    HalApp app;
    app.Run();
    return 0;
}
