// cleona_tray.dll -- the thread that owns the daemon's notification-area icon
// on Windows (v4_2 §22.6 "tray via Win32 FFI", §22.9).
//
// WHY A NATIVE THREAD (S423 B-5, report S423-RCA-WINDOWS.md):
// The icon belongs to a window (NOTIFYICONDATAW.hWnd), and a window belongs to
// the thread that created it. Until S423 the daemon created that window from
// Dart. Dart code after an `await` runs on a worker of the VM's thread pool
// (runtime/vm/dart_api_impl.cc, Dart_RunLoop: the message handler runs on
// `I->group()->thread_pool()`), and an idle worker ends after 5 s
// (runtime/vm/thread_pool.cc, flag `worker_timeout_millis`, default 5000).
// When a thread ends, "Any resources owned by the thread, such as windows and
// hooks, are freed" (Microsoft Learn, "Terminating a Thread",
// https://learn.microsoft.com/en-us/windows/win32/procthread/terminating-a-thread).
// Measured in the lab on 14.11.2026: NIM_MODIFY rejected with
// `window alive=false` from 7 s after NIM_ADD on, the icon gone.
// No Dart isolate is bound to one OS thread, so the owner has to be a thread
// that Dart does not manage: the one this file starts.
//
// Everything that touches the window or the icon runs HERE, on that thread:
// the window and its class, Shell_NotifyIconW, the icon handles, the context
// menu. Dart talks to the thread through SendMessageTimeoutW. "If the
// specified window was created by a different thread, the system switches to
// that thread and calls the appropriate window procedure. ... The sending
// thread is blocked until the receiving thread processes the message"
// (Microsoft Learn, SendMessage,
// https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendmessagew)
// -- so a pointer handed over in lParam stays valid for the whole call, and
// the thread never needs a lock. Events (double click, menu choice) go back
// through a function pointer that Dart created with
// `NativeCallable<Void Function(Int32)>.listener`, which may be called from
// any thread and posts the call to the isolate without blocking.
//
// The window is an ordinary hidden TOP-LEVEL window, not a message-only
// window (HWND_MESSAGE): "A message-only window ... does not receive
// broadcast messages" (Microsoft Learn, "Window Features",
// https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features),
// and the shell announces a restarted taskbar as a broadcast: "When the
// taskbar is created, it registers a message with the TaskbarCreated string
// and then broadcasts this message to all top-level windows. When your
// taskbar application receives this message, it should assume that any
// taskbar icons it added have been removed and add them again" (Microsoft
// Learn, "The Taskbar", section "Taskbar Creation Notification",
// https://learn.microsoft.com/en-us/windows/win32/shell/taskbar). Class and
// window name stay what they were before S423 ("CleonaTrayWindow",
// "Cleona Tray"); the E2E probe finds the window by its class.
//
// Interface (all functions are called from Dart, lib/core/tray/
// windows_tray_thread.dart; return values are documented there as well):
//   cleona_tray_start(on_event)        -> HWND of the tray window, 0 = failed
//   cleona_tray_notify(msg, nid, &err, &alive) -> BOOL of Shell_NotifyIconW
//   cleona_tray_set_menu(spec)         -> 1 = taken over
//   cleona_tray_load_icon(path, cx, cy, flags) -> HICON, 0 = failed
//   cleona_tray_stop()                 -> 1 = thread ended, 0 = it did not
//
// System libraries only (user32, shell32, kernel32) plus the C runtime of the
// build, like cleona_net.dll.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <process.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define CLEONA_TRAY_EXPORT __declspec(dllexport)

typedef void (*cleona_tray_event_fn)(int32_t event);

// Window messages of the tray window. WM_APP + 1 is the icon's callback
// message (uCallbackMessage); the value is set here, whatever the caller
// wrote into the structure, so the window procedure and the icon cannot
// disagree.
#define TRAY_MSG_CALLBACK (WM_APP + 1)
#define TRAY_MSG_NOTIFY (WM_APP + 2)
#define TRAY_MSG_SET_MENU (WM_APP + 3)
#define TRAY_MSG_LOAD_ICON (WM_APP + 4)

