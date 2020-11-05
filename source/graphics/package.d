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
  package VkShaderModule shaderModule;
  package VkPipelineShaderStageCreateInfo stageCreateInfo;
  private ubyte[] spv;

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
  void initialize(Device device) {
    this.device = device;

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

/// A graphics pipeline transforming input vertex/index buffers and outputting rasterized, tesselated, shaded, and
/// blended output.
class Pipeline : IResource {
  private Device device;
  private Size viewport;
  private Shader[] shaders;
  private VkRenderPass renderPass = VK_NULL_HANDLE;
  private VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
  private VkPipeline graphicsPipeline = VK_NULL_HANDLE;

  /// Initialize a new Pipeline.
  this(Size viewport, Shader[] shaders) {
    this.shaders = shaders;
  }

  ~this() {
    if (pipelineLayout != VK_NULL_HANDLE) vkDestroyPipelineLayout(device.handle, pipelineLayout, null);
    if (renderPass != VK_NULL_HANDLE) vkDestroyRenderPass(device.handle, renderPass, null);
    if (graphicsPipeline != VK_NULL_HANDLE) vkDestroyPipeline(device.handle, graphicsPipeline, null);

    foreach (shader; shaders)
      destroy(shader);
    shaders = [];
  }

  /// Whether this Pipeline has been successfully initialized.
  bool initialized() @property const {
    return graphicsPipeline != VK_NULL_HANDLE;
  }

  /// Initialize this Pipeline.
  void initialize(Device device) {
    import std.algorithm.iteration : map;
    import std.array : array;

    this.device = device;

    VkPipelineVertexInputStateCreateInfo vertexInputInfo = {
      vertexBindingDescriptionCount: 0,
      pVertexBindingDescriptions: null,
      vertexAttributeDescriptionCount: 0,
      pVertexAttributeDescriptions: null,
    };
    VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
      topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
      primitiveRestartEnable: VK_FALSE,
    };
    VkViewport pipelineViewport = {
      x: 0.0f,
      y: 0.0f,
      width: cast(float) this.viewport.width,
      height: cast(float) this.viewport.height,
      minDepth: 0.0f,
      maxDepth: 1.0f,
    };
    VkRect2D scissor = {
      offset: VkOffset2D(0, 0),
      extent: VkExtent2D(this.viewport.width, this.viewport.height),
    };
    VkPipelineViewportStateCreateInfo viewportState = {
      viewportCount: 1,
      pViewports: &pipelineViewport,
      scissorCount: 1,
      pScissors: &scissor,
    };
    VkPipelineRasterizationStateCreateInfo rasterizer = {
      depthClampEnable: VK_FALSE,
      rasterizerDiscardEnable: VK_FALSE,
      polygonMode: VK_POLYGON_MODE_FILL,
      lineWidth: 1.0f,
      cullMode: VK_CULL_MODE_BACK_BIT,
      frontFace: VK_FRONT_FACE_CLOCKWISE,
      depthBiasEnable: VK_FALSE,
      depthBiasConstantFactor: 0.0f,
      depthBiasClamp: 0.0f,
      depthBiasSlopeFactor: 0.0f,
    };
    VkPipelineMultisampleStateCreateInfo multisampling = {
      sampleShadingEnable: VK_FALSE,
      rasterizationSamples: VK_SAMPLE_COUNT_1_BIT,
      minSampleShading: 1.0f,
      pSampleMask: null,
      alphaToCoverageEnable: VK_FALSE,
      alphaToOneEnable: VK_FALSE,
    };
    VkPipelineColorBlendAttachmentState colorBlendAttachment = {
      colorWriteMask: VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT |
        VK_COLOR_COMPONENT_A_BIT,
      blendEnable: VK_TRUE,
      srcColorBlendFactor: VK_BLEND_FACTOR_SRC_ALPHA,
      dstColorBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
      colorBlendOp: VK_BLEND_OP_ADD,
      srcAlphaBlendFactor: VK_BLEND_FACTOR_ONE,
      dstAlphaBlendFactor: VK_BLEND_FACTOR_ZERO,
      alphaBlendOp: VK_BLEND_OP_ADD,
    };
    VkPipelineColorBlendStateCreateInfo colorBlending = {
      logicOpEnable: VK_FALSE,
      logicOp: VK_LOGIC_OP_COPY,
      attachmentCount: 1,
      pAttachments: &colorBlendAttachment,
    };

    VkPipelineLayoutCreateInfo pipelineLayoutInfo = {
      setLayoutCount: 0,
      pSetLayouts: null,
      pushConstantRangeCount: 0,
      pPushConstantRanges: null,
    };
    enforceVk(vkCreatePipelineLayout(device.handle, &pipelineLayoutInfo, null, &pipelineLayout));

    // Render passes
    VkAttachmentDescription colorAttachment = {
      format: VK_FORMAT_B8G8R8A8_SRGB,
      samples: VK_SAMPLE_COUNT_1_BIT,
      loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
      storeOp: VK_ATTACHMENT_STORE_OP_STORE,
      stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
      stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
      initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
      finalLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };
    VkAttachmentReference colorAttachmentRef = {
      attachment: 0,
      layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    VkSubpassDescription subpass = {
      pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
      colorAttachmentCount: 1,
      pColorAttachments: &colorAttachmentRef,
    };

    VkRenderPassCreateInfo renderPassInfo = {
      attachmentCount: 1,
      pAttachments: &colorAttachment,
      subpassCount: 1,
      pSubpasses: &subpass,
    };
    enforceVk(vkCreateRenderPass(device.handle, &renderPassInfo, null, &renderPass));

    // Create the pipeline
    const shaderStages = shaders.map!(shader => shader.stageCreateInfo).array;
    VkGraphicsPipelineCreateInfo pipelineInfo = {
      stageCount: cast(uint) shaders.length,
      pStages: shaderStages.ptr,
      pVertexInputState: &vertexInputInfo,
      pInputAssemblyState: &inputAssembly,
      pViewportState: &viewportState,
      pRasterizationState: &rasterizer,
      pMultisampleState: &multisampling,
      pDepthStencilState: null,
      pColorBlendState: &colorBlending,
      pDynamicState: null,
      layout: pipelineLayout,
      renderPass: renderPass,
      subpass: 0,
      basePipelineHandle: VK_NULL_HANDLE,
      basePipelineIndex: -1,
    };
    enforceVk(vkCreateGraphicsPipelines(device.handle, VK_NULL_HANDLE, 1, &pipelineInfo, null, &graphicsPipeline));
  }
}
