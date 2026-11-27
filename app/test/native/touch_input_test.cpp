// Exercises the runner's real subclass/codec with deterministic Win32 packets.
// Link against the built flutter_wrapper_app.lib (Release, /MD, C++20).
#include "../../windows/runner/touch_input.h"
#include <cassert>
#include <iostream>

namespace {
SUBCLASSPROC callback;
DWORD_PTR callback_data;
POINTER_TOUCH_INFO sample{};
bool readable = true;
int engine_messages = 0;
BOOL FakeSetSubclass(HWND, SUBCLASSPROC proc, UINT_PTR, DWORD_PTR data) {
  callback = proc;
  callback_data = data;
  return TRUE;
}
BOOL FakeRemoveSubclass(HWND, SUBCLASSPROC, UINT_PTR) { return TRUE; }
BOOL FakeIsWindow(HWND) { return TRUE; }
BOOL FakeScreenToClient(HWND, LPPOINT pt) {
  pt->x -= 100;
  pt->y -= 200;
  return TRUE;
}
BOOL FakeGetTouch(UINT32, POINTER_TOUCH_INFO* info) {
  if (!readable) return FALSE;
  *info = sample;
  return TRUE;
}
LRESULT FakeNext(HWND, UINT, WPARAM, LPARAM) {
  ++engine_messages;
  return 42;
}
}  // namespace

#define SetWindowSubclass FakeSetSubclass
#define RemoveWindowSubclass FakeRemoveSubclass
#define IsWindow FakeIsWindow
#define ScreenToClient FakeScreenToClient
#define GetPointerTouchInfo FakeGetTouch
#define DefSubclassProc FakeNext
#include "../../windows/runner/touch_input.cpp"
#undef SetWindowSubclass
#undef RemoveWindowSubclass
#undef IsWindow
#undef ScreenToClient
#undef GetPointerTouchInfo
#undef DefSubclassProc

class Messenger : public flutter::BinaryMessenger {
 public:
  mutable std::vector<flutter::EncodableMap> packets;
  flutter::BinaryMessageHandler handler;
  void Send(const std::string&, const uint8_t* bytes, size_t size,
            flutter::BinaryReply reply) const override {
    const auto call = flutter::StandardMethodCodec::GetInstance()
                          .DecodeMethodCall(bytes, size);
    assert(call && call->method_name() == "pointer");
    packets.push_back(std::get<flutter::EncodableMap>(*call->arguments()));
  }
  void SetMessageHandler(const std::string&,
                         flutter::BinaryMessageHandler next) override {
    handler = std::move(next);
  }
  void Start() {
    auto bytes = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
        flutter::MethodCall<flutter::EncodableValue>("start", nullptr));
    handler(bytes->data(), bytes->size(), [](const uint8_t*, size_t) {});
  }
  template <typename T> T Last(const char* key) const {
    return std::get<T>(packets.back().at(flutter::EncodableValue(key)));
  }
};

int main() {
  Messenger messenger;
  TouchInput input(nullptr, &messenger);
  auto send = [](UINT message, UINT32 id = 7) {
    return callback(nullptr, message, id, 0, 2, callback_data);
  };
  sample.pointerInfo.ptPixelLocation = {110, 220};
  sample.pointerInfo.pointerFlags = POINTER_FLAG_CONFIDENCE;
  sample.touchMask = TOUCH_MASK_CONTACTAREA;
  sample.rcContact = {100, 210, 120, 230};
  assert(send(WM_POINTERDOWN) == 42); // Not attached: engine retains input.
  messenger.Start();
  assert(send(WM_POINTERUPDATE) == 42); // Old contact stays with engine.
  assert(send(WM_POINTERDOWN) == 0);
  assert(messenger.Last<int>("phase") == 0);
  assert(messenger.Last<bool>("intended"));
  assert(messenger.Last<double>("x") == 10);
  assert(messenger.Last<double>("y") == 20);
  assert(messenger.Last<double>("width") == 20);
  sample.pointerInfo.pointerFlags = 0; // Device now identifies a palm.
  assert(send(WM_POINTERUPDATE) == 0);
  assert(!messenger.Last<bool>("intended"));
  assert(send(WM_POINTERUP) == 0);
  assert(messenger.Last<int>("phase") == 2);
  auto count = messenger.packets.size();
  assert(send(WM_POINTERLEAVE) == 0); // No phantom engine pointer after UP.
  assert(messenger.packets.size() == count);

  // Cancellation/focus loss consumes the whole tail; a reused ID starts fresh.
  for (const auto end : {WM_POINTERCAPTURECHANGED, WM_KILLFOCUS}) {
    sample.pointerInfo.pointerFlags = POINTER_FLAG_CONFIDENCE;
    assert(send(WM_POINTERDOWN) == 0);
    send(end);
    assert(messenger.Last<int>("phase") == 3);
    count = messenger.packets.size();
    assert(send(WM_POINTERUPDATE) == 0);
    assert(send(WM_POINTERUP) == 0);
    assert(send(WM_POINTERLEAVE) == 0);
    assert(messenger.packets.size() == count);
  }
  assert(send(WM_POINTERDOWN) == 0);
  readable = false;
  assert(send(WM_POINTERUPDATE) == 0); // Failed read cancels, never strands.
  assert(messenger.Last<int>("phase") == 3);
  assert(send(WM_POINTERUP) == 0);
  assert(send(WM_POINTERLEAVE) == 0);
  assert(send(WM_POINTERDOWN, 99) == 42); // Pen/mouse stay in the engine.
  std::cout << "Native touch transport checks passed\n";
}