// Event codes for on_event. 1001 is the "show" menu identifier the Dart side
// uses for a double click as well; menu choices arrive with their own
// identifier. The 2000s are reports of this thread.
#define TRAY_EVENT_SHOW 1001
#define TRAY_EVENT_READDED 2001
#define TRAY_EVENT_READD_FAILED 2002
// Measurement (S424 R-3, M-1): the end of the window and of this thread is
// reported, so the daemon log shows when and how "CleonaTrayWindow" goes.
// WM_CLOSE arrived / WM_DESTROY arrived / the message loop ended because
// GetMessageW returned 0 (WM_QUIT) / because it returned -1 (error).
#define TRAY_EVENT_CLOSE_RECEIVED 2003
#define TRAY_EVENT_DESTROYED 2004
#define TRAY_EVENT_THREAD_ENDED 2005
#define TRAY_EVENT_THREAD_ENDED_LOOP_ERROR 2006

// How long a call from Dart waits for the tray thread. The thread only
// blocks inside TrackPopupMenu, and a modal menu loop still dispatches sent
// messages; the bound is for a hung thread, not for a busy one.
#define TRAY_SEND_TIMEOUT_MS 5000

// Icons loaded by this thread (the three readiness icons and the base icon).
#define TRAY_MAX_ICONS 16

// The Dart side builds the record in a 976-byte buffer
// (_NOTIFYICONDATAW_SIZE in lib/core/tray/native_tray_windows.dart) and
// do_notify() rejects any other cbSize; this line fails the build if the SDK
// ever disagrees.
typedef char cleona_tray_nid_size_check[sizeof(NOTIFYICONDATAW) == 976 ? 1 : -1];

static const wchar_t kClassName[] = L"CleonaTrayWindow";
static const wchar_t kWindowName[] = L"Cleona Tray";

static HINSTANCE g_module;
static HANDLE g_thread;
static HANDLE g_ready;
static HWND g_hwnd;
static UINT g_taskbar_created;
static cleona_tray_event_fn g_on_event;

// Owned by the tray thread only.
static NOTIFYICONDATAW g_nid;
static BOOL g_added;
static wchar_t *g_menu;
static HICON g_icons[TRAY_MAX_ICONS];
static int g_icon_count;

typedef struct {
  DWORD message;
  const NOTIFYICONDATAW *nid;
  BOOL result;
  DWORD last_error;
  BOOL window_alive;
} NotifyRequest;

typedef struct {
  const wchar_t *path;  // NULL: the shared system application icon
  int cx;
  int cy;
  UINT flags;
  HICON icon;
} IconRequest;

static void emit(int32_t event) {
  cleona_tray_event_fn fn = g_on_event;
  if (fn != NULL) fn(event);
}

// Runs Shell_NotifyIconW on this thread with a copy of the caller's record.
// The copy is kept: after a taskbar restart the icon is added again from it.
static void do_notify(NotifyRequest *r) {
  if (r->nid == NULL || r->nid->cbSize != sizeof(NOTIFYICONDATAW)) {
    r->result = FALSE;
    r->last_error = ERROR_INVALID_PARAMETER;
    r->window_alive = IsWindow(g_hwnd);
    return;
  }
  g_nid = *r->nid;
  g_nid.hWnd = g_hwnd;
  g_nid.uCallbackMessage = TRAY_MSG_CALLBACK;
  SetLastError(0);
  r->result = Shell_NotifyIconW(r->message, &g_nid);
  // Read on the thread that made the call, right after it (Microsoft Learn,
  // Shell_NotifyIconW: "Returns TRUE if successful, or FALSE otherwise. ...
  // you can call GetLastError for more specific information").
  r->last_error = GetLastError();
  r->window_alive = IsWindow(g_hwnd);
  if (r->result && r->message == NIM_ADD) g_added = TRUE;
  if (r->result && r->message == NIM_DELETE) g_added = FALSE;
}

