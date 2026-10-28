---
name: haiku-beapi-core
description: "BeAPI App Kit — BApplication, BLooper, BHandler, BMessage, BMessenger threading and message passing. Load when writing Haiku OS applications, porting to Haiku, or working with BMessage-based IPC. Use whenever Haiku, BeOS, BeAPI, BLooper, BMessage, BApplication, BHandler, BMessenger, App Kit, message passing, or Haiku application architecture is mentioned — even if the user doesn't explicitly say 'BeAPI'."
---

# Haiku BeAPI — App Kit & Message Passing

## NAME
Haiku BeAPI Core — BApplication, BLooper, BHandler, BMessage, BMessenger

## SYNOPSIS
```cpp
#include <Application.h>
#include <Looper.h>
#include <Handler.h>
#include <Message.h>
#include <Messenger.h>
```
> Requires: `libbe.so` (linked automatically by Haiku build system)

## DESCRIPTION

The App Kit is the foundation of every Haiku application. All GUI and
non-GUI apps are built on a message-passing architecture: objects post
`BMessage`s to `BLooper`s, which dispatch them to `BHandler`s.

### Class Hierarchy

```
BArchivable
 └─ BHandler        ← receives messages
     └─ BLooper     ← owns a thread, runs a message loop
         └─ BApplication  ← one per process, is be_app
         └─ BWindow       ← (Interface Kit, see haiku-beapi-interface)
```

---

## THREADING MODEL — READ THIS FIRST

Every `BLooper` owns **exactly one thread** that runs its message loop.

**The Lock Rule:** You **MUST** call `Lock()` before touching a BLooper (or
any BHandler attached to it) from a thread other than the looper's own.
Forgetting this is the #1 source of BeAPI race conditions.

```cpp
if (myLooper->Lock()) {
    myLooper->PostMessage(B_QUIT_REQUESTED);
    myLooper->Unlock();
}
```

Lock calls are **recursive** — every `Lock()` must pair with an `Unlock()`.

`BHandler` provides convenience wrappers:
```cpp
bool   BHandler::LockLooper()
status_t BHandler::LockLooperWithTimeout(bigtime_t timeout)
void   BHandler::UnlockLooper()
```

---

## BApplication

One per process. The constructor sets the global `be_app` pointer.

### Construction
```cpp
BApplication(const char *signature);
BApplication(const char *signature, status_t *error);
```
`signature` is a MIME application signature: `"application/x-vnd.YourName-AppName"`.

### Lifecycle
```cpp
thread_id Run();    // blocks in caller's thread — does NOT spawn a new thread
void      Quit();
status_t  InitCheck() const;
```

`Run()` enters the message loop **in the calling thread** and does not
return until `Quit()` is called. This is different from `BLooper::Run()`
which spawns a thread.

### Key Hooks (override these)
```cpp
virtual void ReadyToRun();                       // app fully initialized
virtual bool QuitRequested();                    // return false to cancel quit
virtual void MessageReceived(BMessage *msg);     // handle custom messages
virtual void ArgvReceived(int32 argc, char **argv);
virtual void RefsReceived(BMessage *msg);        // files dropped / opened
virtual void AboutRequested();
virtual void Pulse();                            // periodic timer (see SetPulseRate)
virtual void AppActivated(bool active);
```

### Minimal App
```cpp
#include <Application.h>
#include <Window.h>

class MyApp : public BApplication {
public:
    MyApp() : BApplication("application/x-vnd.Example-App") {}
    void ReadyToRun() override {
        BWindow *win = new BWindow(BRect(100,100,500,400),
            "Hello", B_TITLED_WINDOW, B_QUIT_ON_WINDOW_CLOSE);
        win->Show();
    }
};

int main() {
    MyApp app;
    app.Run();
    return 0;
}
```

---

## BLooper

A thread that runs a message loop. Create on the **heap** — `Quit()`
deletes `this`.

### Construction
```cpp
BLooper(const char *name = NULL,
        int32 priority = B_NORMAL_PRIORITY,
        int32 portCapacity = B_LOOPER_PORT_DEFAULT_CAPACITY);
```

### Loop Control
```cpp
thread_id Run();              // spawns a message thread, returns its ID
void      Quit();             // stops the loop, deletes the looper
bool      QuitRequested();    // override to allow/deny quit
```

### Locking
```cpp
bool     Lock();
void     Unlock();
bool     IsLocked() const;
status_t LockWithTimeout(bigtime_t timeout);  // microseconds
```

