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
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

enum {
    MSG_POLL = 'poll',
    MSG_QUIT = 'quit',
    MSG_COPY = 'copy',
    MSG_PASTE = 'past',
    MSG_ALL = 'sall',
    MSG_STOP = 'stop',
    MSG_HELP = 'help'
};

static char g_dir[512];
static char path_meta[600], path_frame[600], path_gen[600];
static char path_ptr[600], path_cmd[600], path_keys[600];
static char path_paste[600], path_copy[600];
static char path_go[600], path_model[600], path_reply[600], path_prompt[600];
static char g_root[512], g_runner[512], g_bin[600], g_deskbin[600];
static pid_t g_desk = -1, g_host = -1, g_agent = -1;
static time_t g_agent_t0, g_agent_prog, g_agent_term, g_go_wait, g_host_t0;
static off_t g_prog_n = -1;

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
    snprintf(path_go, sizeof path_go, "%s/go.txt", dir);
    snprintf(path_model, sizeof path_model, "%s/model.txt", dir);
    snprintf(path_reply, sizeof path_reply, "%s/reply.txt", dir);
    snprintf(path_prompt, sizeof path_prompt, "%s/prompt.txt", dir);
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

static void write_reply(const char *s) {
    FILE *f = fopen(path_reply, "w");
    if (!f) return;
    fputs(s, f);
    if (s[0] && s[strlen(s) - 1] != '\n') fputc('\n', f);
    fclose(f);
}

/* The desk renames reply.txt to reply.seen as soon as it paints.
 * That happens before waitpid, so a finished turn looks like a
 * missing reply and used to be overwritten with "hal: empty reply". */
static int reply_taken_this_turn(void) {
    struct stat seen;
    FILE *f;
    char buf[32];
    size_t n;

    if (stat("/tmp/halcode_app/reply.seen", &seen) != 0)
        return 0;
    if (seen.st_size <= 0 || seen.st_mtime < g_agent_t0)
        return 0;
    f = fopen("/tmp/halcode_app/reply.seen", "r");
    if (!f)
        return 0;
    n = fread(buf, 1, sizeof buf - 1, f);
    fclose(f);
    buf[n] = 0;
    if (strncmp(buf, "hal: empty reply", 16) == 0)
        return 0;
    if (strncmp(buf, "hal: agent timed out", 20) == 0)
        return 0;
    return 1;
}

static int pid_alive(pid_t p) {
    return p > 0 && kill(p, 0) == 0;
}

static void reap_if_dead(pid_t *p) {
    int st;
    if (*p <= 0) return;
    if (waitpid(*p, &st, WNOHANG) == *p) *p = -1;
}

static void stop_pid(pid_t *p) {
    int st;
    if (*p <= 0) return;
    kill(*p, SIGTERM);
    for (int i = 0; i < 20; i++) {
        if (waitpid(*p, &st, WNOHANG) == *p) {
            *p = -1;
            return;
        }
        usleep(20000);
    }
    kill(*p, SIGKILL);
    waitpid(*p, &st, 0);
    *p = -1;
}

/* keysave.txt is "hint\nkey\n" from the desk API KEY button.
 * Write ~/.halcode/<hint>_key mode 0600. Never log the key.
 * The Linux agent reads that file. It does not see this process's env. */
static int hint_chars_ok(const char *s) {
    size_t n;
    if (!s || !s[0]) return 0;
    n = strlen(s);
    if (n > 24) return 0;
    for (size_t i = 0; i < n; i++) {
        char c = s[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '_' || c == '-'))
            return 0;
    }
    return 1;
}

static int hint_known(const char *hint) {
    char path[600];
    static const char *ok[] = {
        "deepseek", "anthropic", "xai", "gemini", "openai",
        "openrouter", "groq", NULL
    };
    snprintf(path, sizeof path, "%s/providers/%s.json", g_root, hint);
    if (access(path, R_OK) == 0) return 1;
    for (int i = 0; ok[i]; i++)
        if (strcmp(hint, ok[i]) == 0) return 1;
    return 0;
}

