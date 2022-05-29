/// Authors: Chance Snow
/// Copyright: Copyright © 2022 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.ecs.components;

///
interface Resource {
  import wgpu.api : Adapter, Device;

  /// Whether *all* of an `teraflop.ecs.Entity`'s GPU Resources have been initialized.
  /// See_Also: `teraflop.ecs.Entity.tag`
  static const Initialized = "Initialized";

  ///
  void initialize(Adapter adapter, Device device);
}

///
interface Asset : Resource {
  // TODO: Add a `teraflop.assets` module for cached asset resources?

  /// Whether *all* of an `teraflop.ecs.Entity`'s `Asset` Components have been loaded.
  /// See_Also: `teraflop.ecs.Entity.tag`
  static const Loaded = "Loaded";
}
