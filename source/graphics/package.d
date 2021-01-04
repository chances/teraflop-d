/// Graphics pipeline primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.graphics;

import concepts : implements;
import gfx.core.rc;
import gfx.graal;
import std.traits : fullyQualifiedName;

import std.conv : to;
import std.exception : enforce;
import teraflop.components : IResource;
import teraflop.ecs : NamedComponent;
import teraflop.math;
import teraflop.traits : isStruct;

public {
  import gfx.graal : Primitive;

  static import gfx.graal.pipeline;
  alias Pipeline = gfx.graal.pipeline.Pipeline;
  import gfx.graal.pipeline : ShaderStage;
}

/// RGBA double precision color.
struct Color {
  /// Red component.
  double r;
  /// Blue component.
  double g;
  /// Green component.
  double b;
  /// Alpha component.
  double a;

  /// Solid opaque red.
  static const red = Color(1, 0, 0, 1);
  /// Solid opaque green.
  static const green = Color(0, 1, 0, 1);
  /// Solid opaque blue.
  static const blue = Color(0, 0, 1, 1);
  /// Solid opaque black.
  static const black = Color(0, 0, 0, 1);

  teraflop.math.vec3f vec3f() @property const {
    return teraflop.math.vec3f(r, g, b);
  }
  teraflop.math.vec3d vec3d() @property const {
    return teraflop.math.vec3d(r, g, b);
  }
  teraflop.math.vec4f vec4f() @property const {
    return teraflop.math.vec4f(r, g, b, a);
  }
  teraflop.math.vec4d vec4d() @property const {
    return teraflop.math.vec4d(r, g, b, a);
  }

  package (teraflop) auto toVulkan() const {
    return ClearColorValues(r.to!float, g.to!float, b.to!float, a.to!float);
  }
}

/// Detect whether `T` is vertex attribute data.
template isVertexData(T) if (isStruct!T) {
  // import std.algorithm.searching : all;
  // static immutable attributes = [__traits(allMembers, T)];
}

/// Vertex attribute data comprising a 3D position and opaque color.
struct VertexPosColor {
  /// 3D position.
  vec3f position;
  /// Opaque color.
  vec3f color;

  /// Describes how vertex attributes should be bound to the vertex shader.
  static VertexInputBinding bindingDescription() {
    VertexInputBinding bindingDescription = {
      binding: 0,
      stride: VertexPosColor.sizeof,
    };
    return bindingDescription;
  }

  /// Describes the format of each vertex attribute so that they can be applied to the vertex shader.
  static VertexInputAttrib[2] attributeDescriptions() {
    VertexInputAttrib[2] attributeDescriptions;
    // Position
    attributeDescriptions[0].binding = 0;
    attributeDescriptions[0].location = 0;
    attributeDescriptions[0].format = Format.rgb32_sFloat;
    attributeDescriptions[0].offset = position.offsetof;
    // Color
    attributeDescriptions[1].binding = 0;
    attributeDescriptions[1].location = 1;
    attributeDescriptions[1].format = Format.rgb32_sFloat;
    attributeDescriptions[1].offset = color.offsetof;
    return attributeDescriptions;
  }
}

/// Vertex attribute data comprising a 3D position, diffuse color, and texture coordinates.
struct VertexPosColorTex {
  /// 3D position.
  vec3f position;
  /// Diffuse color.
  vec3f color;
  /// Texture UV coordinates.
  vec2f uv;

  /// Describes how vertex attributes should be bound to the vertex shader.
  static VertexInputBinding bindingDescription() {
    VertexInputBinding bindingDescription = {
      binding: 0,
      stride: VertexPosColorTex.sizeof,
    };
    return bindingDescription;
  }

