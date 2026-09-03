#include "window_controls.h"

WindowControls::WindowControls(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "openote/window_controls",
          &flutter::StandardMethodCodec::GetInstance())) {
  placement_.length = sizeof(placement_);
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getFullscreen") {
          result->Success(flutter::EncodableValue(fullscreen_));
        } else if (call.method_name() == "setFullscreen") {
          const auto value = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
          if (!value) result->Error("argument", "Expected a boolean");
          else if (!SetFullscreen(*value)) result->Error("window", "Cannot resize window");
          else result->Success(flutter::EncodableValue(fullscreen_));
        } else if (call.method_name() == "minimize") {
          ShowWindow(window_, SW_MINIMIZE);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

WindowControls::~WindowControls() { channel_->SetMethodCallHandler(nullptr); }

bool WindowControls::SetFullscreen(bool value) {
  if (fullscreen_ == value) return true;
  if (value) {
    if (!GetWindowPlacement(window_, &placement_)) return false;
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(monitor);
    if (!GetMonitorInfo(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST),
                        &monitor)) return false;
    saved_style_ = GetWindowLongPtr(window_, GWL_STYLE);
    SetWindowLongPtr(window_, GWL_STYLE, saved_style_ & ~WS_OVERLAPPEDWINDOW);
    fullscreen_ = true;
    const auto& r = monitor.rcMonitor;
    if (!SetWindowPos(window_, nullptr, r.left, r.top, r.right - r.left,
                      r.bottom - r.top, SWP_NOZORDER | SWP_FRAMECHANGED | SWP_NOACTIVATE)) {
      fullscreen_ = false;
      SetWindowLongPtr(window_, GWL_STYLE, saved_style_);
      SetWindowPlacement(window_, &placement_);
      return false;
    }
  } else {
    fullscreen_ = false;
    SetWindowLongPtr(window_, GWL_STYLE, saved_style_);
    SetWindowPlacement(window_, &placement_);
    SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }
  return true;
}

void WindowControls::FitMonitor() {
  if (!fullscreen_ || IsIconic(window_)) return;
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!GetMonitorInfo(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &monitor)) return;
  const auto& r = monitor.rcMonitor;
  SetWindowPos(window_, nullptr, r.left, r.top, r.right - r.left, r.bottom - r.top,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}