static void write_key_result(const char *status, const char *hint) {
    char path[600];
    FILE *f;
    snprintf(path, sizeof path, "%s/keyresult.txt", g_dir);
    f = fopen(path, "w");
    if (!f) return;
    fprintf(f, "%s %s\n", status, hint && hint[0] ? hint : "hint");
    fclose(f);
}

static void poll_keysave(void) {
    char path[600];
    char hint[32];
    char key[256];
    char dir[512];
    char file[600];
    char tmp[640];
    FILE *f;
    const char *home;
    size_t n;
    int fd;

    snprintf(path, sizeof path, "%s/keysave.txt", g_dir);
    f = fopen(path, "r");
    if (!f) return;
    if (!fgets(hint, sizeof hint, f) || !fgets(key, sizeof key, f)) {
        fclose(f);
        unlink(path);
        write_key_result("fail", "hint");
        return;
    }
    fclose(f);
    unlink(path);
    hint[strcspn(hint, "\r\n")] = 0;
    key[strcspn(key, "\r\n")] = 0;
    if (!hint_chars_ok(hint) || !hint_known(hint) || !key[0]) {
        write_key_result("fail", hint);
        memset(key, 0, sizeof key);
        return;
    }
    home = getenv("HOME");
    if (!home || !home[0]) home = "/boot/home";
    snprintf(dir, sizeof dir, "%s/.halcode", home);
    mkdir(dir, 0700);
    snprintf(file, sizeof file, "%s/%s_key", dir, hint);
    snprintf(tmp, sizeof tmp, "%s/.keytmp.%s", dir, hint);
    fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) {
        write_key_result("fail", hint);
        memset(key, 0, sizeof key);
        return;
    }
    n = strlen(key);
    if (write(fd, key, n) != (ssize_t)n || write(fd, "\n", 1) != 1) {
        close(fd);
        unlink(tmp);
        write_key_result("fail", hint);
        memset(key, 0, sizeof key);
        return;
    }
    fchmod(fd, 0600);
    close(fd);
    memset(key, 0, sizeof key);
    if (rename(tmp, file) != 0) {
        unlink(tmp);
        write_key_result("fail", hint);
        return;
    }
    chmod(file, 0600);
    write_key_result("ok", hint);
}

static void load_key_env(void) {
    static const char *names[] = {
        "deepseek_key", "DEEPSEEK_API_KEY",
        "anthropic_key", "ANTHROPIC_API_KEY",
        "xai_key", "XAI_API_KEY",
        "gemini_key", "GEMINI_API_KEY",
        NULL
    };
    const char *home = getenv("HOME");
    if (!home || !home[0]) home = "/boot/home";
    for (int i = 0; names[i]; i += 2) {
        char path[512];
        char buf[256];
        FILE *f;
        size_t n;
        snprintf(path, sizeof path, "%s/.halcode/%s", home, names[i]);
        f = fopen(path, "r");
        if (!f) continue;
        n = fread(buf, 1, sizeof buf - 1, f);
        fclose(f);
        while (n && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) n--;
        buf[n] = 0;
        if (n) setenv(names[i + 1], buf, 1);
    }
}

static int have_file(const char *path) {
    return access(path, X_OK) == 0 || access(path, R_OK) == 0;
}

static void find_root(void) {
    const char *env = getenv("HALCODE_ROOT");
    if (env && env[0] && access(env, R_OK) == 0) {
        snprintf(g_root, sizeof g_root, "%s", env);
    } else if (access("/boot/home/HalCode-Haiku/HalCode9000.x", R_OK) == 0) {
        snprintf(g_root, sizeof g_root, "/boot/home/HalCode-Haiku");
    } else {
        snprintf(g_root, sizeof g_root, "/boot/home/HalCode-Haiku");
    }
    snprintf(g_bin, sizeof g_bin, "%s/HalCode9000.x", g_root);
    snprintf(g_deskbin, sizeof g_deskbin, "%s/shell/halcode_desk.x", g_root);
    if (access("/boot/home/sys_compat_run", X_OK) == 0)
        snprintf(g_runner, sizeof g_runner, "/boot/home/sys_compat_run");
    else
        snprintf(g_runner, sizeof g_runner, "sys_compat_run");
}

