/// Authors: Chance Snow
/// Copyright: Copyright © 2022 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.graphics;

import wgpu.bindings : WGPUColor;

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

  ///
  static const cornflowerBlue = Color(0x64, 0x95, 0xED);

  package (teraflop) WGPUColor wgpu() const @property {
    import std.conv : to;
    return WGPUColor(
      r / ubyte.max.to!double,
      g / ubyte.max.to!double,
      b / ubyte.max.to!double,
      a / ubyte.max.to!double
    );
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
  import std.conv : text, to;
  import std.math : isClose;

  // Cornflower Blue #6495ed
  const cornflowerBlue = Color(0x64, 0x95, 0xED);
  const expected = WGPUColor(0.392, 0.584, 0.929, 1);

  assert(cornflowerBlue.wgpu.r.isClose(expected.r, 0.00075), text(cornflowerBlue.wgpu.r));
  assert(cornflowerBlue.wgpu.g.isClose(expected.g, 0.00075), text(cornflowerBlue.wgpu.g));
  assert(cornflowerBlue.wgpu.b.isClose(expected.b, 0.00075), text(cornflowerBlue.wgpu.b));
  assert(cornflowerBlue.wgpu.a.isClose(expected.a, 0.00075), text(cornflowerBlue.wgpu.a));

  assert(cornflowerBlue.toHash == 0x6495EDFF);
  assert(cornflowerBlue == Color(0x6495EDFF));

  assert(cornflowerBlue.toString.equal("Color(100, 149, 237, 255)"));
}
