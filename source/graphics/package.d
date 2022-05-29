/// Authors: Chance Snow
/// Copyright: Copyright © 2022 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.graphics;

import teraflop.math;
import wgpu.api;

public import teraflop.graphics.color;

/// A world-space model view projection matrix. Suitable for use as a uniform buffer object.
/// See_Also: <a href="https://dlang.org/spec/attribute.html#align" title="D Language reference">`align` Attribute</a>
struct ModelViewProjection {
  /// The world-space model view projection matrix.
  mat4f mvp;
}

/// A 3D camera encapsulating model, view, and projection matrices that may be bound to a graphics shader.
///
/// A World's primary camera is the `Camera` world Resource.
/// Ancillary cameras may be added to render target Entities.
class Camera {
  /// World-space model transformation matrix.
  mat4f model = mat4f.identity;
  /// View matrix.
  mat4f view = mat4f.identity;
  /// Projection matrix, e.g. orthographic or perspective.
  mat4f projection = mat4f.identity;

  /// Whether the Y axis of the `projection` matrix shall be inverted.
  bool invertY = true;

  /// A combined model-view-projection matrix.
  ///
  /// The result is corrected for the WebGPU coordinate system.
  /// WebGPU clip space has inverted Y and half Z.
  /// See_Also: `wgpuClipCorrection`
  mat4f mvp() @property const {
    import std.typecons : No, Yes;
    const clip = wgpuClipCorrection(invertY ? Yes.invertY : No.invertY);
    return (clip * projection * view * model).transposed;
  }

  ///
  ray3f mouseRay(float fovInRadians, vec3f cameraTarget, Size framebufferSize, vec2d mousePosition) const {
    // https://github.com/raysan5/raylib/blob/96db787657313c671ff618c23ffc91638cbc72b0/src/core.c#L1997

    // Calculate normalized device coordinates
    // NOTE: y value is negative
    const float x = (2.0f * mousePosition.x) / framebufferSize.width - 1.0f;
    const float y = 1.0f - (2.0f * mousePosition.y) / framebufferSize.height;
    const float z = 1.0f;

    // Store values in a vector
    auto deviceCoords = vec3f(x, y, z);

    // Calculate view matrix from camera look at
    auto view = mat4f.lookAt(view.translationOf, cameraTarget, up);
    auto proj = mat4f.identity;

    // if (camera.type == CAMERA_PERSPECTIVE) {
      // Calculate projection matrix from perspective
      proj = mat4f.perspective(fovInRadians, (framebufferSize.width / framebufferSize.height), 0.01f, 1000.0f);
    // }
    // TODO: Support orthographic cameras?
    // else if (camera.type == CAMERA_ORTHOGRAPHIC) {
    //     float aspect = (float)CORE.Window.screen.width/(float)CORE.Window.screen.height;
    //     double top = camera.fovy/2.0;
    //     double right = top*aspect;

    //     // Calculate projection matrix from orthographic
    //     proj = MatrixOrtho(-right, right, -top, top, 0.01, 1000.0);
    // }

    // Unproject far/near points
    const nearPoint = vec3f(deviceCoords.x, deviceCoords.y, 0.0f).unproject(view * proj);
    const farPoint = vec3f(deviceCoords.x, deviceCoords.y, 1.0f).unproject(view * proj);

    // Unproject the mouse cursor in the near plane.
    // We need this as the source position because orthographic projects, compared to perspect doesn't have a
    // convergence point, meaning that the "eye" of the camera is more like a plane than a point.
    // auto cameraPlanePointerPos = vec3f(deviceCoords.x, deviceCoords.y, -1.0f).unproject(view * proj);

    // Calculate normalized direction vector
    auto direction = (farPoint - nearPoint).normalized;

    // if (camera.type == CAMERA_PERSPECTIVE) ray.orig = view.translationOf;
    // else if (camera.type == CAMERA_ORTHOGRAPHIC) ray.orig = cameraPlanePointerPos;

    return ray3f(view.translationOf, direction);
  }
}