  /// Describes the format of each vertex attribute so that they can be applied to the vertex shader.
  static VertexInputAttrib[3] attributeDescriptions() {
    VertexInputAttrib[3] attributeDescriptions;
    // Position
    attributeDescriptions[0].binding = 0;
    attributeDescriptions[0].location = 0;
    attributeDescriptions[0].format = Format.rgb32_sFloat;
    attributeDescriptions[0].offset = position.offsetof;
    // Color
    attributeDescriptions[1].binding = 0;
    attributeDescriptions[1].location = 1;
    attributeDescriptions[1].format = Format.rgb32_sFloat;
    attributeDescriptions[1].offset = color.offsetof;
    // Texture UV Coordinates
    attributeDescriptions[2].binding = 0;
    attributeDescriptions[2].location = 2;
    attributeDescriptions[2].format = Format.rg32_sFloat;
    attributeDescriptions[2].offset = uv.offsetof;
    return attributeDescriptions;
  }
}

package (teraflop) abstract class MeshBase : NamedComponent, IResource {
  private Buffer _vertexBuffer;
  private Buffer _indexBuffer;
  private uint[] indices_;
  private auto dirty_ = true;

  ///
  Primitive topology = Primitive.triangleStrip;

  this(string name, Primitive topology = Primitive.triangleStrip) {
    super(name);
    this.topology = topology;
  }
  ~this() {
    _vertexBuffer.dispose();
    destroy(_vertexBuffer);
    _indexBuffer.dispose();
    destroy(_indexBuffer);
  }

  /// Whether this mesh's vertex data is new or changed and needs to be uploaded to the GPU.
  bool dirty() @property const {
    return dirty_;
  }
  package (teraflop) void dirty(bool value) @property {
    dirty_ = value;
  }

  package (teraflop) Buffer vertexBuffer() @property const {
    return cast(Buffer) _vertexBuffer;
  }
  package (teraflop) Buffer indexBuffer() @property const {
    return cast(Buffer) _indexBuffer;
  }

  abstract ulong vertexCount() @property const;
  abstract size_t size() @property const;
  abstract const(ubyte[]) data() @property const;

  /// This mesh's vertex index data.
  const(uint[]) indices() @property const {
    return indices_;
  }
  protected void indices(uint[] value) @property {
    indices_ = value;
  }

  /// Describes how this mesh's vertex attributes should be bound to the vertex shader.
  abstract VertexInputBinding bindingDescription() @property const;
  /// Describes the format of this mesh's vertex attributes so that they can be applied to the vertex shader.
  abstract VertexInputAttrib[] attributeDescriptions() @property const;

  /// Whether this Mesh has been successfully initialized.
  bool initialized() @property const {
    return vertexBuffer !is null && indexBuffer !is null;
  }

  /// Initialize this Mesh.
  void initialize(scope Device device) {
    import std.algorithm.mutation : copy;
    import teraflop.platform.vulkan : createDynamicBuffer;

    _vertexBuffer = device.createDynamicBuffer(size, BufferUsage.vertex);
    auto vertexBuf = vertexBuffer.boundMemory.map.view!(ubyte[])[];
    assert(data.copy(vertexBuf).length == vertexBuf.length - size);

    _indexBuffer = device.createDynamicBuffer(uint.sizeof * indices.length, BufferUsage.index);
    auto sz = uint.sizeof * indices.length;
    auto indexBuf = indexBuffer.boundMemory.map.view!(uint[])[];
    auto unfilled = indices.copy(indexBuf);
    assert(unfilled.length == indexBuf.length - indices.length);
  }
}

/// A renderable mesh encapsulating vertex data.
class Mesh(T) : MeshBase if (isStruct!T) {
  // TODO: Make type contraint more robust, e.g. NO pointers/reference types in vertex data
  private T[] vertices_;

