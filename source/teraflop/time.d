/// Time primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.time;

import core.time : Duration;

/// Tracks time-based statistics about the running game.
struct Time {
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

// TODO: Consider switching to libasync.timer (https://libasync.dpldocs.info/libasync.timer.AsyncTimer.html)
/// A Timer that, when running, repeatedly ticks at a specific interval.
final class Timer {
  import teraflop.async.event : Event;
  /// Occurs when an `interval` amount of time has passed since the last tick event.
  Event!Timer onTick;

  /// How often the timer should tick.
  private auto interval = Duration.zero;
  import core.time : MonoTime;
  private auto startedAt = MonoTime.zero;
  private bool justTicked_ = false;
  // Timer worker thread state
  import std.concurrency : Tid;
  private Tid worker;

  import core.time : seconds;
  import std.datetime.stopwatch : AutoStart;
  /// Instantiate a Timer that repeatedly ticks at every given interval.
  this(Duration interval = 1.seconds, AutoStart autostart = AutoStart.no) {
    this.interval = interval;
    if (autostart) start();
  }

  ~this() {
    if (running) stop();
  }

  /// Start this timer.
  void start() {
    import std.concurrency : send, spawn;

    startedAt = MonoTime.currTime;
    // Spawn a timer worker thread
    worker = spawn(&timerWorker, interval);
    shared TickCallback cb = (Duration delta) {
      justTicked_ = delta >= interval;
      if (justTicked_) onTick(this);
    };
    send(worker, TickCallbackMessage(cb));
  }
  /// Stop this timer.
  void stop() {
    if (startedAt == MonoTime.zero) return;

    // Stop the worker thread and wait for acknowledgement
    import std.concurrency : send;
    send(worker, StopMessage());

    startedAt = MonoTime.zero;
  }

  /// Whether or not this timer is ticking.
  bool running() const @property {
    return startedAt != MonoTime.zero;
  }
  /// Whether this timer just ticked.
  bool justTicked() const @property {
    return justTicked_;
  }

  /// Duration that this timer has been `running`.
  Duration duration() const @property {
    return startedAt != MonoTime.zero
      ? MonoTime.currTime - startedAt
      : Duration.zero;
  }
  /// Duration that this timer has been `running`, in seconds.
  long durationSeconds() const @property {
    return duration.total!"seconds";
  }

  /// Update this timer, resetting `justTicked` to `false` if neccesary since the last update.
  void update() {
    if (justTicked_) justTicked_ = false;
  }
}

private {
  alias TickCallback = void delegate(Duration);
  struct TickCallbackMessage {
    shared TickCallback onTick;
  }
  struct StopMessage {}

  import std.concurrency : Tid;
  import core.time : msecs;
  void timerWorker(Duration tickFrequency = 10.msecs) {
    TickCallback onTick = null;
    import std.datetime.stopwatch : AutoStart, StopWatch;
    auto stopwatch = StopWatch(AutoStart.yes);

    bool stopped = false;
    while (!stopped) {
      import core.time : nsecs;
      auto timeout = (tickFrequency.total!"nsecs" / 4).nsecs;
      import std.concurrency : receiveTimeout, OwnerTerminated;
      try {
        receiveTimeout(timeout, (TickCallbackMessage message) {
          onTick = message.onTick;
        }, (StopMessage _) => stopped = true);
      } catch (OwnerTerminated) stopped = true;

      auto elapsed = stopwatch.peek;
      if (elapsed >= tickFrequency) {
        if (onTick !is null) onTick(elapsed);
        stopwatch.reset();
      }
    }

    stopwatch.stop();
  }
}

unittest {
  import std.datetime.stopwatch : AutoStart, StopWatch;
  import core.time : msecs;
  auto timer = new Timer(20.msecs, AutoStart.yes);
  assert(timer.running);

  import core.thread : Thread;
  Thread.sleep(14.msecs);
  timer.update();
  assert(timer.duration >= 14.msecs);
  assert(timer.durationSeconds < 1);

  Thread.sleep(10.msecs);
  assert(timer.justTicked);
  timer.update();
  assert(!timer.justTicked);
  assert(timer.duration >= 24.msecs && timer.duration < 30.msecs);
  assert(timer.durationSeconds < 1);

  Thread.sleep(20.msecs);
  assert(timer.justTicked);
  timer.update();
  assert(!timer.justTicked);
  assert(timer.duration >= 44.msecs && timer.duration < 50.msecs);
  assert(timer.durationSeconds < 1);

  timer.stop();
  assert(!timer.running);
  assert(timer.duration == Duration.zero);

  Thread.sleep(20.msecs);
  timer.start();
  assert(timer.running);
  assert(timer.duration < 5.msecs);
  assert(timer.durationSeconds < 1);

  destroy(timer);
}
