/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.game;

import teraflop.platform.window;

/// Derive this class for your game application.
abstract class Game {
  import core.time : msecs;
  import std.typecons : Rebindable;
  import teraflop.async: EventLoop;
  import teraflop.ecs : System, SystemGenerator, World;
  import teraflop.input : Input, InputDevice, InputEvent;
  import teraflop.time : Time;
  import wgpu.api : Adapter, Device, Instance;

  private string name_;
  private bool active_;
  private auto time_ = Time.zero;
  private bool limitFrameRate = true;
  private int desiredFrameRateHertz_ = 60;

  private Instance instance;
  private Adapter adapter;
  private Device device;
  private Window[] windows_;
  private Window _mainWindow;
  private Input[const Window] input;
  // https://dlang.org/library/std/typecons/rebindable.html#2
  private Rebindable!(const InputEvent)[InputDevice] newInput;

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

  /// This Game's primary window.
  Window mainWindow() @trusted const @property {
    return cast(Window) _mainWindow;
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
    // Setup main window
    input[mainWindow] = new Input(mainWindow);
    input[mainWindow].addNode(mainWindow);
    mainWindow.onUnhandledInput ~= (const InputEvent event) {
      newInput[event.device] = event;
      if (event.isKeyboardEvent)
        world.resources.add(event.asKeyboardEvent);
      if (event.isMouseEvent)
        world.resources.add(event.asMouseEvent);
      if (event.isActionEvent)
        world.resources.add(event.asActionEvent);
    };
    world.resources.add(mainWindow);
    world.resources.add(input[mainWindow]);

    initializeWorld(world);
  }

  /// Called when the Game should initialize its `World`.
  protected abstract void initializeWorld(scope World world);

  /// Run the game
  void run() {
    import std.algorithm.searching : all;
    import std.datetime.stopwatch : AutoStart, StopWatch;
    import teraflop.platform.window : initGlfw, terminateGlfw;
    import wgpu.api : PowerPreference;

    // Setup main window
    if (!initGlfw()) {
      return;
    }
    scope(exit) terminateGlfw();

    windows_ ~= _mainWindow = new Window(instance, name);
    if (!_mainWindow.valid) return;

    // Setup graphics resources
    this.instance = Instance.create();
    // TODO: Select `PowerPreference.lowPower` on laptops and whatnot
    this.adapter = instance.requestAdapter(_mainWindow.surface, PowerPreference.highPerformance);
    assert(adapter.ready);
    device = adapter.requestDevice(adapter.limits);
    assert(device.ready);

    _mainWindow.initialize(adapter, device);
    initialize();
    active_ = true;

    auto stopwatch = StopWatch(AutoStart.yes);
    while (active) {
      if (windows_.all!(w => !w.valid)) {
        active_ = false;
        return;
      }

      auto elapsed = stopwatch.peek();
      time_ = Time(time.total + elapsed, elapsed); // TODO: Use glfwGetTime instead? (https://www.glfw.org/docs/latest/input_guide.html#time)

      const desiredFrameTimeSeconds = 1.0f / desiredFrameRateHertz;
      auto underBudget = time.deltaSeconds < desiredFrameTimeSeconds;
      stopwatch.reset();
      while (limitFrameRate && underBudget) {
        time_ = time_.add(stopwatch.peek());
        underBudget = time.deltaSeconds < desiredFrameTimeSeconds;
        stopwatch.reset();

        // Don't gobble up all available CPU cycles while waiting
        const deltaMilliseconds = desiredFrameTimeSeconds * 1000.0 - elapsed.total!"msecs";
        import core.thread : Thread;
        if (deltaMilliseconds > 8) Thread.sleep(5.msecs);
      }

      import std.typecons : Yes;
      auto deltaSeconds = time.deltaSeconds;
      if (deltaSeconds > desiredFrameTimeSeconds * 1.25) time_ = Time(time_, Yes.runningSlowly);
      world.resources.add(time_);

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
    import teraflop.ecs : SystemException;
    import teraflop.input : InputEventAction, InputEventKeyboard, InputEventMouse;

    _mainWindow.title = format!"%s - Frame time: %02dms"(name_, time_.deltaMilliseconds);
    foreach (window; windows_) {
      window.update();
      // Wait for hidden and minimized windows to restore
      if (!window.visible || window.minimized) continue;
      // Process window input
      input[window].update(window);
    }

    // TODO: Coordinate dependencies between Systems and parallelize those without conflicts
    foreach (system; systems) {
      try system.run();
      catch (SystemException ex) {
        // TODO: Log recoverable System errors
      }
    }

    // Raise callbacks on the event loop
    // TODO: Log if there was an unrecoverable error processing events
    final switch (!_mainWindow.eventLoop.processEvents(Duration.zero)) {
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

    // Prune old input from the World
    foreach (input; newInput.values) {
      if (input.isKeyboardEvent) {
        if (world.resources.contains!InputEventKeyboard)
          world.resources.remove(input.asKeyboardEvent);
      }
      if (input.isMouseEvent) {
        if (world.resources.contains!InputEventMouse)
          world.resources.remove(input.asMouseEvent);
      }
      if (input.isActionEvent) {
        if (world.resources.contains!InputEventAction)
          world.resources.remove(input.asActionEvent);
      }
      newInput.remove(input.device);
    }
  }

  /// Called when the Game should render itself.
  private void render() {
    import std.typecons : Yes;
    import teraflop.graphics.color : Color;
    import wgpu.api : RenderPass;
    import wgpu.utils : wrap;

    auto surface = _mainWindow.surface.getCurrentTexture();
    auto surfaceTexture = surface.texture.wrap(_mainWindow.surface.descriptor);
    auto frame = surfaceTexture.defaultView;
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
    _mainWindow.surface.present();

    // Force wait for a frame to render and pump callbacks
    device.poll(Yes.forceWait);
  }

  /// Stop the game loop and exit the Game.
  protected void exit() {
    active_ = false;
  }
}