  /// Initialize a new mesh.
  /// Params:
  /// vertices = Mesh vertex data to optionally pre-populate.
  /// indices = Mesh vertex indices to optionally pre-populate.
  this(T[] vertices = [], uint[] indices = []) {
    this(fullyQualifiedName!(Mesh!T), vertices, indices);
  }
  /// Initialize a new mesh.
  /// Params:
  /// topology =
  /// vertices = Mesh vertex data to optionally pre-populate.
  /// indices = Mesh vertex indices to optionally pre-populate.
  this(Primitive topology = Primitive.triangleStrip, T[] vertices = [], uint[] indices = []) {
    this(fullyQualifiedName!(Mesh!T), topology, vertices, indices);
  }
  /// Initialize a new named mesh.
  /// Params:
  /// name = The name of this mesh.
  /// vertices = Mesh vertex data to optionally pre-populate.
  /// indices = Mesh vertex indices to optionally pre-populate.
  this(string name, T[] vertices = [], uint[] indices = []) {
    this(name, Primitive.triangleStrip, vertices, indices);
  }
  /// Initialize a new named mesh.
  /// Params:
  /// name = The name of this mesh.
  /// topology =
  /// vertices = Mesh vertex data to optionally pre-populate.
  /// indices = Mesh vertex indices to optionally pre-populate.
  this(string name, Primitive topology = Primitive.triangleStrip, T[] vertices = [], uint[] indices = []) {
    super(name);
    this.topology = topology;
    this.vertices_ = vertices;
    this.indices = indices;
  }

  /// This mesh's vertex data.
  const(T[]) vertices() @property const {
    return vertices_;
  }
  override ulong vertexCount() @property const {
    return vertices_.length;
  }

  /// Size of this mesh, in bytes.
  override size_t size() @property const {
    return T.sizeof * vertices_.length;
  }

  override const(ubyte[]) data() @property const {
    // https://dlang.org/spec/arrays.html#void_arrays
    const(void[]) vertexData = vertices_;
    assert(vertexData.length == size);
    return cast(ubyte[]) vertexData;
  }

  /// Describes how this mesh's vertex attributes should be bound to the vertex shader.
  override VertexInputBinding bindingDescription() @property const {
    return __traits(getMember, T, "bindingDescription");
  }
  /// Describes the format of this mesh's vertex attributes so that they can be applied to the vertex shader.
  override VertexInputAttrib[] attributeDescriptions() @property const {
    return __traits(getMember, T, "attributeDescriptions").dup;
  }

  /// Update this mesh's vertex data.
  void update(T[] vertices) {
    this.vertices_ = vertices;
    this.dirty = true;
  }
}

/// A world-space model view projection matrix. Suitable for use as a uniform buffer object.
/// See_Also: <a href="https://dlang.org/spec/attribute.html#align" title="D Language reference">`align` Attribute</a>
struct ModelViewProjection {
  /// The world-space model view projection matrix.
  mat4f mvp;
}

/// A GPU descriptor binding, e.g. uniform buffer or texture sampler.
/// See_Also: `teraflop.graphics.UniformBuffer`
abstract class BindingDescriptor {
  protected uint bindingLocation_;
  protected ShaderStage shaderStage_;
  protected DescriptorType bindingType_;
  private auto dirty_ = true;

  /// Whether this uniform's data is new or changed and needs to be uploaded to the GPU.
  bool dirty() @property const {
    return dirty_;
  }
  package (teraflop) void dirty(bool value) @property {
    dirty_ = value;
  }

  /// Descriptor binding location, e.g. `layout(binding = 0)` in GLSL.
  uint bindingLocation() @property const {
    return bindingLocation_;
  }

  /// Which shader stages this descriptor is going to be referenced.
  ShaderStage shaderStage() @property const {
    return shaderStage_;
  }

  DescriptorType bindingType() @property const {
    return bindingType_;
  }