static pid_t spawn_compat(const char *in_path, const char *out_path,
                          const char *err_path, char *const av[]) {
    pid_t p = fork();
    if (p != 0) return p;
    if (chdir(g_root) != 0) _exit(127);
    if (in_path) {
        int fd = open(in_path, O_RDONLY);
        if (fd >= 0) {
            dup2(fd, 0);
            if (fd > 2) close(fd);
        }
    }
    if (out_path) {
        int fd = open(out_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0) {
            dup2(fd, 1);
            if (fd > 2) close(fd);
        }
    }
    if (err_path) {
        int fd = open(err_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0) {
            dup2(fd, 2);
            if (fd > 2) close(fd);
        }
    }
    load_key_env();
    execv(g_runner, av);
    _exit(127);
}

static void ensure_desk(void) {
    char *av[3];
    static time_t next_try;
    reap_if_dead(&g_desk);
    if (pid_alive(g_desk)) return;
    if (!have_file(g_deskbin)) return;
    if (next_try != 0 && time(NULL) < next_try) return;
    next_try = time(NULL) + 2;
    av[0] = g_runner;
    av[1] = g_deskbin;
    av[2] = NULL;
    g_desk = spawn_compat(NULL, "/tmp/halcode_app/desk.log",
                          "/tmp/halcode_app/desk.log", av);
}

static void ensure_host(void) {
    char *av[4];
    reap_if_dead(&g_host);
    if (pid_alive(g_host)) return;
    if (!have_file(g_bin)) return;
    av[0] = g_runner;
    av[1] = g_bin;
    av[2] = (char *)"--host";
    av[3] = NULL;
    g_host = spawn_compat("/dev/null", "/tmp/halcode_app/host.log",
                          "/tmp/halcode_app/host.log", av);
}

static void read_model(char *spec, size_t n) {
    FILE *mf = fopen(path_model, "r");
    spec[0] = 0;
    if (!mf) return;
    if (!fgets(spec, (int)n, mf)) spec[0] = 0;
    fclose(mf);
    char *nl = strchr(spec, '\n');
    if (nl) *nl = 0;
    nl = strchr(spec, '\r');
    if (nl) *nl = 0;
}

static void cancel_turn(const char *why) {
    unlink(path_go);
    stop_pid(&g_agent);
    write_reply(why);
    unlink("/tmp/halcode_app/wait.txt");
    g_go_wait = 0;
}

static void agent_finish_locked(void) {
    int st;
    struct stat sb;
    time_t now = time(NULL);
    off_t n = 0;
    pid_t w;
    if (g_agent <= 0) return;
    if (stat("/tmp/halcode_app/agent.err", &sb) == 0) n += sb.st_size;
    if (stat("/tmp/halcode_app/think.txt", &sb) == 0) n += sb.st_size;
    if (stat(path_reply, &sb) == 0) n += sb.st_size;
    if (n != g_prog_n) {
        g_prog_n = n;
        g_agent_prog = now;
    }
    if (g_agent_term > 0) {
        w = waitpid(g_agent, &st, WNOHANG);
        if (w == g_agent || now - g_agent_term >= 2) {
            if (w != g_agent) {
                kill(g_agent, SIGKILL);
                waitpid(g_agent, &st, WNOHANG);
            }
            g_agent = -1;
            g_agent_term = 0;
        }
        return;
    }
    if (now - g_agent_prog > 180 || now - g_agent_t0 > 900) {
        kill(g_agent, SIGTERM);
        g_agent_term = now;
        unlink("/tmp/halcode_app/wait.txt");
        if ((stat(path_reply, &sb) != 0 || sb.st_size <= 0)
            && !reply_taken_this_turn())
            write_reply("hal: agent timed out");
        return;
    }
    w = waitpid(g_agent, &st, WNOHANG);
    if (w == g_agent) {
        g_agent = -1;
        unlink("/tmp/halcode_app/wait.txt");
        if ((stat(path_reply, &sb) != 0 || sb.st_size <= 0)
            && !reply_taken_this_turn())
            write_reply("hal: empty reply");
    }
}