// TaskbarCreated: the shell has forgotten the icon (Explorer restart, or on
// Windows 10 a DPI change of the primary display -- "The Taskbar", see the
// file head). After a DPI change the icon may still be there; then NIM_ADD
// fails and NIM_MODIFY carries the same record.
static void readd(void) {
  BOOL ok;
  if (!g_added) return;
  ok = Shell_NotifyIconW(NIM_ADD, &g_nid);
  if (!ok) ok = Shell_NotifyIconW(NIM_MODIFY, &g_nid);
  emit(ok ? TRAY_EVENT_READDED : TRAY_EVENT_READD_FAILED);
}

// The menu spec: lines separated by '\n'. A line "-" is a separator, any
// other line is "<id>\t<text>"; id 0 is an information line (greyed, not
// selectable). Built by trayMenuSpec() in Dart.
static void append_menu_line(HMENU menu, const wchar_t *line, size_t len) {
  const wchar_t *tab;
  size_t text_len;
  wchar_t *text;
  UINT id;
  UINT flags;
  if (len == 1 && line[0] == L'-') {
    AppendMenuW(menu, MF_SEPARATOR, 0, NULL);
    return;
  }
  tab = wmemchr(line, L'\t', len);
  if (tab == NULL) return;
  id = (UINT)wcstoul(line, NULL, 10);
  text_len = len - (size_t)(tab + 1 - line);
  text = (wchar_t *)malloc((text_len + 1) * sizeof(wchar_t));
  if (text == NULL) return;
  wmemcpy(text, tab + 1, text_len);
  text[text_len] = L'\0';
  flags = MF_STRING;
  if (id == 0) flags |= MF_GRAYED | MF_DISABLED;
  AppendMenuW(menu, flags, id, text);
  free(text);
}

