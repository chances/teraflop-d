/// Built-in Components and Component primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.components;

import gfx.graal : Device;

public import teraflop.components.transform;

/// A Component that holds one or more handles to GPU resources.
///
/// See_Also:
/// <h3>Implementations</h3>
/// $(UL
///   $(LI `teraflop.graphics.Material`)
///   $(LI `teraflop.graphics.Mesh`)
///   $(LI `teraflop.graphics.Shader`)
///   $(LI `teraflop.graphics.Texture`)
/// )
interface IResource {
  /// Whether this Resource has been successfully initialized.
  bool initialized() @property const;
  /// Initialize this Resource. `intiialized` should be `true` if successful.
  void initialize(scope Device device);
}