### Handler Management
```cpp
void       AddHandler(BHandler *handler);
bool       RemoveHandler(BHandler *handler);
int32      CountHandlers() const;
BHandler  *HandlerAt(int32 index) const;
int32      IndexOf(BHandler *handler) const;
void       SetPreferredHandler(BHandler *handler);
BHandler  *PreferredHandler() const;
```

### Posting Messages
```cpp
status_t PostMessage(uint32 command);
status_t PostMessage(BMessage *message);
status_t PostMessage(uint32 command, BHandler *handler,
                     BHandler *replyTo = NULL);
status_t PostMessage(BMessage *message, BHandler *handler,
                     BHandler *replyTo = NULL);
```
Messages are **copied** — delete heap-allocated originals yourself.

### Message Access (from within the loop thread only)
```cpp
BMessage *CurrentMessage() const;
BMessage *DetachCurrentMessage();   // takes ownership from looper
```

### Thread Info
```cpp
thread_id Thread() const;           // 0 if not running
team_id   Team() const;
static BLooper *LooperForThread(thread_id thread);
```

---

## BHandler

Receives messages dispatched by its owning BLooper. A handler **must** be
attached to a looper via `AddHandler()` before it can receive messages.

### Construction
```cpp
BHandler(const char *name = NULL);
```

### Core
```cpp
virtual void MessageReceived(BMessage *msg);  // override this
BLooper     *Looper() const;                  // NULL if unattached
```

### Handler Chain
```cpp
void       SetNextHandler(BHandler *handler);  // looper must be locked
BHandler  *NextHandler() const;
```
Unhandled messages pass up the chain. Always call the base
`BHandler::MessageReceived()` for messages you don't handle.

### Message Filtering
```cpp
void   AddFilter(BMessageFilter *filter);
bool   RemoveFilter(BMessageFilter *filter);
void   SetFilterList(BList *filters);
BList *FilterList();
```

---

## BMessage

A typed key-value container with a `uint32 what` code that identifies its
purpose. Messages are the **only** way to communicate between loopers.

### Construction
```cpp
BMessage();                       // what = 0
BMessage(uint32 what);            // what = command constant
BMessage(const BMessage &other);  // deep copy
```

### Public Field
```cpp
uint32 what;   // set freely — e.g. msg.what = MY_MSG_CODE;
```

### Field API Pattern
Every type has `Add*`, `Find*`, `Replace*`, `Has*` methods. Fields are
named strings that can hold arrays of values (indexed by `int32`).

```cpp
// Add a value
status_t AddString(const char *name, const char *string);
status_t AddInt32(const char *name, int32 value);

// Find a value (returns B_OK or B_NAME_NOT_FOUND)
status_t FindString(const char *name, const char **string) const;
status_t FindString(const char *name, int32 index, const char **string) const;
status_t FindInt32(const char *name, int32 *value) const;

// Replace an existing value
status_t ReplaceString(const char *name, const char *string);
status_t ReplaceString(const char *name, int32 index, const char *string);

// Check existence
bool HasString(const char *name, int32 index = 0) const;
```

> For the **complete field type table** (all Add/Find/Replace/Has variants
> and type_code constants), see `references/bmessage-fields.md`.

### Utility
```cpp
status_t RemoveData(const char *name, int32 index = 0);
status_t RemoveName(const char *name);
status_t MakeEmpty();
bool     IsEmpty() const;
int32    CountNames(type_code type) const;
void     PrintToStream() const;     // debug dump to stdout
```

### Serialization
```cpp
ssize_t  FlattenedSize() const;
status_t Flatten(char *buffer, ssize_t size) const;
status_t Flatten(BDataIO *stream, ssize_t *size = NULL) const;
status_t Unflatten(const char *flatBuffer);
status_t Unflatten(BDataIO *stream);
```

### Replies
```cpp
status_t SendReply(uint32 command, BHandler *replyTo = NULL);
status_t SendReply(BMessage *reply, BHandler *replyTo = NULL,
                   bigtime_t timeout = B_INFINITE_TIMEOUT);
BMessenger ReturnAddress() const;
bool       IsSourceWaiting() const;
bool       WasDelivered() const;
```

---

## BMessenger

Sends messages to a target BHandler/BLooper — within the same team
(local) or to another application (remote).

### Construction
```cpp
BMessenger();                                          // uninitialized
BMessenger(const BHandler *handler,
           const BLooper *looper = NULL,
           status_t *result = NULL);                   // local target
BMessenger(const char *signature,
           team_id team = -1,
           status_t *result = NULL);                   // remote target
```

