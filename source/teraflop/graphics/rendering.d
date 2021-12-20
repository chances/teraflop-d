/// Authors: Chance Snow
/// Copyright: Copyright © 2021 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.graphics.rendering;

import gfx.graal;
import teraflop.graphics;
import teraflop.math : Size;
import teraflop.platform;

///
struct Renderable {
  ///
  Pipeline pipeline;
  ///
  PipelineLayout layout;
  ///
  DescriptorSet descriptorSet;
  ///
  MeshBase mesh;
  ///
  const(BindingDescriptor)[] pushBindings;
}

///
alias BindingGroups = BindingGroup[];

/// SeeAlso: `PipelineCache`
interface IPipelineCache {
  ///
  const(BindingGroups[const Material]) bindingGroups() @property const;
  ///
  @property Buffer[const Material] uniformBuffers();
  /// Returns: Whether the pipeline changed (i.e. was created, changed, or disposed) because one or more materials have
  /// changed, e.g. when a `Shader` is recompiled.
  /// Observers of this flag ought re-record render pass command buffers.
  bool update(
    Device device, RenderPass renderPass, Size surfaceSize,
    const Material material, const MeshBase mesh,
    BindingDescriptor[] bindings, const Camera camera = null
  );
}

///
final class PipelineCache : IPipelineCache {
  private alias PipelineKey = size_t;
  private DescriptorPool[PipelineKey] descriptorPools;
  private DescriptorSet[PipelineKey] descriptorSets;
  private Buffer[const Material] _uniformBuffers;
  private BindingGroups[const Material] _bindingGroups;
  private Pipeline[PipelineKey] pipelines;
  private PipelineLayout[PipelineKey] pipelineLayouts;

  ~this() {
    foreach (pipeline; pipelines.values) pipeline.dispose();
    foreach (descriptorPool; descriptorPools.values) descriptorPool.dispose();
    foreach (uniformBuffer; _uniformBuffers.values) uniformBuffer.dispose();
  }

  ///
  Renderable opIndex(size_t key) {
    return Renderable(
      pipelines[key], pipelineLayouts[key],
      (key in descriptorSets) !is null ? descriptorSets[key] : null,
    );
  }

  ///
  const(BindingGroups[const Material]) bindingGroups() @property const {
    return _bindingGroups;
  }
  ///
  @property Buffer[const Material] uniformBuffers() {
    return _uniformBuffers;
  }

  ///
  static size_t key(const Material material, const MeshBase mesh) {
    return material.hashOf(mesh.bindingDescription.hashOf(mesh.attributeDescriptions.hashOf(mesh.topology)));
  }
  private PipelineKey key(const MaterialDirtied material, const MeshBase mesh) {
    return material.formerMaterialHash.hashOf(
      mesh.bindingDescription.hashOf(mesh.attributeDescriptions.hashOf(mesh.topology))
    );
  }
  private bool hasPipeline(PipelineKey key) {
    return (key in pipelines) !is null;
  }

