module teraflop.game;

/// Derive from this class for your game application
abstract class Game {
  private bool active_;
  import teraflop.time : Time;
  private auto time_ = Time.zero;
  private bool limitFrameRate = true;
  private int desiredFramerateHertz_ = 60;

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
  protected void update() {}
  private void render() {}

  /// Stop the game loop and exit the game
  protected void exit() {
    active_ = false;
  }
}
