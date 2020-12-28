module engine.scripting;

import libasync : EventLoop, getThreadEventLoop, AsyncSignal;
import std.container : DList;
import wasmer;
public import wasmer : Extern, Function, Memory, Module, Trap, Value;

import teraflop.async.event : Event;
public import std.json : JSONType, JSONValue, parseJSON, toJSON;

alias Queue = DList;

abstract class Actor(Msg) {
  private EventLoop eventLoop;
  private auto mailbox = Queue!Msg();
  private shared AsyncSignal onMessageSignal;

  protected Event!Msg onMessage;

  this() {
    eventLoop = getThreadEventLoop();
    onMessageSignal = new shared AsyncSignal(eventLoop);
  }

  void postMessage(Msg message) {
    synchronized {
      assert(mailbox.insertBack!Msg(message) == 1);
    }
    onMessageSignal.trigger();
  }

  void start() {
    import std.range : popFrontN, walkLength;

    onMessageSignal.run({
      auto messages = mailbox[];
      if (walkLength(messages) == 0) return;

      auto message = mailbox.front;
      mailbox.popFirstOf(messages);
      onMessage(message);
    });
  }

  void stop() {
    onMessageSignal.kill();
  }
}

auto externNameMatches = (Extern a, string b) => a.name == b;

/// An abstract class with helpers to create WebAssembly bindings.
abstract class Interface : Actor!string {
  protected Module entryModule;
  protected Instance instance;
  protected Extern[] exports;
  protected Function entryPoint;

  /// Params:
  /// entry=
  /// entryPoint=Name of the entry point function to retreive from the module
  /// imports=Globals, memories, tables, and functions to expose to the module
  this(Module entry, string entryPoint, Extern[] imports = []) {
    import std.algorithm : canFind, find;
    import std.exception : enforce;
    import std.string : format;

    enforce(entry.valid, "Entry module is not compiled.");
    entryModule = entry;
    instance = entryModule.instantiate(imports);
    enforce(instance.valid, "Could not instantiate entry module.\nPerhaps there are mismatched imports?");
    exports = instance.exports;

    const entryPointError = format!"Could not retreive '%s' entry point function."(entryPoint);
    enforce(exports.canFind!(externNameMatches)(entryPoint), entryPointError);
    this.entryPoint = Function.from(exports.find!(externNameMatches)(entryPoint)[0]);
    enforce(this.entryPoint.valid, entryPointError);
  }
}
