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
///   $(LI Sends messages to other actors)
///   $(LI Creates new actors)
///   $(LI Behaviorly responds to messages it receives from other actors)
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
  private auto mailbox = Queue!Msg();
  // https://libasync.dpldocs.info/libasync.signal.AsyncSignal.html
  private shared AsyncSignal onMessageSignal;

  /// Fired when this Actor pops a received message from its mailbox.
  protected Event!Msg onMessage;

  ///
  this(string name = "") {
    super(name);
    auto eventLoop = getThreadEventLoop();
    onMessageSignal = new shared AsyncSignal(eventLoop);
  }
  ~this() {
    onMessageSignal.kill();
  }

  /// Push a new `Msg` to this Actor's mailbox queue.
  package (teraflop) void postMessage(Msg message) {
    synchronized assert(mailbox.insertBack!Msg(message) == 1);
    onMessageSignal.trigger();
  }

  /// Start processing this Actor's mailbox in its thread's event loop.
  package (teraflop) void start() {
    import std.range : walkLength;

    onMessageSignal.run({
      auto messages = mailbox[];
      if (walkLength(messages) == 0) return;

      auto message = mailbox.front;
      synchronized mailbox.popFirstOf(messages);
      onMessage(message);
    });
  }

  /// Stop processing this Actor's mailbox.
  package (teraflop) void stop() {
    onMessageSignal.kill();
  }
}

// TODO: Test the Actor class
// unittest {}

///
enum Error {
  ///
  unknown = 0,
  ///
  exception,
  ///
  msgpack,
  ///
  commandNotFound,
  ///
  actionNotFound
}

///
struct ErrorMessage {
  /// See_Also: `Error`
  uint code;
  ///
  string message;
}

///
struct Message {
  ///
  ErrorMessage* error = null;
  /// Body of this Message encoded in the <a href="https://msgpack.org">MessagePack</a> format.
  ubyte[] value = null;

  ///
  static Message fromError(Msg)(ref ErrorMessage error) {
    return Message(&error);
  }

  ///
  static Message fromError(Msg)(Error code, string message) {
    return Message.fromError(ErrorMessage(code, message));
  }

  ///
  static Message fromValue(Msg)(ubyte[] value) {
    return Message(null, value);
  }
}

/// A Component that is scriptable and exposes an interface to WebAssembly.
/// See_Also:
/// $(UL
///   $(LI `ScriptableComponent`)
/// )
// / <h3>Implementations</h3>
// / $(UL
// /   $(LI `teraflop.components.Transform`)
// /   $(LI `teraflop.graphics.Material`)
// /   $(LI `teraflop.graphics.Mesh`)
// /   $(LI `teraflop.graphics.Shader`)
// /   $(LI `teraflop.graphics.Texture`)
// / )
interface IScriptable(Msg) {
  ScriptableComponent!Msg script() @property const;
}

///
auto externNameMatches = (const Extern a, string b) => a.name == b;

/// An abstract class with helpers to create WebAssembly bindings.
/// See_Also:
/// $(UL
///   $(LI <a href="https://chances.github.io/wasmer-d">`wasmer` API Documentation</a>)
///   $(LI <a href="https://msgpack.org">MessagePack</a> specification)
///   $(LI <a href="http://msgpack.github.io/msgpack-d">`msgpack-d` API Documentation</a>)
/// )
abstract class ScriptableComponent(Msg) : Actor!Msg {
  static import msgpack;

  protected Module entryModule;
  protected Instance instance;
  protected const(Extern)[] exports;
  protected Function entryPoint;

  /// Params:
  /// entry=
  /// entryPoint=Name of the entry point function to retreive from the module
  /// imports=Globals, memories, tables, and functions to expose to the module
  this(Module entry, string entryPoint, Extern[] imports = []) {
    import std.algorithm : countUntil, joiner, map;
    import std.exception : enforce;
    import std.string : format;

    enforce(entry.valid, "Entry module is not or could not be compiled.");
    entryModule = entry;
    instance = entryModule.instantiate(imports);
    if (!instance.valid) {
      enforce(0, format!("Could not instantiate module with entry point `%s`!" ~
        "\n\tPerhaps there are mismatched imports?" ~
        "\n\tExpected imports:\n\t%s")(
          entryPoint,
          imports.map!(i => format!"\n\t%s"(i.name)).joiner
      ));
    }
    exports = instance.exports;

    const entryPointError = format!"Could not retreive '%s' entry point function."(entryPoint);
    const entryPointIndex = enforce(exports.countUntil!(externNameMatches)(entryPoint) >= 0, entryPointError);
    this.entryPoint = Function.from(exports[entryPointIndex]);
    enforce(this.entryPoint.valid, entryPointError);
  }

  /// Wheter the `entryPoint` has loaded and is ready for execution.
  bool ready() @property const {
    return entryPoint.valid;
  }

  /// Serialize a `Msg` in the <a href="https://msgpack.org">MessagePack</a> format.
  ///
  /// Throws: Stack Overflow when cyclic references occur in `data`.
  ubyte[] pack(in Msg data) {
    return msgpack.pack!true(data);
  }

  /// Deserialize a `Msg` in the <a href="https://msgpack.org">MessagePack</a> format.
  Msg unpack(in ubyte[] buffer) {
    auto result = Msg.init;
    msgpack.unpack(buffer, result);
    return result;
  }
}
