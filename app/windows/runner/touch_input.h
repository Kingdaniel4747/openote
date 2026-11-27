#ifndef OPENOTE_TOUCH_INPUT_H_
#define OPENOTE_TOUCH_INPUT_H_

#include <windows.h>
#include <commctrl.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <map>
#include <memory>
#include <set>

// App-local touch transport: retain Windows confidence/contact area, which the
// engine's pointer events currently omit. Pen/mouse input stays with Flutter.
class TouchInput {
 public:
  TouchInput(HWND view, flutter::BinaryMessenger* messenger);
  ~TouchInput();
  void CancelAll();

 private:
  static LRESULT CALLBACK Observe(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam, UINT_PTR id, DWORD_PTR data);
  bool Handle(UINT message, WPARAM wparam);
  void Send(UINT32 id, int phase, const POINTER_TOUCH_INFO& info);
  HWND view_;
  bool started_ = false;
  std::map<UINT32, POINTER_TOUCH_INFO> contacts_;
  std::set<UINT32> ended_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
