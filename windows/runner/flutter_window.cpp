#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shlobj.h>

#include <ctime>
#include <fstream>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"


namespace {

// WDA_EXCLUDEFROMCAPTURE needs Windows 10 version 2004 (section 23.10); older SDK
// headers do not define it.
#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif

// Writes |png| to <Pictures>\Cleona\cleona_<time>.png and returns the full
// path, or an empty string on failure. The picture leaves the application's
// protection on purpose - the user asked for it (section 23.10, section 21.4.2).
std::wstring SaveOwnScreenshot(const std::vector<uint8_t>& png) {
  PWSTR pictures = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_Pictures, 0, nullptr, &pictures))) {
    return L"";
  }
  std::wstring dir = std::wstring(pictures) + L"\\Cleona";
  CoTaskMemFree(pictures);
  CreateDirectoryW(dir.c_str(), nullptr);  // exists already: fine
  std::time_t now = std::time(nullptr);
  std::tm local{};
  localtime_s(&local, &now);
  wchar_t stamp[32];
  wcsftime(stamp, 32, L"%Y%m%d_%H%M%S", &local);
  std::wstring path = dir + L"\\cleona_" + stamp + L".png";
  std::ofstream out(path, std::ios::binary);
  if (!out) return L"";
  out.write(reinterpret_cast<const char*>(png.data()),
            static_cast<std::streamsize>(png.size()));
  return out.good() ? path : L"";
}

std::string Utf8(const std::wstring& w) {
  if (w.empty()) return std::string();
  int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr,
                              nullptr);
  std::string s(n > 0 ? n - 1 : 0, '\0');
  if (n > 0) {
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, s.data(), n, nullptr,
                        nullptr);
  }
  return s;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // section 23.10: exclude the main window from capture - screenshots, recorders
  // and remote-support tools do not show it - on every build, before the
  // first frame. Only the test run lifts it (`allowCapture`, beta builds
  // only, decided on the Dart side: capture_exclusion.dart).
  HWND top = GetHandle();
  if (!SetWindowDisplayAffinity(top, WDA_EXCLUDEFROMCAPTURE)) {
    OutputDebugStringW(
        L"[cleona] SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE) failed - "
        L"Windows older than 10 version 2004?\n");
  }

  auto* messenger = flutter_controller_->engine()->messenger();
  capture_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "chat.cleona/capture",
          &flutter::StandardMethodCodec::GetInstance());
  capture_channel_->SetMethodCallHandler(
      [top](const flutter::MethodCall<flutter::EncodableValue>& call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                result) {
        if (call.method_name() == "allowCapture") {
          SetWindowDisplayAffinity(top, WDA_NONE);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  screenshot_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "chat.cleona/screenshot",
          &flutter::StandardMethodCodec::GetInstance());
  screenshot_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "savePng") {
          result->NotImplemented();
          return;
        }
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (args == nullptr) {
          result->Error("NO_PNG", "missing arguments");
          return;
        }
        auto it = args->find(flutter::EncodableValue("png"));
        const auto* png = it == args->end()
                              ? nullptr
                              : std::get_if<std::vector<uint8_t>>(&it->second);
        if (png == nullptr || png->empty()) {
          result->Error("NO_PNG", "missing picture");
          return;
        }
        std::wstring path = SaveOwnScreenshot(*png);
        if (path.empty()) {
          result->Error("SAVE_FAILED", "could not write the picture");
          return;
        }
        flutter::EncodableMap reply;
        reply[flutter::EncodableValue("uri")] =
            flutter::EncodableValue(Utf8(path));
        result->Success(flutter::EncodableValue(reply));
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
