// PWM observation transaction (one per pin per observed event).
//
// Three event kinds, all published on the same analysis port:
//   PWM_RISE / PWM_FALL  — a level TRANSITION on `pin`; `hold_cycles` is how many
//                          sampling clocks the PREVIOUS level was held.
//   PWM_WINDOW           — a periodic ACTIVITY sample for `pin`: how many edges the
//                          pin made during the last `window_cycles` clocks and what
//                          level it is sitting at now. This is what lets a subscriber
//                          distinguish "toggling" from "held low" / "held high"
//                          without re-deriving it from the edge stream.
//   PWM_RESET            — reset was asserted; monitor state was re-armed.
typedef enum { PWM_RISE, PWM_FALL, PWM_WINDOW, PWM_RESET } pwm_evt_e;

class pwm_item extends uvm_sequence_item;
    pwm_evt_e    kind;
    int unsigned pin;             // pin index [0 .. NUM_PINS-1]
    bit          level;           // level at/after the event
    bit          prev_level;      // level before the event (edge kinds)
    int unsigned hold_cycles;     // clocks prev_level was held (edge kinds)
    int unsigned edges_in_window; // edges seen in the window (PWM_WINDOW)
    int unsigned window_cycles;   // width of that window in clocks (PWM_WINDOW)
    realtime     t_event;         // simulation time of the event

    `uvm_object_utils_begin(pwm_item)
        `uvm_field_enum(pwm_evt_e, kind, UVM_ALL_ON)
        `uvm_field_int(pin,             UVM_ALL_ON)
        `uvm_field_int(level,           UVM_ALL_ON)
        `uvm_field_int(prev_level,      UVM_ALL_ON)
        `uvm_field_int(hold_cycles,     UVM_ALL_ON)
        `uvm_field_int(edges_in_window, UVM_ALL_ON)
        `uvm_field_int(window_cycles,   UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "pwm_item"); super.new(name); endfunction

    function bit is_edge(); return (kind == PWM_RISE) || (kind == PWM_FALL); endfunction
endclass
