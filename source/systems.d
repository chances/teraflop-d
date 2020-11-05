/// Teraflop's built-in ECS Systems.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.systems;

import teraflop.components : IResource;
import teraflop.ecs : Component, System, World;
import teraflop.vulkan : Device;

/// Initialize un-initialized Components with handles to GPU resources.
final class ResourceInitializer : System {
  private Device device;

  /// Initialize a new ResourceInitializer.
  this(const World world, Device device) {
    super(world);

    this.device = device;
  }

  override void run() const {
    import std.algorithm.iteration : filter, map, joiner;
    import std.algorithm.searching : any, canFind;
    import std.array : array;
    import std.conv : to;

    auto resources = query().map!(entity => entity.getMut!IResource).joiner
      .filter!(c => !c.initialized).array;
    foreach (resource; resources)
      resource.initialize(device);
  }
}
