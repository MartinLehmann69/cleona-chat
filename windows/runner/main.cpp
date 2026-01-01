#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

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
  if (!window.Create(L"cleona", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Try to load beta icon from bundled assets (overrides compiled RC icon).
  // If app_icon_beta.ico exists next to data/, use it as the window icon.
  {
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

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
