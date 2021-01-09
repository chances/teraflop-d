/// Scripting API integration primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.scripting;

import libasync : EventLoop, getThreadEventLoop, AsyncSignal;
import std.container : DList;
import teraflop.ecs : NamedComponent;
import wasmer;
public import wasmer : Extern, Function, Memory, Module, Trap, Value;

import teraflop.async.event : Event;
public import std.json : JSONType, JSONValue, parseJSON, toJSON;

alias Queue = DList;

/// A computational `teraflop.ecs.Component` that concurrently:
/// $(UL
///   $(LI Send messages to other actors)
///   $(LI Create new actors)
///   $(LI Behaviorly respond to messages it receives from other actors)
/// )
///
/// Recipients of messages are identified by an Entity's `teraflop.ecs.Entity.id`. Thus, an actor can only
/// communicate with actors whose addresses it has. It can obtain those from a message it receives, or if the address
/// is for an actor it has itself created.
///
/// The actor model is characterized by inherent concurrency of computation within and among actors, dynamic creation
/// of actors, inclusion of actor addresses in messages, and interaction only through direct asynchronous message
/// passing with no restriction on message arrival order.
/// See_Also: <a href="https://en.wikipedia.org/wiki/Actor_model#Fundamental_concepts">Fundamental Concepts, Actor Model</a> on Wikipedia
abstract class Actor(Msg) : NamedComponent {
  private EventLoop eventLoop;
  private auto mailbox = Queue!Msg();
  private shared AsyncSignal onMessageSignal;

  /// Fired when this Actor pops a received message from its mailbox.
  protected Event!Msg onMessage;

  ///
  this(string name = "") {
    super(name);
    eventLoop = getThreadEventLoop();
    onMessageSignal = new shared AsyncSignal(eventLoop);
  }

  ///
  void postMessage(Msg message) {
    synchronized {
      assert(mailbox.insertBack!Msg(message) == 1);
    }
    onMessageSignal.trigger();
  }

  /// Start processing this Actor's mailbox in a new event loop.
  package (teraflop) void start() {
    import std.range : popFrontN, walkLength;

    onMessageSignal.run({
      auto messages = mailbox[];
      if (walkLength(messages) == 0) return;

      auto message = mailbox.front;
      mailbox.popFirstOf(messages);
      onMessage(message);
    });
  }

  /// Stop this Actor's event loop, effectually ending processing of its mailbox.
  void stop() {
    onMessageSignal.kill();
  }
}

///
auto externNameMatches = (Extern a, string b) => a.name == b;

/// An abstract class with helpers to create WebAssembly bindings.
abstract class ScriptableComponent : Actor!string {
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
