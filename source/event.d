module teraflop.event;

// Adapted from https://forum.dlang.org/post/dcdtuqyrxpteuaxmvwft@forum.dlang.org

/// Abstraction over D $(D delegate), modelling the C# event paradigm.
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
  bool opCast(T)() const if (is(T == bool)) {
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
  auto s = S(expectedSDotA); // @suppress(dscanner.suspicious.unmodified)

  assert(!onChanged);

  onChanged += (int arg) { assert(arg == expectedArg, "Mismatched argument for lambda callback!"); };
  onChanged ~= &func;
  onChanged += &s.handler;
  assert(onChanged);
  onChanged(expectedArg += 1);

  onChanged -= &s.handler;
  onChanged(expectedArg += 1);

  onChanged -= &func;
  onChanged(expectedArg += 1);
}
