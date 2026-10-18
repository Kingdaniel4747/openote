#ifndef OPENOTE_PEN_BUTTON_STATE_H_
#define OPENOTE_PEN_BUTTON_STATE_H_

// Proximity, contact and the physical side switch are independent states.
enum class PenSwitchChange { none, pressed, released };

class PenButtonState {
 public:
  constexpr void Update(bool in_range, bool in_contact, bool inverted,
                        bool pointer_barrel, PenSwitchChange change,
                        bool has_raw_barrel, bool raw_barrel) {
    if (!in_range && !in_contact) {
      Reset();
      return;
    }
    in_range_ = true;
    inverted_ = inverted;
    if (has_raw_barrel) {
      barrel_ = raw_barrel;
      released_ = !raw_barrel;
    } else if (change != PenSwitchChange::none) {
      barrel_ = change == PenSwitchChange::pressed;
      released_ = !barrel_;
    } else if (!pointer_barrel) {
      barrel_ = false;
      released_ = false;
    } else if (!released_) {
      barrel_ = true;
    }
  }

  constexpr void Reset() {
    in_range_ = inverted_ = barrel_ = released_ = false;
  }
  constexpr bool in_range() const { return in_range_; }
  constexpr bool barrel() const { return barrel_; }
  constexpr bool eraser() const { return in_range_ && (inverted_ || barrel_); }

 private:
  bool in_range_ = false;
  bool inverted_ = false;
  bool barrel_ = false;
  bool released_ = false;
};

#endif
