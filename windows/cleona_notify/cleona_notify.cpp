// cleona-notify -- shows ONE Windows toast notification for the daemon and
// exits (v4_2 §22.6 "toast notifications", §22.8 "What a system notification
// shows"). Started once per notification by
// lib/core/platform/windows_toast_notifier.dart.
//
// Why a helper program and not a DLL inside the daemon: a crash or a hang in
// WinRT/COM ends this throw-away process, never the daemon -- and with the
// daemon the GUI (§22.1). Same reasoning as cleona-play.exe.
//
// The argument list carries NOTHING of the notification (§22.8: "it is not
// passed as an argument of a process, where every local user could read
// it"):
//   cleona-notify.exe --app-id <AUMID> --name <display name> --icon <path>
//   cleona-notify.exe --check      (build-time self check: no toast, no
//                                    registry, no output)
// Standard input carries the notification: three fields, each a 4-byte
// little-endian length and that many UTF-8 bytes -- tag, title, body. The
// tag is derived in the daemon (never a contact id in the clear).
//
// Nothing is written to stderr or a file. stdout carries at most ONE line, and
// only on failure: `cleona-notify: step=<word> hresult=0x<8 hex>` -- which
// step failed and the HRESULT (a Win32 error as HRESULT_FROM_WIN32; for
// step=setting the NotificationSetting value). Never a text of the
// notification and never an error message (it could quote its input). S420:
// the first lab run ended with exit 5 and nothing to tell which call failed.
// Exit codes (the daemon logs the code and that line, never the text):
//   0  the toast was handed to Windows (or --check passed)
//   2  usage: unknown or missing argument
//   3  input: stdin unreadable, too long, malformed or not UTF-8
//   4  the app id could not be registered: the HKCU key (step=registration)
//      or the start-menu shortcut that carries it (step=shortcut)
//   5  the toast API failed (apartment, XML, notifier, Show), or --check failed
//   6  Windows blocks toasts for this app or user (ToastNotifier.Setting)
//
// THE START-MENU SHORTCUT (S420, variant A). The HKCU key alone was not
// enough: in the lab (Windows 11 build 26200, 11.11.2026) ToastNotifier.Setting
// failed with HRESULT 0x80070490 ("Element not found") for an app id that was
// registered only there. Microsoft: "For a desktop app to display a toast,
// the app must have a shortcut on the Start screen. The shortcut must have an
// AppUserModelID." (CreateToastNotifier(String), "Sending toast notifications
// from desktop apps",
// https://learn.microsoft.com/en-us/uwp/api/windows.ui.notifications.toastnotificationmanager.createtoastnotifier)
// and "Without a valid shortcut installed in the Start screen or in All
// Programs, you cannot raise a toast notification from a desktop app."
// (archived "How to enable desktop toast notifications through an
// AppUserModelID", which creates it with IShellLink + IPropertyStore
// (PKEY_AppUserModel_ID) + IPersistFile::Save,
// https://learn.microsoft.com/en-us/previous-versions/windows/desktop/legacy/hh802762(v=vs.85)).
// So at every run this program makes sure that
//   <FOLDERID_Programs>\<display name>\<display name>.lnk
// exists, targets cleona.exe next to this program and carries
// System.AppUserModel.ID = the app id; it writes only when the file is
// missing or its target or id differs. That is the very file the setup
// creates ([Icons] "{group}\{#ProductName}", {group} = the start-menu folder
// named after the product in the current user's profile, measured by E2E
// 63.05: "...\Start Menu\Programs\Cleona Beta\Cleona Beta.lnk"), so setup
// users and ZIP users each have ONE entry; the setup sets the same id on it
// (AppUserModelID) and removes it on uninstall. In-network updates never run
// the setup (v4_2 §22.6) -- an installation from before this change gets the
// id on its existing shortcut from here.
//
// Sources (read 11.11.2026, see `mycelium/berichte/S420-BAUPLAN-WIN-TOAST.md`):
//   CreateToastNotifier(applicationId): "Do not use this overload [without
//     an argument] when creating a toast notifier for a desktop app."
//     https://learn.microsoft.com/en-us/uwp/api/windows.ui.notifications.toastnotificationmanager.createtoastnotifier
//   Tag/Group, at most 64 characters (since 15063), an empty tag throws:
//     https://learn.microsoft.com/en-us/uwp/api/windows.ui.notifications.toastnotification.tag
//   <audio silent="true"/>: "True to mute the sound":
//     https://learn.microsoft.com/en-us/uwp/schemas/tiles/toastschema/element-audio
//   ToastNotifier.Setting:
//     https://learn.microsoft.com/en-us/uwp/api/windows.ui.notifications.toastnotifier.setting
//   HKCU\Software\Classes\AppUserModelId\<AUMID> with DisplayName/IconUri:
//     Microsoft names the values (archived page "Send a local toast
//     notification from other types of unpackaged apps", Step 1, repo
//     MicrosoftDocs/windows-dev-docs @ 2e559c1c, shows HKLM); HKCU as the
//     Windows Community Toolkit (ToastNotificationManagerCompat.cs @ 41c9964c,
//     lines 153, 207-209) and Firefox (measured on the lab VM) use it.
//   AUMID form, at most 128 characters, no spaces:
//     https://learn.microsoft.com/en-us/windows/win32/shell/appids
//   ReadFile on a pipe whose writer closed: FALSE with ERROR_BROKEN_PIPE:
//     https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-readfile
//   The shortcut (see above):
//     IShellLinkW: https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ishelllinkw
//     IShellLinkW::GetPath (S_FALSE: no path; SLGP_RAWPATH):
//       https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ishelllinkw-getpath
//     IPersistFile: https://learn.microsoft.com/en-us/windows/win32/api/objidl/nn-objidl-ipersistfile
//     IPropertyStore: https://learn.microsoft.com/en-us/windows/win32/api/propsys/nn-propsys-ipropertystore
//     PKEY_AppUserModel_ID (System.AppUserModel.ID, a string, Propkey.h):
//       https://learn.microsoft.com/en-us/windows/win32/properties/props-system-appusermodel-id
//     "In the System.AppUserModel.ID property of the application's shortcut
//       file": https://learn.microsoft.com/en-us/windows/win32/shell/appids
//     FOLDERID_Programs, per user, default
//       %APPDATA%\Microsoft\Windows\Start Menu\Programs:
//       https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid
//     SHGetKnownFolderPath (the caller frees the path with CoTaskMemFree):
//       https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shgetknownfolderpath
//   CLSID_ShellLink is registered with ThreadingModel "Both" (measured on the
//   lab VM, reg query HKCR\CLSID\{00021401-...}\InprocServer32), so it is
//   created in this program's multi-threaded apartment.
#include <windows.h>
#include <shellapi.h>
#include <unknwn.h>
#include <shlobj_core.h>
#include <knownfolders.h>
#include <shobjidl_core.h>
#include <propkey.h>
#include <propvarutil.h>
#include <wrl/client.h>