static void agent_tick(void) {
    char spec[160];
    char *av[5];
    /* --host at idle panicked this guest. Start it only after a send. */
    if (access(path_go, F_OK) != 0) {
        agent_finish_locked();
        return;
    }
    if (pid_alive(g_agent)) {
        unlink(path_go);
        write_reply("hal: busy — a turn is already running. Escape stops it.");
        return;
    }
    read_model(spec, sizeof spec);
    if (!spec[0]) {
        unlink(path_go);
        write_reply("select a model first");
        unlink("/tmp/halcode_app/wait.txt");
        g_go_wait = 0;
        return;
    }
    if (access("/tmp/halcode_app/ready.txt", F_OK) != 0) {
        reap_if_dead(&g_host);
        if (!pid_alive(g_host)) {
            if (g_host_t0 != 0 && time(NULL) - g_host_t0 < 3) {
                unlink(path_go);
                write_reply("hal: agent host exited before the turn started");
                unlink("/tmp/halcode_app/wait.txt");
                g_go_wait = 0;
                g_host_t0 = 0;
                return;
            }
            ensure_host();
            g_host_t0 = time(NULL);
        }
        if (g_go_wait == 0) g_go_wait = time(NULL);
        /* RegisterTool spends ~10s per missing tool before StartProxy.
         * Relmem, Pgmem, and MCP can burn the whole window. Wait until
         * ready.txt appears, and give up only after this long. */
        if (time(NULL) - g_go_wait < 45) return;
    }
    g_go_wait = 0;
    unlink(path_go);
    av[0] = g_runner;
    av[1] = g_bin;
    av[2] = (char *)"--agent";
    av[3] = spec;
    av[4] = NULL;
    g_agent = spawn_compat(path_prompt, "/tmp/halcode_app/agent.out",
                           "/tmp/halcode_app/agent.err", av);
    if (g_agent < 0) {
        write_reply("hal: could not start the agent");
        unlink("/tmp/halcode_app/wait.txt");
        return;
    }
    g_agent_t0 = time(NULL);
    g_agent_prog = g_agent_t0;
    g_agent_term = 0;
    g_prog_n = -1;
}

static void shutdown_children(void) {
    unlink(path_go);
    stop_pid(&g_agent);
    stop_pid(&g_host);
    stop_pid(&g_desk);
}

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
        case B_ESCAPE:
            if (pid_alive(g_agent) || access("/tmp/halcode_app/wait.txt", F_OK) == 0) {
                cancel_turn("cancelled");
                return;
            }
            write_line(path_keys, "e");
            return;
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
        file->AddItem(new BMenuItem("Stop turn", new BMessage(MSG_STOP)));
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
        shutdown_children();
        write_cmd("quit");
        be_app->PostMessage(B_QUIT_REQUESTED);
        return true;
    }

    void MessageReceived(BMessage *msg) {
        switch (msg->what) {
        case MSG_POLL:
            poll_keysave();
            ensure_desk();
            agent_tick();
            if (fView) fView->Poll();
            return;
        case MSG_STOP:
            cancel_turn("cancelled");
            return;
        case MSG_QUIT:
            shutdown_children();
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
                "Pick a model before Enter. In Models, click API KEY, "
                "paste the provider key, and press Enter. It is saved in "
                "~/.halcode/ and is not shown again. Escape, or File → "
                "Stop turn, cancels the running turn. Command+Q quits.",
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
        find_root();
        unlink(path_go);
        unlink("/tmp/halcode_app/wait.txt");
        ensure_desk();
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
