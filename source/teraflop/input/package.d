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
struct InputEventHandlers {
  ///
  const ActionInput actionHandler;
  ///
  const UnhandledInput unhandledHandler;
}

///
final class Input {
  import std.typecons : Flag, No;
  import teraflop.platform : Window;

  ///
  const(InputEventHandlers)[] nodes;
  private auto _map = new InputMap();

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
          keyModifiers |= Modifiers.SHIFT | Modifiers.LEFT_SHIFT;
        if (window.isKeyDown(KeyboardKey.leftControl))
          keyModifiers |= Modifiers.CONTROL | Modifiers.LEFT_CONTROL;
        if (window.isKeyDown(KeyboardKey.leftAlt))
          keyModifiers |= Modifiers.ALT | Modifiers.LEFT_ALT;
        if (window.isKeyDown(KeyboardKey.leftSuper))
          keyModifiers |= Modifiers.SUPER | Modifiers.LEFT_SUPER;

        if (window.isKeyDown(KeyboardKey.rightShift))
          keyModifiers |= Modifiers.SHIFT | Modifiers.RIGHT_SHIFT;
        if (window.isKeyDown(KeyboardKey.rightControl))
          keyModifiers |= Modifiers.CONTROL | Modifiers.RIGHT_CONTROL;
        if (window.isKeyDown(KeyboardKey.rightAlt))
          keyModifiers |= Modifiers.ALT | Modifiers.RIGHT_ALT;
        if (window.isKeyDown(KeyboardKey.rightSuper))
          keyModifiers |= Modifiers.SUPER | Modifiers.RIGHT_SUPER;

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
      if (handlers.unhandledHandler(event)) break;
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