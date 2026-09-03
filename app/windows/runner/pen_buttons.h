#ifndef OPENOTE_PEN_BUTTONS_H_
#define OPENOTE_PEN_BUTTONS_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <commctrl.h>
#include <memory>
#include <vector>

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
  void Send(bool in_range, bool eraser);
  void ReadPointer(UINT message, WPARAM wparam);
  void ReadRawInput(HRAWINPUT input);
  flutter::EncodableValue State() const;
  HWND view_;
  UINT32 pointer_id_ = 0;
  bool in_range_ = false;
  bool eraser_ = false;
  bool raw_registered_ = false;
  bool raw_in_range_ = false;
  bool raw_eraser_ = false;
  HANDLE raw_device_ = nullptr;
  std::vector<BYTE> raw_descriptor_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
