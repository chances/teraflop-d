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
    import std.array : array;

    auto resources = query().map!(entity => entity.getMut!IResource).joiner
      .filter!(c => !c.initialized).array;
    foreach (resource; resources)
      resource.initialize(device);
  }
}

/// Update dirty `teraflop.graphics.Texture` GPU resources.
final class TextureUploader : System {
  private Device device;

  /// Initialize a new TextureUploader.
  this(const World world, Device device) {
    super(world);

    this.device = device;
  }

  override void run() inout {
    import std.algorithm.iteration : filter, map, joiner;
    import std.array : array;
    import teraflop.graphics : Material;
    import teraflop.vulkan : ImageLayoutTransition;

    auto textures = query().map!(entity => entity.getMut!Material).joiner
      .filter!(c => c.textured && c.initialized && c.texture.dirty)
      .map!(c => c.texture).array;
    if (textures.length == 0) return;

    auto commands = device.createSingleTimeCommandBuffer();
    foreach (texture; textures) {
      commands.transitionImageLayout(texture.image, ImageLayoutTransition.undefinedToTransferOptimal);
      commands.copyBufferToImage(texture.buffer, texture.image);
      commands.transitionImageLayout(texture.image, ImageLayoutTransition.transferOptimalToShaderReadOnlyOptimal);
      texture.dirty = false;
    }
    commands.flush();
  }
}
