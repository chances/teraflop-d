/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.game;

import teraflop.platform.vulkan;
import teraflop.platform.window;

/// Derive this class for your game application.
abstract class Game {
  import core.time : msecs;
  import gfx.core.rc : Rc;
  import gfx.graal;
  import teraflop.graphics : Pipeline, Material;
  import libasync.events : EventLoop, getThreadEventLoop;
  import teraflop.ecs : isSystem, System, SystemGenerator, World;
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
  private FrameData[] frameDatas;
  private Rc!RenderPass renderPass;
  private CommandPool oneOffCommandPool;
  private Pipeline[const Material] pipelines;
  private EventLoop eventLoop;

  private auto world = new World();
  private auto systems = new System[0];

  /// Initialize a new Game.
  ///
  /// Params:
  /// name = Name of the Game.
  this(string name) {
    name_ = name;
    initVulkan(name);
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

  /// Run the game
  void run() {
    import std.algorithm.searching : all;
    import std.datetime.stopwatch : AutoStart, StopWatch;
    import teraflop.platform.window : initGlfw, terminateGlfw;

    if (!initGlfw() || !initVulkan(name)) {
      // TODO: Log an error
      return;
    }
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
      time_ = Time(time.total + elapsed, elapsed); // TODO: Use glfwGetTime instead?
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
    destroy(world);

    foreach (window; windows_) {
      device.waitIdle();
      imageAvailable[window].unload();
      renderingFinished[window].unload();
      swapChains[window].dispose();

      destroy(window);
    }

    foreach (pipeline; pipelines.values) {
      device.waitIdle();
      pipeline.dispose();
    }
    device.waitIdle();
    renderPass.unload();
    foreach (i, frameData; frameDatas) {
      device.waitIdle();
      frameData.release();
    }

    device.waitIdle();
    device.release();
    unloadVulkan();
  }

  private void initialize() {
    import gfx.core : none, retainObj;
    import std.typecons : No;
    import std.exception : enforce;
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
      oneOffCommandPool = device.createCommandPool(graphicsQueueIndex);
    } catch (Exception ex) {
      enforce(0, "GPU Device initialization failed: " ~ ex.msg);
    }

    // Setup swap chain
    swapchainNeedsRebuild[mainWindow] = false;
    updateSwapChain(mainWindow);
    imageAvailable[mainWindow] = device.createSemaphore();
    renderingFinished[mainWindow] = device.createSemaphore();

    // Setup render pass
    const attachments = [AttachmentDescription(swapChains[mainWindow].format, 1,
      AttachmentOps(LoadOp.clear, StoreOp.store),
      AttachmentOps(LoadOp.dontCare, StoreOp.dontCare),
      trans(ImageLayout.undefined, ImageLayout.presentSrc),
      No.mayAlias
    )];
    const subpasses = [SubpassDescription(
      [], [ AttachmentRef(0, ImageLayout.colorAttachmentOptimal) ],
      none!AttachmentRef, []
    )];
    renderPass = device.createRenderPass(attachments, subpasses, []);

    // Setup frame buffers
    auto images = swapChains[mainWindow].images;
    frameDatas = new FrameData[images.length];

    foreach(i, img; images)
      frameDatas[i] = retainObj(new GameFrameData(graphicsQueue[mainWindow].index, img));

    // Setup built-in Systems
    systems ~= new ResourceInitializer(world, device);
    systems ~= new TextureUploader(world, oneOffCommandPool, (PrimaryCommandBuffer cmdBuf) => {
      graphicsQueue[mainWindow].submit(
        [Submission([StageWait(imageAvailable[mainWindow], PipelineStage.transfer)], [], [cmdBuf])],
        null
      );
    }());

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
      updatePipelines();
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
    import gfx.graal : Surface;
    import gfx.graal.format : Format;
    import gfx.graal.image : ImageUsage;
    import gfx.graal.presentation : CompositeAlpha, PresentMode;

    // If the window is new, create its swap chain and graphics command buffer
    if ((window in swapChains) is null) {
      swapChains[window] = device.createSwapchain(
        window.surface, PresentMode.fifo, 3, Format.bgra8_sRgb,
        [window.framebufferSize.width, window.framebufferSize.height],
        ImageUsage.colorAttachment, CompositeAlpha.opaque
      );
      return;
    }

    // Otherwise, recreate the window's swap chain
    auto swapChain = swapChains[window];
    if (window.dirty || needsRebuild)
      swapChains[window] = device.createSwapchain(
        window.surface, PresentMode.fifo, 3, Format.bgra8_sRgb,
        [window.framebufferSize.width, window.framebufferSize.height],
        ImageUsage.colorAttachment, CompositeAlpha.opaque, swapChain
      );
  }

