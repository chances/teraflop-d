/// Built-in Components and Component primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.components;

import teraflop.time : Time;
import teraflop.vulkan : Device;

/// A Component that should be updated every frame.
interface IUpdatable {
  /// Update the component given the current `Time`.
  void update(Time gameTime);
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
