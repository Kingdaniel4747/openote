#include "pen_buttons.h"

PenButtons::PenButtons(HWND view, flutter::BinaryMessenger* messenger)
    : view_(view),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "openote/windows_pen_buttons",
          &flutter::StandardMethodCodec::GetInstance())) {
  SetWindowSubclass(view_, Observe, 1, reinterpret_cast<DWORD_PTR>(this));
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getState") {
          result->Success(State());
        } else {
          result->NotImplemented();
        }
      });
}

PenButtons::~PenButtons() {
  if (IsWindow(view_)) RemoveWindowSubclass(view_, Observe, 1);
  channel_->SetMethodCallHandler(nullptr);
}

flutter::EncodableValue PenButtons::State() const {
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("inRange"), flutter::EncodableValue(in_range_)},
      {flutter::EncodableValue("eraser"), flutter::EncodableValue(eraser_)}});
}

void PenButtons::Send(bool in_range, bool eraser) {
  if (in_range == in_range_ && eraser == eraser_) return;
  in_range_ = in_range;
  eraser_ = eraser;
  channel_->InvokeMethod("state", std::make_unique<flutter::EncodableValue>(State()));
}

void PenButtons::Reset() {
  pointer_id_ = 0;
  Send(false, false);
}

LRESULT CALLBACK PenButtons::Observe(HWND hwnd, UINT message, WPARAM wparam,
                                    LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  auto self = reinterpret_cast<PenButtons*>(data);
  switch (message) {
    case WM_POINTERENTER:
    case WM_POINTERDOWN:
    case WM_POINTERUPDATE:
    case WM_POINTERUP: {
      POINTER_PEN_INFO pen{};
      if (GetPointerPenInfo(GET_POINTERID_WPARAM(wparam), &pen)) {
        self->pointer_id_ = GET_POINTERID_WPARAM(wparam);
        const bool active = (pen.pointerInfo.pointerFlags & POINTER_FLAG_INRANGE)
            && !(pen.pointerInfo.pointerFlags & POINTER_FLAG_CANCELED);
        const bool erase = active && (pen.penFlags &
            (PEN_FLAG_BARREL | PEN_FLAG_ERASER | PEN_FLAG_INVERTED));
        self->Send(active, erase);
      }
      break;
    }
    case WM_POINTERLEAVE:
    case WM_POINTERCAPTURECHANGED:
      // A palm/finger leaving must not reset the pen's own button state.
      if (GET_POINTERID_WPARAM(wparam) == self->pointer_id_) self->Reset();
      break;
    case WM_KILLFOCUS:
      self->Reset();
      break;
    case WM_NCDESTROY:
      RemoveWindowSubclass(hwnd, Observe, id);
      break;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}
