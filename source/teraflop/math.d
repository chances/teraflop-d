/// Mathematics primitives.
///
/// See_Also: The <a href="https://code.dlang.org/packages/gfm">gfm</a> library and its <a href="https://gfm.dpldocs.info/gfm.math.html">API documentation</a>.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.math;

public import gfm.math;
import std.typecons : Flag, Yes;

private const float ONE_DEGREE_IN_RADIANS = 0.01745329252;

/// Convert and angle from radians to degrees.
float degrees(float radians) {
  return radians / ONE_DEGREE_IN_RADIANS;
}

unittest {
  import std.math : PI;
  const piDegrees = 179.9999999994152f;
  assert(PI.degrees == piDegrees);
}

/// Convert and angle from degrees to radians.
float radians(float degrees) {
  return ONE_DEGREE_IN_RADIANS * degrees;
}

unittest {
  import std.math : PI;
  const piDegrees = 179.9999999994152f;
  assert(piDegrees.radians == 3.14159274f);
}

/// Up unit vector, i.e. Y-up.
enum vec3f up = vec3f(0, 1, 0);
/// Down unit vector, i.e. inverse of Y-up.
enum vec3f down = vec3f(0, -1, 0);
/// Forward unit vector, i.e. Z-forward.
enum vec3f forward = vec3f(0, 0, 1);
/// Backward unit vector, i.e. inverse of Z-forward.
enum vec3f back = vec3f(0, 0, -1);

/// Transformation matrix to correct for the Vulkan coordinate system.
/// Vulkan clip space has inverted Y and half Z.
/// Params:
/// invertY = Whether the Y axis of the matrix is inverted.
mat4f vulkanClipCorrection(Flag!"invertY" invertY = Yes.invertY) @property pure {
  return mat4f(
    1f, 0f, 0f, 0f,
    0f, invertY ? -1f : 1.0f, 0f, 0f,
    0f, 0f, 0.5f, 0.5f,
    0f, 0f, 0f, 1f,
  );
}

/// Size of an object.
struct Size {
  /// Width of the object.
  uint width;
  /// Height of the object.
  uint height;
}
