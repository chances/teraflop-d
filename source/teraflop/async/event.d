/// Abstraction over a D $(D delegate), modelling the C# <a href="https://docs.microsoft.com/en-us/dotnet/standard/events/">event</a> paradigm.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.async.event;

import std.traits : TemplateOf;

// Adapted from https://forum.dlang.org/post/dcdtuqyrxpteuaxmvwft@forum.dlang.org

/// Detect whether `T` is an instance of the `Event` struct.
enum isEvent(T) = __traits(isSame, TemplateOf!T, Event);

/// Abstraction over a D $(D delegate), modelling the C# <a href="https://docs.microsoft.com/en-us/dotnet/standard/events/">event</a> paradigm.
struct Event(Args) {
  alias Callback = void delegate(Args);
  private Callback[] callbacks;

  /// Add or remove an event handler via compound assignment (`~=`, `+=`, `-=`).
  void opOpAssign(string op)(Callback handler) if (op == "~" || op == "+" || op == "-") {
    static if (op == "~" || op == "+")
      callbacks ~= handler;
    else
    {
      import std.algorithm.mutation : remove;
      callbacks = callbacks.remove!(x => x == handler);
    }
  }

  /// Invoke all of this `Event`s assigned handlers given any event arguments.
  void opCall(Args args) {
    synchronized {
      foreach (cb; callbacks)
        cb(args);
    }
  }

  /// Whether or not this event has any assigned handlers.
  bool hasHandlers() const @property {
    synchronized return callbacks.length != 0;
  }
}

unittest {
  auto expectedSDotA = 666;
  auto expectedArg = 0;

  struct S
  {
    int a;
    void handler(int arg)
    {
      assert(a == expectedSDotA);
      assert(arg == expectedArg);
    }
  }
  void func(int arg) { assert(arg == expectedArg, "Mismatched argument for func callback!"); }

  // Test the Event with int event arg
  Event!int onChanged;
  const s = S(expectedSDotA);

  assert(!onChanged.hasHandlers);

  onChanged += (int arg) { assert(arg == expectedArg, "Mismatched argument for lambda callback!"); };
  onChanged ~= &func;
  onChanged += &(cast(S) s).handler;
  assert(onChanged.hasHandlers);
  onChanged(expectedArg += 1);

  onChanged -= &(cast(S) s).handler;
  onChanged(expectedArg += 1);

  onChanged -= &func;
  onChanged(expectedArg += 1);
}
