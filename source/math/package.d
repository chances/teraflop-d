/// Mathematics primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.math;

public import gfm.math;

private const float ONE_DEGREE_IN_RADIANS = 0.01745329252;

/// Convert and angle from radians to degrees
float degrees(float radians) {
  return radians / ONE_DEGREE_IN_RADIANS;
}

/// Convert and angle from degrees to radians
float radians(float degrees) {
  return ONE_DEGREE_IN_RADIANS * degrees;
}

/// Up unit vector, i.e. Y-up.
enum vec3f up = vec3f(0, 1, 0);
/// Down unit vector, i.e. inverse of Y-up.
enum vec3f down = vec3f(0, -1, 0);

/// Size of an object.
struct Size {
  /// Width of the object.
  uint width;
  /// Height of the object.
  uint height;
}
