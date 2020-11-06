/// Graphics pipeline primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.graphics;

import concepts : implements;
import erupted;
import std.traits : fullyQualifiedName;

import teraflop.components : IResource;
import teraflop.ecs : NamedComponent;
import teraflop.math;
import teraflop.traits : isStruct;
import teraflop.vulkan : Buffer, Device, enforceVk;

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
    import erupted : VkClearValue;

    VkClearValue color = {
      color: VkClearColorValue([cast(float) r, cast(float) g, cast(float) b, cast(float) a])
    };
    return color;
  }
}

/// Detect whether `T` is vertex attribute data.
template isVertexData(T) if (isStruct!T) {
  // import std.algorithm.searching : all;
  // static immutable attributes = [__traits(allMembers, T)];
}

/// Vertex attribute data comprising a 2D position and opaque color.
struct VertexPosColor {
  /// 2D position.
  vec2f position;
  /// Opaque color.
  vec3f color;

  /// Describes how vertex attributes should be bound to the vertex shader.
  static VkVertexInputBindingDescription bindingDescription() {
    VkVertexInputBindingDescription bindingDescription = {
      binding: 0,
      stride: VertexPosColor.sizeof,
      inputRate: VK_VERTEX_INPUT_RATE_VERTEX,
    };
    return bindingDescription;
  }

  /// Describes the format of each vertex attribute so that they can be applied to the vertex shader.
  static VkVertexInputAttributeDescription[2] attributeDescriptions() {
    VkVertexInputAttributeDescription[2] attributeDescriptions;
    attributeDescriptions[0].binding = 0;
    attributeDescriptions[0].location = 0;
    attributeDescriptions[0].format = VK_FORMAT_R32G32_SFLOAT;
    attributeDescriptions[0].offset = VertexPosColor.position.offsetof;
    attributeDescriptions[1].binding = 0;
    attributeDescriptions[1].location = 1;
    attributeDescriptions[1].format = VK_FORMAT_R32G32B32_SFLOAT;
    attributeDescriptions[1].offset = VertexPosColor.color.offsetof;
    return attributeDescriptions;
  }
}

package (teraflop) abstract class MeshBase : NamedComponent, IResource {
  package (teraflop) Buffer vertexBuffer;
  package (teraflop) Buffer indexBuffer;
  private auto dirty_ = true;

  this(string name) {
    super(name);
  }
  ~this() {
    destroy(vertexBuffer);
    destroy(indexBuffer);
  }

  /// Whether this mesh's vertex data is new or changed and needs to be uploaded to the GPU.
  bool dirty() @property const {
    return dirty_;
  }
  package (teraflop) void dirty(bool value) @property {
    dirty_ = value;
  }

  abstract ulong vertexCount() @property const;
  abstract size_t size() @property const;
  abstract const(ubyte[]) data() @property const;
  abstract const(uint[]) indices() @property const;

  /// Describes how this mesh's vertex attributes should be bound to the vertex shader.
  abstract VkVertexInputBindingDescription bindingDescription() @property const;
  /// Describes the format of this mesh's vertex attributes so that they can be applied to the vertex shader.
  abstract VkVertexInputAttributeDescription[] attributeDescriptions() @property const;

  /// Whether this Mesh has been successfully initialized.
  bool initialized() @property const {
    return vertexBuffer !is null && vertexBuffer.ready &&
      indexBuffer !is null && indexBuffer.ready;
  }

  /// Initialize this Mesh.
  void initialize(const Device device) {
    import std.algorithm.mutation : copy;
    import teraflop.vulkan : BufferUsage;

    vertexBuffer = device.createBuffer(size);
    auto unfilled = data.copy(vertexBuffer.map());
    assert(unfilled.length == 0);
    vertexBuffer.unmap();

    indexBuffer = device.createBuffer(uint.sizeof * indices.length, BufferUsage.indexBuffer);
    const(void[]) indexData = indices;
    assert(indexData.length == indexBuffer.size);
    unfilled = (cast(ubyte[]) indexData).copy(indexBuffer.map());
    assert(unfilled.length == 0);
    indexBuffer.unmap();
  }
}

/// A renderable mesh encapsulating vertex data.
class Mesh(T) : MeshBase if (isStruct!T) {
  // TODO: Make type contraint more robust, e.g. NO pointers/reference types in vertex data
  private T[] vertices_;
  private uint[] indices_;

  /// Initialize a new mesh.
  ///
  /// Params:
  /// vertices = Mesh vertex data to optionally pre-populate
  this(T[] vertices = [], uint[] indices = []) {
    this(fullyQualifiedName!(Mesh!T), vertices, indices);
  }
  /// Initialize a new named mesh.
  ///
  /// Params:
  /// name = The name of this mesh.
  /// vertices = Mesh vertex data to optionally pre-populate
  this(string name, T[] vertices = [], uint[] indices = []) {
    super(name);
    this.vertices_ = vertices;
    this.indices_ = indices;
  }