### Sending (async — returns immediately)
```cpp
status_t SendMessage(uint32 command, BHandler *replyTo = NULL) const;
status_t SendMessage(BMessage *message, BHandler *replyTo = NULL,
                     bigtime_t timeout = B_INFINITE_TIMEOUT) const;
```

### Sending (sync — waits for reply)
```cpp
status_t SendMessage(uint32 command, BMessage *reply) const;
status_t SendMessage(BMessage *message, BMessage *reply,
                     bigtime_t deliveryTimeout = B_INFINITE_TIMEOUT,
                     bigtime_t replyTimeout = B_INFINITE_TIMEOUT) const;
```

### Target Info
```cpp
bool       IsValid() const;
bool       IsTargetLocal() const;
BHandler  *Target(BLooper **looper) const;   // local targets only
team_id    Team() const;
```

---

## COMMON PATTERNS

### Custom Message Constants
```cpp
enum {
    MSG_BUTTON_CLICKED = 'btcl',  // 4-char codes are common
    MSG_DATA_READY     = 'data',
    MSG_UPDATE_VIEW    = 'updv',
};
```

### Message-Based State Machine
```cpp
void MyHandler::MessageReceived(BMessage *msg) {
    switch (msg->what) {
        case MSG_START:
            fState = STATE_RUNNING;
            break;
        case MSG_DATA_READY: {
            const char *path;
            if (msg->FindString("path", &path) == B_OK)
                _ProcessFile(path);
            break;
        }
        default:
            BHandler::MessageReceived(msg);  // always call base
    }
}
```

### Cross-Application Messaging
```cpp
// Send to another app by signature
BMessenger target("application/x-vnd.Other-App");
if (target.IsValid()) {
    BMessage msg(MSG_PING);
    msg.AddString("from", "MyApp");
    target.SendMessage(&msg);
}
```

### Synchronous Request/Reply
```cpp
BMessenger target(someHandler);
BMessage request(MSG_GET_STATUS);
BMessage reply;
if (target.SendMessage(&request, &reply) == B_OK) {
    int32 status;
    reply.FindInt32("status", &status);
}
```

### Worker Looper Pattern
```cpp
class Worker : public BLooper {
public:
    Worker() : BLooper("worker", B_LOW_PRIORITY) {}
    void MessageReceived(BMessage *msg) override {
        if (msg->what == MSG_DO_WORK) {
            // heavy lifting here — on worker's own thread
            BMessage reply(MSG_WORK_DONE);
            reply.AddInt32("result", 42);
            msg->SendReply(&reply);
        } else {
            BLooper::MessageReceived(msg);
        }
    }
};

// Usage:
Worker *worker = new Worker();
worker->Run();
BMessenger(worker).SendMessage(new BMessage(MSG_DO_WORK));
```

---

## SYSTEM MESSAGE CONSTANTS

| Constant | Value | Meaning |
|----------|-------|---------|
| `B_QUIT_REQUESTED` | `'_QRQ'` | Request to quit |
| `B_ABOUT_REQUESTED` | `'_ABR'` | Show about box |
| `B_REFS_RECEIVED` | `'_RRC'` | Files opened/dropped |
| `B_ARGV_RECEIVED` | `'_ARG'` | Command-line args |
| `B_READY_TO_RUN` | `'_RTR'` | App initialized |
| `B_PULSE` | `'_PUL'` | Periodic pulse |
| `B_APP_ACTIVATED` | `'_ACT'` | App activated/deactivated |
| `B_KEY_DOWN` | `'_KYD'` | Key press |
| `B_KEY_UP` | `'_KYU'` | Key release |
| `B_MOUSE_DOWN` | `'_MDN'` | Mouse button press |
| `B_MOUSE_UP` | `'_MUP'` | Mouse button release |
| `B_MOUSE_MOVED` | `'_MMV'` | Mouse movement |

---

## GOTCHAS

1. **BApplication::Run() does NOT spawn a thread.** It blocks. Call it
   from `main()`. All other BLoopers DO spawn threads via `Run()`.
2. **Always allocate BLoopers on the heap.** `Quit()` calls `delete this`.
3. **Lock before touching.** Any cross-thread access to a looper or its
   handlers requires `Lock()`/`Unlock()`.
4. **Call the base class.** If `MessageReceived()` doesn't handle a
   message, call `BHandler::MessageReceived(msg)` — don't silently drop.
5. **Messages are copied on post.** `PostMessage()` copies the BMessage.
   Delete originals you allocated with `new`.
6. **BHandler must be attached.** A handler won't receive messages until
   added to a looper with `AddHandler()`.