static void show_menu(HWND hwnd) {
  HMENU menu;
  POINT pt;
  UINT cmd;
  const wchar_t *p;
  menu = CreatePopupMenu();
  if (menu == NULL) return;
  p = g_menu;
  while (p != NULL && *p != L'\0') {
    const wchar_t *end = wcschr(p, L'\n');
    size_t len = end != NULL ? (size_t)(end - p) : wcslen(p);
    append_menu_line(menu, p, len);
    p = end != NULL ? end + 1 : NULL;
  }
  if (!GetCursorPos(&pt)) {
    pt.x = 0;
    pt.y = 0;
  }
  // "To display a context menu for a notification icon, the current window
  // must be the foreground window before the application calls
  // TrackPopupMenu ... you must force a task switch to the application that
  // called TrackPopupMenu. This is done by posting a benign message to the
  // window" (Microsoft Learn, TrackPopupMenu, Remarks,
  // https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-trackpopupmenu).
  // TPM_RETURNCMD: "the return value is the menu-item identifier of the item
  // that the user selected ... zero" when cancelled (same page).
  SetForegroundWindow(hwnd);
  cmd = (UINT)TrackPopupMenu(menu,
                             TPM_LEFTALIGN | TPM_BOTTOMALIGN | TPM_RETURNCMD |
                                 TPM_NONOTIFY,
                             pt.x, pt.y, 0, hwnd, NULL);
  PostMessageW(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (cmd != 0) emit((int32_t)cmd);
}

static void load_icon(IconRequest *r) {
  HICON h;
  if (r->path == NULL) {
    // Shared system icon: never destroyed (DestroyIcon: "Do not use this
    // function to destroy a shared icon",
    // https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-destroyicon).
    r->icon = LoadIconW(NULL, MAKEINTRESOURCEW(32512) /* IDI_APPLICATION */);
    return;
  }
  if (g_icon_count >= TRAY_MAX_ICONS) {
    r->icon = NULL;
    return;
  }
  // LR_SHARED is masked out: a shared icon must not be destroyed, and every
  // icon loaded here is destroyed when the thread ends.
  h = (HICON)LoadImageW(NULL, r->path, IMAGE_ICON, r->cx, r->cy,
                        r->flags & ~(UINT)LR_SHARED);
  if (h != NULL) g_icons[g_icon_count++] = h;
  r->icon = h;
}

static LRESULT CALLBACK tray_wndproc(HWND hwnd, UINT msg, WPARAM wp,
                                     LPARAM lp) {
  switch (msg) {
    case TRAY_MSG_CALLBACK: {
      // Shell version 0 behaviour (no NIM_SETVERSION): lParam is the mouse
      // message ("The Taskbar", "Receiving Notification Area Callback
      // Messages").
      UINT ev = (UINT)LOWORD(lp);
      if (ev == WM_LBUTTONDBLCLK) {
        emit(TRAY_EVENT_SHOW);
      } else if (ev == WM_RBUTTONUP) {
        show_menu(hwnd);
      }
      return 0;
    }
    case TRAY_MSG_NOTIFY:
      do_notify((NotifyRequest *)lp);
      return 1;
    case TRAY_MSG_SET_MENU: {
      const wchar_t *spec = (const wchar_t *)lp;
      wchar_t *copy = spec != NULL ? _wcsdup(spec) : NULL;
      if (spec != NULL && copy == NULL) return 0;
      free(g_menu);
      g_menu = copy;
      return 1;
    }
    case TRAY_MSG_LOAD_ICON:
      load_icon((IconRequest *)lp);
      return 1;
    case WM_CLOSE:
      emit(TRAY_EVENT_CLOSE_RECEIVED);
      DestroyWindow(hwnd);
      return 0;
    case WM_DESTROY:
      emit(TRAY_EVENT_DESTROYED);
      if (g_added) {
        Shell_NotifyIconW(NIM_DELETE, &g_nid);
        g_added = FALSE;
      }
      PostQuitMessage(0);
      return 0;
    default:
      if (g_taskbar_created != 0 && msg == g_taskbar_created) {
        readd();
        return 0;
      }
      break;
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}

static unsigned __stdcall tray_thread(void *unused) {
  WNDCLASSW wc;
  MSG m;
  BOOL got;
  int i;
  (void)unused;
  ZeroMemory(&wc, sizeof wc);
  wc.lpfnWndProc = tray_wndproc;
  wc.hInstance = g_module;
  wc.lpszClassName = kClassName;
  if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    SetEvent(g_ready);
    return 1;
  }
  g_taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
  // Hidden (no WS_VISIBLE, never shown) and without a parent: top-level, so
  // the TaskbarCreated broadcast reaches it (see the file head).
  g_hwnd = CreateWindowExW(0, kClassName, kWindowName, WS_OVERLAPPEDWINDOW, 0,
                           0, 0, 0, NULL, NULL, g_module, NULL);
  SetEvent(g_ready);
  if (g_hwnd == NULL) {
    UnregisterClassW(kClassName, g_module);
    return 1;
  }
  // GetMessageW: "If the function retrieves the WM_QUIT message, the return
  // value is zero. If there is an error, the return value is -1" (Microsoft
  // Learn, GetMessageW,
  // https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getmessagew).
  while ((got = GetMessageW(&m, NULL, 0, 0)) > 0) {
    TranslateMessage(&m);
    DispatchMessageW(&m);
  }
  // WM_DESTROY has removed the icon; now the handles of this thread.
  for (i = 0; i < g_icon_count; i++) DestroyIcon(g_icons[i]);
  g_icon_count = 0;
  free(g_menu);
  g_menu = NULL;
  UnregisterClassW(kClassName, g_module);
  // Last call before the thread returns 0; the callback is still open
  // (cleona_tray_stop and the Dart side close it only after the thread ended).
  emit(got == 0 ? TRAY_EVENT_THREAD_ENDED : TRAY_EVENT_THREAD_ENDED_LOOP_ERROR);
  return 0;
}

static void reset_handles(void) {
  if (g_thread != NULL) CloseHandle(g_thread);
  if (g_ready != NULL) CloseHandle(g_ready);
  g_thread = NULL;
  g_ready = NULL;
  g_hwnd = NULL;
  g_on_event = NULL;
}

CLEONA_TRAY_EXPORT intptr_t cleona_tray_start(cleona_tray_event_fn on_event) {
  if (g_thread != NULL) return (intptr_t)g_hwnd;
  // The module of THIS DLL (the window procedure lives here), found from the
  // address of one of its own variables.
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          (LPCWSTR)&g_module, &g_module)) {
    return 0;
  }
  g_on_event = on_event;
  g_hwnd = NULL;
  g_ready = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (g_ready == NULL) {
    g_on_event = NULL;
    return 0;
  }
  g_thread = (HANDLE)_beginthreadex(NULL, 0, tray_thread, NULL, 0, NULL);
  if (g_thread == NULL) {
    reset_handles();
    return 0;
  }
  if (WaitForSingleObject(g_ready, TRAY_SEND_TIMEOUT_MS) != WAIT_OBJECT_0 ||
      g_hwnd == NULL) {
    // The thread failed to create its window and ends by itself; if it did
    // not even signal, it is left alone rather than killed.
    if (WaitForSingleObject(g_thread, TRAY_SEND_TIMEOUT_MS) == WAIT_OBJECT_0) {
      reset_handles();
    } else {
      g_on_event = NULL;
    }
    return 0;
  }
  return (intptr_t)g_hwnd;
}

