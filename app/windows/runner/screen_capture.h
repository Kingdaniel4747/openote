#ifndef OPENOTE_SCREEN_CAPTURE_H_
#define OPENOTE_SCREEN_CAPTURE_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <vector>

/// Full-desktop selection overlay for the Windows-only screen clipping tool.
/// It hides the Openote HWND while selecting, then returns PNG bytes through
/// the platform channel after the overlay has gone away.
class ScreenCapture {
 public:
  ScreenCapture(HWND host, flutter::BinaryMessenger* messenger);
  ~ScreenCapture();

  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam);

 private:
  using Result = flutter::MethodResult<flutter::EncodableValue>;

  bool Start(std::unique_ptr<Result> result);
  void Finish(bool accepted);
  void Paint();
  bool EncodeSelection(std::vector<uint8_t>* png) const;
  HWND host_;
  HWND overlay_ = nullptr;
  POINT screen_origin_{};
  POINT start_{};
  POINT current_{};
  bool selecting_ = false;
  std::unique_ptr<Result> pending_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // OPENOTE_SCREEN_CAPTURE_H_
