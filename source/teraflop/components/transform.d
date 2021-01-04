/// Built-in graphics transformation Components.
///
/// See_Also: `teraflop.ecs.Component`
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: MIT License
module teraflop.components.transform;

import teraflop.ecs : Entity;
import teraflop.graphics : UniformBuffer;
import teraflop.math;

/// A 3D transformation matrix uniform buffer object.
///
/// See_Also: `teraflop.graphics.UniformBuffer`
class Transform : UniformBuffer!mat4f {
  alias value this;

  ///
  this(uint bindingLocation = 0) {
    super(bindingLocation);
  }

  ///
  vec3f translation() @property const {
    return vec3f(value.c[0][3], value.c[1][3], value.c[2][3]);
  }
  /// ditto
  void translation(vec3f value) @property {
    this.value.c[0][3] = value.x;
    this.value.c[1][3] = value.y;
    this.value.c[2][3] = value.z;
  }
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
    this.value.c[0][0] = value.x;
    this.value.c[1][1] = value.y;
    this.value.c[2][2] = value.z;
  }
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
