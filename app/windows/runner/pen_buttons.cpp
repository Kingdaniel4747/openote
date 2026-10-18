#include "pen_buttons.h"

namespace {
constexpr USHORT kDigitizer = 0x0d;
constexpr USHORT kBarrel = 0x44;
constexpr USHORT kInvert = 0x3c;
}  // namespace

PenButtons::PenButtons(HWND view, flutter::BinaryMessenger* messenger)
    : view_(view),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "openote/windows_pen_buttons",
          &flutter::StandardMethodCodec::GetInstance())) {
  SetWindowSubclass(view_, Observe, 1, reinterpret_cast<DWORD_PTR>(this));
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getState") result->Success(State());
        else result->NotImplemented();
      });
}

PenButtons::~PenButtons() {
  if (IsWindow(view_)) RemoveWindowSubclass(view_, Observe, 1);
  channel_->SetMethodCallHandler(nullptr);
}

flutter::EncodableValue PenButtons::State() const {
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("inRange"), flutter::EncodableValue(state_.in_range())},
      {flutter::EncodableValue("eraser"), flutter::EncodableValue(state_.eraser())},
      {flutter::EncodableValue("barrel"), flutter::EncodableValue(state_.barrel())},
      {flutter::EncodableValue("source"), flutter::EncodableValue(source_)}});
}

void PenButtons::Publish() {
  if (sent_in_range_ == state_.in_range() && sent_eraser_ == state_.eraser()) return;
  sent_in_range_ = state_.in_range();
  sent_eraser_ = state_.eraser();
  channel_->InvokeMethod("state", std::make_unique<flutter::EncodableValue>(State()));
}

void PenButtons::Reset() {
  pointer_id_ = 0;
  state_.Reset();
  source_ = "reset";
  Publish();
}

void PenButtons::ReadDeviceProperties(HANDLE device) {
  if (device_ == device) return;
  device_ = device;
  properties_.clear();
  barrel_property_ = invert_property_ = -1;
  UINT32 count = 0;
  if (!GetPointerDeviceProperties(device, &count, nullptr) || count == 0) return;
  std::vector<POINTER_DEVICE_PROPERTY> all(count);
  if (!GetPointerDeviceProperties(device, &count, all.data())) return;
  for (UINT32 i = 0; i < count; ++i) {
    const auto& property = all[i];
    if (property.usagePageId != kDigitizer) continue;
    if (property.usageId == kBarrel && barrel_property_ < 0) {
      barrel_property_ = static_cast<int>(properties_.size());
      properties_.push_back(property);
    } else if (property.usageId == kInvert && invert_property_ < 0) {
      invert_property_ = static_cast<int>(properties_.size());
      properties_.push_back(property);
    }
  }
}

void PenButtons::ObserveMessage(const MSG& message) {
  // Read exactly once before Flutter dispatches the message. A second read
  // from the subclass could see later data after a nested message pump.
  if (message.hwnd == view_) ReadPointer(message.message, message.wParam);
}

void PenButtons::ReadPointer(UINT message, WPARAM wparam) {
  const auto id = GET_POINTERID_WPARAM(wparam);
  switch (message) {
    case WM_POINTERLEAVE:
    case WM_POINTERCAPTURECHANGED:
      if (id == pointer_id_) Reset();
      return;
    case WM_POINTERENTER:
    case WM_POINTERDOWN:
    case WM_POINTERUPDATE:
    case WM_POINTERUP:
      break;
    default:
      return;
  }
  POINTER_PEN_INFO pen{};
  // Touch and mouse packets cannot change this pen's physical switch.
  if (!GetPointerPenInfo(id, &pen)) return;
  if (pointer_id_ != id || device_ != pen.pointerInfo.sourceDevice) state_.Reset();
  pointer_id_ = id;
  const auto flags = pen.pointerInfo.pointerFlags;
  if (flags & POINTER_FLAG_CANCELED) {
    Reset();
    return;
  }
  ReadDeviceProperties(pen.pointerInfo.sourceDevice);
  bool has_raw_barrel = false;
  bool raw_barrel = false;
  bool inverted = (pen.penFlags & PEN_FLAG_INVERTED) != 0;
  std::vector<LONG> values(properties_.size());
  if (!properties_.empty() && GetRawPointerDeviceData(
          id, 1, static_cast<UINT32>(properties_.size()), properties_.data(), values.data())) {
    if (barrel_property_ >= 0) {
      has_raw_barrel = true;
      raw_barrel = values[barrel_property_] != 0;
    }
    if (invert_property_ >= 0) inverted = values[invert_property_] != 0;
  }
  auto change = PenSwitchChange::none;
  if (pen.pointerInfo.ButtonChangeType == POINTER_CHANGE_SECONDBUTTON_DOWN)
    change = PenSwitchChange::pressed;
  else if (pen.pointerInfo.ButtonChangeType == POINTER_CHANGE_SECONDBUTTON_UP)
    change = PenSwitchChange::released;
  // ERASER is not a physical barrel switch: some drivers latch that mapped
  // tool for the entire proximity session. Never OR it into the switch.
  const bool barrel = (pen.penFlags & PEN_FLAG_BARREL) != 0;
  source_ = has_raw_barrel ? "raw-pointer" : "pointer-barrel";
  state_.Update((flags & POINTER_FLAG_INRANGE) != 0,
                message != WM_POINTERUP && (flags & POINTER_FLAG_INCONTACT) != 0,
                inverted, barrel, change, has_raw_barrel, raw_barrel);
  Publish();
}

LRESULT CALLBACK PenButtons::Observe(HWND hwnd, UINT message, WPARAM wparam,
                                    LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  auto self = reinterpret_cast<PenButtons*>(data);
  switch (message) {
    case WM_POINTERACTIVATE:
      return PA_ACTIVATE;
    case WM_POINTERDOWN: {
      POINTER_INPUT_TYPE type{};
      if (GetPointerType(GET_POINTERID_WPARAM(wparam), &type) && type == PT_TOUCH) {
        const HWND root = GetAncestor(hwnd, GA_ROOT);
        if (root && GetForegroundWindow() != root) SetForegroundWindow(root);
      }
      break;
    }
    case WM_KILLFOCUS:
      self->Reset();
      break;
    case WM_NCDESTROY:
      RemoveWindowSubclass(hwnd, Observe, id);
      break;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}
