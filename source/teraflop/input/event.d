/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.input.event;

import teraflop.math : vec2d;
import teraflop.input : MouseButton;
import teraflop.input.keyboard;
import teraflop.traits;

alias ActionInput = void delegate(const InputEventAction event);
alias UnhandledInput = bool delegate(const InputEvent event);

///
struct InputEventHandlers {
  ///
  const ActionInput actionHandler;
  ///
  const UnhandledInput unhandledHandler;
}

/// The user input device from which an `InputEvent` originated.
enum InputDevice {
  ///
  keyboard = 0,
  ///
  mouse,
  ///
  joypad
}

/// Generic input event.
abstract class InputEvent {
  ///
  const InputDevice device;
  private bool _handled = false;

  ///
  this(const InputDevice device) {
    this.device = device;
  }

  // Input events are keyed as Resources given their device
  // https://dlang.org/spec/hash-map.html#using_classes_as_key
  override size_t toHash() @safe @nogc const pure {
    return device;
  }
  override bool opEquals(Object o) @safe @nogc const pure {
    InputEvent other = cast(InputEvent) o;
    return other && device == other.device;
  }

  /// Whether this `InputEvent` has been handled.
  /// See_Also: `stopPropagation`
  bool handled() @property const {
    return _handled;
  }

  bool isKeyboardEvent() @property const {
    return typeid(InputEventKeyboard).isBaseOf(this.classinfo);
  }

  bool isMouseEvent() @property const {
    return typeid(InputEventMouse).isBaseOf(this.classinfo);
  }

  bool isActionEvent() @property const {
    return typeid(InputEventAction).isBaseOf(this.classinfo);
  }

  InputEventKeyboard asKeyboardEvent() @property const {
    assert(this.isKeyboardEvent, "Event is not an instance of `KeyboardEvent`");
    if (this.isKeyboardEvent) {
      return cast(InputEventKeyboard) this;
    }
    return null;
  }

  InputEventMouse asMouseEvent() @property const {
    assert(this.isMouseEvent, "Event is not an instance of `MouseEvent`");
    if (this.isMouseEvent) {
      return cast(InputEventMouse) this;
    }
    return null;
  }

  InputEventAction asActionEvent() @property const {
    assert(this.isActionEvent, "Event is not an instance of `ActionEvent`");
    if (this.isActionEvent) {
      return cast(InputEventAction) this;
    }
    return null;
  }

  /// Mark this `InputEvent` as handled, stopping propagation through the input tree.
  /// See_Also: `handled`
  void stopPropagation() {
    _handled = true;
  }
}

// TODO: Joypad input enums: https://github.com/BindBC/bindbc-glfw/blob/5bed82e7bdd18afb0e810aeb173e11d38e18075b/source/bindbc/glfw/types.d#L229-L283

/// Keyboard input event.
class InputEventKeyboard : InputEvent {
  /// Whether the key was just pressed.
  /// If `false`, the key is being held *or* was just released
  const bool pressed;
  /// Whether the key was already pressed before this event.
  const bool held;
  ///
  const KeyboardKey key;
  /// A bitwise combitation of `Modifiers`
  const int modifiers = 0;

  ///
  this(const KeyboardKey key, bool pressed, bool held, int modifiers = 0) {
    super(InputDevice.keyboard);
    this.key = key;
    this.pressed = pressed && !held;
    this.held = held;
    this.modifiers = modifiers;
  }
}

unittest {
  auto event = new InputEventKeyboard(KeyboardKey.enter, true, false);

  assert(event.device == InputDevice.keyboard);
  assert(!event.handled);
  assert(event.isKeyboardEvent);
  assert(event.asKeyboardEvent == event);
  assert(event == new InputEventKeyboard(event.key, event.pressed, event.held));

  event.stopPropagation();
  assert(event.handled);
}

