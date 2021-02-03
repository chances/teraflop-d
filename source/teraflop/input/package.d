/// User input primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.input;

import teraflop.async.event;
public import teraflop.input.event;
public import teraflop.input.keyboard;
public import teraflop.input.map;

///
enum MouseButton {
  ///
  none = 0,
  ///
  left = 1,
  ///
  right = 2,
  ///
  middle = 4
}

///
final class Input {
  import std.typecons : Flag, No;
  import teraflop.math : vec2d;
  import teraflop.platform : Window;

  ///
  const(InputEventHandlers)[] nodes;
  private Window window;
  private auto _map = new InputMap();

  package (teraflop) this(Window window) {
    this.window = window;
  }

  ///
  bool isKeyDown(KeyboardKey key) @property const {
    return window.isKeyDown(key);
  }
  ///
  bool wasKeyDown(KeyboardKey key) @property const {
    return window.wasKeyDown(key);
  }
  ///
  bool isKeyReleased(KeyboardKey key) @property const {
    return window.isKeyReleased(key);
  }

  ///
  vec2d mousePosition() @property const {
    return window.mousePosition;
  }
  ///
  vec2d lastMousePosition() @property const {
    return window.lastMousePosition;
  }
  ///
  int mouseButtons() @property const {
    return window.mouseButtons;
  }
  ///
  int lastMouseButtons() @property const {
    return window.lastMouseButtons;
  }

  ///
  static ActionInput ignoreActions() {
    return (const InputEventAction event) => {
      assert(event.action.length);
    }();
  }

  ///
  static UnhandledInput ignoreUnhandledInputs() {
    return (const InputEvent event) => {
      assert(event.device >= 0);
      return false;
    }();
  }

  InputMap map() @property const {
    return cast(InputMap) _map;
  }

  ///
  void addNode(InputNode node) {
    nodes ~= InputEventHandlers(&node.actionInput, &node.unhandledInput);
  }

  ///
  void on(T) (
    string action, T handler, Flag!"markInputHandled" markInputHandled = No.markInputHandled
  ) if (isCallable!T) {
    // TODO: Port logger from grocery game or use gfx's logging infra?
    // import logger : trace;
    // import std.string : format;

    // trace(format!"adding anonymous '%s' action handler"(action));
    this.nodes ~= InputEventHandlers(
      event => {
        if (event.action == action) handler();
      }(),
      event => {
        if (event.isActionEvent && event.asActionEvent.action == action) return markInputHandled;
        return false;
      }()
    );
  }

  package (teraflop) void update(const Window window) {
    // Keyboard keys with modifiers
    foreach (key; KeyboardKey.min .. KeyboardKey.max) {
      if (window.isKeyDown(key) || (window.isKeyReleased(key) && window.wasKeyDown(key))) {
        int keyModifiers = 0;
        if (window.isKeyDown(KeyboardKey.leftShift))
          keyModifiers |= Modifiers.shift | Modifiers.leftShift;
        if (window.isKeyDown(KeyboardKey.leftControl))
          keyModifiers |= Modifiers.control | Modifiers.leftControl;
        if (window.isKeyDown(KeyboardKey.leftAlt))
          keyModifiers |= Modifiers.alt | Modifiers.leftAlt;
        if (window.isKeyDown(KeyboardKey.leftSuper))
          keyModifiers |= Modifiers.super_ | Modifiers.leftSuper;

        if (window.isKeyDown(KeyboardKey.rightShift))
          keyModifiers |= Modifiers.shift | Modifiers.rightShift;
        if (window.isKeyDown(KeyboardKey.rightControl))
          keyModifiers |= Modifiers.control | Modifiers.rightControl;
        if (window.isKeyDown(KeyboardKey.rightAlt))
          keyModifiers |= Modifiers.alt | Modifiers.rightAlt;
        if (window.isKeyDown(KeyboardKey.rightSuper))
          keyModifiers |= Modifiers.super_ | Modifiers.rightSuper;

        propagate(new InputEventKeyboard(
          key, window.isKeyDown(key), window.isKeyDown(key) && window.wasKeyDown(key), keyModifiers
        ));
      }
    }

    if (window.hasMouseInputChanged()) propagate(new InputEventMouse(
      window.mousePosition, window.lastMousePosition, window.mouseButtons, window.lastMouseButtons
    ));
  }

  private void propagate(InputEvent event) {
    const actionEvents = toActions(event);

    foreach (handlers; nodes) {
      if (actionEvents.length) foreach (actionEvent; actionEvents) handlers.actionHandler(actionEvent);
      if (handlers.unhandledHandler(event) || event.handled) break;
    }
  }

  private InputEventAction[] toActions(InputEvent event) {
    auto actionEvents = new InputEventAction[0];

    foreach (binding; map.bindings.byKeyValue) {
      if (binding.value.appliesTo(event))
        actionEvents ~= binding.value.accumulateIntoAction(event, binding.key);
    }

    return actionEvents;
  }
}

/// A node in the input event tree.
interface InputNode {
  ///
  void actionInput(const InputEventAction event);

  /// Returns: Whether the mark the given input `event` as handled, stopping propagation through the input tree.
  bool unhandledInput(const InputEvent event);
}

unittest {
  // TODO: Test an event tree
}
