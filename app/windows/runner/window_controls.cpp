#include "window_controls.h"
#include <dwmapi.h>

WindowControls::WindowControls(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "openote/window_controls",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "customChrome") {
          // Keep the native resize border and system menu. Flutter supplies
          // the caption only once its replacement controls are mounted.
          SetWindowLongPtr(window_, GWL_STYLE,
              GetWindowLongPtr(window_, GWL_STYLE) & ~WS_CAPTION);
          SetWindowPos(window_, nullptr, 0, 0, 0, 0,
              SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
          result->Success(flutter::EncodableValue(true));
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
          ShowWindow(window_, IsZoomed(window_) ? SW_RESTORE : SW_MAXIMIZE);
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
        } else {
          result->NotImplemented();
        }
      });
}

WindowControls::~WindowControls() { channel_->SetMethodCallHandler(nullptr); }