#include <cstdint>
#include <cstdio>
#include <cwchar>
#include <string>
#include <string_view>
#include <vector>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.UI.Notifications.h>

namespace {

using winrt::Windows::Data::Xml::Dom::XmlDocument;
using winrt::Windows::Data::Xml::Dom::XmlElement;
using winrt::Windows::UI::Notifications::NotificationSetting;
using winrt::Windows::UI::Notifications::ToastNotification;
using winrt::Windows::UI::Notifications::ToastNotificationManager;

constexpr int kExitShown = 0;
constexpr int kExitUsage = 2;
constexpr int kExitInput = 3;
constexpr int kExitRegistration = 4;
constexpr int kExitToast = 5;
constexpr int kExitBlocked = 6;

// Title (a display name), body (at most 100 characters of a message) and a
// 32-character tag are far below this; it bounds what a broken writer can
// make this process hold.
constexpr DWORD kInputLimit = 64 * 1024;
constexpr size_t kTagLimit = 64;
constexpr size_t kAppIdLimit = 128;

// Every toast of Cleona is in one group; the tag tells them apart. A toast
// with the same tag and group replaces the earlier one.
constexpr wchar_t kGroup[] = L"cleona";

void Scrub(std::wstring& s) {
  if (!s.empty()) SecureZeroMemory(s.data(), s.size() * sizeof(wchar_t));
}

// Reads all of stdin, at most kInputLimit bytes. The buffer is reserved up
// front, so no reallocation leaves a copy of the text behind.
bool ReadInput(std::vector<unsigned char>& out) {
  const HANDLE in = GetStdHandle(STD_INPUT_HANDLE);
  if (in == nullptr || in == INVALID_HANDLE_VALUE) return false;
  out.reserve(kInputLimit);
  unsigned char chunk[4096];
  bool ok = true;
  for (;;) {
    DWORD got = 0;
    if (!ReadFile(in, chunk, static_cast<DWORD>(sizeof(chunk)), &got,
                  nullptr)) {
      // The writer closed its end: that is the end of the input.
      ok = GetLastError() == ERROR_BROKEN_PIPE;
      break;
    }
    if (got == 0) break;
    if (out.size() + got > kInputLimit) {
      ok = false;
      break;
    }
    out.insert(out.end(), chunk, chunk + got);
  }
  SecureZeroMemory(chunk, sizeof(chunk));
  return ok;
}

// One length-prefixed UTF-8 field -> UTF-16. MB_ERR_INVALID_CHARS rejects
// broken input instead of showing replacement characters.
bool NextField(const std::vector<unsigned char>& in, size_t& pos,
               std::wstring& out) {
  if (in.size() - pos < 4) return false;
  const uint32_t len = static_cast<uint32_t>(in[pos]) |
                       (static_cast<uint32_t>(in[pos + 1]) << 8) |
                       (static_cast<uint32_t>(in[pos + 2]) << 16) |
                       (static_cast<uint32_t>(in[pos + 3]) << 24);
  pos += 4;
  if (len > in.size() - pos) return false;
  out.clear();
  if (len == 0) return true;
  const char* src = reinterpret_cast<const char*>(in.data() + pos);
  const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, src,
                                    static_cast<int>(len), nullptr, 0);
  if (n <= 0) return false;
  out.resize(static_cast<size_t>(n));
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, src,
                          static_cast<int>(len), out.data(), n) != n) {
    return false;
  }
  pos += len;
  return true;
}

