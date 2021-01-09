/// Application primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.game;

import gfx.graal;
import std.conv : to;
import teraflop.platform.vulkan;
import teraflop.platform.window;

/// Derive this class for your game application.
abstract class Game {
  import core.time : msecs;
  import gfx.core.rc : Rc;
  import libasync.events : EventLoop, getThreadEventLoop;
  import std.exception : enforce;
  import teraflop.ecs : isSystem, System, SystemGenerator, World;
  import teraflop.graphics : BindingGroup, Pipeline, Material, MeshBase;
  import teraflop.systems : PipelinePreparer;
  import teraflop.time : Time;

  private string name_;
  private bool active_;
  private auto time_ = Time.zero;
  private bool limitFrameRate = true;
  private int desiredFrameRateHertz_ = 60;

  private Device device;
  private Window[] windows_;
  private Swapchain[const Window] swapChains;
  private bool[const Window] swapchainNeedsRebuild;
  private Queue[const Window] graphicsQueue;
  private Queue[const Window] presentQueue;
  private Rc!Semaphore[const Window] imageAvailable;
  private Rc!Semaphore[const Window] renderingFinished;
  private FrameData[] frameBuffers;
  private Rc!RenderPass renderPass;
  private PipelinePreparer pipelinePreparer;
  private EventLoop eventLoop;

  private auto world = new World();
  private auto systems = new System[0];

  /// Initialize a new Game.
  ///
  /// Params:
  /// name = Name of the Game.
  this(string name) {
    name_ = name;
  }

  /// Name of the Game.
  string name() const @property {
    return name_;
  }

  /// Whether the Game is active, i.e. is open and running.
  bool active() const @property {
    return active_;
  }

  const(Time) time() const @property {
    return time_;
  }

  /// Whether the Game's framerate is being limited.
  ///
  /// See_Also: `desiredFrameRateHertz`
  bool frameRateLimited() const @property {
    return limitFrameRate;
  }

  /// Target frame rate of the Game, in hertz.
  ///
  /// If `frameRateLimited` is `true`, the main loop will make its best effort to reach this goal
  /// while updating and rendering the Game.
  ///
  /// See_Also: `frameRateLimited`
  int desiredFrameRateHertz() const @property {
    return desiredFrameRateHertz_;
  }
  void desiredFrameRateHertz(int value) @property {
    desiredFrameRateHertz_ = value;
  }

  /// Add a System that operates on resources and Components in the game's `World`.
  void add(System system) {
    systems ~= system;
  }
  /// Add a System, dynamically generated from a function, that operates on resources and Components in the game's `World`.
  void add(SystemGenerator system) {
    systems ~= system(world);
  }

  /// Called when the Game should initialize its `World`.
  protected abstract void initializeWorld(scope World world);

  /// Run the game.
  void run() {
    import std.algorithm.searching : all;
    import std.datetime.stopwatch : AutoStart, StopWatch;
    import teraflop.platform.window : initGlfw, terminateGlfw;

    enforce(initGlfw()); // TODO: Log an error
    enforce(initVulkan(name), "Unsupported platform: Could not load Vulkan! Try upgrading your graphics drivers.");
    scope(exit) terminateGlfw();

    initialize();
    active_ = true;

    eventLoop = getThreadEventLoop();

    auto stopwatch = StopWatch(AutoStart.yes);
    while (active) {
      if (windows_.all!(w => !w.valid())) {
        active_ = false;
        break;
      }

      auto elapsed = stopwatch.peek();
      time_ = Time(time.total + elapsed, elapsed); // TODO: Use glfwGetTime instead? (https://www.glfw.org/docs/latest/input_guide.html#time)
      auto deltaSeconds = time.deltaSeconds;

      const desiredFrameTimeSeconds = 1.0f / desiredFrameRateHertz;
      while (limitFrameRate && deltaSeconds < desiredFrameTimeSeconds) {
        elapsed = stopwatch.peek();
        time_ = Time(time.total + elapsed, elapsed);
        deltaSeconds += time.deltaSeconds;
        stopwatch.reset();

        // Don't gobble up all available CPU cycles while waiting
        const deltaMilliseconds = desiredFrameTimeSeconds * 1000.0 - elapsed.total!"msecs";
        import core.thread : Thread;
        if (deltaMilliseconds > 8) Thread.sleep(5.msecs);
      }

      import std.typecons : Yes;
      if (deltaSeconds > desiredFrameTimeSeconds * 1.25) time_ = Time(time_, Yes.runningSlowly);
      stopwatch.reset();

      // TODO: Calculate average FPS given deltaSeconds

      update();
      if (!active) break;
      render();
    }

    eventLoop.exit();

    // Gracefully release GPU and other unmanaged resources
    foreach (entity; world.entities) {
      device.waitIdle();
      foreach (component; entity.components) {
        device.waitIdle();
        destroy(component);
      }
    }
    foreach (system; systems) destroy(system);
    destroy(world);

    foreach (window; windows_) {
      device.waitIdle();
      imageAvailable[window].unload();
      renderingFinished[window].unload();
      swapChains[window].dispose();

      destroy(window);
    }

    device.waitIdle();
    destroy(pipelinePreparer);

    device.waitIdle();
    renderPass.unload();
    foreach (frameBuffer; frameBuffers) frameBuffer.release();

    device.waitIdle();
    device.release();
    unloadVulkan();
  }

