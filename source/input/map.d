/// Map user inputs to named actions.
///
/// Inspired by Godot's <a href="https://docs.godotengine.org/en/3.2/classes/class_inputmap.html">`InputMap`</a> and <a href="https://github.com/PradeepKumarRajamanickam/bevy_input_map/blob/39443a1a1bc1e59959f31d92543a065575c03a7e/example/binding_in_code.rs#L21">bevy_input_map</a>.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.input.map;

import teraflop.input : MouseButton;
import teraflop.input.event;
import teraflop.input.keyboard;
import teraflop.math : vec2d;

/// Map user inputs to named actions.
final class InputMap {
  ///
  InputMapBinding[string] bindings;

  ///
  InputMapBinding bind(string action) {
    assert(action.length > 0);
    return bindings[action] = new InputMapBinding();
  }
}

/// Axis of motion for analog inputs, i.e. mouse motion, mouse wheel movement, and joypad sticks.
enum Axis {
  ///
  static_ = 1,
  ///
  any = 2,
  ///
  xNegative = 4,
  ///
  xPositive = 8,
  ///
  yNegative = 16,
  ///
  yPositive = 32
}

/// A formula to influence the strength of a held input given the current strength, `x`, and the
/// last strength value.
alias StrengthCurve = float delegate(float x, float last = 0.0);
/// Doubles the current strength value.
static StrengthCurve double_ = (float x, float last = 0.0) => x + x;
/// Increases the strength by continuious accumulation, i.e. linearly.
static StrengthCurve accumulation = (float x, float last = 0.0) => x + last;

unittest {
  assert(double_(2) == 4);
  assert(accumulation(1, 1) == 2);
}

/// An `InputEventAction` builder.
/// See_Also: <a href="https://refactoring.guru/design-patterns/builder">Builder Design Pattern</a> on <a href="https://refactoring.guru">refactoring.guru</a>
class InputMapBinding {
  private BindingState[] states = new BindingState[0];
  /// A minimum threshold to avoid small input noise and reduce sensitivity.
  /// Useful with analog inputs, i.e. mouse motion, mouse wheel movement, and joypad sticks.
  float deadZone = 0.0f;
  /// A curve formula to influence the strength of held inputs. Defaults to constant strength.
  StrengthCurve strengthCurve = null;

  ///
  InputMapBinding keyboardPressed(KeyboardKey key, Modifiers modifiers = Modifiers.none) {
    states ~= BindingState.keyboard(true, false, key, modifiers);
    return this;
  }

  ///
  InputMapBinding keyboardHeld(KeyboardKey key, Modifiers modifiers = Modifiers.none) {
    states ~= BindingState.keyboard(false, true, key, modifiers);
    return this;
  }

  ///
  InputMapBinding keyboardDown(KeyboardKey key, Modifiers modifiers = Modifiers.none) {
    states ~= BindingState.keyboard(true, false, key, modifiers);
    states ~= BindingState.keyboard(false, true, key, modifiers);
    return this;
  }

  ///
  InputMapBinding keyboardReleased(KeyboardKey key, Modifiers modifiers = Modifiers.none) {
    states ~= BindingState.keyboard(false, false, key, modifiers);
    return this;
  }

  ///
  InputMapBinding mousePressed(MouseButton button) {
    states ~= BindingState.mouse(true, false, button);
    return this;
  }

  ///
  InputMapBinding mouseHeld(MouseButton button) {
    states ~= BindingState.mouse(true, true, button);
    return this;
  }

  ///
  InputMapBinding mouseReleased(MouseButton button) {
    states ~= BindingState.mouse(false, false, button);
    return this;
  }

  /// Bind changes to the mouse wheel state, optionally filtered by the given bitwise combination of `Axis`
  InputMapBinding mouseWheel(int axes = Axis.any) {
    states ~= BindingState.mouseWheel(axes);
    return this;
  }

  /// Bind changes to the mouse motion state, optionally filtered by the given bitwise combination of `Axis`
  InputMapBinding mouseMotion(int axes = Axis.any) {
    states ~= BindingState.mouseMotion(axes);
    return this;
  }

  // TODO: Add joypad binding contraint builder functions?

  ///
  InputMapBinding withDeadZone(float deadZone) {
    this.deadZone = deadZone;
    return this;
  }

  ///
  InputMapBinding withStrengthCurve(StrengthCurve curve) {
    strengthCurve = curve;
    return this;
  }

  private alias stateAppliesAggregate = int delegate(int, BindingState);
  private stateAppliesAggregate totalApplicableStatesFor(InputEvent event) {
    return (int numApplicableStates, BindingState state) {
      if (event.device != state.device) return 0;
      return numApplicableStates + (state.appliesTo(event) ? 1 : 0);
    };
  }

  /// Whether this action binding applies to the given `InputEvent`
  ///
  /// An action is applicable to the given `event` _iff_ **all** bound input constraints with
  /// equivalent device IDs are met
  bool appliesTo(InputEvent event) {
    import std.algorithm.iteration : filter, fold;
    import std.array : array;

    auto numApplicableStates = 0;
    foreach (state; states) {
      numApplicableStates += totalApplicableStatesFor(event)(numApplicableStates, state);
    }
    return numApplicableStates > 0;
  }