// "no more than 128 characters and cannot contain spaces" (appids page). A
// backslash is refused as well: the id becomes part of a registry path.
bool ValidAppId(const std::wstring& id) {
  if (id.empty() || id.size() > kAppIdLimit) return false;
  for (const wchar_t c : id) {
    if (c == L' ' || c == L'\\' || c < 0x20) return false;
  }
  return true;
}

// The one diagnostic line on stdout (see the head of this file). [step] is a
// fixed word of this program, [hr] a number -- nothing else is written.
void Report(const char* step, HRESULT hr) {
  char line[80];
  const int n = std::snprintf(line, sizeof line,
                              "cleona-notify: step=%s hresult=0x%08X\n", step,
                              static_cast<unsigned>(hr));
  const HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
  if (n <= 0 || n >= static_cast<int>(sizeof line) || out == nullptr ||
      out == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written = 0;
  WriteFile(out, line, static_cast<DWORD>(n), &written, nullptr);
}

// Writes one REG_SZ value only when it is missing or different.
LSTATUS SetIfDifferent(HKEY key, const wchar_t* name, const std::wstring& value) {
  const size_t want = (value.size() + 1) * sizeof(wchar_t);
  DWORD bytes = 0;
  if (RegGetValueW(key, nullptr, name, RRF_RT_REG_SZ, nullptr, nullptr,
                   &bytes) == ERROR_SUCCESS &&
      static_cast<size_t>(bytes) == want) {
    std::wstring current(value.size() + 1, L'\0');
    if (RegGetValueW(key, nullptr, name, RRF_RT_REG_SZ, nullptr,
                     current.data(), &bytes) == ERROR_SUCCESS &&
        std::wcscmp(current.c_str(), value.c_str()) == 0) {
      return ERROR_SUCCESS;
    }
  }
  return RegSetValueExW(key, name, 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(value.c_str()),
                        static_cast<DWORD>(want));
}

// HKCU\Software\Classes\AppUserModelId\<appId>: DisplayName, IconUri --
// written at every run when missing or different. In-network updates and the
// ZIP never run the setup (v4_2 §22.6), and a moved ZIP folder heals itself
// (IconUri). No CustomActivator: there is no click target in this step.
// Returns ERROR_SUCCESS or the first Win32 error.
LSTATUS EnsureRegistration(const std::wstring& app_id, const std::wstring& name,
                           const std::wstring& icon) {
  const std::wstring path = L"Software\\Classes\\AppUserModelId\\" + app_id;
  HKEY key = nullptr;
  LSTATUS s = RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr,
                              REG_OPTION_NON_VOLATILE,
                              KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr, &key,
                              nullptr);
  if (s != ERROR_SUCCESS) return s;
  s = SetIfDifferent(key, L"DisplayName", name);
  if (s == ERROR_SUCCESS) s = SetIfDifferent(key, L"IconUri", icon);
  RegCloseKey(key);
  return s;
}