  private void initialize() {
    import gfx.core : retainObj, some;
    import std.typecons : No;
    import teraflop.systems : TextureUploader, ResourceInitializer;

    // Setup main window
    auto mainWindow = new Window(name);
    enforce(mainWindow.valid, "Could not open main game window!");
    windows_ ~= mainWindow;

    try {
      const graphicsQueueIndex = selectGraphicsQueue();
      enforce(graphicsQueueIndex >= 0, "Try upgrading your graphics drivers.");
      device = selectGraphicsDevice(graphicsQueueIndex, mainWindow.surface);
      // TODO: Create a separate presentation queue?
      graphicsQueue[mainWindow] = presentQueue[mainWindow] = device.getQueue(graphicsQueueIndex, 0);
    } catch (Exception ex) {
      enforce(0, "GPU Device initialization failed: " ~ ex.msg);
    }

    // Setup swap chain
    swapchainNeedsRebuild[mainWindow] = false;
    updateSwapChain(mainWindow);
    imageAvailable[mainWindow] = device.createSemaphore();
    renderingFinished[mainWindow] = device.createSemaphore();

    // Setup render pass
    const attachments = [
      AttachmentDescription(swapChains[mainWindow].format, 1,
        AttachmentOps(LoadOp.clear, StoreOp.store),
        AttachmentOps(LoadOp.dontCare, StoreOp.dontCare),
        trans(ImageLayout.undefined, ImageLayout.presentSrc),
        No.mayAlias
      ),
      AttachmentDescription(findDepthFormat(device.physicalDevice), 1,
        AttachmentOps(LoadOp.clear, StoreOp.dontCare),
        AttachmentOps(LoadOp.dontCare, StoreOp.dontCare),
        trans(ImageLayout.undefined, ImageLayout.depthStencilAttachmentOptimal),
        No.mayAlias
      )
    ];
    const subpasses = [SubpassDescription(
      [], [ AttachmentRef(0, ImageLayout.colorAttachmentOptimal) ],
      some(AttachmentRef(1, ImageLayout.depthStencilAttachmentOptimal)),
      []
    )];
    renderPass = device.createRenderPass(attachments, subpasses, []);

    // Setup pipeline preparer
    pipelinePreparer = new PipelinePreparer(world, device, renderPass.obj);

    // Setup frame buffers
    auto images = swapChains[mainWindow].images;
    frameBuffers = new FrameData[images.length];

    foreach(i, img; images)
      frameBuffers[i] = retainObj(new GameFrameData(graphicsQueue[mainWindow].index, img));

    // Setup built-in Systems
    systems ~= new ResourceInitializer(world, device);
    systems ~= new TextureUploader(world, new OneTimeCmdBufPool(device, graphicsQueue[mainWindow]));

    world.resources.add(mainWindow);
    initializeWorld(world);
  }

