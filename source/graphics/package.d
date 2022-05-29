/// Authors: Chance Snow
/// Copyright: Copyright © 2022 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.graphics;

import teraflop.math;
import teraflop.traits : isStruct;
public import teraflop.graphics.color;
public import teraflop.graphics.primitives;
public import wgpu.api : ShaderStage;

/// A shaded material for geometry encapsulating its `Shader`s, graphics pipeline state, and optionally a `Texture`.
/// See_Also: `teraflop.systems.rendering.PipelinePreparer`
struct Material {
  import std.typecons : Flag, No, Yes;
  import wgpu.api : CullMode, FrontFace;

  private bool _depthTest = true;
  private FrontFace _frontFace = FrontFace.cw;
  private CullMode _cullMode = CullMode.back;

  package (teraflop) Shader*[] _shaders;
  // TODO: package (teraflop) Texture _texture;

  /// Initialize a new Material.
  this(Shader*[] shaders, Flag!"depthTest" depthTest = Yes.depthTest) {
    this(shaders, FrontFace.cw, CullMode.back, depthTest);
  }
  /// Initialize a new Material.
  this(
    Shader*[] shaders,
    FrontFace frontFace = FrontFace.cw, CullMode cullMode = CullMode.back,
    Flag!"depthTest" depthTest = Yes.depthTest
  ) {
    _shaders = shaders;
    _frontFace = frontFace;
    _cullMode = cullMode;
    _depthTest = depthTest;
  }

  /// Whether to perform the depth test. If `true`, assumes the render target has a depth buffer attachment.
  bool depthTest() @property const {
    return _depthTest;
  }
  /// Specifies the vertex order for faces to be considered front-facing.
  FrontFace frontFace() @property const {
    return _frontFace;
  }
  /// Type of <a href="https://en.wikipedia.org/wiki/Back-face_culling">face culling</a> to use during graphic pipeline rasterization.
  CullMode cullMode() @property const {
    return _cullMode;
  }
}

///
struct Mesh(T) if (isStruct!T) {
  ///
  T[] vertices;
  ///
  size_t[] indices;
}

///
enum SourceLanguage {
  /// SPIR-V source bytecode.
  spirv,
  /// WGSL source text.
  wgsl
}

///
struct Shader {
  import std.conv : to;
  import std.exception : enforce;
  import std.typecons : Flag, No, Yes;
  import teraflop.ecs.components : ObservableFile;
  import wgpu.api : Device, ShaderModule;
  import wgpu.utils : valid;

  private ObservableFile* _source;
  private SourceLanguage _language;
  private Device device;
  private ShaderModule _shaderModule;

  /// The stage in the graphics pipeline in which this Shader performs.
  const ShaderStage stage;

  /// Initialize a new Shader compiled from the given `filePath`.
  ///
  /// Params:
  /// stage = The stage in the graphics pipeline in which this Shader performs.
  /// filePath = Path to a file containing SPIR-V source bytecode.
  /// language = Shading language of the given file's sources.
  /// hotReload = Whether to watch the given `filePath` for changes and to recompile this Shader at runtime.
  this(
    ShaderStage stage, string filePath,
    SourceLanguage language = SourceLanguage.wgsl,
    Flag!"hotReload" hotReload = No.hotReload
  ) {
    import std.string : format;

    this.stage = stage;
    _source = new ObservableFile(filePath, hotReload);
    _language = language;
    enforce(_source.exists, format!"File not found: %s"(filePath));
    setupChangeDetection();
  }
  /// Initialize a new Shader.
  ///
  /// Params:
  /// stage = The stage in the graphics pipeline in which this Shader performs.
  /// wgsl = WGSL source text.
  this(ShaderStage stage, string wgsl) {
    this.stage = stage;
    _source = new ObservableFile(wgsl);
    _language = SourceLanguage.wgsl;
    setupChangeDetection();
  }
  /// Initialize a new Shader.
  ///
  /// Params:
  /// stage = The stage in the graphics pipeline in which this Shader performs.
  /// spv = SPIR-V source bytecode.
  this(ShaderStage stage, const ubyte[] spv) {
    this.stage = stage;
    _source = new ObservableFile(spv);
    _language = SourceLanguage.spirv;
    setupChangeDetection();
  }
  ~this() {
    if (_shaderModule.valid) _shaderModule.destroy();
  }

  /// Whether this Shader has been successfully initialized.
  bool initialized() @property const {
    return _shaderModule.valid;
  }

  /// Initialize this Shader.
  void initialize(scope Device device) {
    assert(!initialized);
    this.device = device;
    this._shaderModule = _language == SourceLanguage.spirv
      ? device.createShaderModule(_source.contents.to!(const byte[]))
      : device.createShaderModule(_source.contents.to!string);
  }

  private void setupChangeDetection() {
    _source.onChanged ~= (const(ubyte)[] _) {
      if (_shaderModule.valid) {
        // TODO: Log "Reloading shader: filePath"
        device.poll(Yes.forceWait);
        _shaderModule.destroy();
      }
    };
  }
}

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
