/// Graphics pipeline primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.graphics;

import concepts : implements;
import erupted;

import teraflop.components : IResource;
import teraflop.ecs : NamedComponent;
import teraflop.math : Size;
import teraflop.vulkan : Device, enforceVk;

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

  package (teraflop) auto toVulkan() const {
    import erupted : VkClearValue;

    VkClearValue color = {
      color: VkClearColorValue([cast(float) r, cast(float) g, cast(float) b, cast(float) a])
    };
    return color;
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

  private Shader[] shaders;

  /// Initialize a new Material.
  this(Shader[] shaders) {
    import std.traits : fullyQualifiedName;

    super(fullyQualifiedName!Material);
    this.shaders = shaders;
  }
  /// Initialize a new named Material.
  this(string name, Shader[] shaders) {
    super(name);
    this.shaders = shaders;
  }

  /// Whether this Shader has been successfully initialized.
  bool initialized() @property const {
    import std.algorithm.searching : all;

    if (!shaders.length) return true;
    return shaders.all!(shader => shader.initialized);
  }

  /// Initialize this Shader.
  void initialize(const Device device) {
    foreach (shader; shaders) shader.initialize(device);
  }
}
