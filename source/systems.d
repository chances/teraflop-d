/// Teraflop's built-in ECS Systems.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.systems;

import teraflop.components : IResource;
import teraflop.ecs : Component, System, World;
import gfx.graal;

/// Initialize un-initialized Components with handles to GPU resources.
final class ResourceInitializer : System {
  private Device device;

  /// Initialize a new ResourceInitializer.
  this(const World world, Device device) {
    super(world);

    this.device = device;
  }

  override void run() {
    import std.algorithm.iteration : filter, map, joiner;
    import std.array : array;

    auto resources = query().map!(entity => entity.getMut!IResource).joiner
      .filter!(c => !c.initialized).array;
    foreach (resource; resources)
      resource.initialize(device);
  }
}

///
alias CommandBufFlush = void delegate(PrimaryCommandBuffer buf);

/// Update dirty `teraflop.graphics.Texture` GPU resources.
final class TextureUploader : System {
  private CommandPool commandPool;
  private CommandBufFlush flush;

  /// Initialize a new TextureUploader.
  this(const World world, CommandPool commandPool, CommandBufFlush flushCmdBuf) {
    super(world);

    this.commandPool = commandPool;
    this.flush = flushCmdBuf;
  }

  override void run() {
    import std.algorithm.iteration : filter, map, joiner;
    import std.array : array;
    import teraflop.graphics : Material;

    auto commands = commandPool.allocatePrimary(1)[0];
    commands.begin(CommandBufferUsage.oneTimeSubmit);

    auto textures = query().map!(entity => entity.getMut!Material).joiner
      .filter!(c => c.textured && c.initialized && c.texture.dirty)
      .map!(c => c.texture).array;
    if (textures.length == 0) return;

    foreach (texture; textures) {
      commands.pipelineBarrier(trans(PipelineStage.topOfPipe, PipelineStage.transfer), [], [
        ImageMemoryBarrier(
          trans(Access.none, Access.transferWrite),
          trans(ImageLayout.undefined, ImageLayout.transferDstOptimal),
          trans(queueFamilyIgnored, queueFamilyIgnored),
          texture.image, ImageSubresourceRange(ImageAspect.color)
        )
      ]);

      const dims = texture.image.info.dims;
      BufferImageCopy region = {
        extent: [dims.width, dims.height, dims.depth]
      };
      const regions = (&region)[0 .. 1];
      commands.copyBufferToImage(texture.buffer, texture.image, ImageLayout.transferDstOptimal, regions);

      commands.pipelineBarrier(trans(PipelineStage.transfer, PipelineStage.fragmentShader), [], [
        ImageMemoryBarrier(
          trans(Access.transferWrite, Access.shaderRead),
          trans(ImageLayout.transferDstOptimal, ImageLayout.shaderReadOnlyOptimal),
          trans(queueFamilyIgnored, queueFamilyIgnored),
          texture.image, ImageSubresourceRange(ImageAspect.color)
        )
      ]);

      texture.dirty = false;
    }

    commands.end();
    flush(commands);
  }
}
