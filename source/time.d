module teraflop.time;

/// Tracks time-based statistics about the running game.
struct Time {
  import core.time : Duration;
  private Duration totalElapsedTime_ = Duration.zero;
  private Duration elapsedTime_ = Duration.zero;
  private bool runningSlowly_ = false;

  /// Instantiate an instance where `runningSlowly` is `false`.
  this(Duration totalElapsedTime, Duration elapsedTime) {
    totalElapsedTime_ = totalElapsedTime;
    elapsedTime_ = elapsedTime;
  }

  import std.typecons : Flag;
  /// Instantiate a copy of an instance with an explicit value for `runningSlowly`.
  this(Time other, Flag!"runningSlowly" runningSlowly) {
    totalElapsedTime_ = other.totalElapsedTime;
    elapsedTime_ = other.elapsedTime;
    runningSlowly_ = runningSlowly;
  }

  /// Modify the given `Time` instance, setting the `runningSlowly` flag.
  static void elapsingSlowly(Time other) {
    other.runningSlowly_ = true;
  }

  /// Amount of time elapsed since the start of the game.
  Duration totalElapsedTime() const @property {
    return totalElapsedTime_;
  }

  /// Amount of time elapsed since the last update.
  Duration elapsedTime() const @property {
    return elapsedTime_;
  }

  /// Amount of time elapsed since the last update, in seconds.
  float deltaSeconds() const @property {
    return totalElapsedTime.total!"msecs" / 1000.0f;
  }

  /// Whether or not the game loop is taking longer than its `targetElapsedTime`. In this case, the
  /// game loop can be considered to be running too slowly and should do something to "catch up."
  bool runningSlowly() const @property {
    return runningSlowly_;
  }
}
