/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: MIT License
module teraflop.systems.rendering;

import gfx.graal;
import teraflop.ecs : System, World;
import teraflop.graphics;
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
}

/// Initialize GPU pipelines for Entity `Material`-`Mesh` combinations.
final class PipelinePreparer : System {
  ///
  alias BindingGroups = BindingGroup[];

  private Device device;
  private RenderPass renderPass;
  private alias PipelineKey = size_t;
  private DescriptorPool[PipelineKey] descriptorPools;
  private DescriptorSet[PipelineKey] descriptorSets;
  private Buffer[const Material] _uniformBuffers;
  private BindingGroups[const Material] _bindingGroups;
  private Pipeline[PipelineKey] pipelines;
  private PipelineLayout[PipelineKey] pipelineLayouts;
  private Renderable[] _renderables;

  /// Initialize a new ResourceInitializer.
  this(const World world, Device device, RenderPass renderPass) {
    super(world);

    this.device = device;
    this.renderPass = renderPass;
  }
  ~this() {
    foreach (pipeline; pipelines.values) pipeline.dispose();
    foreach (descriptorPool; descriptorPools.values) descriptorPool.dispose();
    foreach (uniformBuffer; _uniformBuffers.values) uniformBuffer.dispose();
  }

  const(BindingGroups[const Material]) bindingGroups() @property const {
    return _bindingGroups;
  }
  const(Renderable)[] renderables() @property const {
    return _renderables;
  }
  ///
  @property Buffer[const Material] uniformBuffers() {
    return _uniformBuffers;
  }

  private PipelineKey key(const Material material, const MeshBase mesh) {
    return material.hashOf(mesh.bindingDescription.hashOf(mesh.attributeDescriptions.hashOf(mesh.topology)));
  }
  private bool hasPipeline(PipelineKey key) {
    return (key in pipelines) !is null;
  }

  override void run() {
    import gfx.core : none;
    import std.algorithm : canFind, countUntil, filter, map, sum;
    import std.array : array;
    import std.conv : to;
    import std.exception : enforce;
    import std.range : tail;
    import std.typecons : No, Yes;
    import teraflop.components : Transform;

    const window = this.resources.get!Window;
    auto surfaceSize = window.framebufferSize;

    // Aggregate graphics pipelines
    foreach (entity; this.query()) {
      if (!entity.contains!Material) continue;
      const material = entity.get!Material()[0];
      if (!material.initialized) continue;
      const mesh = entity.get!MeshBase()[0];
      if (!mesh.initialized) continue;

      const key = this.key(material, mesh);
      if (hasPipeline(key)) continue;
      _bindingGroups[material] = new BindingGroup[0];
      const(BindingDescriptor)[] bindings = entity.get!BindingDescriptor();

      // Bind the World's primary camera mvp uniform, if any
      const(BindingDescriptor)[] transformBindings;
      const hasWorldCamera = this.resources.contains!Camera;
      if (hasWorldCamera) {
        transformBindings ~= this.resources.get!Camera.uniform;
      }
      // Bind the Entity's `Transform` uniform in the same binding group as the World camera, if any
      auto findBinding = (const BindingDescriptor binding, TypeInfo_Class type) => binding.classinfo.isBaseOf(type);
      const hasTransform = bindings.canFind!(findBinding)(typeid(Transform));
      if (hasTransform) {
        auto transformIndex = bindings.countUntil!(findBinding)(typeid(Transform));
        transformBindings ~= bindings[transformIndex];
        // Remove the uniform from general array of bindings
        bindings = bindings[0 .. transformIndex] ~ bindings.tail(transformIndex);
      }

      auto pipelineBindings = new PipelineLayoutBinding[0];
      foreach (i, binding; transformBindings) pipelineBindings ~= PipelineLayoutBinding(
        i.to!uint, DescriptorType.uniformBuffer, 1, binding.shaderStage
      );
      pipelineBindings ~= bindings.map!(binding =>
        PipelineLayoutBinding(binding.bindingLocation, binding.bindingType, 1, binding.shaderStage)
      ).array;
      bindings = transformBindings ~ bindings;
      // TODO: Support more than one binding set
      DescriptorSetLayout[] descriptorSetLayouts;

      if (pipelineBindings.length) {
        _bindingGroups[material] ~= BindingGroup(0, bindings);

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
          _uniformBuffers[material] = device.createDynamicBuffer(size, BufferUsage.uniform);
        }
        WriteDescriptorSet[] descriptorWrites;
        for (auto i = 0, offset = 0; i < pipelineBindings.length; i += 1) {
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
                ColorBlendAttachment(No.enabled,
                    BlendState(trans(BlendFactor.one, BlendFactor.zero), BlendOp.add),
                    BlendState(trans(BlendFactor.one, BlendFactor.zero), BlendOp.add),
                    ColorMask.all
                )
            ],
            [ 0f, 0f, 0f, 0f ]
        ),
        // dynamicStates: [DynamicState.viewport, DynamicState.scissor],
        layout: device.createPipelineLayout(descriptorSetLayouts.length ? descriptorSetLayouts : [], []),
        renderPass: renderPass,
        subpassIndex: 0
      };
      if (material.depthTest)
        info.depthInfo = DepthInfo(Yes.enabled, Yes.write, CompareOp.less, No.boundsTest, 0f, 1f);

      // TODO: Optimize this to make _all_ the pipelines at once?
      pipelines[key] = device.createPipelines([info])[0];
      pipelineLayouts[key] = info.layout;
    }

    // Aggregate renderable Entities
    _renderables = [];
    foreach (entity; this.query()) {
      if (!entity.contains!Material) continue;
      const material = entity.get!Material()[0];
      if (!material.initialized) continue;
      const mesh = entity.get!MeshBase()[0];
      if (!mesh.initialized) continue;

      const key = this.key(material, mesh);
      _renderables ~= Renderable(
        pipelines[key], pipelineLayouts[key],
        (key in descriptorSets) !is null ? descriptorSets[key] : null,
        cast(MeshBase) mesh
      );
    }
  }
}