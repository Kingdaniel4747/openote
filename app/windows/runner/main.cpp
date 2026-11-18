#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {
// Inno Setup's SetupMutex is an existence marker, not an owned mutex.
// Close our probe handle immediately so it cannot keep the marker alive.
bool SetupIsRunning() {
  constexpr wchar_t kSetupMutex[] =
      L"Openote.Setup.8E5C0C41-6C2E-4E2C-9E5B-1F7A2D2F1A10";
  const auto setup = OpenMutexW(SYNCHRONIZE, FALSE, kSetupMutex);
  if (!setup) return GetLastError() == ERROR_ACCESS_DENIED;
  CloseHandle(setup);
  return true;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  auto command_line_arguments = GetCommandLineArguments();
  const bool after_update = command_line_arguments.size() == 1 &&
      command_line_arguments.front() == "--after-update";
  // Do not wait inside the old exe: keeping it mapped could block replacement.
  // Setup owns the relaunch, after its file-copy phase has completed.
  if (!after_update && SetupIsRunning()) return EXIT_SUCCESS;
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"openote", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    window.ObservePenMessage(msg);
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
