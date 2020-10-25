module teraflop.time;

/// Tracks time-based statistics about the running game.
struct Time {
  import core.time : Duration;
  private Duration total_ = Duration.zero;
  private Duration delta_ = Duration.zero;
  private bool runningSlowly_ = false;

  /// An instance of `Time` where `total`, `delta`, and `runningSlowly` is `false`
  static @property Time zero() {
    return Time();
  }

  /// Instantiate an instance where `runningSlowly` is `false`.
  this(Duration total, Duration elapsed) {
    total_ = total;
    delta_ = elapsed;
  }

  import std.typecons : Flag;
  /// Instantiate a copy of an instance of `Time` with an explicit value for `runningSlowly`.
  this(Time other, Flag!"runningSlowly" runningSlowly) {
    total_ = other.total;
    delta_ = other.delta;
    runningSlowly_ = runningSlowly;
  }

  /// Amount of time elapsed since the start of the game.
  Duration total() const @property {
    return total_;
  }

  /// Amount of time elapsed since the start of the game, in milliseconds.
  long totalMilliseconds() const @property {
    return total.total!"msecs";
  }

  /// Amount of time elapsed since the start of the game, in seconds.
  float totalSeconds() const @property {
    return totalMilliseconds / 1000.0f;
  }

  /// Amount of time elapsed since the last update.
  Duration delta() const @property {
    return delta_;
  }

  /// Amount of time elapsed since the last update, in milliseconds.
  long deltaMilliseconds() const @property {
    return delta.total!"msecs";
  }

  /// Amount of time elapsed since the last update, in seconds.
  float deltaSeconds() const @property {
    return deltaMilliseconds / 1000.0f;
  }

  /// Whether or not the game loop is taking longer than its `targetElapsedTime`. In this case, the
  /// game loop can be considered to be running too slowly and should do something to "catch up."
  bool runningSlowly() const @property {
    return runningSlowly_;
  }
}

unittest {
  import std.datetime.stopwatch : AutoStart, StopWatch;
  auto stopwatch = StopWatch(AutoStart.yes);
  auto time = Time.zero;

  import core.thread : Thread;
  import core.time : msecs, seconds;
  Thread.sleep(24.msecs);
  auto elapsed = stopwatch.peek();
  time = Time(time.total + elapsed, elapsed);
  auto deltaMilliseconds = time.delta.total!"msecs";
  assert(deltaMilliseconds >= 24);
  assert(deltaMilliseconds == time.deltaMilliseconds);
  assert(time.deltaSeconds < 1);
  stopwatch.reset();

  Thread.sleep(2.seconds);
  elapsed = stopwatch.peek();
  time = Time(time.total + elapsed, elapsed);
  assert(time.total > 2.seconds && time.total < 3.seconds);
  deltaMilliseconds = time.delta.total!"msecs";
  assert(time.total > time.delta);
  assert(deltaMilliseconds >= 2000 && deltaMilliseconds < 2200);
  assert(deltaMilliseconds == time.deltaMilliseconds);
  assert(time.totalMilliseconds >= 2024 && time.totalSeconds < 3);

  import std.typecons : Yes;
  time = Time(time, Yes.runningSlowly);
  assert(time.runningSlowly);
}
