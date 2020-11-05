/// Built-in Components and Component primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.components;

import concepts : implements;
import std.meta : templateAnd, templateOr;

import teraflop.ecs : isComponent, storableAsComponent;
import teraflop.time : Time;
import teraflop.traits : isStruct;
import teraflop.vulkan : Device;

/// A Component that should be updated every frame.
interface IUpdatable {
  /// Update the component given the current `Time`.
  void update(Time gameTime);
}

/// Detect whether `T` is a disposable Component.
template isDisposable(T) {
  alias implementsDisposable(T) = implements!(T, IDisposable);
  alias isDisposableStruct = templateAnd!(isStruct, implementsDisposable);
  enum bool isDisposable = storableAsComponent!T && (isDisposableStruct!T || isComponent!T);
}

/// Provides a mechanism for releasing unmanaged resources.
interface IDisposable {
  /// Performs application-defined tasks associated with freeing, releasing, or resetting unmanaged resources.
  void dispose();
}

/// A Component that holds one or more handles to GPU resources.
///
/// See_Also: `teraflop.ecs.Component`
interface IResource {
  /// Whether this Resource has been successfully initialized.
  bool initialized() @property const;
  /// Initialize this Resource. Sets `intiialized` to `true` when successful.
  void initialize(Device device);
}
