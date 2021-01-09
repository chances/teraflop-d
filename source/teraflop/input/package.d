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
class Input {
  ///
  auto map = new InputMap();
  ///
  auto nodes = new InputEventHandlers[0];

  ///
  static ActionInput ignoreActions() {
    return (InputEventAction event) => {
      assert(event.action.length);
    }();
  }

  ///
  static UnhandledInput ignoreUnhandledInputs() {
    return (InputEvent event) => {
      assert(event.device >= 0);
      return false;
    }();
  }

  ///
  void update() {
    foreach (key; KeyboardKey.min .. KeyboardKey.max) {
      if (IsKeyDown(key) || IsKeyReleased(key)) propagate(new InputEventKeyboard(key));
    }

    if (hasMouseInputChanged()) propagate(new InputEventMouse());
  }

  ///
  void addNode(InputNode node) {
    nodes ~= InputEventHandlers(&node.actionInput, &node.unhandledInput);
  }

  private void propagate(InputEvent event) {
    const actionEvents = toActions(event);

    foreach (handlers; nodes) {
      if (actionEvents.length) {
        auto actionHandler = handlers[0];
        import std.algorithm.iteration : each;
        actionEvents.each!(actionEvent => actionHandler(actionEvent));
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
