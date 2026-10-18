// Compile with cl /std:c++20 /Zs to exercise the actual runner state reducer.
#include "../../windows/runner/pen_button_state.h"

constexpr bool HoverCycles() {
  PenButtonState pen;
  for (int i = 0; i < 8; ++i) {
    pen.Update(true, false, false, false, PenSwitchChange::none, true, true);
    if (!pen.in_range() || !pen.eraser()) return false;
    // Physical release wins over a delayed BARREL flag without leaving range.
    pen.Update(true, false, false, true, PenSwitchChange::none, true, false);
    if (!pen.in_range() || pen.eraser()) return false;
  }
  return true;
}
static_assert(HoverCycles(), "Hover must support repeated press/release cycles");

constexpr bool ContactTransitions() {
  PenButtonState pen;
  pen.Update(true, true, false, false, PenSwitchChange::none, true, true);
  if (!pen.eraser()) return false;
  // Lifting the nib must not release a still-held switch.
  pen.Update(true, false, false, false, PenSwitchChange::none, true, true);
  if (!pen.eraser()) return false;
  pen.Update(true, true, false, true, PenSwitchChange::none, true, false);
  if (pen.eraser()) return false;
  // A genuine inverted tail remains an eraser independently of the switch.
  pen.Update(true, true, true, false, PenSwitchChange::none, true, false);
  if (!pen.eraser()) return false;
  pen.Reset();
  return !pen.eraser() && !pen.in_range();
}
static_assert(ContactTransitions(), "Nib contact and switch state must be independent");

constexpr bool PointerFallback() {
  PenButtonState pen;
  pen.Update(true, false, false, true, PenSwitchChange::pressed, false, false);
  if (!pen.eraser()) return false;
  pen.Update(true, false, false, true, PenSwitchChange::released, false, false);
  if (pen.eraser()) return false;
  // A stale snapshot cannot undo an explicit release.
  pen.Update(true, false, false, true, PenSwitchChange::none, false, false);
  if (pen.eraser()) return false;
  pen.Update(true, false, false, true, PenSwitchChange::pressed, false, false);
  if (!pen.eraser()) return false;
  pen.Update(false, false, false, true, PenSwitchChange::none, false, false);
  return !pen.eraser() && !pen.in_range();
}
static_assert(PointerFallback(), "Explicit release and leaving range must clear the switch");
