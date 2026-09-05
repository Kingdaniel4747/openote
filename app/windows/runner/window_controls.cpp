#include "window_controls.h"
#include <dwmapi.h>
#include <shellapi.h>

WindowControls::WindowControls(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "openote/window_controls",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "customChrome") {
          // Use the real Windows caption and caption buttons. Besides looking
          // familiar, this gives Windows 11 its Snap Layout suggestions,
          // native taskbar behaviour and the normal minimize/maximize/close
          // animations without trying to reproduce them in Flutter.
          result->Success(flutter::EncodableValue(false));
        } else if (call.method_name() == "chromeColor") {
          const auto color = call.arguments() ? std::get_if<int32_t>(call.arguments()) : nullptr;
          if (!color) { result->Error("argument", "Expected COLORREF"); return; }
          // Windows 11 caption/border colour; older Windows safely ignores it.
          const COLORREF value = static_cast<COLORREF>(*color);
          DwmSetWindowAttribute(window_, static_cast<DWMWINDOWATTRIBUTE>(34), &value, sizeof(value));
          DwmSetWindowAttribute(window_, static_cast<DWMWINDOWATTRIBUTE>(35), &value, sizeof(value));
          result->Success();
        } else if (call.method_name() == "drag") {
          result->Success();
          ReleaseCapture();
          PostMessage(window_, WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);
        } else if (call.method_name() == "maximize") {
          // Let Windows do this itself. It knows the taskbar work area and
          // supplies the same native maximize/restore animation as every
          // other desktop app. Manual SetWindowPos looked like fullscreen and
          // bypassed both of those behaviours.
          if (IsZoomed(window_)) {
            ShowWindow(window_, SW_RESTORE);
          } else {
            ShowWindow(window_, SW_MAXIMIZE);
          }
          result->Success();
        } else if (call.method_name() == "minimize") {
          ShowWindow(window_, SW_MINIMIZE);
          result->Success();
        } else if (call.method_name() == "hide") {
          ShowWindow(window_, SW_HIDE);
          result->Success();
        } else if (call.method_name() == "show") {
          ShowWindow(window_, SW_SHOW);
          SetForegroundWindow(window_);
          result->Success();
        } else if (call.method_name() == "showTouchKeyboard") {
          // Flutter's Windows text connection accepts touch input but does not
          // ask Windows to show its tablet keyboard. In tablet mode TabTip is
          // the system-owned keyboard, so start it rather than implementing a
          // second keyboard in the app.
          const wchar_t* tab_tip =
              L"C:\\Program Files\\Common Files\\microsoft shared\\ink\\TabTip.exe";
          const auto launched = reinterpret_cast<INT_PTR>(
              ShellExecuteW(nullptr, L"open", tab_tip, nullptr, nullptr, SW_SHOWNORMAL));
          if (launched <= 32) {
            ShellExecuteW(nullptr, L"open", L"TabTip.exe", nullptr, nullptr, SW_SHOWNORMAL);
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

WindowControls::~WindowControls() { channel_->SetMethodCallHandler(nullptr); }