  package (teraflop.input) InputEventAction accumulateIntoAction(InputEvent event, string actionName) {
    auto action = new InputEventAction(event.device, actionName);
    import std.algorithm.iteration : filter, fold;
    import std.array : array;

    auto keyboardStates = states.filter!(state => state.device == InputDevice.keyboard).array;
    action.pressed = keyboardStates.fold!((pressed, state) => pressed && state.pressed)(true);
    action.held = keyboardStates.fold!((held, state) => held && state.held)(true);

    // Accumulate the action's strength given its `strengthCurve`
    auto strengthCurve = this.strengthCurve != null ? this.strengthCurve : accumulation;
    const keyboardStrength = keyboardStates.length > 1
      ? keyboardStates.fold!((strength, state) => strengthCurve(1.0 / keyboardStates.length, strength))(0.0)
      : 1.0;
    auto mouseStates = states.filter!(state => state.device == InputDevice.mouse).array;
    if (event.device == InputDevice.mouse)
      action.delta = event.asMouseEvent().delta;
    const scrollStrength = mouseStates.length > 1
      ? mouseStates.fold!((strength, state) => strengthCurve(1.0 / mouseStates.length, strength))(0.0)
      : 1.0;
    const motionStrength = mouseStates.length > 1
      ? mouseStates.fold!((strength, state) => strengthCurve(1.0 / mouseStates.length, strength))(0.0)
      : 1.0;
    auto strength = (keyboardStrength / 3.0) + (scrollStrength / 3.0) + (motionStrength / 3.0);
    import std.algorithm.comparison : clamp;
    action.strength = strength.clamp(0.0, 1.0);
    action.bloomStrength = strength - 1.0;

    return action;
  }
}

private struct BindingState {
  int device;
  /// If `true`, the action was just pressed.
  /// Otherwise the action is being held *or* was just released
  bool pressed;
  /// If `true`, the action was already pressed before this event
  bool held;
  /// A member of `KeyboardKey`
  int key = 0;
  /// A bitwise combitation of keyboard `Modifiers`
  int modifiers = Modifiers.none;
  auto button = MouseButton.none;
  bool wheel = false;
  bool motion = false;
  /// A bitwise combitation of `Axis`
  int wheelAxes = 0;
  /// A bitwise combitation of `Axis`
  int motionAxes = 0;

  static BindingState keyboard(bool pressed, bool held, KeyboardKey key, Modifiers modifiers) {
    assert(pressed && held ? false : true);
    return BindingState(InputDevice.keyboard, pressed, held, key, modifiers);
  }

  static BindingState mouse(bool pressed, bool held, MouseButton button) {
    assert(pressed && held ? false : true);
    auto state = BindingState(InputDevice.mouse, pressed, held);
    state.button = button;
    return state;
  }

  static BindingState mouseWheel(int axes) {
    auto state = BindingState(InputDevice.mouse);
    state.wheel = true;
    state.wheelAxes = axes;
    return state;
  }

  static BindingState mouseMotion(int axes) {
    auto state = BindingState(InputDevice.mouse);
    state.motion = true;
    state.motionAxes = axes;
    return state;
  }

  bool appliesTo(InputEvent e) {
    assert(e.device != InputDevice.joypad);
    if (e.device == InputDevice.keyboard) {
      if (device != InputDevice.keyboard) return false;
      auto event = e.asKeyboardEvent();
      return event.pressed == pressed && event.held == held && event.key == key && event.modifiers == modifiers;
    }

    if (device != InputDevice.mouse) return false;
    auto event = e.asMouseEvent();

    auto wheelAxesApply = wheel && (
      (wheelAxes == Axis.static_ && event.wheel == 0) ||
      ((wheelAxes & Axis.any) == Axis.any && event.wheel != 0) ||
      ((wheelAxes & Axis.yNegative) == Axis.yNegative && event.wheel < 0) ||
      ((wheelAxes & Axis.yPositive) == Axis.yPositive && event.wheel > 0)
    );
    wheelAxesApply = wheelAxesApply || wheelAxes == 0;
    // Confirm mouse motion expectation if motion is expected
    auto motionAxesApply = motion && (
      // Motionlessness
      (motionAxes == Axis.static_ && event.delta == vec2d.init) ||
      // Any axis motion axis
      ((motionAxes & Axis.any) == Axis.any && event.delta != vec2d.init) ||
      // Confirm that no axes are constrained in opposite directions
      // X-negative motion
      ((motionAxes & Axis.xNegative) ==
        Axis.xNegative && event.delta.x < 0 && (motionAxes & Axis.xPositive) != Axis.xPositive) ||
      // X-positive motion
      ((motionAxes & Axis.xPositive) ==
        Axis.xPositive && event.delta.x > 0 && (motionAxes & Axis.xNegative) != Axis.xNegative) ||
      // Y-negative motion
      ((motionAxes & Axis.yNegative) ==
        Axis.yNegative && event.delta.y < 0 && (motionAxes & Axis.yPositive) != Axis.yPositive) ||
      // Y-positive motion
      ((motionAxes & Axis.yPositive) ==
        Axis.yPositive && event.delta.y > 0 && (motionAxes & Axis.yNegative) != Axis.yNegative)
    );
    // Otherwise permit any motion
    motionAxesApply = motionAxesApply || motionAxes == 0;

    bool buttonApplies = true;
    if (button != MouseButton.none) {
      // Check that the event's button state matches this binding's expectation
      const isButtonPressed = (event.buttons & button) == button;

      import std.conv : to;
      if (pressed && !held) {
        buttonApplies = isButtonPressed && event.wasButtonJustPressed(button.to!MouseButton);
      } else if (!pressed && held) {
        buttonApplies = isButtonPressed && !event.wasButtonJustPressed(button.to!MouseButton);
      } else {
        buttonApplies = !isButtonPressed && event.wasButtonJustClicked(button.to!MouseButton);
      }
    }

    return buttonApplies && wheelAxesApply && motionAxesApply;
  }
}
