/// Authors: Chance Snow
/// Copyright: Copyright © 2022 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.async;

import eventcore.core : EventDriverCore, eventDriver, tryGetEventDriver;
public import eventcore.driver : ExitReason;

///
alias EventLoop = EventDriverCore;

// Free the current thread's event loop.
static ~this() {
  import core.time : Duration;

  if (tryGetEventDriver() is null) return;

  auto eventLoop = eventDriver().core;
  eventLoop.processEvents(Duration.zero);
  eventLoop.exit();
  // TODO: Does `eventLoop.exit` dispose the event loop? eventLoop.dispose();
}

/// Creates an event loop associated with the calling thread.
/// Remarks:
/// Callers do <i>not</i> need to worry about disposing of the returned event loop.
/// A current thread's event loop is automatically disposed when its thread is destroyed.
/// See_Also: <a href="https://dlang.org/spec/module.html#staticorder">Static Construction and Destruction</a> (D Language Specification)
EventDriverCore createEventLoop() { return eventDriver().core; }

unittest {
  auto eventLoop = createEventLoop();
  assert(eventLoop !is null);

  eventLoop.exit();
  // TODO: Does `eventLoop.exit` dispose the event loop? eventLoop.dispose();
}
