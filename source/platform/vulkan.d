module teraflop.platform.vulkan;

import gfx.graal;
import gfx.vulkan;
import std.exception : enforce;

// https://www.glfw.org/docs/3.3/vulkan_guide.html#vulkan_present
alias GLFWvkproc = void function();
extern(C) @nogc nothrow {
  private GLFWvkproc glfwGetInstanceProcAddress(VkInstance, const(char)*);
}

debug {
  private enum bool enableValidationLayers = true;
} else {
  private enum bool enableValidationLayers = false;
}

private Rc!Instance _instance;
package (teraflop.platform) Rc!Instance instance() {
  return _instance;
}
package (teraflop) bool initVulkan(string appName) {
  import std.algorithm : remove;
  import std.stdio : writeln;

  vulkanInit();

  VulkanCreateInfo createInfo;
  createInfo.appName = appName;
  createInfo.optionalLayers ~= enableValidationLayers
    ? [
        "VK_LAYER_KHRONOS_validation",
        "VK_LAYER_GOOGLE_threading",
        "VK_LAYER_LUNARG_object_tracker",
        "VK_LAYER_GOOGLE_unique_objects"
    ] : [];
  createInfo.optionalExtensions ~= enableValidationLayers ? debugReportInstanceExtensions : [];

  try {
    _instance = createVulkanInstance(createInfo);
  } catch (Exception ex) {
    writeln(ex.msg);
    return false;
  }

  return true;
}

private PhysicalDevice selectedPhysicalDevice;

package (teraflop) uint selectGraphicsQueue() {
  import std.conv : to;
  import std.algorithm : canFind, countUntil;

  auto findRequiredCap = (QueueFamily family, QueueCap requiredCap) => (family.cap & requiredCap) == requiredCap;

  foreach (physicalDevice; _instance.devices) {
    if (physicalDevice.queueFamilies.canFind!(findRequiredCap)(QueueCap.graphics) == false) continue;
    selectedPhysicalDevice = physicalDevice;
    return physicalDevice.queueFamilies.countUntil!(findRequiredCap)(QueueCap.graphics).to!uint;
  }

  return -1;
}

package (teraflop) Device selectGraphicsDevice(Surface surface) {
  import std.exception : enforce;

  const error = "Cannot find a suitable graphics device! Try upgrading your graphics drivers.";

  auto queueFamilyIndex = selectGraphicsQueue();
  enforce(queueFamilyIndex > -1, error);
  enforce(selectedPhysicalDevice.supportsSurface(queueFamilyIndex, surface), error);
  return enforce(selectedPhysicalDevice.open([QueueRequest(queueFamilyIndex, [1.0f])]), error);
}

/// Data that is duplicated for every frame in the swapchain
/// This typically include framebuffer and command pool.
abstract class FrameData : AtomicRefCounted {
  import teraflop.math : Size;

  Rc!Fence fence; // to keep track of when command processing is done
  Rc!CommandPool cmdPool;

  ImageBase swapChainColor;
  Size size;

  this(Device device, uint queueFamilyIndex, ImageBase swapChainColor) {
    import std.typecons : Yes;

    this.fence = device.createFence(Yes.signaled);
    this.cmdPool = device.createCommandPool(queueFamilyIndex);

    this.swapChainColor = swapChainColor;
    const dimensions = swapChainColor.info.dims;
    size = Size(dimensions.width, dimensions.height);
  }

  override void dispose() {
    fence.unload();
    cmdPool.unload();
  }
}