  private bool hasPipeline(const Material material) {
    return (material in pipelines) !is null;
  }
  private void updatePipelines() {
    import gfx.core : none;
    import gfx.core.rc : rc;
    import std.algorithm.iteration : filter, map;
    import std.conv : to;
    import std.range : enumerate;
    import std.typecons : No;
    import teraflop.graphics : Camera, Color, Material, MeshBase;

    const window = world.resources.get!Window;
    auto surfaceSize = window.framebufferSize;

    struct Renderable {
      Pipeline pipeline;
      const MeshBase mesh;
    }
    Renderable[] renderables;

    foreach (entity; world.entities) {
      if (!entity.contains!Material || !entity.contains!MeshBase) continue;
      const material = entity.get!Material()[0];
      if (!material.initialized) continue;
      const mesh = entity.get!MeshBase()[0];
      if (!mesh.initialized) continue;

      if (hasPipeline(material)) continue;

      DescriptorSetLayout[] descriptors;
      // Bind the World's primary camera mvp uniform, if any
      if (world.resources.contains!Camera) {
        auto uniform = world.resources.get!Camera.uniform;
        descriptors ~= device.createDescriptorSetLayout([
          PipelineLayoutBinding(uniform.bindingLocation, uniform.bindingType, 1, uniform.shaderStage)
        ]);
      }

      PipelineInfo info = {
        shaders: material.shaders,
        inputBindings: [mesh.bindingDescription],
        inputAttribs: mesh.attributeDescriptions,
        assembly: InputAssembly(Primitive.triangleList, No.primitiveRestart),
        rasterizer: Rasterizer(
          PolygonMode.fill, material.cullMode, material.frontFace, No.depthClamp,
          none!DepthBias, 1f
        ),
        viewports: [
            ViewportConfig(
                Viewport(0, 0, surfaceSize.width.to!float, surfaceSize.height.to!float),
                Rect(0, 0, surfaceSize.width, surfaceSize.height)
            )
        ],
        blendInfo: ColorBlendInfo(
            none!LogicOp, [
                ColorBlendAttachment(No.enabled,
                    BlendState(trans(BlendFactor.one, BlendFactor.zero), BlendOp.add),
                    BlendState(trans(BlendFactor.one, BlendFactor.zero), BlendOp.add),
                    ColorMask.all
                )
            ],
            [ 0f, 0f, 0f, 0f ]
        ),
        layout: device.createPipelineLayout(descriptors.length ? descriptors : [], []),
        renderPass: renderPass,
        subpassIndex: 0
      };

      auto pipeline = device.createPipelines([info])[0];
      pipelines[material] = pipeline;
      renderables ~= Renderable(pipeline, mesh);
    }

    if (renderables.length == 0) return;

    // Renderables in the world changed, re-record graphics commands
    foreach (frameData; frameDatas) {
      auto frame = (cast(GameFrameData) frameData);
      auto commands = frame.cmdBuf;
      auto clearColor = window.clearColor.toVulkan;

      commands.begin(CommandBufferUsage.simultaneousUse);
      commands.beginRenderPass(
        renderPass, frame.frameBuffer,
        Rect(0, 0, surfaceSize.width, surfaceSize.height),
        [ClearValues(clearColor)]
      );
      foreach (renderable; renderables) {
        commands.bindPipeline(renderable.pipeline);
        // TODO: Use a staging buffer? https://vulkan-tutorial.com/en/Vertex_buffers/Staging_buffer
        commands.bindVertexBuffers(0, [VertexBinding(renderable.mesh.vertexBuffer, 0)]);
        commands.bindIndexBuffer(renderable.mesh.indexBuffer, 0, IndexType.u32);
        commands.drawIndexed(renderable.mesh.indices.length.to!uint, 1, 0, 0, 0);
      }
      commands.endRenderPass();
      commands.end();
    }
  }

  /// Called when the Game should render itself.
  private void render() {
    import gfx.graal.error : OutOfDateException;

    foreach (window; windows_) {
      // Wait for minimized windows to restore
      if (window.minimized) continue;

      auto swapChain = swapChains[window];
      const acq = swapChain.acquireNextImage(imageAvailable[window].obj);
      swapchainNeedsRebuild[window] = acq.swapchainNeedsRebuild;

      if (acq.hasIndex) {
        auto frameData = frameDatas[acq.index];
        frameData.fence.wait();
        frameData.fence.reset();

        auto commands = (cast(GameFrameData) frameData).cmdBuf;
        auto submissions = simpleSubmission(window, [commands]);

        graphicsQueue[window].submit(submissions, frameData.fence);

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

  /// Build a submission for the simplest cases with one submission
  final Submission[] simpleSubmission(Window window, PrimaryCommandBuffer[] cmdBufs) {
    return [Submission(
      [ StageWait(imageAvailable[window], PipelineStage.transfer) ],
      [ renderingFinished[window].obj ], cmdBufs
    )];
  }

  private class GameFrameData : FrameData {
    PrimaryCommandBuffer cmdBuf;
    Rc!Framebuffer frameBuffer;

    this(uint queueFamilyIndex, ImageBase swcColor, CommandBuffer tempBuf = null) {
      super(device, queueFamilyIndex, swcColor);
      cmdBuf = cmdPool.allocatePrimary(1)[0];

      frameBuffer = device.createFramebuffer(this.outer.renderPass.obj, [
        swcColor.createView(
          ImageType.d2,
          ImageSubresourceRange(ImageAspect.color),
          Swizzle.identity
        )
      ], size.width, size.height, 1);
    }

    override void dispose() {
      cmdPool.free([ cast(CommandBuffer)cmdBuf ]);
      frameBuffer.unload();
      super.dispose();
    }
  }
}