// The display name becomes a folder and a file name of the shortcut: nothing
// that could leave the start-menu folder or that a file name cannot hold.
bool ValidName(const std::wstring& name) {
  if (name.empty() || name.size() > 64 || name == L"." || name == L"..") {
    return false;
  }
  for (const wchar_t c : name) {
    if (c < 0x20 || std::wcschr(L"\\/:*?\"<>|", c) != nullptr) return false;
  }
  return true;
}

// cleona.exe and its folder: this program is bundled next to it
// (windows/runner/CMakeLists.txt copies it into the folder of cleona.exe;
// measured in the lab bundle 11.11.2026: cleona-notify.exe, cleona-play.exe
// and cleona.exe in ...\runner\Release).
HRESULT AppExe(std::wstring& exe, std::wstring& folder) {
  std::wstring self(MAX_PATH, L'\0');
  for (;;) {
    const DWORD n = GetModuleFileNameW(nullptr, self.data(),
                                       static_cast<DWORD>(self.size()));
    if (n == 0) return HRESULT_FROM_WIN32(GetLastError());
    if (n < self.size()) {
      self.resize(n);
      break;
    }
    // Truncated: try a larger buffer, up to the longest Windows path.
    if (self.size() >= 32768) {
      return HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER);
    }
    self.resize(self.size() * 2);
  }
  const size_t slash = self.find_last_of(L'\\');
  if (slash == std::wstring::npos) return E_UNEXPECTED;
  folder = self.substr(0, slash);
  exe = folder + L"\\cleona.exe";
  const DWORD attributes = GetFileAttributesW(exe.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
    // No shortcut to a program that is not there.
    return HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
  }
  return S_OK;
}

// <FOLDERID_Programs>\<name>\<name>.lnk -- the file of the setup's
// [Icons] "{group}\{#ProductName}" (see the head of this file).
HRESULT ShortcutPath(const std::wstring& name, std::wstring& folder,
                     std::wstring& file) {
  PWSTR programs = nullptr;
  const HRESULT hr =
      SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &programs);
  if (SUCCEEDED(hr)) folder = std::wstring(programs) + L"\\" + name;
  CoTaskMemFree(programs);  // "whether SHGetKnownFolderPath succeeds or not"
  if (FAILED(hr)) return hr;
  file = folder + L"\\" + name + L".lnk";
  return S_OK;
}

// The start-menu shortcut that carries the app id (see the head of this
// file): created when missing; when it exists, loaded and changed only in
// what differs -- its target (cleona.exe next to this program) or its
// System.AppUserModel.ID -- so the setup's icon, and anything else on it,
// stays. Returns S_OK or the first failing HRESULT.
HRESULT EnsureShortcut(const std::wstring& app_id, const std::wstring& name) {
  using Microsoft::WRL::ComPtr;
  std::wstring exe;
  std::wstring app_folder;
  HRESULT hr = AppExe(exe, app_folder);
  if (FAILED(hr)) return hr;
  std::wstring folder;
  std::wstring file;
  hr = ShortcutPath(name, folder, file);
  if (FAILED(hr)) return hr;

  ComPtr<IShellLinkW> link;
  hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                        IID_PPV_ARGS(&link));
  if (FAILED(hr)) return hr;
  ComPtr<IPersistFile> persist;
  hr = link.As(&persist);
  if (FAILED(hr)) return hr;
  ComPtr<IPropertyStore> store;
  hr = link.As(&store);
  if (FAILED(hr)) return hr;

  const bool exists = GetFileAttributesW(file.c_str()) != INVALID_FILE_ATTRIBUTES;
  bool same_target = false;
  bool same_id = false;
  if (exists) {
    hr = persist->Load(file.c_str(), STGM_READ);
    if (FAILED(hr)) return hr;
    wchar_t target[MAX_PATH] = {};
    // S_OK only with a path; S_FALSE means none (GetPath page).
    if (link->GetPath(target, MAX_PATH, nullptr, SLGP_RAWPATH) == S_OK) {
      same_target = CompareStringOrdinal(target, -1, exe.c_str(), -1, TRUE) ==
                    CSTR_EQUAL;
    }
    PROPVARIANT current;
    PropVariantInit(&current);
    if (SUCCEEDED(store->GetValue(PKEY_AppUserModel_ID, &current)) &&
        current.vt == VT_LPWSTR && current.pwszVal != nullptr) {
      same_id = app_id == current.pwszVal;
    }
    PropVariantClear(&current);
  }
  if (same_target && same_id) return S_OK;

  if (!same_target) {
    hr = link->SetPath(exe.c_str());
    if (SUCCEEDED(hr)) hr = link->SetWorkingDirectory(app_folder.c_str());
    if (FAILED(hr)) return hr;
  }
  if (!same_id) {
    PROPVARIANT id;
    hr = InitPropVariantFromString(app_id.c_str(), &id);
    if (FAILED(hr)) return hr;
    hr = store->SetValue(PKEY_AppUserModel_ID, id);
    PropVariantClear(&id);
    if (SUCCEEDED(hr)) hr = store->Commit();
    if (FAILED(hr)) return hr;
  }
  if (!exists && !CreateDirectoryW(folder.c_str(), nullptr)) {
    const DWORD error = GetLastError();
    if (error != ERROR_ALREADY_EXISTS) return HRESULT_FROM_WIN32(error);
  }
  hr = persist->Save(file.c_str(), TRUE);
  // Save: "S_OK ... Otherwise, it is S_FALSE" -- S_FALSE is a failure here.
  return hr == S_OK ? S_OK : (FAILED(hr) ? hr : E_FAIL);
}

