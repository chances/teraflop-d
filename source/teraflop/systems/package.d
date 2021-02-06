/// Teraflop's built-in ECS Systems.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.systems;

public import teraflop.systems.rendering;

import gfx.graal;
import std.algorithm.iteration : filter, map, joiner;
import std.array : array;
import teraflop.components : IResource;
import teraflop.ecs : Component, System, World;

/// Initialize un-initialized Components with handles to GPU resources.
final class ResourceInitializer : System {
  private Device device;

  /// Initialize a new ResourceInitializer.
  this(const World world, Device device) {
    super(world);

    this.device = device;
  }

  override void run() {
    auto resources = query().map!(entity => entity.getMut!IResource).joiner
      .filter!(c => !c.initialized).array;
    foreach (resource; resources) resource.initialize(device);
  }
}

/// Dispose managed GPU resources.
final class ResourceGarbageCollector : System {
  private Device device;

  /// Initialize a new ResourceGarbageCollector.
  this(const World world, Device device) {
    super(world);

    this.device = device;
  }

  override void run() {
    auto resources = query().map!(entity => cast(Component[]) entity.components).joiner
      .filter!(c => typeid(IResource).isBaseOf(c.classinfo) && (cast(IResource) c).initialized).array;
    foreach (resource; resources) {
      device.waitIdle();
      destroy(resource);
    }
  }
}

/// Update dirty `teraflop.graphics.Texture` GPU resources.
final class TextureUploader : System {
  import teraflop.platform.vulkan : OneTimeCmdBufPool;

  private OneTimeCmdBufPool cmdBuf;

  /// Initialize a new TextureUploader.
  this(const World world, OneTimeCmdBufPool cmdBuf) {
    super(world);

    this.cmdBuf = cmdBuf;
  }
  ~this() {
    destroy(cmdBuf);
  }

  override void run() {
    import teraflop.graphics : Material;

    auto materials = query().map!(entity => entity.getMut!Material).joiner
      .filter!(c => c.initialized && c.textured && c.dirty && c.dirtied.textureChanged)
      .map!(c => c.dirtied).array;
    if (materials.length == 0) return;

    auto commands = cmdBuf.get;
    foreach (material; materials) {
      const texture = material.texture;
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

      material.resetDirtied();
      texture.dirty = false;
    }
    cmdBuf.submit(commands);
  }
}

/// Watch `teraflop.components.ObservableFile`s for changes where `ObservableFile.hotReload` is `true`.
/// See_Also: `teraflop.components.ObservableFile`
final class FileWatcher : System {
  import libasync.watcher : AsyncDirectoryWatcher;
  import teraflop.components : ObservableFile, ObservableFileCollection;

  private ObservableFile[string] observedFiles;
  private string[string] observedDirectories;
  private AsyncDirectoryWatcher watcher;

  /// Initialize a new FileWatcher.
  this(const World world /* TODO: Add a whitelist of directories that may be watched */) {
    import libasync.events : getThreadEventLoop;

    super(world);
    watcher = new AsyncDirectoryWatcher(getThreadEventLoop);
    assert(watcher !is null);
    this.watch();
  }
  ~this() {
    watcher.kill();
  }

  override void run() {
    import std.algorithm : canFind, find, multiwayUnion, setSymmetricDifference, sort, SwapStrategy;
    import std.path : dirName;
    import std.range : chain;
    import std.string : format;

    auto observableFiles = chain(
      query().map!(entity => entity.getMut!ObservableFileCollection).joiner.map!(c => c.observableFiles).joiner,
      query().map!(entity => entity.getMut!ObservableFile).joiner
    ).filter!(file => file.hotReload).array;
    auto observableFilePaths = multiwayUnion([
      observableFiles.map!(c => c.filePath).array.dup.sort!("a < b", SwapStrategy.stable)
    ]);
    auto changes = setSymmetricDifference(observedFiles.keys, observableFilePaths).array;

    // Unwatch files removed from the World
    foreach (removedFile; changes.filter!(f => observedFiles.keys.canFind(f))) {
      observedFiles.remove(removedFile);
      observedDirectories.remove(removedFile);
      auto parentDirectory = removedFile.dirName;
      // Unwatch the removed file's parent directory iff no other files in the directory are being watched
      if (!observedDirectories.values.canFind(parentDirectory)) {
        const error = format!"Could not unwatch %s for changes!"(removedFile);
        assert(watcher.unwatchDir(parentDirectory, false), error);
        // TODO: Log `error`
      }
    }

    // Watch files added to the World
    auto additions = changes.filter!(f => !observedFiles.keys.canFind(f));
    foreach (addedFile; additions) {
      observedFiles[addedFile] =
        observableFiles.find!((ObservableFile c, string filePath) => c.filePath == filePath)(addedFile)[0];
      auto parentDirectory = addedFile.dirName;
      // Watch the added file's parent directory if it's _not_ already being watched
      if (!observedDirectories.values.canFind(parentDirectory)) {
        const error = format!"Could not watch %s for changes!"(addedFile);
        assert(watcher.watchDir(parentDirectory), error);
        observedDirectories[addedFile] = parentDirectory;
        // TODO: Log `error`
      }
    }
  }

  private void watch() {
    import libasync.watcher : DWChangeInfo, DWFileEvent;

    watcher.run(() => {
      auto changes = new DWChangeInfo[observedFiles.length ? observedFiles.length : 1];
      while(watcher.readChanges(changes)) {
        foreach (change; changes) {
          if ((change.path in observedFiles) is null) continue;

          auto file = observedFiles[change.path];

          switch (change.event) {
            case DWFileEvent.ERROR:
              // TODO: Log something here?
              break;
	          case DWFileEvent.MODIFIED:
              file.readFile();
              file.onChanged(file.contents);
              break;
	          case DWFileEvent.CREATED:
              file.readFile();
              file.onChanged(file.contents);
              break;
	          case DWFileEvent.DELETED:
              file.readFile();
              if (!file.exists) file.onDeleted(change.path);
              break;
            default:
              if (change.event == DWFileEvent.MOVED_FROM || change.event == DWFileEvent.MOVED_TO) {
                // TODO: Report this status, maybe with an `onMoved` or `onLost` event?
                break;
              }
              assert(0);
          }
        }
      }
    }());
  }
}

// TODO: Add an integration test that writes to a text file to temp_dir, watches it, and then changes its contents