  package (teraflop) WriteDescriptorSet descriptorWrite(DescriptorSet set, Buffer uniformBuffer) const {
    WriteDescriptorSet descriptorSet = {
      dstSet: set,
      dstBinding: bindingLocation_,
      dstArrayElem: 0,
    };
    switch (bindingType_) {
      case DescriptorType.uniformBuffer:
        descriptorSet.write = DescriptorWrite.make(
          bindingType_, BufferDescriptor(uniformBuffer, 0, uniformBuffer.size)
        );
        break;
      case DescriptorType.sampler:
      case DescriptorType.sampledImage:
        assert(sampler !is null);
        descriptorSet.write = DescriptorWrite.make(
          bindingType_,
          ImageSamplerDescriptor(
            image !is null ? image.createView(image.info.type, ImageSubresourceRange(), Swizzle.identity) : null,
            ImageLayout.shaderReadOnlyOptimal,
            sampler,
          )
        );
        break;
      default: assert(0, "Descriptor type not supported");
    }
    return cast(WriteDescriptorSet) descriptorSet;
  }

  size_t size() @property const {
    return 0;
  }
  const(ubyte[]) data() @property const {
    return [];
  }
  package (teraflop) Sampler sampler() @property inout {
    return null;
  }
  package (teraflop) Image image() @property inout {
    return null;
  }
}

package (teraflop) struct BindingGroup {
  uint index;
  const BindingDescriptor[] bindings;
}

/// A uniform buffer object.
class UniformBuffer(T) : BindingDescriptor if (isStruct!T) {
  private T value_;

  /// Initialize a new uniform buffer.
  /// Params:
  /// bindingLocation = Uniform binding location, e.g. `layout(binding = 0)` in GLSL.
  /// shaderStage = Which shader stages the UBO is going to be referenced.
  /// value = Uniform data to optionally pre-populate.
  this(uint bindingLocation = 0, ShaderStage shaderStage = ShaderStage.allGraphics, T value = T.init) {
    this.bindingLocation_ = bindingLocation;
    this.shaderStage_ = shaderStage;
    this.bindingType_ = DescriptorType.uniformBuffer;
    this.value_ = value;
  }

  T value() @property const {
    return value_;
  }

  override size_t size() @property const {
    return T.sizeof;
  }
  override const(ubyte[]) data() @property const {
    // https://dlang.org/spec/arrays.html#void_arrays
    const(void[]) uniformData = [value_];
    assert(uniformData.length == size);
    return cast(ubyte[]) uniformData;
  }

  /// Update the uniform value.
  void update(T value) {
    this.value_ = value;
    this.dirty = true;
  }
}

/// A 3D camera encapsulating model, view, and projection matrices that may be bound to a vertex shader.
///
/// A World's primary camera is the `Camera` world Resource.
/// Ancillary cameras may be added to render target Entities.
class Camera : NamedComponent {
  package (teraflop) UniformBuffer!mat4f uniform;
  private mat4f model_ = mat4f.identity;
  private mat4f view_ = mat4f.identity;
  private mat4f projection_ = mat4f.identity;

  /// Whether the Y axis of the `projection` matrix shall be inverted.
  bool invertY = true;

  /// Initialize a new camera.
  /// Params:
  /// bindingLocation = Vertex shader uniform binding location, e.g. `layout(binding = 0)` in GLSL.
  this(uint bindingLocation = 0) {
    super(this.classinfo.name);
    uniform = new UniformBuffer!mat4f(bindingLocation, ShaderStage.vertex, mvp);
  }

  /// World-space model transformation matrix.
  mat4f model() @property const {
    return model_;
  }
  void model(mat4f value) @property {
    model_ = value;
    uniform.update(mvp);
  }
  /// View matrix.
  mat4f view() @property const {
    return view_;
  }
  void view(mat4f value) @property {
    view_ = value;
    uniform.update(mvp);
  }
  /// Projection matrix, e.g. orthographic or perspective.
  mat4f projection() @property const {
    return projection_;
  }
  void projection(mat4f value) @property {
    projection_ = value;
    uniform.update(mvp);
  }

