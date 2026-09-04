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
          if (work_area_maximized_) {
            SetWindowPos(window_, nullptr, restore_bounds_.left,
                restore_bounds_.top,
                restore_bounds_.right - restore_bounds_.left,
                restore_bounds_.bottom - restore_bounds_.top,
                SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
            work_area_maximized_ = false;
          } else {
            GetWindowRect(window_, &restore_bounds_);
            const HMONITOR monitor =
                MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST);
            MONITORINFO info{};
            info.cbSize = sizeof(info);
            if (GetMonitorInfo(monitor, &info)) {
              const RECT area = info.rcWork;
              // Leave the bottom edge to Explorer. A borderless window that
              // owns the final screen pixel can prevent an auto-hidden
              // taskbar from opening when the pen or mouse reaches it.
              const LONG available_height = area.bottom - area.top - 1;
              SetWindowPos(window_, nullptr, area.left, area.top,
                  area.right - area.left,
                  available_height > 1 ? available_height : 1,
                  SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
              work_area_maximized_ = true;
            }
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
        } else {
          result->NotImplemented();
        }
      });
}

WindowControls::~WindowControls() { channel_->SetMethodCallHandler(nullptr); }
