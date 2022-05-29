/// Native platform integrations.
///
/// $(UL
///   $(LI <a href="platform/wgpu.html">WebGPU</a>: Utilities for <a href="https://chances.github.io/wgpu-d">WebGPU</a> graphics library integration.)
///   $(LI <a href="platform/window.html">Window</a>: Native window primitives.)
/// )
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.platform;

public:

import teraflop.platform.wgpu : createPlatformSurface;
import teraflop.platform.window;
