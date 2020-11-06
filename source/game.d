/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.game;

import teraflop.platform.window;
import teraflop.vulkan;

/// Derive this class for your game application.
abstract class Game {
  import core.time : msecs;
  import libasync.events : EventLoop, getThreadEventLoop;
  import teraflop.ecs : isSystem, System, SystemGenerator, World;
  import teraflop.graphics : Material;
  import teraflop.time : Time;
  import teraflop.vulkan : Pipeline, SwapChain;

  private string name_;
  private bool active_;
  private auto time_ = Time.zero;
  private bool limitFrameRate = true;
  private int desiredFrameRateHertz_ = 60;

  private Device device;
  private Window[] windows_;
  private SwapChain[const Window] swapChains;
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

  /// Run the game
  void run() {
    import std.algorithm.searching : all;
    import std.datetime.stopwatch : AutoStart, StopWatch;
    import teraflop.platform.window : initGlfw, terminateGlfw;
    import teraflop.vulkan : initVulkan;

    // Setup main window
    if (!initGlfw() || !initVulkan()) {
      // TODO: Log an error
      return;
    }
    scope(exit) terminateGlfw();
    auto mainWindow = new Window(name);
    windows_ ~= mainWindow;

    initialize();
    active_ = true;

    eventLoop = getThreadEventLoop();

    auto stopwatch = StopWatch(AutoStart.yes);
    while (active) {
      if (windows_.all!(w => !w.valid())) {
        active_ = false;
        return;
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
      if (deltaSeconds > desiredFrameTimeSeconds * 1.25) Time(time_, Yes.runningSlowly);

      // TODO: Calculate average FPS given deltaSeconds

      update();
      if (!active) break;
      render();
    }

    foreach (window; windows_)
      destroy(window);

    eventLoop.exit();
  }

  private void initialize() {
    import std.exception : enforce;
    import teraflop.graphics : Material;
    import teraflop.systems : ResourceInitializer;

    // Setup main window
    auto mainWindow = windows_[0];
    device = new Device(name);
    mainWindow.createSurface(device.instance);
    device.acquire();
    enforce(device.ready, "GPU Device initialization failed");
    enforce(SwapChain.supported(device, mainWindow.surface),
      "GPU not supported. Try upgrading your graphics drivers."
    );
    updateSwapChain(mainWindow);

    // Setup built-in Systems
    systems ~= new ResourceInitializer(world, device);

    world.resources.add(mainWindow);
    initializeWorld(world);
  }

  /// Called when the Game should update itself.
  private void update() {
    import core.time : Duration;
    import std.string : format;

    windows_[0].title = format!"%s - Frame time: %02dms"(name_, time_.deltaMilliseconds);
    foreach (window; windows_) {
      window.update();
      updateSwapChain(window);
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

  private void updateSwapChain(const Window window) {
    if ((window in swapChains) is null)
      swapChains[window] = device.createSwapChain(window.surface, window.framebufferSize);
    else if (window.dirty) {
      // TODO: Destroy old swap chain
      // auto oldSwapChain = swapChains[window];
      // oldSwapChain.destroy();
      swapChains[window] = device.createSwapChain(window.surface, window.framebufferSize, swapChains[window]);
    }
  }

  private void updatePipelines() {
    import teraflop.graphics : Color;

    foreach (entity; world.entities) {
      if (!entity.contains!Material) continue;
      const material = entity.get!Material()[0];
      if (!material.initialized || (material in pipelines) !is null) continue;

      const window = world.resources.get!Window;
      auto swapChain = swapChains[window];
      pipelines[material] = new Pipeline(device, window.framebufferSize, material, swapChain.presentationPass);
      auto clearColor = Color.black.toVulkan;

      auto buffer = device.createCommandBuffer(swapChain);
      buffer.beginRenderPass(&clearColor);
      buffer.bindPipeline(pipelines[material]);
      buffer.draw(3, 1, 0, 0);
      buffer.endRenderPass();
    }
  }

  /// Called when the Game should render itself.
  private void render() {
    const window = world.resources.get!Window;
    auto swapChain = swapChains[window];
    if (swapChain.ready) swapChain.drawFrame();

    foreach (entity; world.entities) {
      // TODO: Add a `Renderable` component with data needed to render an Entity with wgpu
    }
  }

  /// Stop the game loop and exit the Game.
  protected void exit() {
    active_ = false;
  }
}