  /// Update the cached GPU pipeline for a given `Material`-`Mesh` combination.
  ///
  /// Returns: Whether the pipeline changed because the given material changed, e.g. when a `Shader` is recompiled.
  /// Observers of this flag ought re-record render pass command buffers.
  bool update(
    Device device, RenderPass renderPass, Size surfaceSize,
    const Material material, const MeshBase mesh,
    BindingDescriptor[] bindings, const Camera camera = null
  ) {
    import gfx.core : none;
    import std.algorithm : copy, countUntil, filter, map, remove, sort, sum;
    import std.array : array;
    import std.conv : to;
    import std.exception : enforce;
    import std.typecons : No, Yes;
    import teraflop.components : Transform;
    import teraflop.math : mat4f;

    assert(material.initialized && mesh.initialized, "Given material and mesh must be initialized!");

    // Prune dirtied Materials, i.e. Materials whose shaders have changed
    const materialDirtied = material.dirty && material.dirtied.shaderChanged;
    bool materialsChanged = false;
    const key = materialDirtied
      ? this.key(material.dirtied, mesh)
      : PipelineCache.key(material, mesh);

    if (materialDirtied && (key in pipelines) !is null) {
      materialsChanged = true;
      device.waitIdle();

      pipelines[key].dispose();
      pipelines.remove(key);
      descriptorPools[key].dispose();
      descriptorPools.remove(key);
      descriptorSets.remove(key);
      if ((material in _uniformBuffers) !is null) _uniformBuffers[material].dispose();
      _uniformBuffers.remove(material);
      _bindingGroups.remove(material);
      pipelineLayouts.remove(key);
    }

    // Bail early if this material/mesh pair already have a cached pipeline
    if (hasPipeline(key)) return materialsChanged;

    // Bind the Material's Texture, if any
    if (material.textured) bindings ~= material.texture;
    // Bind the given camera as a mvp uniform, if any
    // if (camera !is null) bindings ~= cast(UniformBuffer!mat4f) camera.uniform;
    if (camera !is null) bindings ~= camera.uniform.dup;
    bindings.sort!((a, b) => a.bindingLocation < b.bindingLocation);

    // Push constants
    PushConstantRange[] pushConstants;
    // Bind the Entity's `Transform` uniform, if any, as a push constant
    const transformIndex = bindings.countUntil!(BindingDescriptor.findBinding)(typeid(Transform));
    if (transformIndex >= 0) {
      auto binding = bindings[transformIndex];
      pushConstants ~= PushConstantRange(binding.shaderStage, pushConstants.length.to!uint, binding.size.to!uint);
      // Remove the uniform from general array of bindings
      bindings = bindings.remove(transformIndex);
    }
    enforce(
      pushConstants.map!(pushConstant => pushConstant.size).sum <= device.physicalDevice.limits.maxPushConstantsSize,
      "Exceeded maximum push constants size!"
    );

    auto pipelineBindings = bindings.map!(binding =>
      PipelineLayoutBinding(binding.bindingLocation, binding.bindingType, 1, binding.shaderStage)
    ).array;
    // TODO: Support more than one binding set
    DescriptorSetLayout[] descriptorSetLayouts;

    if (pipelineBindings.length) {
      _bindingGroups[material] = [BindingGroup(0, bindings)];

      descriptorPools[key] = device.createDescriptorPool(
        pipelineBindings.length.to!uint,
        bindings.map!(binding => DescriptorPoolSize(binding.bindingType, 1)).array
      );
      descriptorSetLayouts ~= device.createDescriptorSetLayout(pipelineBindings);
      descriptorSets[key] = descriptorPools[key].allocate(descriptorSetLayouts)[0];

      auto uniforms = bindings.filter!(binding => binding.bindingType == DescriptorType.uniformBuffer).array;
      if (uniforms.length) enforce(
        uniforms.length <= device.physicalDevice.limits.maxDescriptorSetUniformBuffersDynamic,
        "Exceeded maximum number of dynamic uniforms per descriptor set!"
      );
      if (uniforms.length) {
        // Align uniform buffer size to `Device`'s minimum uniform buffer offset alignment
        auto size = uniforms.map!(uniform => device.physicalDevice.uniformAlignment(uniform.size)).sum;
        enforce(size <= device.physicalDevice.limits.maxUniformBufferSize, "Exceeded maximum uniform buffer size!");
        _uniformBuffers[material] = device.createDynamicBuffer(size, BufferUsage.uniform);
      }
      WriteDescriptorSet[] descriptorWrites;
      for (auto i = 0, offset = 0; i < bindings.length; i += 1) {
        const size = bindings[i].size;
        descriptorWrites ~= bindings[i].descriptorWrite(
          descriptorSets[key], i,
          uniforms.length ? _uniformBuffers[material] : null,
          offset, size
        );
        // Align binding offset in uniform buffer to `Device`'s minimum uniform buffer offset alignment
        offset += device.physicalDevice.uniformAlignment(size);
      }
      device.updateDescriptorSets(descriptorWrites, []);
    }

    PipelineInfo info = {
      shaders: material.shaders,
      inputBindings: [mesh.bindingDescription],
      inputAttribs: mesh.attributeDescriptions,
      assembly: InputAssembly(mesh.topology, No.primitiveRestart),
      rasterizer: Rasterizer(
        PolygonMode.fill, material.cullMode, material.frontFace, No.depthClamp, none!DepthBias, 1f
      ),
      viewports: [ViewportConfig(
        Viewport(0, 0, surfaceSize.width.to!float, surfaceSize.height.to!float),
        Rect(0, 0, surfaceSize.width, surfaceSize.height)
      )],
      blendInfo: ColorBlendInfo(
          none!LogicOp, [
              ColorBlendAttachment(Yes.enabled,
                  BlendState(trans(BlendFactor.srcAlpha, BlendFactor.oneMinusSrcAlpha), BlendOp.add),
                  BlendState(trans(BlendFactor.one, BlendFactor.zero), BlendOp.add),
                  ColorMask.all
              )
          ],
          [ 0f, 0f, 0f, 0f ]
      ),
      // TODO: dynamicStates: [DynamicState.viewport, DynamicState.scissor],
      layout: device.createPipelineLayout(descriptorSetLayouts, pushConstants),
      renderPass: renderPass,
      subpassIndex: 0
    };
    if (material.depthTest)
      info.depthInfo = DepthInfo(Yes.enabled, Yes.write, CompareOp.less, No.boundsTest, 0f, 1f);

    // TODO: Optimize this to make _all_ the pipelines at once?
    pipelines[key] = device.createPipelines([info])[0];
    pipelineLayouts[key] = info.layout;

    return materialsChanged;
  }
}
