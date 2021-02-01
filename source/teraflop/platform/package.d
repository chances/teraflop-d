/// Native platform integrations.
///
/// $(UL
///   $(LI <a href="platform/vulkan.html">Vulkan</a>: Utilities for <a href="https://github.com/rtbo/gfx-d#readme">gfx</a> graphics library integration.)
///   $(LI <a href="platform/window.html">Window</a>: Native window primitives.)
/// )
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.platform;

public {
  import teraflop.platform.vulkan;
  import teraflop.platform.window;
}