  /// Called when the Game should update itself.
  private void update() {
    import core.time : Duration;
    import gfx.graal.presentation : ImageAcquisition;
    import std.string : format;

    windows_[0].title = format!"%s - Frame time: %02dms"(name_, time_.deltaMilliseconds);
    foreach (window; windows_) {
      window.update();
      // Wait for minimized windows to restore
      if (window.minimized) continue;
      updateSwapChain(window, swapchainNeedsRebuild[window]);
      pipelinePreparer.run();
      recordCommands();
    }

    // Raise callbacks on the event loop
    if (!eventLoop.loop(Duration.zero)) {
      // TODO: Log that there was an unrecoverable error
      active_ = false;
      return;
    }

    world.resources.add(time_);

    // TODO: Coordinate dependencies between Systems and parallelize those without conflicts
    foreach (system; systems)
      system.run();
  }

  private void updateSwapChain(const Window window, bool needsRebuild = false) {
    import gfx.core : retainObj;
    import gfx.graal : Surface;
    import gfx.graal.format : Format;
    import gfx.graal.image : ImageUsage;
    import gfx.graal.presentation : CompositeAlpha, PresentMode;

    const hasSwapchain = (window in swapChains) !is null;
    if (!hasSwapchain || window.dirty || needsRebuild) {
      if (hasSwapchain) foreach (frameBuffer; frameBuffers) {
        frameBuffer.fence.wait();
        frameBuffer.release();
      }

      auto former = hasSwapchain ? swapChains[window] : null;
      swapChains[window] = device.createSwapchain(
        window.surface, PresentMode.fifo, 3, Format.bgra8_sRgb,
        [window.framebufferSize.width, window.framebufferSize.height],
        ImageUsage.colorAttachment, CompositeAlpha.opaque,
        former
      );

      // Recreate frame buffers when swapchains are recreated
      if (hasSwapchain) {
        device.waitIdle();
        former.dispose();

        auto images = swapChains[window].images;
        frameBuffers = new FrameData[images.length];

        foreach(i, img; images)
          frameBuffers[i] = retainObj(new GameFrameData(graphicsQueue[window].index, img));
      }
    }
  }

  // TODO: Extract this into a command recorder system
  private void recordCommands() {
    import std.algorithm : all;

    const nothingToRender = pipelinePreparer.renderables.length == 0;
    const frameBuffersAreNotFresh = !frameBuffers.all!(fb => fb.to!GameFrameData.fresh)();
    const materialsDidNotChange = !pipelinePreparer.materialsChanged;
    if ((nothingToRender || frameBuffersAreNotFresh) && materialsDidNotChange) return;

    // Renderables in the world changed or framebuffers were recreated, re-record graphics commands
    const window = world.resources.get!Window;
    foreach (frameBuffer; frameBuffers) {
      auto frame = frameBuffer.to!GameFrameData;
      auto commands = frame.cmdBuf;
      auto clearColor = window.clearColor.toVulkan;

      frame.fence.wait();
      frame.markRecorded();

      commands.begin(CommandBufferUsage.simultaneousUse);
      commands.beginRenderPass(
        renderPass, frame.frameBuffer,
        Rect(0, 0, window.framebufferSize.width, window.framebufferSize.height),
        [ClearValues(clearColor), ClearValues(ClearDepthStencilValues(1f, 0))]
      );
      foreach (renderable; pipelinePreparer.renderables) {
        commands.bindPipeline(cast(Pipeline) renderable.pipeline);
        // TODO: Use a staging buffer? https://vulkan-tutorial.com/en/Vertex_buffers/Staging_buffer
        commands.bindVertexBuffers(0, [VertexBinding(renderable.mesh.vertexBuffer, 0)]);
        commands.bindIndexBuffer(renderable.mesh.indexBuffer, 0, IndexType.u32);
        if (renderable.descriptorSet !is null) commands.bindDescriptorSets(
          PipelineBindPoint.graphics, cast(PipelineLayout) renderable.layout, 0,
          cast(DescriptorSet[]) [renderable.descriptorSet], []
        );
        foreach (i, pushConstant; renderable.pushBindings) commands.pushConstants(
          cast(PipelineLayout) renderable.layout, pushConstant.shaderStage, i, pushConstant.size, pushConstant.data.ptr
        );
        commands.drawIndexed(renderable.mesh.indices.length.to!uint, 1, 0, 0, 0);
      }
      commands.endRenderPass();
      commands.end();
    }
  }

