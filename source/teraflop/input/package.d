/// User input primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.input;

import std.typecons : Tuple;
import teraflop.async.event;
public import teraflop.input.event;
public import teraflop.input.keyboard;
public import teraflop.input.map;

alias InputEventHandlers = Tuple!(ActionInput, UnhandledInput);

///
void on(T) (Input input, string action, T handler, bool markInputHandled = false) if (isCallable!T) {
  import logger : trace;
  import std.string : format;
  trace(format!"adding anonymous '%s' action handler"(action));
  input.nodes ~= InputEventHandlers(
    event => {
      if (event.action == action) handler();
    }(),
    event => {
      if (event.isActionEvent && event.asActionEvent.action == action) return markInputHandled;
      return false;
    }()
  );
}

///
struct Input {
  import teraflop.platform : Window;

  ///
  const Window window;
  ///
  auto map = new InputMap();
  ///
  InputEventHandlers[] nodes;

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

  ///
  void update() {
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

  ///
  void addNode(InputNode node) {
    nodes ~= InputEventHandlers(&node.actionInput, &node.unhandledInput);
  }

  private void propagate(InputEvent event) {
    const actionEvents = toActions(event);

    foreach (handlers; nodes) {
      if (actionEvents.length) {
        ActionInput actionHandler = handlers[0];
        foreach (actionEvent; actionEvents) actionHandler(actionEvent);
      }

      auto unhandledInputHandler = handlers[1];
      if (unhandledInputHandler(event)) break;
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
