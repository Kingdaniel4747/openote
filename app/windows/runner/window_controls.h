#ifndef OPENOTE_WINDOW_CONTROLS_H_
#define OPENOTE_WINDOW_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <memory>

class WindowControls {
 public:
  WindowControls(HWND window, flutter::BinaryMessenger* messenger);
  ~WindowControls();
 private:
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
