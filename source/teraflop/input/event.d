/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.input.event;

import teraflop.math : vec2d;
import teraflop.input.keyboard;

alias ActionInput = void delegate(const InputEventAction event);
alias UnhandledInput = bool delegate(const InputEvent event);

///
abstract class InputNode {
  ///
  void actionInput(const InputEventAction event) {
    assert(event.action.length);
  }

  ///
  bool unhandledInput(const InputEvent event) {
    assert(event.device);
    return false;
  }
}

///
enum InputDevice {
  keyboard = 0,
  mouse,
  joypad
}

/// Generic input event.
abstract class InputEvent {
  ///
  const InputDevice device;

  ///
  this(const InputDevice device) {
    this.device = device;
  }

  bool isKeyboardEvent() @property const {
    return typeid(this) == typeid(InputEventKeyboard);
  }

  bool isMouseEvent() @property const {
    return typeid(this) == typeid(InputEventMouse);
  }

  bool isActionEvent() @property const {
    return typeid(this) == typeid(InputEventAction);
  }

  InputEventKeyboard asKeyboardEvent() @property const {
    if (this.isKeyboardEvent) {
      return cast(InputEventKeyboard) this;
    }
    return null;
  }

  InputEventMouse asMouseEvent() @property const {
    if (this.isMouseEvent) {
      return cast(InputEventMouse) this;
    }
    return null;
  }

  InputEventAction asActionEvent() @property const {
    if (this.isActionEvent) {
      return cast(InputEventAction) this;
    }
    return null;
  }
}

// TODO: Joypad input enums: https://github.com/BindBC/bindbc-glfw/blob/5bed82e7bdd18afb0e810aeb173e11d38e18075b/source/bindbc/glfw/types.d#L229-L283

///
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
  this(const KeyboardKey key, bool pressed, bool held, int modifiers) {
    super(InputDevice.keyboard);
    this.key = key;
    this.pressed = pressed && !held;
    this.held = held;
    this.modifiers = modifiers;
  }
}

///
enum MouseButton {
  NONE = 1,
  LEFT = 2,
  RIGHT = 4,
  MIDDLE = 8
}

package (teraflop) int glfw(MouseButton button) @nogc nothrow {
  import bindbc.glfw: GLFW_MOUSE_BUTTON_LEFT, GLFW_MOUSE_BUTTON_RIGHT, GLFW_MOUSE_BUTTON_MIDDLE;

  switch (button) {
    case MouseButton.NONE: return -1;
    case MouseButton.LEFT: return GLFW_MOUSE_BUTTON_LEFT;
    case MouseButton.RIGHT: return GLFW_MOUSE_BUTTON_RIGHT;
    case MouseButton.MIDDLE: return GLFW_MOUSE_BUTTON_MIDDLE;
    default: assert(0);
  }
}

/// Mouse button and/or motion event
class InputEventMouse : InputEvent {
  /// One of or a bitwise combination of `MouseButton`s that are down.
  int buttons = MouseButton.NONE;
  /// One of or a bitwise combination of `MouseButton`s that were just down.
  int lastButtons = MouseButton.NONE;
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

  assert((event.buttons & MouseButton.LEFT) != MouseButton.LEFT);
  assert((event.buttons & MouseButton.RIGHT) != MouseButton.RIGHT);
  assert((event.buttons & MouseButton.MIDDLE) != MouseButton.MIDDLE);

  event.buttons |= MouseButton.RIGHT;
  assert((event.buttons & MouseButton.LEFT) != MouseButton.LEFT);
  assert((event.buttons & MouseButton.RIGHT) == MouseButton.RIGHT);
  assert((event.buttons & MouseButton.MIDDLE) != MouseButton.MIDDLE);

  event.buttons |= MouseButton.MIDDLE;
  assert((event.buttons & MouseButton.LEFT) != MouseButton.LEFT);
  assert((event.buttons & MouseButton.RIGHT) == MouseButton.RIGHT);
  assert((event.buttons & MouseButton.MIDDLE) == MouseButton.MIDDLE);
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
}