winrt::hstring ToHString(const std::wstring& s) {
  return winrt::hstring(s.c_str(),
                        static_cast<winrt::hstring::size_type>(s.size()));
}

// The toast XML. The two texts are set as TEXT NODES -- never spliced into
// the markup, so a message cannot add elements or attributes. Silent:
// Cleona plays its own sound (cleona-play.exe, in its own quiet hours);
// without silent="true" Windows would play a second one.
XmlDocument BuildToast(const std::wstring& title, const std::wstring& body) {
  XmlDocument doc;
  doc.LoadXml(
      L"<toast><visual><binding template=\"ToastGeneric\">"
      L"<text/><text/></binding></visual>"
      L"<audio silent=\"true\"/></toast>");
  const auto texts = doc.GetElementsByTagName(L"text");
  texts.Item(0).AppendChild(doc.CreateTextNode(ToHString(title)));
  texts.Item(1).AppendChild(doc.CreateTextNode(ToHString(body)));
  return doc;
}

// [report]: say the failure on stdout (not in --check, which writes nothing).
bool InitApartment(bool report) {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    return true;
  } catch (const winrt::hresult_error& e) {
    if (report) Report("apartment", e.code());
    return false;
  } catch (...) {
    if (report) Report("apartment", E_FAIL);
    return false;
  }
}

bool SameText(const winrt::hstring& got, const std::wstring& want) {
  return std::wstring_view(got) == std::wstring_view(want);
}

// --check: builds the toast from a fixed sample full of markup characters and
// reads it back. Exit 0 only if both texts survive as text, no element came
// from the sample, and the toast is silent. No toast, no registry, no output.
int SelfCheck() {
  if (!InitApartment(false)) return kExitToast;
  try {
    const std::wstring title = L"<b>&amp;\"'</b>";
    const std::wstring body = L"a<text>x</text>]]><audio src=\"y\"/>b";
    const XmlDocument doc = BuildToast(title, body);
    const auto texts = doc.GetElementsByTagName(L"text");
    if (texts.Size() != 2u) return kExitToast;
    if (!SameText(texts.Item(0).as<XmlElement>().InnerText(), title) ||
        !SameText(texts.Item(1).as<XmlElement>().InnerText(), body)) {
      return kExitToast;
    }
    if (doc.GetElementsByTagName(L"b").Size() != 0u) return kExitToast;
    const auto audio = doc.GetElementsByTagName(L"audio");
    if (audio.Size() != 1u) return kExitToast;
    if (!SameText(audio.Item(0).as<XmlElement>().GetAttribute(L"silent"),
                  L"true")) {
      return kExitToast;
    }
    return kExitShown;
  } catch (...) {
    return kExitToast;
  }
}

}  // namespace