  /// A combined model-view-projection matrix.
  mat4f mvp() @property const {
    // Vulkan clip space has inverted Y and half Z
    const clip = mat4f(1.0f, 0.0f, 0.0f, 0.0f,
                         0.0f, invertY ? -1.0f : 1.0f, 0.0f, 0.0f,
                         0.0f, 0.0f, 0.5f, 0.0f,
                         0.0f, 0.0f, 0.5f, 1.0f);
    return projection * view * model * clip;
  }
}

/// A 2D image stored in GPU memory.
class Texture : BindingDescriptor, IResource {
  import gfx.graal : Image, Sampler;

  /// Size of this Texture, in pixels.
  const Size size;

  private ubyte[] data_;
  private Buffer stagingBuffer;
  private Image image_;
  private Sampler sampler_;

  /// Initialize a new Texture.
  this(const Size size, uint bindingLocation, ShaderStage shaderStage = ShaderStage.fragment) {
    bindingLocation_ = bindingLocation;
    bindingType_ = DescriptorType.sampledImage;
    shaderStage_ = shaderStage;

    this.size = size;
  }
  /// Initialize a new Texture with initial data.
  this(const Size size, ubyte[] data, uint bindingLocation, ShaderStage shaderStage = ShaderStage.fragment) {
    bindingLocation_ = bindingLocation;
    bindingType_ = DescriptorType.sampledImage;
    shaderStage_ = shaderStage;

    this.size = size;
    this.data_ = data;
    dirty = true;
  }

  /// Whether this Shader has been successfully initialized.
  bool initialized() @property const {
    return stagingBuffer !is null &&
      (cast(Buffer) stagingBuffer).size == data_.length &&
      image_ !is null && sampler_ !is null;
  }

  /// Texture data.
  override const(ubyte[]) data() @property const {
    return data_;
  }

  package (teraflop) Buffer buffer() @property const {
    return cast(Buffer) stagingBuffer;
  }
  package (teraflop) Sampler sampler() @property inout {
    return cast(Sampler) sampler_;
  }
  package (teraflop) Image image() @property inout {
    return cast(Image) image_;
  }

  /// Initialize this Texture.
  void initialize(scope Device device) {
    import teraflop.platform.vulkan : createDynamicBuffer;

    stagingBuffer = device.createDynamicBuffer(size.width * size.height * 4, BufferUsage.transferSrc);
    image_ = device.createImage(ImageInfo.d2(size.width, size.height));
    sampler_ = device.createSampler(SamplerInfo.nearest.withWrapMode(WrapMode.border));

    copyToStage();
  }

  /// Update this texture's data.
  void update(ubyte[] data) {
    this.data_ = data;
    dirty = true;
    if (stagingBuffer !is null && data_.length == stagingBuffer.size)
      copyToStage();
  }

  private void copyToStage() {
    import std.algorithm.mutation : copy;

    assert(stagingBuffer !is null);
    auto buf = stagingBuffer.boundMemory.map.view!(ubyte[])[];
    const unfilled = data.copy(buf);
    assert(unfilled.length == 0);
  }
}

/// A SPIR-V program for one programmable stage in the graphics `Pipeline`.
class Shader : IResource {
  /// The stage in the graphics pipeline in which this Shader performs.
  const ShaderStage stage;

  private Device device;
  private ShaderModule _shaderModule;
  private ubyte[] spv;

  /// Initialize a new Shader.
  ///
  /// Params:
  /// stage = The stage in the graphics pipeline in which this Shader performs.
  /// filePath = Path to a file containing SPIR-V source bytecode.
  this(ShaderStage stage, string filePath) {
    import std.file : exists;
    import std.stdio : File;
    import std.string : format;

    enforce(exists(filePath), format!"File not found: %s"(filePath));

    auto file = File(filePath, "rb");
    auto spvBuffer = file.rawRead(new ubyte[file.size()]);
    file.close();

    this(stage, spvBuffer);
  }
  /// Initialize a new Shader.
  ///
  /// Params:
  /// stage = The stage in the graphics pipeline in which this Shader performs.
  /// spv = SPIR-V source bytecode.
  this(ShaderStage stage, ubyte[] spv) {
    this.stage = stage;
    this.spv = spv;
  }

