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
import teraflop.graphics : Color;

private const float ONE_DEGREE_IN_RADIANS = 0.01745329252;

/// Convert and angle from radians to degrees.
float degrees(float radians) @property {
  return radians / ONE_DEGREE_IN_RADIANS;
}

unittest {
  import std.math : PI;
  const piDegrees = 179.9999999994152f;
  assert(PI.degrees == piDegrees);
}

/// Convert and angle from degrees to radians.
float radians(float degrees) @property {
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

/// Extract the translation transformation from the given `matrix`.
vec3f translationOf(mat4f matrix) @property {
  return vec3f(matrix.c[0][3], matrix.c[1][3], matrix.c[2][3]);
}

/// Result of a failed extraction while executing `rotationOf`.
quatf failedExtraction() {
  import std.math : NaN;
  return quatf.fromEulerAngles(NaN(0), NaN(0), NaN(0));
}

/// Extract the rotation transformation from the given `matrix`.
quatf rotationOf(mat4f value) @property {
  import std.math : sqrt;

  // TODO: Fix this cast to a Quaternion (https://gfm.dpldocs.info/source/gfm.math.matrix.d.html#L370)
  // https://gfm.dpldocs.info/source/gfm.math.matrix.d.html#L301
  // return cast(quatf) value;

  // https://math.stackexchange.com/a/895033/744305
  const r = value.c;
  float wSquared = 0.25 * (1.0 + r[1][1] + r[2][2] + r[3][3]);
  if (wSquared >= 0.25) {
    const float w = sqrt(wSquared);

    const float overW_4 = 0.25 / w;
    const float x = (r[3][2] - r[2][3]) * overW_4;
    const float y = (r[1][3] - r[3][1]) * overW_4;
    const float z = (r[2][1] - r[1][2]) * overW_4;

    return quatf(w, x, y, z);
  } else return failedExtraction;

  // http://www.euclideanspace.com/maths/geometry/rotations/conversions/matrixToQuaternion/
  // auto w = sqrt(1.0 + value.c[0][0] + value.c[1][1] + value.c[2][2]) / 2.0;
	// auto w4 = 4.0 * w;
	// auto x = (value.c[1][2] - value.c[2][1]) / w4;
	// auto y = (value.c[2][0] - value.c[0][2]) / w4;
	// auto z = (value.c[0][1] - value.c[1][0]) / w4;
  // return quatf(w, x, y, z);
}

/// Extract the scale transformation from the given `matrix`.
vec3f scaleOf(mat4f value) @property {
  return vec3f(value.c[0][0], value.c[1][1], value.c[2][2]);
}

unittest {
  auto xform = mat4f.identity;
  assert(xform.translationOf == vec3f(0));
  assert(xform.rotationOf == quatf.fromEulerAngles(0, 0, 0));
  assert(xform.scaleOf == vec3f(1));

  const translation = vec3f(0, 1, 0);
  xform = mat4f.translation(translation);
  assert(xform.translationOf == translation);
  assert(xform.rotationOf == quatf(1, 0, 0.25f, 0));
  assert(xform.scaleOf == vec3f(1));

  // xform = cast(mat4f) quatf.fromEulerAngles(0, 45.radians, 0);
  // assert(xform.translationOf == vec3f(0));
  // auto r = xform.rotationOf;
  // auto r2 = xform.rotationOf.toEulerAngles;
  // assert(xform.rotationOf == quatf.fromEulerAngles(0, 45.radians, 0));
  // assert(xform.scaleOf == vec3f(1));

  xform = mat4f.scaling(translation);
  assert(xform.translationOf == vec3f(0));
  assert(xform.rotationOf == quatf(0.866025388f, 0, 0, 0));
  assert(xform.scaleOf == translation);
}

///
vec3f scale(vec3f a, float scale) {
  return vec3f(a.x * scale, a.y * scale, a.z * scale);
}

///
vec3f abs(vec3f a) @property {
  import std.math : abs;
  return vec3f(abs(a.x), abs(a.y), abs(a.z));
}

/// Projects a Vector from screen space into object space.
vec3f unproject(vec3f source, mat4f viewProj) {
  return (viewProj.inverse * vec4f(source, 0)).xyz;
}

///
alias ray2f = Ray!(float, 2);
///
alias ray3f = Ray!(float, 3);

/// Size of an object.
struct Size {
  /// Width of the object.
  uint width;
  /// Height of the object.
  uint height;
}
