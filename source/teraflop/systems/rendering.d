/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.systems.rendering;

import gfx.graal;
import teraflop.ecs : System, World;
import teraflop.graphics;
import teraflop.platform;

/// Initialize GPU pipelines for Entity `Material`-`Mesh` combinations.
final class PipelinePreparer : System {
  ///
  alias BindingGroups = BindingGroup[];

  private Device device;
  private RenderPass renderPass;
  private bool _materialsChanged = false;
  private PipelineCache pipelines;
  private Renderable[] _renderables;

  /// Initialize a new ResourceInitializer.
  this(const World world, Device device, RenderPass renderPass) {
    super(world);

    this.device = device;
    this.renderPass = renderPass;
    this.pipelines = new PipelineCache();
  }
  ~this() {
    pipelines.destroy();
  }

  const(BindingGroups[const Material]) bindingGroups() @property const {
    return pipelines.bindingGroups;
  }
  ///
  @property Buffer[const Material] uniformBuffers() {
    return pipelines.uniformBuffers;
  }
  /// Whether one or more materials have changed, e.g. when a `Shader` is recompiled.
  /// Observers of this property ought re-record render pass command buffers.
  @property bool materialsChanged() {
    auto result = _materialsChanged;
    _materialsChanged = false;
    return result;
  }
  const(Renderable)[] renderables() @property const {
    return _renderables;
  }

  override void run() {
    import gfx.core : none;
    import std.algorithm : canFind, countUntil, filter, map, remove, sort, sum;
    import std.array : array;
    import std.conv : to;
    import std.exception : enforce;
    import std.range : tail;
    import std.typecons : No, Yes;
    import teraflop.components : Transform;
    import teraflop.math : mat4f;
    import teraflop.platform : SurfaceSizeProvider;

    // TODO: Run both of these loops in parallel

    // Aggregate graphics pipelines
    foreach (entity; this.query()) {
      if (!entity.contains!Material) continue;
      const material = entity.get!Material()[0];
      if (!material.initialized) continue;
      const mesh = entity.get!MeshBase()[0];
      if (!mesh.initialized) continue;
      BindingDescriptor[] bindings = entity.getMut!BindingDescriptor();

      _materialsChanged = _materialsChanged || pipelines.update(
        device, renderPass, this.resources.get!SurfaceSizeProvider.surfaceSize,
        material, mesh, bindings,
        this.resources.contains!Camera ? this.resources.get!Camera : null,
      );
    }

    // Aggregate renderable Entities
    _renderables = [];
    foreach (entity; this.query()) {
      if (!entity.contains!Material) continue;
      const material = entity.get!Material()[0];
      if (!material.initialized) continue;
      const mesh = entity.get!MeshBase()[0];
      if (!mesh.initialized) continue;
      BindingDescriptor[] bindings = entity.getMut!BindingDescriptor();

      // Bind the Entity's `Transform` uniform, if any, as a push constant
      const(BindingDescriptor)[] pushBindings;
      const transformIndex = bindings.countUntil!(BindingDescriptor.findBinding)(typeid(Transform));
      if (transformIndex >= 0) pushBindings ~= bindings[transformIndex];

      auto renderable = pipelines[PipelineCache.key(material, mesh)];
      renderable.mesh = cast(MeshBase) mesh;
      renderable.pushBindings = pushBindings;
      _renderables ~= renderable;
    }
  }
}