CLEONA_TRAY_EXPORT int32_t cleona_tray_notify(uint32_t message,
                                              const void *nid,
                                              uint32_t *last_error,
                                              int32_t *window_alive) {
  NotifyRequest r;
  DWORD_PTR answer = 0;
  r.message = message;
  r.nid = (const NOTIFYICONDATAW *)nid;
  r.result = FALSE;
  r.last_error = 0;
  r.window_alive = FALSE;
  if (g_hwnd == NULL) {
    r.last_error = ERROR_INVALID_WINDOW_HANDLE;
  } else if (!SendMessageTimeoutW(g_hwnd, TRAY_MSG_NOTIFY, 0, (LPARAM)&r,
                                  SMTO_NORMAL | SMTO_ABORTIFHUNG,
                                  TRAY_SEND_TIMEOUT_MS, &answer)) {
    // Not delivered: the error of SendMessageTimeoutW (ERROR_TIMEOUT 1460
    // when the thread hangs, 1400 when the window is gone).
    r.result = FALSE;
    r.last_error = GetLastError();
    r.window_alive = IsWindow(g_hwnd);
  }
  if (last_error != NULL) *last_error = r.last_error;
  if (window_alive != NULL) *window_alive = r.window_alive ? 1 : 0;
  return r.result ? 1 : 0;
}

CLEONA_TRAY_EXPORT int32_t cleona_tray_set_menu(const wchar_t *spec) {
  DWORD_PTR answer = 0;
  if (g_hwnd == NULL) return 0;
  if (!SendMessageTimeoutW(g_hwnd, TRAY_MSG_SET_MENU, 0, (LPARAM)spec,
                           SMTO_NORMAL | SMTO_ABORTIFHUNG,
                           TRAY_SEND_TIMEOUT_MS, &answer)) {
    return 0;
  }
  return answer != 0 ? 1 : 0;
}

CLEONA_TRAY_EXPORT intptr_t cleona_tray_load_icon(const wchar_t *path,
                                                  int32_t cx, int32_t cy,
                                                  uint32_t flags) {
  IconRequest r;
  DWORD_PTR answer = 0;
  if (g_hwnd == NULL) return 0;
  r.path = path;
  r.cx = cx;
  r.cy = cy;
  r.flags = flags;
  r.icon = NULL;
  if (!SendMessageTimeoutW(g_hwnd, TRAY_MSG_LOAD_ICON, 0, (LPARAM)&r,
                           SMTO_NORMAL | SMTO_ABORTIFHUNG,
                           TRAY_SEND_TIMEOUT_MS, &answer)) {
    return 0;
  }
  return (intptr_t)r.icon;
}

// Ends the thread: WM_CLOSE -> DestroyWindow -> WM_DESTROY (NIM_DELETE,
// PostQuitMessage) -> the loop ends, the icons are destroyed. Returns 1 when
// the thread has ended. Only then may the caller close the callback it gave
// to cleona_tray_start: until the thread has ended it may still call it.
CLEONA_TRAY_EXPORT int32_t cleona_tray_stop(void) {
  if (g_thread == NULL) return 1;
  if (g_hwnd != NULL) PostMessageW(g_hwnd, WM_CLOSE, 0, 0);
  if (WaitForSingleObject(g_thread, TRAY_SEND_TIMEOUT_MS) != WAIT_OBJECT_0) {
    return 0;
  }
  reset_handles();
  return 1;
}
