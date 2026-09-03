#ifndef OPENOTE_PEN_BUTTONS_H_
#define OPENOTE_PEN_BUTTONS_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <commctrl.h>
#include <memory>

// Observes only this app's Flutter child window. Never consumes pointer input.
class PenButtons {
 public:
  PenButtons(HWND view, flutter::BinaryMessenger* messenger);
  ~PenButtons();
  void Reset();

 private:
  static LRESULT CALLBACK Observe(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam, UINT_PTR id, DWORD_PTR data);
  void Send(bool in_range, bool eraser);
  flutter::EncodableValue State() const;
  HWND view_;
  UINT32 pointer_id_ = 0;
  bool in_range_ = false;
  bool eraser_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
