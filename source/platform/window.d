module teraflop.platform.window;

import bindbc.glfw;

// VkInstance
// VkPhysicalDevice
// VkResult
// const(VkAllocationCallbacks)*
// VkSurfaceKHR*
// TODO: Stub these dependent types with aliases? Do I even need to if I'm giving the window handle from below to wgpu?
// mixin(bindGLFW_Vulkan);

version(Linux) {
  // Mixin function declarations and loader
  mixin(bindGLFW_X11);
}

version(OSX) {
  // Mixin function declarations and loader
  mixin(bindGLFW_Cocoa);
}

version(Windows) {
  // Import the platform API bindings
  import core.sys.windows.windows;
  // Mixin function declarations and loader
  mixin(bindGLFW_Windows);
}
