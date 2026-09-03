#ifndef OPENOTE_WRITING_SERVICES_H_
#define OPENOTE_WRITING_SERVICES_H_
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>

// Local Windows spelling/handwriting only. Workers never call a destroyed
// Flutter messenger: Dart polls results; teardown never waits on recognition.
class WritingServices {
 public:
  explicit WritingServices(flutter::BinaryMessenger* messenger);
  ~WritingServices();
 private:
  struct State;
  std::shared_ptr<State> state_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