  /// This mesh's vertex data.
  const(T[]) vertices() @property const {
    return vertices_;
  }
  override ulong vertexCount() @property const {
    return vertices_.length;
  }
  /// This mesh's vertex index data.
  override const(uint[]) indices() @property const {
    return indices_;
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
  override VkVertexInputBindingDescription bindingDescription() @property const {
    return __traits(getMember, T, "bindingDescription");
  }
  /// Describes the format of this mesh's vertex attributes so that they can be applied to the vertex shader.
  override VkVertexInputAttributeDescription[] attributeDescriptions() @property const {
    return __traits(getMember, T, "attributeDescriptions").dup;
  }

  /// Update this mesh's vertex data.
  void update(T[] vertices) {
    this.vertices_ = vertices;
    dirty_ = true;
  }
}

/// A programmable stage in the graphics `Pipeline`.
enum ShaderStage {
  /// For every vertex, generally applies transformations to turn vertex positions from model space to screen space.
  vertex,
  /// Subdivide geometry to increase the mesh quality.
  tesselation,
  /// For every primitive (triangle, line, point) either discard it or output more primitives than came in. Similar to
  /// the tessellation shader, but much more flexible.
  geometry,
  /// For every fragment that survives and determines which framebuffer(s) the fragments are written to and with which
  /// color and depth values. It can do this using the interpolated data from the vertex shader, which can include
  /// things like texture coordinates and normals for lighting.
  fragment
}

private VkShaderStageFlagBits vkShaderStage(ShaderStage stage) pure {
  switch (stage) {
    case ShaderStage.vertex: return VK_SHADER_STAGE_VERTEX_BIT;
    case ShaderStage.tesselation:
      return VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT | VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT;
    case ShaderStage.geometry: return VK_SHADER_STAGE_GEOMETRY_BIT;
    case ShaderStage.fragment: return VK_SHADER_STAGE_FRAGMENT_BIT;
    default: assert(0);
  }
}

/// A SPIR-V program for one programmable stage in the graphics `Pipeline`.
class Shader : IResource {
  /// The stage in the graphics pipeline in which this Shader performs.
  const ShaderStage stage;

  private Device device;
  private VkShaderModule shaderModule;
  package (teraflop) VkPipelineShaderStageCreateInfo stageCreateInfo;
  private ubyte[] spv;

  /// Initialize a new Shader.
  ///
  /// Params:
  /// stage = The stage in the graphics pipeline in which this Shader performs.
  /// filePath = Path to a file containing SPIR-V source bytecode.
  this(ShaderStage stage, string filePath) {
    import std.exception : enforce;
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
    vkDestroyShaderModule(device.handle, shaderModule, null);
    spv = new ubyte[0];
  }

  /// Whether this Shader has been successfully initialized.
  bool initialized() @property const {
    return shaderModule != VK_NULL_HANDLE;
  }

  /// Initialize this Shader.
  void initialize(const Device device) {
    this.device = cast(Device) device;

    VkShaderModuleCreateInfo createInfo = {
      codeSize: spv.length,
      pCode: cast(uint*) spv.ptr,
    };
    enforceVk(vkCreateShaderModule(device.handle, &createInfo, null, &shaderModule));

    this.stageCreateInfo.stage = vkShaderStage(stage);
    this.stageCreateInfo.module_ = shaderModule;
    this.stageCreateInfo.pName = "main";
  }
}

/// Type of <a href="https://en.wikipedia.org/wiki/Back-face_culling">face culling</a> to use during graphic pipeline rasterization.
enum CullMode {
  /// Disable face culling.
  none,
  /// Cull front faces.
  frontFace,
  /// Cull back faces.
  backFace,
  /// Cull both front and back faces.
  both
}

/// Specifies the vertex order for faces to be considered front-facing.
enum FrontFace {
  clockwise,
  counterClockwise
}

/// A shaded material for geometry encapsulating its `Shader`s and graphics pipeline state.
class Material : NamedComponent, IResource {
  /// Type of <a href="https://en.wikipedia.org/wiki/Back-face_culling">face culling</a> to use during graphic pipeline rasterization.
  CullMode cullMode = CullMode.backFace;
  /// Specifies the vertex order for faces to be considered front-facing.
  FrontFace frontFace = FrontFace.clockwise;

  package (teraflop) Shader[] shaders;

  /// Initialize a new Material.
  this(Shader[] shaders) {
    super(fullyQualifiedName!Material);
    this.shaders = shaders;
  }
  /// Initialize a new named Material.
  this(string name, Shader[] shaders) {
    super(name);
    this.shaders = shaders;
  }
  ~this() {
    foreach (shader; shaders)
      destroy(shader);
  }

  /// Whether this Shader has been successfully initialized.
  bool initialized() @property const {
    import std.algorithm.searching : all;

    if (!shaders.length) return true;
    return shaders.all!(shader => shader.initialized);
  }

  // Pipelines are keyed on Material instances
  // https://dlang.org/spec/hash-map.html#using_classes_as_key
  override size_t toHash() const pure {
    size_t accumulatedHash = cullMode.hashOf(frontFace);
    foreach (shader; shaders)
      accumulatedHash = shader.spv.hashOf(accumulatedHash);
    return accumulatedHash;
  }
  override bool opEquals(Object o) const pure {
    Material other = cast(Material) o;
    return other && toHash() == other.toHash();
  }

  /// Initialize this Shader.
  void initialize(const Device device) {
    foreach (shader; shaders) shader.initialize(device);
  }
}
