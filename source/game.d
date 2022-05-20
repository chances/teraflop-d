/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.game;

import teraflop.platform.window;

/// Derive this class for your game application.
abstract class Game {
  import core.time : msecs;
  import teraflop.async: EventLoop;
  import teraflop.ecs : isSystem, System, SystemGenerator, World;
  import teraflop.time : Time;
  import wgpu.api : Adapter, Device, SwapChain;

  private string name_;
  private bool active_;
  private auto time_ = Time.zero;
  private bool limitFrameRate = true;
  private int desiredFrameRateHertz_ = 60;

  private Adapter adapter;
  private Device device;
  private Window[] windows_;
  private Window mainWindow_;

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

  private void initialize() {
    initializeWorld();
  }

  /// Called when the Game should initialize its `World`.
  protected abstract void initializeWorld();

  /// Run the game
  void run() {
    import std.algorithm.searching : all;
    import std.datetime.stopwatch : AutoStart, StopWatch;
    import teraflop.platform.window : initGlfw, terminateGlfw;
    import wgpu.api : Instance, PowerPreference;

    // Setup main window
    if (!initGlfw()) {
      return;
    }
    scope(exit) terminateGlfw();

    windows_ ~= mainWindow_ = new Window(name);
    if (!mainWindow_.valid) return;

    // Setup root graphics resources
    // TODO: Select `PowerPreference.lowPower` on laptops and whatnot
    auto adapter = Instance.requestAdapter(mainWindow_.surface, PowerPreference.highPerformance);
    assert(adapter.ready);
    device = adapter.requestDevice(adapter.limits);
    assert(device.ready);

    mainWindow_.initialize(adapter, device);
    initialize();
    active_ = true;

    auto stopwatch = StopWatch(AutoStart.yes);
    while (active) {
      if (windows_.all!(w => !w.valid)) {
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

    foreach (window; windows_) destroy(window);
  }

  /// Called when the Game should update itself.
  private void update() {
    import core.time : Duration;
    import std.string : format;
    import teraflop.async : ExitReason;

    mainWindow_.title = format!"%s - Frame time: %02dms"(name_, time_.deltaMilliseconds);
    foreach (window; windows_) window.update();

    // TODO: Coordinate dependencies between Systems and parallelize those without conflicts
    foreach (system; systems) system.run();

    // Raise callbacks on the event loop
    // TODO: Log if there was an unrecoverable error processing events
    final switch (!mainWindow_.eventLoop.processEvents(Duration.zero)) {
      case ExitReason.exited:
        active_ = false;
        return;
      case ExitReason.outOfWaiters:
        import std.traits : fullyQualifiedName;
        assert(0, "What does `" ~ fullyQualifiedName!(ExitReason.outOfWaiters) ~ "` mean?");
      case ExitReason.idle: goto case;
      case ExitReason.timeout:
        // Nothing happened, that's fine
    }
  }

  /// Called when the Game should render itself.
  private void render() {
    import std.typecons : Yes;
    import teraflop.graphics : Color;
    import wgpu.api : RenderPass;

    auto frame = mainWindow_.swapChain.getNextTexture();
    // TODO: Add `wgpu.api.TextureView.valid` property
    // TODO: assert(frame.valid !is null, "Could not get next swap chain texture");
    auto encoder = device.createCommandEncoder(name);
    auto renderPass = encoder.beginRenderPass(
      RenderPass.colorAttachment(frame, Color.cornflowerBlue.wgpu)
      // RenderPass.colorAttachment(frame, /* Red */ Color(1, 0, 0, 1))
    );

    foreach (entity; world.entities) {
      // TODO: Add a `Renderable` component with data needed to render an Entity with wgpu
    }

    renderPass.end();

    auto commandBuffer = encoder.finish();
    device.queue.submit(commandBuffer);
    mainWindow_.swapChain.present();

    // Force wait for a frame to render and pump callbacks
    device.poll(Yes.forceWait);
  }

  /// Stop the game loop and exit the Game.
  protected void exit() {
    active_ = false;
  }
}