  /// Called when the Game should render itself.
  private void render() {
    import gfx.graal.error : OutOfDateException;
    import std.algorithm.iteration : filter, joiner, map;
    import std.algorithm.mutation : copy;
    import std.array : array;
    import std.range : repeat;

    foreach (window; windows_) {
      // Wait for minimized windows to restore
      if (window.minimized) continue;

      auto swapChain = swapChains[window];
      const acq = swapChain.acquireNextImage(imageAvailable[window].obj);
      swapchainNeedsRebuild[window] = acq.swapchainNeedsRebuild;

      if (acq.hasIndex) {
        auto frameBuffer = frameBuffers[acq.index];
        frameBuffer.fence.wait();
        frameBuffer.fence.reset();

        // Update uniforms
        foreach (material, descriptorGroups; pipelinePreparer.bindingGroups) {
          if (!descriptorGroups.length) continue;
          if ((material in pipelinePreparer.uniformBuffers) is null) continue;
          // TODO: Only blit dirty uniforms?
          ubyte[] uniformData;
          auto uniforms = descriptorGroups
            .map!(group => group.bindings.filter!(b => b.bindingType == DescriptorType.uniformBuffer))
            .joiner;
          foreach (uniform; uniforms) {
            uniformData ~= uniform.data;
            // Align data in uniform buffer to `Device`'s minimum uniform buffer offset alignment
            const padding = device.physicalDevice.uniformAlignment(uniform.size) - uniform.size;
            uniformData ~= 0.to!ubyte.repeat(padding).array;
          }
          auto buf = pipelinePreparer.uniformBuffers[material].boundMemory.map.view!(ubyte[])[];
          const unfilled = uniformData.copy(buf);
          assert(unfilled.length == buf.length - uniformData.length);
        }

        auto commands = frameBuffer.to!GameFrameData.cmdBuf;
        auto submissions = simpleSubmission(window, [commands]);

        graphicsQueue[window].submit(submissions, frameBuffer.fence);

        try {
          presentQueue[window].present(
            [ renderingFinished[window].obj ],
            [ PresentRequest(swapChains[window], acq.index) ]
          );
        }
        catch (OutOfDateException ex) {
          // The swapchain became out of date between acquire and present.
          // Rare, but can happen
          // TODO: Log error
          // gfxExLog.errorf("error during presentation: %s", ex.msg);
          // gfxExLog.errorf("acquisition was %s", acq.state);
          swapchainNeedsRebuild[window] = true;
          return;
        }
      }
    }
  }

  /// Stop the game loop and exit the Game.
  protected void exit() {
    active_ = false;
  }

  /// Build a graphics pipeline submission for the simplest cases with a single submission.
  final Submission[] simpleSubmission(Window window, PrimaryCommandBuffer[] cmdBufs) {
    return [Submission(
      [ StageWait(imageAvailable[window], PipelineStage.transfer) ],
      [ renderingFinished[window].obj ], cmdBufs
    )];
  }

  private class GameFrameData : FrameData {
    protected auto _fresh = true;
    PrimaryCommandBuffer cmdBuf;
    Rc!Image depth;
    Rc!Framebuffer frameBuffer;

    this(uint queueFamilyIndex, ImageBase color, CommandBuffer tempBuf = null) {
      super(device, queueFamilyIndex, color);
      cmdBuf = cmdPool.allocatePrimary(1)[0];
      cmdBuf.begin(CommandBufferUsage.simultaneousUse);
      cmdBuf.end();

      depth = createDepthImage(this.outer.device, size);

      frameBuffer = this.outer.device.createFramebuffer(this.outer.renderPass.obj, [
        color.createView(
          ImageType.d2,
          ImageSubresourceRange(ImageAspect.color),
          Swizzle.identity
        ),
        depth.createView(
          ImageType.d2,
          ImageSubresourceRange(ImageAspect.depth),
          Swizzle.identity
        )
      ], size.width, size.height, 1);
    }

    /// Whether this framebuffer is newly created
    bool fresh() @property const {
      return _fresh;
    }
    ///
    void markRecorded() {
      _fresh = false;
    }

    override void dispose() {
      cmdPool.free([ cast(CommandBuffer)cmdBuf ]);
      depth.unload();
      frameBuffer.unload();
      super.dispose();
    }
  }
}
