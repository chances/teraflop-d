/// Mathematics primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.math;

public import gfm.math;

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
