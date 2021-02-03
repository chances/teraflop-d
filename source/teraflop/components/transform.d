/// Built-in graphics transformation Components.
///
/// See_Also: `teraflop.ecs.Component`
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.components.transform;

import teraflop.ecs : Entity;
import teraflop.graphics : UniformBuffer;
import teraflop.math;

/// A 3D transformation matrix uniform buffer object.
///
/// See_Also: `teraflop.graphics.UniformBuffer`
class Transform : UniformBuffer!mat4f {
  import teraflop.graphics : ShaderStage;

  alias value this;

  ///
  this(ShaderStage shaderStage = ShaderStage.vertex) {
    super(0 /* bindingLocation */, shaderStage, mat4f.identity);
  }
  ///
  this(mat4f value = mat4f.identity, ShaderStage shaderStage = ShaderStage.vertex) {
    super(0 /* bindingLocation */, shaderStage, value);
  }

  /// The 3D transformation matrix.
  ///
  /// The result is corrected for the Vulkan coordinate system.
  override mat4f value() @property const {
    return super.value.transposed;
  }

  ///
  vec3f translation() @property const {
    const value = this.value;
    return vec3f(value.c[3][0], value.c[3][1], value.c[3][2]);
  }
  /// ditto
  void translation(vec3f value) @property {
    auto matrix = this.value;
    matrix.c[3][0] = value.x;
    matrix.c[3][1] = value.y;
    matrix.c[3][2] = value.z;
    super.value = matrix.transposed;
  }
  // TODO: Add rotation properties
  // TODO: Fix this cast to a Quaternion (https://gfm.dpldocs.info/source/gfm.math.matrix.d.html#L370)
  // ///
  // quatf rotation() @property const {
  //   return cast(Quaternion!float) value;
  // }
  ///
  vec3f scale() @property const {
    return vec3f(value.c[0][0], value.c[1][1], value.c[2][2]);
  }
  /// ditto
  void scale(vec3f value) @property {
    auto matrix = this.value;
    matrix.c[0][0] = value.x;
    matrix.c[1][1] = value.y;
    matrix.c[2][2] = value.z;
    super.value = matrix;
  }
}

/// Construct a `Transform` Component given a transformation matrix.
Transform transform(mat4f matrix) {
  return new Transform(matrix);
}

unittest {
  const translation = vec3f(0, 1, 0);
  auto xform = transform(mat4f.translation(translation));
  assert(xform.translation == translation);
  assert(xform.scale == vec3f(1));

  xform = transform(mat4f.identity);

  // xform = transform(mat4f.rotation(45.radians, up));
  // auto r = xform.rotation;
  // assert(xform.translation == vec3f(0));
}

///
struct Parent {
  ///
  Entity entity;
}

///
struct Children {
  ///
  Entity[] entities;
}
