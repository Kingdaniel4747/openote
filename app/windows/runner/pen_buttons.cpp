#include "pen_buttons.h"

#include <hidsdi.h>
#include <algorithm>
#include <cstddef>

namespace {
constexpr USAGE kDigitizer = 0x0d;
constexpr USAGE kPen = 0x02;
constexpr USAGE kInRange = 0x32;
constexpr USAGE kInvert = 0x3c;
constexpr USAGE kBarrel = 0x44;
constexpr USAGE kEraser = 0x45;

bool HasUsage(const HIDP_BUTTON_CAPS& cap, USAGE usage) {
  return cap.UsagePage == kDigitizer &&
      (cap.IsRange ? cap.Range.UsageMin <= usage && usage <= cap.Range.UsageMax
                   : cap.NotRange.Usage == usage);
}
}  // namespace

PenButtons::PenButtons(HWND view, flutter::BinaryMessenger* messenger)
    : view_(view),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "openote/windows_pen_buttons",
          &flutter::StandardMethodCodec::GetInstance())) {
  SetWindowSubclass(view_, Observe, 1, reinterpret_cast<DWORD_PTR>(this));
  // Compatibility path for the reported S Pen proximity-only switching:
  // read the physical HID switch too. Flags=0 means foreground only;
  // importantly, NO NOLEGACY/INPUTSINK: Flutter still owns all drawing input.
  RAWINPUTDEVICE device{kDigitizer, kPen, 0, view_};
  raw_registered_ = RegisterRawInputDevices(&device, 1, sizeof(device)) != FALSE;
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
  if (raw_registered_) {
    RAWINPUTDEVICE device{kDigitizer, kPen, RIDEV_REMOVE, nullptr};
    RegisterRawInputDevices(&device, 1, sizeof(device));
  }
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
  raw_in_range_ = false;
  raw_eraser_ = false;
  Send(false, false);
}

void PenButtons::ObserveMessage(const MSG& message) {
  if (message.hwnd == view_) ReadPointer(message.message, message.wParam);
}

void PenButtons::ReadPointer(UINT message, WPARAM wparam) {
  switch (message) {
    case WM_POINTERENTER:
    case WM_POINTERDOWN:
    case WM_POINTERUPDATE:
    case WM_POINTERUP: {
      const auto id = GET_POINTERID_WPARAM(wparam);
      POINTER_PEN_INFO pen{};
      if (GetPointerPenInfo(id, &pen)) {
        pointer_id_ = id;
        const bool active = (pen.pointerInfo.pointerFlags & POINTER_FLAG_INRANGE)
            && !(pen.pointerInfo.pointerFlags & POINTER_FLAG_CANCELED);
        const bool erase = (pen.penFlags &
            (PEN_FLAG_BARREL | PEN_FLAG_ERASER | PEN_FLAG_INVERTED)) != 0 ||
            IS_POINTER_SECONDBUTTON_WPARAM(wparam);
        if (!active) Reset();
        else Send(true, raw_in_range_ ? raw_eraser_ : erase);
      } else if (id == pointer_id_ && IS_POINTER_INCONTACT_WPARAM(wparam)) {
        // Message flags remain usable even if a nested message pump expired
        // GetPointerPenInfo. Hover buttons require the pen/HID report instead.
        Send(true, raw_in_range_ ? raw_eraser_ :
            IS_POINTER_SECONDBUTTON_WPARAM(wparam) != 0);
      }
      break;
    }
    case WM_POINTERLEAVE:
    case WM_POINTERCAPTURECHANGED:
      if (GET_POINTERID_WPARAM(wparam) == pointer_id_) Reset();
      break;
  }
}