  ~this() {
    _shaderModule.dispose();
    spv = new ubyte[0];
  }

  /// Whether this Shader has been successfully initialized.
  bool initialized() @property const {
    return _shaderModule !is null;
  }

  ShaderModule shaderModule() @property const {
    return cast(ShaderModule) _shaderModule;
  }

  /// Initialize this Shader.
  void initialize(scope Device device) {
    this.device = device;
    this._shaderModule = device.createShaderModule(cast(uint[]) spv, "main");
  }
}

/// Type of <a href="https://en.wikipedia.org/wiki/Back-face_culling">face culling</a> to use during graphic pipeline rasterization.
enum CullMode : Cull {
  /// Disable face culling.
  none = Cull.none,
  /// Cull front faces.
  front = Cull.front,
  /// Cull back faces.
  back = Cull.back,
  /// Cull both front and back faces.
  both = Cull.frontAndBack
}

/// Specifies the vertex order for faces to be considered front-facing.
enum FrontFace : gfx.graal.FrontFace {
  /// Clockwise ordered faces will be considered front-facing.
  clockwise = gfx.graal.FrontFace.cw,
  /// Counter-clockwise ordered faces will be considered front-facing.
  counterClockwise = gfx.graal.FrontFace.ccw
}

/// A shaded material for geometry encapsulating its `Shader`s, graphics pipeline state, and optionally a `Texture`.
class Material : NamedComponent, IResource {
  /// Whether to perform the depth test. If `true`, assumes the render target has a depth buffer attachment.
  bool depthTest = true;
  /// Specifies the vertex order for faces to be considered front-facing.
  FrontFace frontFace = FrontFace.clockwise;
  /// Type of <a href="https://en.wikipedia.org/wiki/Back-face_culling">face culling</a> to use during graphic pipeline rasterization.
  CullMode cullMode = CullMode.back;

  package (teraflop) Shader[] _shaders;
  package (teraflop) Texture texture_;

  /// Initialize a new Material.
  this(Shader[] shaders, FrontFace frontFace = FrontFace.clockwise, CullMode cullMode = CullMode.back) {
    this(fullyQualifiedName!Material, shaders, frontFace, cullMode);
  }
  /// Initialize a new textured Material.
  this(
    Shader[] shaders, Texture texture, FrontFace frontFace = FrontFace.clockwise, CullMode cullMode = CullMode.back
  ) {
    this(fullyQualifiedName!Material, shaders, texture, frontFace, cullMode);
  }
  /// Initialize a new named Material.
  this(
    string name, Shader[] shaders, FrontFace frontFace = FrontFace.clockwise, CullMode cullMode = CullMode.back
  ) {
    this(name, shaders, null, frontFace, cullMode);
  }
  /// Initialize a new named and textured Material.
  this(
    string name, Shader[] shaders, Texture texture,
    FrontFace frontFace = FrontFace.clockwise, CullMode cullMode = CullMode.back
  ) {
    super(name);

    this._shaders = shaders;
    this.texture_ = texture;
    this.frontFace = frontFace;
    this.cullMode = cullMode;
  }
  ~this() {
    foreach (shader; _shaders)
      destroy(shader);
  }

  /// Whether this Shader has been successfully initialized.
  bool initialized() @property const {
    import std.algorithm.searching : all;

    if (!_shaders.length) return true;
    return _shaders.all!(shader => shader.initialized) && (texture is null || texture.initialized);
  }

