/// Authors: Chance Snow
/// Copyright: Copyright © 2022 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.graphics.color;

import std.conv : to;
static import teraflop.math;
import wgpuApi = wgpu.api;

///
struct Color {
  /// Red channel component.
  ubyte r;
  /// Green channel component.
  ubyte g;
  /// Blue channel component.
  ubyte b;
  /// Alpha channel component.
  ubyte a;

  ///
  this(uint hex) {
    import std.conv : to;

    auto r = ((hex >> 24) & 0xFF).to!ubyte;
    auto g = ((hex >> 16) & 0xFF).to!ubyte;
    auto b = ((hex >> 8) & 0xFF).to!ubyte;
    auto a = (hex & 0xFF).to!ubyte;
    this(r, g, b, a);
  }
  ///
  this(ubyte r, ubyte g, ubyte b, ubyte a = ubyte.max) {
    this.r = r;
    this.g = g;
    this.b = b;
    this.a = a;
  }

  /// Opaque red.
  static const red = Color(255, 0, 0);
  /// Opaque green.
  static const green = Color(0, 255, 0);
  /// Opaque blue.
  static const blue = Color(0, 0, 255);
  /// Opaque black.
  static const black = Color(0, 0, 0);
  /// Opaque white.
  static const white = Color(255, 255, 255);
  /// Fully transparent black.
  static const transparent = Color(0, 0, 0, 0);
  /// Opaque cornflower blue.
  static const cornflowerBlue = Color(0x64, 0x95, 0xED);

  ///
  teraflop.math.vec3f vec3f() @property const {
    return teraflop.math.vec3f(
      r / ubyte.max.to!float,
      g / ubyte.max.to!float,
      b / ubyte.max.to!float,
    );
  }
  ///
  teraflop.math.vec3d vec3d() @property const {
    return teraflop.math.vec3d(
      r / ubyte.max.to!double,
      g / ubyte.max.to!double,
      b / ubyte.max.to!double,
    );
  }
  ///
  teraflop.math.vec4f vec4f() @property const {
    return teraflop.math.vec4f(
      r / ubyte.max.to!float,
      g / ubyte.max.to!float,
      b / ubyte.max.to!float,
      a / ubyte.max.to!float
    );
  }
  ///
  teraflop.math.vec4d vec4d() @property const {
    return teraflop.math.vec4d(
      r / ubyte.max.to!double,
      g / ubyte.max.to!double,
      b / ubyte.max.to!double,
      a / ubyte.max.to!double
    );
  }

  package (teraflop) wgpuApi.Color wgpu() const @property {
    auto color = this.vec4f;
    return wgpuApi.Color(color.r, color.g, color.b, color.a);
  }

  /// Adjust a `Color`s alpha channel, setting it to the given percentage.
  /// Returns: A newly adjusted `Color`.
  /// Throws: A `RangeError` if the given `alpha` component is outside the range `0.0` through `1.0`.
  Color withAlpha(float alpha) const {
    import core.exception : RangeError;
    import std.exception : enforce;

    const outOfBounds = alpha < 0.0 || alpha > 1.0;
    assert(!outOfBounds);
    enforce!RangeError(!outOfBounds);
    return Color(r, g, b, (alpha * 255).to!ubyte);
  }

  uint hex() const @nogc @trusted @property pure nothrow {
    return ((r & 0xFF) << 24) + ((g & 0xFF) << 16) + ((b & 0xFF) << 8) + (a & 0xFF);
  }

  ///
  size_t toHash() const @nogc @safe pure nothrow {
    return this.hex;
  }
  ///
  bool opEquals(R)(const R other) const {
    return this.toHash == other.toHash;
  }

  string toString() const @safe {
    import std.conv : text;
    return "Color(" ~ text(r) ~ ", " ~ text(g) ~ ", " ~ text(b) ~ ", " ~ text(a) ~ ")";
  }
}

unittest {
  import std.algorithm : equal;
  import std.conv : text;
  import std.math : isClose;
  import teraflop.math : vec4f;

  // Cornflower Blue #6495ed
  const cornflowerBlue = Color(0x64, 0x95, 0xED);
  const expected = wgpuApi.Color(0.392, 0.584, 0.929, 1);

  assert(cornflowerBlue.wgpu.r.isClose(expected.r, 0.00075), text(cornflowerBlue.wgpu.r));
  assert(cornflowerBlue.wgpu.g.isClose(expected.g, 0.00075), text(cornflowerBlue.wgpu.g));
  assert(cornflowerBlue.wgpu.b.isClose(expected.b, 0.00075), text(cornflowerBlue.wgpu.b));
  assert(cornflowerBlue.wgpu.a.isClose(expected.a, 0.00075), text(cornflowerBlue.wgpu.a));

  assert(cornflowerBlue.toHash == 0x6495EDFF);
  assert(cornflowerBlue == Color(0x6495EDFF));

  assert(Color.green.withAlpha(0.5).vec4f.w.isClose(0.5, 0.004), text(Color.green.withAlpha(0.5).vec4f.w));

  assert(cornflowerBlue.toString.equal("Color(100, 149, 237, 255)"));
}
