/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.async.worker;

import libasync.threads : destroyAsyncThreads;

shared static ~this() { destroyAsyncThreads(); }

/// An asynchronous primitive that performs work in the background.
class Worker {
  // TODO: Threaded worker, see https://github.com/etcimon/libasync/blob/c505944e58e87663e889bc87f1ee6a3d38130e74/examples/netcat/source/app.d#L199
}
