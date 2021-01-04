/// Utilities for <a href="https://github.com/rtbo/gfx-d#readme">gfx</a> graphics library integration.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: MIT License
module teraflop.platform.vulkan;

import gfx.graal;
import gfx.vulkan;
import std.exception : enforce;
import teraflop.math : Size;

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

package (teraflop.platform) Instance instance;
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
    instance = createVulkanInstance(createInfo);
    instance.retain();
  } catch (Exception ex) {
    writeln(ex.msg);
    return false;
  }

  return true;
}
package (teraflop) void unloadVulkan() {
  instance.release();
}

private PhysicalDevice selectedPhysicalDevice;

package (teraflop) uint selectGraphicsQueue() {
  import std.conv : to;
  import std.algorithm : canFind, countUntil;

  auto findRequiredCap = (QueueFamily family, QueueCap requiredCap) => (family.cap & requiredCap) == requiredCap;

  foreach (physicalDevice; instance.devices) {
    if (physicalDevice.queueFamilies.canFind!(findRequiredCap)(QueueCap.graphics) == false) continue;
    selectedPhysicalDevice = physicalDevice;
    return physicalDevice.queueFamilies.countUntil!(findRequiredCap)(QueueCap.graphics).to!uint;
  }

  return -1;
}

package (teraflop) Device selectGraphicsDevice(uint queueFamilyIndex, Surface surface = null) {
  import std.exception : enforce;

  const error = "Cannot find a suitable graphics device! Try upgrading your graphics drivers.";

  if (surface !is null) enforce(selectedPhysicalDevice.supportsSurface(queueFamilyIndex, surface), error);
  return enforce(selectedPhysicalDevice.open([QueueRequest(queueFamilyIndex, [1.0f])]), error);
}

/// Return the index of a memory type supporting all of the given props.
private uint findMemoryType(PhysicalDevice physicalDevice, uint typeFilter, MemProps props = MemProps.deviceLocal) {
  const memoryProperties = physicalDevice.memoryProperties;
  for (uint i = 0, typeMask = 1; i < memoryProperties.types.length; i += 1, typeMask <<= 1) {
    auto memoryTypesMatch = (typeFilter & typeMask) != 0;
    auto memoryPropsMatch = (memoryProperties.types[i].props & props) == props;
    if (memoryTypesMatch && memoryPropsMatch) return i;
  }

  enforce(false, "Could not allocate GPU memory: Failed to find suitable GPU memory type!");
  assert(0);
}

package (teraflop) Buffer createBuffer(Device device, size_t size, BufferUsage usage, MemProps props) {
  auto buffer = device.createBuffer(usage, size);
  const memoryType = findMemoryType(device.physicalDevice, buffer.memoryRequirements.memTypeMask, props);
  auto memory = device.allocateMemory(memoryType, buffer.memoryRequirements.size);
  buffer.bindMemory(memory, 0);

  return buffer;
}

/// Create a buffer, bind memory to it, and leave content undefined.
/// The buffer will be host visible and host coherent such that content can be updated without a staging buffer.
package (teraflop) Buffer createDynamicBuffer(Device device, size_t size, BufferUsage usage) {
  return createBuffer(device, size, usage, MemProps.hostVisible | MemProps.hostCoherent);
}

package (teraflop) ImageBase createImage(Device device, Size size, Format format, ImageUsage usage) {
  auto image = device.createImage(ImageInfo.d2(size.width, size.height).withFormat(format).withUsage(usage));
  const memoryType = findMemoryType(device.physicalDevice, image.memoryRequirements.memTypeMask);
  auto memory = device.allocateMemory(memoryType, image.memoryRequirements.size).rc;
  image.bindMemory(memory, 0);
  return image;
}

/// Data that is duplicated for every frame in the swapchain.
/// This typically includes a framebuffer and command pool.
abstract class FrameData : AtomicRefCounted {
  import teraflop.math : Size;

  /// To keep track of when command processing is done.
  Rc!Fence fence;
  ///
  Rc!CommandPool cmdPool;
  ///
  ImageBase swapChainColor;
  /// Size of this frame's framebuffer.
  Size size;

  ///
  this(Device device, uint queueFamilyIndex, ImageBase swapChainColor) {
    import std.typecons : Yes;

    this.fence = device.createFence(Yes.signaled);
    this.cmdPool = device.createCommandPool(queueFamilyIndex);

    this.swapChainColor = swapChainColor;
    const dimensions = swapChainColor.info.dims;
    size = Size(dimensions.width, dimensions.height);
  }

  ///
  override void dispose() {
    fence.unload();
    cmdPool.unload();
  }
}

/// A factory for one time submission command buffers.
/// Generally used for transfer operations, or image layout change.
final class OneTimeCmdBufPool {
  private Queue graphicsQueue;
  private CommandPool pool;

  ///
  this(Device device, Queue graphicsQueue) {
    this.graphicsQueue = graphicsQueue;
    pool = device.createCommandPool(graphicsQueue.index);
  }
  ~this() {
    // TODO: Figure out why this is broken: pool.dispose();
  }

  /// Get a newly created command buffer.
  @property CommandBuffer get() {
    auto cmdBuf = pool.allocatePrimary(1)[0];
    cmdBuf.begin(CommandBufferUsage.oneTimeSubmit);
    return cmdBuf;
  }

  ///
  void submit(CommandBuffer cmdBuf) {
    cmdBuf.end();
    graphicsQueue.submit([
        Submission([], [], [cast(PrimaryCommandBuffer) cmdBuf])
    ], null);
    graphicsQueue.waitIdle();
    pool.free((&cmdBuf)[0 .. 1]);
  }
}
