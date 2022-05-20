/// Authors: Chance Snow
/// Copyright: Copyright © 2022 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.ecs.components;

///
interface Resource {
  import wgpu.api : Adapter, Device;

  ///
  void initialize(Adapter adapter, Device device);
}