/// Mouse button and/or motion event.
class InputEventMouse : InputEvent {
  /// One of or a bitwise combination of `MouseButton`s that are down.
  int buttons = MouseButton.none;
  /// One of or a bitwise combination of `MouseButton`s that were just down.
  int lastButtons = MouseButton.none;
  ///
  const bool buttonsChanged = false;
  ///
  const int wheel = 0;
  ///
  const vec2d position;
  ///
  const vec2d delta;
  // TODO: Do I need mouse speed? (position delta per unit of time)

  ///
  this(vec2d position, vec2d lastMousePosition, int mouseButtons = 0, int lastMouseButtons = 0, int wheel = 0) {
    super(InputDevice.mouse);
    buttons = mouseButtons;
    lastButtons = lastMouseButtons;
    buttonsChanged = buttons != lastMouseButtons;
    this.wheel = wheel;
    this.position = position;
    delta = position - lastMousePosition;

    lastMouseButtons = buttons;
    lastMousePosition = position;
  }

  /// Whether the given `button` was just pressed, i.e. it's last state was unpressed and is now pressed.
  bool wasButtonJustPressed(MouseButton button) @property const {
    return (buttons & button) == button && (lastButtons & button) != button;
  }

  /// Whether the given `button` was just clicked, i.e. it's last state was pressed and is now unpressed.
  bool wasButtonJustClicked(MouseButton button) @property const {
    return isButtonUp(button) && (lastButtons & button) == button;
  }

  bool isButtonUp(MouseButton button) @property const {
    return (buttons & button) != button;
  }
}

unittest {
  auto event = new InputEventMouse(vec2d.init, vec2d.init);

  assert(event.device == InputDevice.mouse);
  assert(event.isMouseEvent);
  assert(event.asMouseEvent == event);

  assert((event.buttons & MouseButton.left) != MouseButton.left);
  assert((event.buttons & MouseButton.right) != MouseButton.right);
  assert((event.buttons & MouseButton.middle) != MouseButton.middle);

  event.buttons |= MouseButton.right;
  assert(!event.wasButtonJustClicked(MouseButton.left));
  assert(event.wasButtonJustPressed(MouseButton.right));
  assert((event.buttons & MouseButton.left) != MouseButton.left);
  assert((event.buttons & MouseButton.right) == MouseButton.right);
  assert((event.buttons & MouseButton.middle) != MouseButton.middle);

  event.buttons |= MouseButton.middle;
  assert(event.wasButtonJustPressed(MouseButton.middle));
  assert((event.buttons & MouseButton.left) != MouseButton.left);
  assert((event.buttons & MouseButton.right) == MouseButton.right);
  assert((event.buttons & MouseButton.middle) == MouseButton.middle);
}

/// Mapped action input event.
class InputEventAction : InputEvent {
  ///
  const string action;
  /// If `true`, the action was just pressed. Otherwise the action was just released.
  bool pressed;
  /// If `true`, the action was already pressed before this event.
  bool held;
  /// The discrete change of the action's analog inputs, e.g. mouse wheel, mouse motion, joystick motion, etc.
  vec2d delta = vec2d(0, 0);
  /// A percentage, between 0.0 and 1.0, indicating the strength of this action given its state.
  float strength = 1.0;
  /// The difference between the clamped `strength` value and this action's total accumulation given
  /// its `StrengthCurve`.
  float bloomStrength = 0.0;

  ///
  this(const InputDevice device, string action) {
    super(device);
    this.action = action;
  }

  // Action input events are keyed as Resources given their device and action name
  // https://dlang.org/spec/hash-map.html#using_classes_as_key
  override size_t toHash() @safe @nogc const pure {
    return action.hashOf(super.toHash);
  }
  override bool opEquals(Object o) @safe @nogc const pure {
    InputEventAction other = cast(InputEventAction) o;
    return other && device == other.device && action == other.action;
  }
}

unittest {
  auto event = new InputEventAction(InputDevice.keyboard, "cancel");
  event.pressed = true;

  assert(event.device == InputDevice.keyboard);
  assert(event.isActionEvent);
  assert(event.asActionEvent == event);
  assert(event == new InputEventAction(event.device, event.action));
}
