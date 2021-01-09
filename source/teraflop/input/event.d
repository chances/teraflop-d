/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.input.event;

import teraflop.math : vec2i;
public import teraflop.input.keyboard : KeyboardKey;

alias ActionInput = void delegate(InputEventAction event);
alias UnhandledInput = bool delegate(InputEvent event);

///
abstract class InputNode {
  ///
  void actionInput(InputEventAction event) {
    assert(event.action.length);
  }

  ///
  bool unhandledInput(InputEvent event) {
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

///
enum Modifiers {
  NONE = 0,
  SHIFT = 1,
  CONTROL = 2,
  ALT = 4,
  SUPER = 8,
  LEFT_SHIFT = 16,
  LEFT_CONTROL = 32,
  LEFT_ALT = 64,
  LEFT_SUPER = 128,
  RIGHT_SHIFT = 256,
  RIGHT_CONTROL = 512,
  RIGHT_ALT = 1024,
  RIGHT_SUPER = 2048,

  CAPS_LOCK = 0x0010, // Added in GLFW 3.3
  NUM_LOCK = 0x0020,  // ditto
}

// TODO: Joypad input enums: https://github.com/BindBC/bindbc-glfw/blob/5bed82e7bdd18afb0e810aeb173e11d38e18075b/source/bindbc/glfw/types.d#L229-L283

///
class InputEventKeyboard : InputEvent {
  /// If `true`, the key was just pressed.
  /// Otherwise the key is being held *or* was just released
  const bool pressed;
  /// If `true`, the key was already pressed before this event
  const bool held;
  ///
  const KeyboardKey key;
  /// A bitwise combitation of `Modifiers`
  const int modifiers = 0;

  ///
  this(const KeyboardKey key) {
    super(InputDevice.keyboard);
    this.key = key;
    pressed = IsKeyPressed(key);
    held = IsKeyDown(key) && !IsKeyPressed(key);

    int keyModifiers = 0;
    if (IsKeyDown(KeyboardKey.KEY_LEFT_SHIFT))
      keyModifiers |= Modifiers.SHIFT | Modifiers.LEFT_SHIFT;
    if (IsKeyDown(KeyboardKey.KEY_LEFT_CONTROL))
      keyModifiers |= Modifiers.CONTROL | Modifiers.LEFT_CONTROL;
    if (IsKeyDown(KeyboardKey.KEY_LEFT_ALT))
      keyModifiers |= Modifiers.ALT | Modifiers.LEFT_ALT;
    if (IsKeyDown(KeyboardKey.KEY_LEFT_SUPER))
      keyModifiers |= Modifiers.SUPER | Modifiers.LEFT_SUPER;

    if (IsKeyDown(KeyboardKey.KEY_RIGHT_SHIFT))
      keyModifiers |= Modifiers.SHIFT | Modifiers.RIGHT_SHIFT;
    if (IsKeyDown(KeyboardKey.KEY_RIGHT_CONTROL))
      keyModifiers |= Modifiers.CONTROL | Modifiers.RIGHT_CONTROL;
    if (IsKeyDown(KeyboardKey.KEY_RIGHT_ALT))
      keyModifiers |= Modifiers.ALT | Modifiers.RIGHT_ALT;
    if (IsKeyDown(KeyboardKey.KEY_RIGHT_SUPER))
      keyModifiers |= Modifiers.SUPER | Modifiers.RIGHT_SUPER;

    this.modifiers = keyModifiers;
  }

  bool isKeyUp(KeyboardKey key) @property const {
    return IsKeyUp(key);
  }
}

private static int lastMouseButtons = 0;
private static vec2i lastMousePosition = vec2i(0, 0);

///
@property bool hasMouseInputChanged() {
  auto changed = false;
  changed = changed || lastMouseButtons != getMouseButtons();
  changed = changed || GetMouseWheelMove() != 0;
  const position = GetMousePosition();
  changed = changed || lastMousePosition.x != position.x || lastMousePosition.y != position.y;

  return changed;
}

///
enum MouseButton {
  NONE = 1,
  LEFT = 2,
  RIGHT = 4,
  MIDDLE = 8
}

private @property int getMouseButtons() {
  int buttons = 0;
  if (IsMouseButtonDown(raylib.MouseButton.MOUSE_LEFT_BUTTON))
    buttons |= MouseButton.LEFT;
  if (IsMouseButtonDown(raylib.MouseButton.MOUSE_RIGHT_BUTTON))
    buttons |= MouseButton.RIGHT;
  if (IsMouseButtonDown(raylib.MouseButton.MOUSE_MIDDLE_BUTTON))
    buttons |= MouseButton.MIDDLE;

  if (buttons == 0)
    buttons = MouseButton.NONE;

  return buttons;
}

/// Mouse button and/or motion event
class InputEventMouse : InputEvent {
  /// One of or a bitwise combination of `MouseButton`s that are down
  int buttons = MouseButton.NONE;
  ///
  const bool buttonsChanged = false;
  ///
  const int wheel = 0;
  ///
  const vec2i position;
  ///
  const vec2i delta;
  // TODO: Do I need mouse speed? (position delta per unit of time)

  ///
  this() {
    super(InputDevice.mouse);
    buttons = getMouseButtons();
    buttonsChanged = buttons != lastMouseButtons;
    wheel = GetMouseWheelMove();
    position = GetMousePosition();
    delta = position - lastMousePosition;

    lastMouseButtons = buttons;
    lastMousePosition = position;
  }

  bool wasButtonJustPressed(MouseButton button) @property const {
    switch (button) {
      case MouseButton.LEFT:
        return IsMouseButtonPressed(raylib.MouseButton.MOUSE_LEFT_BUTTON);
      case MouseButton.MIDDLE:
        return IsMouseButtonPressed(raylib.MouseButton.MOUSE_MIDDLE_BUTTON);
      case MouseButton.RIGHT:
        return IsMouseButtonPressed(raylib.MouseButton.MOUSE_RIGHT_BUTTON);
      default:
        return false;
    }
  }

  bool wasButtonJustClicked(MouseButton button) @property const {
    return buttonsChanged && isButtonUp(button);
  }

  bool isButtonUp(MouseButton button) @property const {
    import raylib : IsMouseButtonReleased;
    switch (button) {
      case MouseButton.LEFT:
        return IsMouseButtonReleased(raylib.MouseButton.MOUSE_LEFT_BUTTON);
      case MouseButton.MIDDLE:
        return IsMouseButtonReleased(raylib.MouseButton.MOUSE_MIDDLE_BUTTON);
      case MouseButton.RIGHT:
        return IsMouseButtonReleased(raylib.MouseButton.MOUSE_RIGHT_BUTTON);
      default:
        return false;
    }
  }
}

unittest {
  auto event = new InputEventMouse();

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
  /// If `true`, the action was just pressed. Otherwise the action was just released
  bool pressed;
  /// If `true`, the action was already pressed before this event
  bool held;
  /// The discrete change of the action's analog inputs, e.g. mouse wheel, mouse motion, joystick
  /// motion, etc.
  vec2i delta = vec2i(0, 0);
  /// A percentage, between 0.0 and 1.0, indicating the strength of this action given its state
  float strength = 1.0;
  /// The difference between the clamped `strength` value and this action's total accumulation
  /// given its `StrengthCurve`
  float bloomStrength = 0.0;

  ///
  this(const InputDevice device, string action) {
    super(device);
    this.action = action;
  }
}
