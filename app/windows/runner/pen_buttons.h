#ifndef OPENOTE_PEN_BUTTONS_H_
#define OPENOTE_PEN_BUTTONS_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <commctrl.h>
#include <memory>
#include <vector>
#include "pen_button_state.h"

// Observes only this app's input. Never consumes or synthesizes pointer input.
class PenButtons {
 public:
  PenButtons(HWND view, flutter::BinaryMessenger* messenger);
  ~PenButtons();
  void Reset();
  // Read queued pointer information before Flutter/plugins can read the next
  // message (GetPointerPenInfo is only valid for the current message).
  void ObserveMessage(const MSG& message);

 private:
  static LRESULT CALLBACK Observe(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam, UINT_PTR id, DWORD_PTR data);
  void Publish();
  void ReadPointer(UINT message, WPARAM wparam);
  void ReadDeviceProperties(HANDLE device);
  flutter::EncodableValue State() const;
  HWND view_;
  UINT32 pointer_id_ = 0;
  PenButtonState state_;
  bool sent_in_range_ = false;
  bool sent_eraser_ = false;
  HANDLE device_ = nullptr;
  std::vector<POINTER_DEVICE_PROPERTY> properties_;
  int barrel_property_ = -1;
  int invert_property_ = -1;
  const char* source_ = "pointer";
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