  GraphicsShaderSet shaders() @property const {
    import std.algorithm : canFind, find;

    auto findShader = (const Shader s, ShaderStage st) => s.stage == st;

    GraphicsShaderSet shaderSet = {
      vertex: _shaders.canFind!(findShader)(ShaderStage.vertex)
        ? _shaders.find!(findShader)(ShaderStage.vertex)[0].shaderModule
        : null,
      tessControl: _shaders.canFind!(findShader)(ShaderStage.tessellationControl)
        ? _shaders.find!(findShader)(ShaderStage.tessellationControl)[0].shaderModule
        : null,
      tessEval: _shaders.canFind!(findShader)(ShaderStage.tessellationEvaluation)
        ? _shaders.find!(findShader)(ShaderStage.tessellationEvaluation)[0].shaderModule
        : null,
      geometry: _shaders.canFind!(findShader)(ShaderStage.geometry)
        ? _shaders.find!(findShader)(ShaderStage.geometry)[0].shaderModule
        : null,
      fragment: _shaders.canFind!(findShader)(ShaderStage.fragment)
        ? _shaders.find!(findShader)(ShaderStage.fragment)[0].shaderModule
        : null,
    };
    return shaderSet;
  }

  Texture texture() @property const {
    return cast(Texture) texture_;
  }
  bool textured() @property const {
    return texture_ !is null;
  }

  // Pipelines are keyed on Material instances
  // https://dlang.org/spec/hash-map.html#using_classes_as_key
  override size_t toHash() const pure {
    size_t accumulatedHash = cullMode.hashOf(frontFace);
    foreach (shader; _shaders)
      accumulatedHash = shader.spv.hashOf(accumulatedHash);
    return accumulatedHash;
  }
  override bool opEquals(Object o) const pure {
    Material other = cast(Material) o;
    return other && toHash() == other.toHash();
  }

  /// Initialize this Material.
  void initialize(scope Device device) {
    foreach (shader; _shaders) shader.initialize(device);
    if (texture_ !is null)
      texture.initialize(device);
  }
}

version (unittest) {
  import teraflop.platform.vulkan : FrameData;

  private class TestFrameData : FrameData {
    PrimaryCommandBuffer cmdBuf;
    Rc!Framebuffer frameBuffer;

    this(
      Device device, uint queueFamilyIndex, ImageBase swcColor, RenderPass renderPass, CommandBuffer tempBuf = null
    ) {
      super(device, queueFamilyIndex, swcColor);
      cmdBuf = cmdPool.allocatePrimary(1)[0];

      cmdBuf.begin(CommandBufferUsage.simultaneousUse);
      cmdBuf.end();

      frameBuffer = device.createFramebuffer(renderPass, [
        swcColor.createView(
          ImageType.d2,
          ImageSubresourceRange(ImageAspect.color),
          Swizzle.identity
        )
      ], size.width, size.height, 1);
    }

    override void dispose() {
      cmdPool.free([ cast(CommandBuffer)cmdBuf ]);
      frameBuffer.unload();
      super.dispose();
    }
  }
}

