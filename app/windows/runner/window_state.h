#ifndef OPENOTE_WINDOW_STATE_H_
#define OPENOTE_WINDOW_STATE_H_

#include <windows.h>

// All automatic activation paths use normal maximization, never a toggle or
// borderless fullscreen. Caption buttons and F11 still let the user restore.
inline BOOL ShowOpenoteMaximized(HWND window) {
  if (IsWindowVisible(window) && IsZoomed(window) && !IsIconic(window)) {
    return TRUE;
  }
  return ShowWindow(window, SW_SHOWMAXIMIZED);
}

#endif  // OPENOTE_WINDOW_STATE_H_
