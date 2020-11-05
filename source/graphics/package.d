/// Graphics pipeline primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.graphics;

import concepts : implements;
import erupted;

import teraflop.components : IResource;
import teraflop.math : Size;
import teraflop.vulkan : Device, enforceVk;

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
    spv = new ubyte[0];

    this.stageCreateInfo.stage = vkShaderStage(stage);
    this.stageCreateInfo.module_ = shaderModule;
    this.stageCreateInfo.pName = "main";
  }
}