unittest {
  version (GPU) {
    import gfx.core : none;
    import std.conv : to;
    import std.typecons : No;
    import teraflop.platform.vulkan;

    assert(initVulkan("test-triangle"));
    const graphicsQueueIndex = selectGraphicsQueue();
    enforce(graphicsQueueIndex >= 0, "Try upgrading your graphics drivers.");
    auto device = selectGraphicsDevice(graphicsQueueIndex);
    auto graphicsQueue = device.getQueue(graphicsQueueIndex, 0);

    // Render a blank scene to a single image
    auto renderTargetSize = Size(400, 400);
    auto renderTarget = createImage(device, renderTargetSize, Format.bgra8_sRgb, ImageUsage.colorAttachment);

    const attachments = [AttachmentDescription(Format.bgra8_sRgb, 1,
      AttachmentOps(LoadOp.clear, StoreOp.store),
      AttachmentOps(LoadOp.dontCare, StoreOp.dontCare),
      trans(ImageLayout.undefined, ImageLayout.presentSrc),
      No.mayAlias
    )];
    const subpasses = [SubpassDescription(
      [], [ AttachmentRef(0, ImageLayout.colorAttachmentOptimal) ],
      none!AttachmentRef, []
    )];
    auto renderPass = device.createRenderPass(attachments, subpasses, []);
    auto frameBuffer = new TestFrameData(device, graphicsQueueIndex, renderTarget, renderPass);

    auto triangle = new Mesh!VertexPosColor([
      VertexPosColor(vec3f(0.0f, -0.5f, 0), Color.red.vec3f),
      VertexPosColor(vec3f(0.5f, 0.5f, 0), Color.green.vec3f),
      VertexPosColor(vec3f(-0.5f, 0.5f, 0), Color.blue.vec3f),
    ], [0, 1, 2]);
    triangle.initialize(device);
    assert(triangle.initialized);
    assert(triangle.dirty);
    assert(triangle.vertexCount == 3);
    assert(triangle.indices == [0, 1, 2]);

    auto vert = new Shader(ShaderStage.vertex, "examples/triangle/assets/shaders/triangle.vs.spv");
    auto frag = new Shader(ShaderStage.fragment, "examples/triangle/assets/shaders/triangle.fs.spv");
    auto material = new Material([vert, frag]);
    material.depthTest = false;
    material.initialize(device);
    assert(vert.initialized && frag.initialized);
    assert(material.initialized);

    Pipeline[Material] pipelines;
    DescriptorSetLayout[] descriptors;
    PipelineInfo info = {
      shaders: material.shaders,
      inputBindings: [triangle.bindingDescription],
      inputAttribs: triangle.attributeDescriptions,
      assembly: InputAssembly(Primitive.triangleList, No.primitiveRestart),
      rasterizer: Rasterizer(
        PolygonMode.fill, material.cullMode, material.frontFace, No.depthClamp,
        none!DepthBias, 1f
      ),
      viewports: [
        ViewportConfig(
          Viewport(0, 0, renderTargetSize.width.to!float, renderTargetSize.height.to!float),
          Rect(0, 0, renderTargetSize.width, renderTargetSize.height)
        )
      ],
      blendInfo: ColorBlendInfo(
        none!LogicOp, [
          ColorBlendAttachment(No.enabled,
            BlendState(trans(BlendFactor.one, BlendFactor.zero), BlendOp.add),
            BlendState(trans(BlendFactor.one, BlendFactor.zero), BlendOp.add),
            ColorMask.all
          )
        ],
        [ 0f, 0f, 0f, 0f ]
      ),
      layout: device.createPipelineLayout(descriptors.length ? descriptors : [], []),
      renderPass: renderPass,
      subpassIndex: 0
    };
    pipelines[material] = device.createPipelines([info])[0];

    auto commands = frameBuffer.cmdPool.allocatePrimary(1)[0];
    commands.begin(CommandBufferUsage.oneTimeSubmit);
    const clearColor = Color.black.toVulkan;
    commands.beginRenderPass(
      renderPass, frameBuffer.frameBuffer,
      Rect(0, 0, renderTargetSize.width, renderTargetSize.height),
      [ClearValues(clearColor)]
    );
    commands.bindPipeline(pipelines[material]);
    commands.bindVertexBuffers(0, [VertexBinding(triangle.vertexBuffer, 0)]);
    commands.bindIndexBuffer(triangle.indexBuffer, 0, IndexType.u32);
    commands.drawIndexed(triangle.indices.length.to!uint, 1, 0, 0, 0);
    commands.endRenderPass();
    commands.end();
    // TODO: Diff with a PPM file, e.g. https://github.com/mruby/mruby/blob/master/benchmark/bm_ao_render.rb#L308

    auto submissions = [Submission([], [], [commands])];
    graphicsQueue.submit(submissions, null);

    // Render one frame
    device.waitIdle();

    // Gracefully teardown GPU resources
    destroy(material);
    destroy(triangle);

    foreach (pipeline; pipelines.values) {
      device.waitIdle();
      pipeline.dispose();
    }
    device.waitIdle();
    renderPass.dispose();
    frameBuffer.dispose();

    device.waitIdle();
    device.release();
    unloadVulkan();
  }
}
