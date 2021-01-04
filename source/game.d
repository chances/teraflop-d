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
  import teraflop.graphics : BindingGroup, Pipeline, Material, MeshBase;
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
  private DescriptorPool[const Material] descriptorPools;
  private DescriptorSet[const Material] descriptorSets;
  private Buffer[const Material] uniformBuffers;
  private alias BindingGroups = BindingGroup[];
  private BindingGroups[const Material] bindingGroups;
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
    import std.exception : enforce;
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
    foreach (pipeline; pipelines.values) pipeline.dispose();
    foreach (descriptorPool; descriptorPools.values) descriptorPool.dispose();
    foreach (uniformBuffer; uniformBuffers.values) uniformBuffer.dispose();

    device.waitIdle();
    renderPass.unload();
    foreach (frameData; frameDatas) frameData.release();

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
    import gfx.core : retainObj;
    import gfx.graal : Surface;
    import gfx.graal.format : Format;
    import gfx.graal.image : ImageUsage;
    import gfx.graal.presentation : CompositeAlpha, PresentMode;

    auto hasSwapchain = (window in swapChains) !is null;
    if (!hasSwapchain || window.dirty || needsRebuild) {
      if (hasSwapchain) foreach (frameData; frameDatas) {
        frameData.fence.wait();
        frameData.release();
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
        frameDatas = new FrameData[images.length];

        foreach(i, img; images)
          frameDatas[i] = retainObj(new GameFrameData(graphicsQueue[window].index, img));
      }
    }
  }

  // TODO: Extract this into a pipeline system
  private struct Renderable {
    Pipeline pipeline;
    PipelineLayout layout;
    DescriptorSet set;
    const MeshBase mesh;
  }
  alias Renderables = Renderable[];
  private Renderables[const Material] renderables;
  private bool hasPipeline(const Material material) {
    return (material in pipelines) !is null;
  }
  private void updatePipelines() {
    import gfx.core : none;
    import std.algorithm : all, filter, map, joiner, sum;
    import std.array : array;
    import std.range : enumerate;
    import std.typecons : No;
    import teraflop.graphics : BindingDescriptor, Camera, Color;
    import teraflop.platform.vulkan : createDynamicBuffer;

    const window = world.resources.get!Window;
    auto surfaceSize = window.framebufferSize;

    foreach (entity; world.entities) {
      if (!entity.contains!Material || !entity.contains!MeshBase) continue;
      const material = entity.get!Material()[0];
      if (!material.initialized) continue;
      const mesh = entity.get!MeshBase()[0];
      if (!mesh.initialized) continue;

      if (hasPipeline(material)) continue;
      renderables[material] = new Renderable[0];

      DescriptorPoolSize[] poolSizes;
      DescriptorSetLayout[] descriptors;
      const(BindingDescriptor)[] uniforms;
      // Bind the World's primary camera mvp uniform, if any
      if (world.resources.contains!Camera) {
        auto uniform = world.resources.get!Camera.uniform;
        poolSizes ~= DescriptorPoolSize(DescriptorType.uniformBuffer, 1);
        descriptors ~= device.createDescriptorSetLayout([
          PipelineLayoutBinding(uniform.bindingLocation, uniform.bindingType, 1, uniform.shaderStage)
        ]);
        uniforms ~= uniform;
      }

      if (descriptors.length) {
        bindingGroups[material] = [BindingGroup(bindingGroups.length.to!uint, uniforms)];
        descriptorPools[material] = device.createDescriptorPool(1, poolSizes);
        descriptorSets[material] = descriptorPools[material].allocate(descriptors)[0];
        uniformBuffers[material] = device.createDynamicBuffer(
          uniforms.map!(uniform => uniform.size).sum, BufferUsage.uniform
        );
        WriteDescriptorSet[] descriptorWrites = uniforms.map!(
          uniform => uniform.descriptorWrite(descriptorSets[material], uniformBuffers[material])
        ).array;
        device.updateDescriptorSets(descriptorWrites, []);
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
      renderables[material] ~= Renderable(
        pipeline, info.layout,
        descriptors.length ? descriptorSets[material] : null, mesh
      );
    }

    if (renderables.length == 0 || !frameDatas.all!(fb => fb.to!GameFrameData.fresh)()) return;

    // Renderables in the world changed or framebuffers were recreated, re-record graphics commands
    foreach (frameData; frameDatas) {
      auto frame = frameData.to!GameFrameData;
      auto commands = frame.cmdBuf;
      auto clearColor = window.clearColor.toVulkan;

      frame.fence.wait();
      frame.markRecorded();

      commands.begin(CommandBufferUsage.simultaneousUse);
      commands.beginRenderPass(
        renderPass, frame.frameBuffer,
        Rect(0, 0, surfaceSize.width, surfaceSize.height),
        [ClearValues(clearColor)]
      );
      foreach (renderable; renderables.values.joiner) {
        commands.bindPipeline(renderable.pipeline);
        // TODO: Use a staging buffer? https://vulkan-tutorial.com/en/Vertex_buffers/Staging_buffer
        commands.bindVertexBuffers(0, [VertexBinding(renderable.mesh.vertexBuffer, 0)]);
        commands.bindIndexBuffer(renderable.mesh.indexBuffer, 0, IndexType.u32);
        if (renderable.set !is null)
          commands.bindDescriptorSets(PipelineBindPoint.graphics, renderable.layout, 0, [renderable.set], []);
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

        // Update uniforms
        foreach (material, descriptorGroups; bindingGroups) {
          // TODO: Only blit dirty uniforms?
          ubyte[] uniformData;
          auto uniforms = descriptorGroups
            .map!(group => group.bindings.filter!(b => b.bindingType == DescriptorType.uniformBuffer))
            .joiner;
          foreach (uniform; uniforms)
            uniformData ~= uniform.data;
          auto buf = uniformBuffers[material].boundMemory.map.view!(ubyte[])[];
          const unfilled = uniformData.copy(buf);
          assert(unfilled.length == buf.length - uniformData.length);
        }

        auto commands = frameData.to!GameFrameData.cmdBuf;
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
    Rc!Framebuffer frameBuffer;

    this(uint queueFamilyIndex, ImageBase swcColor, CommandBuffer tempBuf = null) {
      super(device, queueFamilyIndex, swcColor);
      cmdBuf = cmdPool.allocatePrimary(1)[0];

      cmdBuf.begin(CommandBufferUsage.simultaneousUse);
      cmdBuf.end();

      frameBuffer = device.createFramebuffer(this.outer.renderPass.obj, [
        swcColor.createView(
          ImageType.d2,
          ImageSubresourceRange(ImageAspect.color),
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
      frameBuffer.unload();
      super.dispose();
    }
  }
}
