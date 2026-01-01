#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdlib>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Whether this bundle is a live build (v4_2 §26.2). The channel is compiled into
// the Dart side only; data\channel is written by the release build. Without the
// file a build counts as beta, like the Dart default.
bool BundleIsLive() {
  wchar_t exe_path[MAX_PATH];
  if (!GetModuleFileNameW(nullptr, exe_path, MAX_PATH)) return false;
  std::wstring dir(exe_path);
  auto pos = dir.find_last_of(L'\\');
  if (pos == std::wstring::npos) return false;
  HANDLE file = ::CreateFileW((dir.substr(0, pos) + L"\\data\\channel").c_str(),
                              GENERIC_READ, FILE_SHARE_READ, nullptr,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  char buffer[4] = {0};
  DWORD read = 0;
  const BOOL ok = ::ReadFile(file, buffer, sizeof(buffer), &read, nullptr);
  ::CloseHandle(file);
  return ok && read == sizeof(buffer) && std::string(buffer, 4) == "live";
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  const bool is_live = BundleIsLive();
  if (!window.Create(is_live ? L"Cleona Chat" : L"Cleona Beta", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Try to load beta icon from bundled assets (overrides compiled RC icon).
  // If app_icon_beta.ico exists next to data/, use it as the window icon.
  // Every bundle carries both icons, so the channel decides.
  if (!is_live) {
    wchar_t exe_path[MAX_PATH];
    if (GetModuleFileNameW(nullptr, exe_path, MAX_PATH)) {
      std::wstring dir(exe_path);
      auto pos = dir.find_last_of(L'\\');
      if (pos != std::wstring::npos) {
        dir = dir.substr(0, pos);
        std::wstring beta_ico = dir + L"\\data\\flutter_assets\\assets\\app_icon_beta.ico";
        HANDLE hIcon = LoadImageW(nullptr, beta_ico.c_str(), IMAGE_ICON, 0, 0,
                                  LR_LOADFROMFILE | LR_DEFAULTSIZE);
        if (hIcon) {
          HWND hwnd = window.GetHandle();
          SendMessage(hwnd, WM_SETICON, ICON_BIG, (LPARAM)hIcon);
          SendMessage(hwnd, WM_SETICON, ICON_SMALL, (LPARAM)hIcon);
        }
      }
    }
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // v4_2 §26.5.4 (S407-RUECKNAHME R-2): the message loop ended in order — the
  // window was closed, it did not crash. While a desktop update is pending,
  // leave a note beside its marker; the next window start reads it
  // (BinaryUpdateManager.guiStartAfterUpdate) and does not roll back. A crash
  // or a forced end never reaches this line. The Dart side cannot write it:
  // the framework's exit request (AppLifecycleListener.onExitRequested) was
  // measured not to arrive on this runner (lab VM, 20.10.2026), and the
  // process ends right after this loop. AppPaths.home on Windows is
  // %USERPROFILE%; the profile is <home>\.cleona (live) or <home>\.cleona-beta
  // (beta, §21.4).
  {
    wchar_t* profile = nullptr;
    size_t len = 0;
    if (_wdupenv_s(&profile, &len, L"USERPROFILE") == 0 && profile != nullptr) {
      std::wstring dir = std::wstring(profile) +
                         (is_live ? L"\\.cleona\\update\\" : L"\\.cleona-beta\\update\\");
      free(profile);
      if (::GetFileAttributesW((dir + L"update-pending.json").c_str()) !=
          INVALID_FILE_ATTRIBUTES) {
        HANDLE note = ::CreateFileW((dir + L"gui-clean-exit").c_str(),
                                    GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                                    FILE_ATTRIBUTE_NORMAL, nullptr);
        if (note != INVALID_HANDLE_VALUE) ::CloseHandle(note);
      }
    }
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
