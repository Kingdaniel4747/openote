#include "touch_input.h"

#include <algorithm>

TouchInput::TouchInput(HWND view, flutter::BinaryMessenger* messenger)
    : view_(view),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "openote/windows_touch_input",
          &flutter::StandardMethodCodec::GetInstance())) {
  SetWindowSubclass(view_, Observe, 2, reinterpret_cast<DWORD_PTR>(this));
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "start") {
          result->NotImplemented();
          return;
        }
        // Do not replace the engine transport halfway through an old contact.
        started_ = true;
        result->Success();
      });
}

TouchInput::~TouchInput() {
  if (IsWindow(view_)) RemoveWindowSubclass(view_, Observe, 2);
  channel_->SetMethodCallHandler(nullptr);
}

void TouchInput::Send(UINT32 id, int phase, const POINTER_TOUCH_INFO& info) {
  POINT point = info.pointerInfo.ptPixelLocation;
  ScreenToClient(view_, &point);
  const bool area = (info.touchMask & TOUCH_MASK_CONTACTAREA) != 0;
  const auto& rect = info.rcContact;
  channel_->InvokeMethod("pointer", std::make_unique<flutter::EncodableValue>(
      flutter::EncodableMap{
          {flutter::EncodableValue("id"), flutter::EncodableValue(static_cast<int64_t>(id))},
          {flutter::EncodableValue("phase"), flutter::EncodableValue(phase)},
          {flutter::EncodableValue("x"), flutter::EncodableValue(static_cast<double>(point.x))},
          {flutter::EncodableValue("y"), flutter::EncodableValue(static_cast<double>(point.y))},
          {flutter::EncodableValue("width"), flutter::EncodableValue(area ? static_cast<double>(std::max(0L, rect.right - rect.left)) : 0.0)},
          {flutter::EncodableValue("height"), flutter::EncodableValue(area ? static_cast<double>(std::max(0L, rect.bottom - rect.top)) : 0.0)},
          {flutter::EncodableValue("intended"), flutter::EncodableValue(
              (info.pointerInfo.pointerFlags & POINTER_FLAG_CONFIDENCE) != 0 &&
              (info.pointerInfo.pointerFlags & POINTER_FLAG_CANCELED) == 0)},
          {flutter::EncodableValue("time"), flutter::EncodableValue(static_cast<int64_t>(GetTickCount64()))},
      }));
}

void TouchInput::CancelAll() {
  // Clear before sending: dispatch may cause nested window messages.
  auto contacts = std::move(contacts_);
  contacts_.clear();
  for (const auto& [id, info] : contacts) {
    ended_.insert(id);
    Send(id, 3, info);
  }
}

bool TouchInput::Handle(UINT message, WPARAM wparam) {
  if (!started_) return false;
  if (message != WM_POINTERDOWN && message != WM_POINTERUPDATE &&
      message != WM_POINTERUP && message != WM_POINTERLEAVE &&
      message != WM_POINTERCAPTURECHANGED) return false;
  const auto id = GET_POINTERID_WPARAM(wparam);
  if (ended_.contains(id)) {
    if (message == WM_POINTERDOWN) {
      ended_.erase(id);
    } else {
      if (message == WM_POINTERLEAVE)
        ended_.erase(id);
      return true;
    }
  }
  auto previous = contacts_.find(id);
  if (message == WM_POINTERLEAVE || message == WM_POINTERCAPTURECHANGED) {
    if (previous == contacts_.end()) return false;
    const auto info = previous->second;
    contacts_.erase(previous);
    if (message != WM_POINTERLEAVE) ended_.insert(id);
    Send(id, 3, info);
    return true;
  }
  POINTER_TOUCH_INFO info{};
  if (!GetPointerTouchInfo(id, &info)) {
    // Do not strand an owned contact or hand its tail to Flutter.
    if (previous == contacts_.end()) return false;
    const auto old = previous->second;
    contacts_.erase(previous);
    ended_.insert(id);
    Send(id, 3, old);
    return true;
  }
  if (message == WM_POINTERDOWN) {
    if (previous != contacts_.end()) {
      const auto old = previous->second;
      contacts_.erase(previous);
      Send(id, 3, old);
    }
    contacts_[id] = info;
    Send(id, 0, info);
  } else if (previous == contacts_.end()) {
    return false;  // A contact begun before start still belongs to the engine.
  } else if (message == WM_POINTERUP ||
             (info.pointerInfo.pointerFlags & POINTER_FLAG_CANCELED) != 0) {
    contacts_.erase(previous);
    ended_.insert(id);  // Also consume the trailing LEAVE after a normal UP.
    Send(id, (info.pointerInfo.pointerFlags & POINTER_FLAG_CANCELED) ? 3 : 2, info);
  } else {
    contacts_[id] = info;
    Send(id, 1, info);
  }
  return true;
}

LRESULT CALLBACK TouchInput::Observe(HWND hwnd, UINT message, WPARAM wparam,
                                    LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  auto self = reinterpret_cast<TouchInput*>(data);
  if (message == WM_KILLFOCUS || (message == WM_ACTIVATEAPP && !wparam))
    self->CancelAll();
  if (self->Handle(message, wparam)) return 0;
  if (message == WM_NCDESTROY) RemoveWindowSubclass(hwnd, Observe, id);
  return DefSubclassProc(hwnd, message, wparam, lparam);
}