// Windows subsystem, no window: a console program started from the daemon
// would flash a console window on every notification.
int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR command_line,
                   int show) {
  (void)instance;
  (void)previous;
  (void)command_line;
  (void)show;

  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == nullptr) return kExitUsage;
  bool check = false;
  bool usage_ok = true;
  std::wstring app_id;
  std::wstring name;
  std::wstring icon;
  for (int i = 1; i < argc && usage_ok; i++) {
    const std::wstring_view arg(argv[i]);
    if (arg == L"--check") {
      check = true;
    } else if (arg == L"--app-id" && i + 1 < argc) {
      app_id = argv[++i];
    } else if (arg == L"--name" && i + 1 < argc) {
      name = argv[++i];
    } else if (arg == L"--icon" && i + 1 < argc) {
      icon = argv[++i];
    } else {
      usage_ok = false;
    }
  }
  LocalFree(argv);
  if (!usage_ok) return kExitUsage;
  if (check) {
    if (!app_id.empty() || !name.empty() || !icon.empty()) return kExitUsage;
    return SelfCheck();
  }
  if (!ValidAppId(app_id) || !ValidName(name) || icon.empty()) {
    return kExitUsage;
  }

  std::vector<unsigned char> in;
  std::wstring tag;
  std::wstring title;
  std::wstring body;
  const auto finish = [&](int code) {
    if (!in.empty()) SecureZeroMemory(in.data(), in.size());
    Scrub(tag);
    Scrub(title);
    Scrub(body);
    return code;
  };

  size_t pos = 0;
  if (!ReadInput(in) || !NextField(in, pos, tag) ||
      !NextField(in, pos, title) || !NextField(in, pos, body) ||
      pos != in.size() || tag.empty() || tag.size() > kTagLimit) {
    return finish(kExitInput);
  }
  SecureZeroMemory(in.data(), in.size());

  if (!InitApartment(true)) return finish(kExitToast);
  const LSTATUS registered = EnsureRegistration(app_id, name, icon);
  if (registered != ERROR_SUCCESS) {
    Report("registration", HRESULT_FROM_WIN32(registered));
    return finish(kExitRegistration);
  }
  // Before the toast: without the shortcut Windows refuses it (head of file).
  const HRESULT linked = EnsureShortcut(app_id, name);
  if (FAILED(linked)) {
    Report("shortcut", linked);
    return finish(kExitRegistration);
  }
  // The step that is running, for the one diagnostic line.
  const char* step = "xml";
  try {
    const ToastNotification toast{BuildToast(title, body)};
    step = "tag";
    toast.Tag(ToHString(tag));
    toast.Group(kGroup);
    step = "notifier";
    const auto notifier =
        ToastNotificationManager::CreateToastNotifier(ToHString(app_id));
    step = "setting";
    // Setting is a diagnosis, not a gate. For this unpackaged app it threw
    // HRESULT 0x80070490 (ERROR_NOT_FOUND) in every lab run since S420 --
    // also on 12.11.2026 23:50, with the registry key AND the start-menu
    // shortcut in place since 11.11. 20:11 -- and Show() was never called,
    // so no toast was ever shown (S422-RCA-E2E-LAUF-4.2.8 R-13). A comment
    // on Raymond Chen's "The Old New Thing" (10.08.2020,
    // https://devblogs.microsoft.com/oldnewthing/20200810-00/?p=104058)
    // reports the same: Setting may throw when the app is not fully
    // registered with the system; Microsoft's own desktop samples call
    // Show() without asking Setting first
    // (https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/send-local-toast-desktop-cpp-wrl).
    // A real block (a value other than Enabled) still ends here with exit 6;
    // "not found" goes on to Show().
    bool blocked = false;
    NotificationSetting setting = NotificationSetting::Enabled;
    try {
      setting = notifier.Setting();
      blocked = setting != NotificationSetting::Enabled;
    } catch (const winrt::hresult_error& e) {
      if (e.code() != HRESULT_FROM_WIN32(ERROR_NOT_FOUND)) throw;
    }
    if (blocked) {
      Report("setting", static_cast<HRESULT>(setting));
      return finish(kExitBlocked);
    }
    step = "show";
    notifier.Show(toast);
  } catch (const winrt::hresult_error& e) {
    // The code only: the error text is not needed and could quote its input.
    Report(step, e.code());
    return finish(kExitToast);
  } catch (...) {
    Report(step, E_FAIL);
    return finish(kExitToast);
  }
  return finish(kExitShown);
}