void PenButtons::ReadRawInput(HRAWINPUT input) {
  if (GetForegroundWindow() != GetAncestor(view_, GA_ROOT)) return;
  UINT size = 0;
  if (GetRawInputData(input, RID_INPUT, nullptr, &size,
                      sizeof(RAWINPUTHEADER)) != 0 ||
      size < offsetof(RAWINPUT, data.hid.bRawData)) return;
  std::vector<BYTE> bytes(size);
  if (GetRawInputData(input, RID_INPUT, bytes.data(), &size,
                      sizeof(RAWINPUTHEADER)) != size) return;
  const auto raw = reinterpret_cast<const RAWINPUT*>(bytes.data());
  if (raw->header.dwType != RIM_TYPEHID) return;
  if (raw->header.hDevice != raw_device_ || raw_descriptor_.empty()) {
    raw_descriptor_.clear();
    raw_device_ = raw->header.hDevice;
    raw_in_range_ = false;
    UINT length = 0;
    if (GetRawInputDeviceInfo(raw_device_, RIDI_PREPARSEDDATA, nullptr,
                             &length) == UINT(-1) || length == 0) return;
    raw_descriptor_.resize(length);
    if (GetRawInputDeviceInfo(raw_device_, RIDI_PREPARSEDDATA,
                             raw_descriptor_.data(), &length) == UINT(-1)) {
      raw_descriptor_.clear();
      return;
    }
  }
  auto descriptor = reinterpret_cast<PHIDP_PREPARSED_DATA>(raw_descriptor_.data());
  HIDP_CAPS caps{};
  if (HidP_GetCaps(descriptor, &caps) != HIDP_STATUS_SUCCESS ||
      caps.UsagePage != kDigitizer || caps.Usage != kPen) return;
  USHORT count = caps.NumberInputButtonCaps;
  if (count == 0) return;
  std::vector<HIDP_BUTTON_CAPS> buttons(count);
  if (HidP_GetButtonCaps(HidP_Input, buttons.data(), &count, descriptor) !=
      HIDP_STATUS_SUCCESS) return;
  const auto& hid = raw->data.hid;
  const size_t offset = reinterpret_cast<const BYTE*>(hid.bRawData) - bytes.data();
  if (hid.dwSizeHid == 0 || offset > bytes.size() ||
      hid.dwCount > (bytes.size() - offset) / hid.dwSizeHid) return;
  for (DWORD i = 0; i < hid.dwCount; ++i) {
    auto report = reinterpret_cast<PCHAR>(
        const_cast<BYTE*>(hid.bRawData + i * hid.dwSizeHid));
    bool has_barrel = false;
    bool has_range = false;
    for (USHORT j = 0; j < count; ++j) {
      const auto& cap = buttons[j];
      if (cap.ReportID != 0 && cap.ReportID != static_cast<BYTE>(report[0])) continue;
      has_barrel |= HasUsage(cap, kBarrel);
      has_range |= HasUsage(cap, kInRange);
    }
    // Require both usages in this report. Never interpret an unrelated report
    // (e.g. battery status) as a button release, or latch an out-of-range pen.
    if (!has_barrel || !has_range) continue;
    ULONG length = HidP_MaxUsageListLength(HidP_Input, kDigitizer, descriptor);
    if (length == 0) continue;
    std::vector<USAGE> usages(length);
    if (HidP_GetUsages(HidP_Input, kDigitizer, 0, usages.data(), &length,
                      descriptor, report, hid.dwSizeHid) != HIDP_STATUS_SUCCESS) continue;
    auto on = [&](USAGE usage) {
      return std::find(usages.begin(), usages.begin() + length, usage) !=
          usages.begin() + length;
    };
    raw_in_range_ = on(kInRange);
    raw_eraser_ = on(kBarrel) || on(kInvert) || on(kEraser);
    Send(raw_in_range_, raw_in_range_ && raw_eraser_);
  }
}

LRESULT CALLBACK PenButtons::Observe(HWND hwnd, UINT message, WPARAM wparam,
                                    LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  auto self = reinterpret_cast<PenButtons*>(data);
  self->ReadPointer(message, wparam);
  switch (message) {
    case WM_INPUT:
      self->ReadRawInput(reinterpret_cast<HRAWINPUT>(lparam));
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
