/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.game;

/// Derive this class for your game application.
abstract class Game {
  import teraflop.ecs : isSystem, System, SystemGenerator, World;
  import teraflop.time : Time;

  private bool active_;
  private auto time_ = Time.zero;
  private bool limitFrameRate = true;
  private int desiredFramerateHertz_ = 60;

  private auto world = new World();
  private auto systems = new System[0];

  bool active() const @property {
    return active_;
  }

  const(Time) time() const @property {
    return time_;
  }

  bool frameRateLimited() const @property {
    return limitFrameRate;
  }

  int desiredFramerateHertz() const @property {
    return desiredFramerateHertz_;
  }

  /// Add a System that operates on resources and Components in the game's World.
  void add(System system) {
    systems ~= system;
  }
  /// Add a System, dynamically generated from a function, that operates on resources and Components in the game's World.
  void add(SystemGenerator system) {
    systems ~= system(world);
  }

  protected abstract void initialize();

  private void initializeWorld() {}

  /// Run the game
  void run() {
    active_ = true;

    initialize();
    initializeWorld();

    import std.datetime.stopwatch : AutoStart, StopWatch;
    auto stopwatch = StopWatch(AutoStart.yes);

    while (active) {
      auto elapsed = stopwatch.peek();
      time_ = Time(time.total + elapsed, elapsed);
      auto deltaSeconds = time.deltaSeconds;

      const desiredFrameTimeSeconds = 1.0f / desiredFramerateHertz;
      while (limitFrameRate && deltaSeconds < desiredFrameTimeSeconds) {
        elapsed = stopwatch.peek();
        time_ = Time(time.total + elapsed, elapsed);
        deltaSeconds += time.deltaSeconds;
        stopwatch.reset();

        // Don't gobble up all available CPU cycles while waiting
        const deltaMilliseconds = desiredFrameTimeSeconds * 1000.0 - elapsed.total!"msecs";
        import core.thread : Thread;
        import core.time : msecs;
        if (deltaMilliseconds > 8) Thread.sleep(5.msecs);
      }

      import std.typecons : Yes;
      if (deltaSeconds > desiredFrameTimeSeconds * 1.25) Time(time_, Yes.runningSlowly);

      // TODO: Calculate average FPS given deltaSeconds

      update();
      if (!active) break;
      render();
    }
  }

  /// Called when the game should update itself
  private void update() {
    // TODO: Coordinate dependencies between Systems and parallelize those without conflicts
    foreach (system; systems)
      system.run();
  }

  /// Called when the game should render itself
  private void render() {
    foreach (entity; world.entities) {
      // TODO: Add a `Renderable` component with data needed to render an Entity with wgpu
    }
  }

  /// Stop the game loop and exit the game
  protected void exit() {
    active_ = false;
  }
}
