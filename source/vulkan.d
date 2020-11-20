/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.vulkan;

import bindbc.glfw : GLFWwindow;
import erupted;
import erupted.vulkan_lib_loader;
import std.algorithm.iteration : map;
import std.algorithm.searching : any;
import std.array : array;
import std.conv : to;
import std.exception : enforce;
import std.string : toStringz;

import teraflop.components : IResource;
import teraflop.platform.window : Window;
import teraflop.math : Size;

// https://www.glfw.org/docs/3.3/vulkan_guide.html#vulkan_present
alias GLFWvkproc = void function();
extern(C) @nogc nothrow {
  private const(char)** glfwGetRequiredInstanceExtensions(uint*);
  private GLFWvkproc glfwGetInstanceProcAddress(VkInstance, const(char)*);
  private int glfwGetPhysicalDevicePresentationSupport(VkInstance,VkPhysicalDevice, uint);
  package (teraflop) VkResult glfwCreateWindowSurface(
    VkInstance, GLFWwindow*, const(VkAllocationCallbacks)*, VkSurfaceKHR*
  );
}

package (teraflop) void enforceVk(VkResult res) {
  enforce(res == VkResult.VK_SUCCESS, res.to!string);
}

package (teraflop) bool initVulkan() {
  return loadGlobalLevelFunctions();
}

// https://vulkan.lunarg.com/doc/view/1.1.114.0/windows/khronos_validation_layer.html
// VK_LAYER_KHRONOS_validation
private string[] validationLayers = [
  "VK_LAYER_GOOGLE_threading",
  "VK_LAYER_LUNARG_parameter_validation",
  "VK_LAYER_LUNARG_object_tracker",
  "VK_LAYER_LUNARG_core_validation",
  "VK_LAYER_GOOGLE_unique_objects"
];
debug {
  private enum bool enableValidationLayers = true;
} else {
  private enum bool enableValidationLayers = false;
}

package (teraflop) bool checkValidationLayerSupport() {
  import std.algorithm.iteration : filter;
  import std.algorithm.searching : all;
  import std.string : icmp, fromStringz;
  import std.stdio : writefln;
  import std.math : abs;
  import std.range : enumerate;

  uint layerCount;
  vkEnumerateInstanceLayerProperties(&layerCount, null);
  VkLayerProperties[] availableLayers = new VkLayerProperties[layerCount];
  vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.ptr);
  auto availableLayerNames = new string[layerCount];
  foreach (i, layer; availableLayers.enumerate()) {
    availableLayerNames[i] = fromStringz(layer.layerName.ptr).to!string;
  }

  if (availableLayerNames.any!(availableLayer => icmp(availableLayer, "VK_LAYER_KHRONOS_validation") == 0)) {
    validationLayers = new string[1];
    validationLayers[0] = "VK_LAYER_KHRONOS_validation";
  }

  return validationLayers.all!(layer => availableLayerNames.any!(availableLayer => icmp(availableLayer, layer) == 0));
}

private const string[] defaultDeviceExtensions = [VK_KHR_SWAPCHAIN_EXTENSION_NAME];

package (teraflop) final class Device {
  private VkInstance instance_;
  private VkDevice device = VK_NULL_HANDLE;
  private const string[] deviceExtensions;
  private VkPhysicalDevice physicalDevice_ = VK_NULL_HANDLE;
  private uint graphicsQueueFamilyIndex = uint.max;
  private VkCommandPool commandPool_;
  private VkCommandBuffer[] commandBuffers;
  private VkQueue presentQueue_;

  this(string appName, const string[] deviceExtensions = defaultDeviceExtensions) {
    this.deviceExtensions = deviceExtensions;

    // Create instance
    VkApplicationInfo appInfo = {
      pApplicationName: toStringz(appName),
      pEngineName: "Teraflop",
      engineVersion: VK_MAKE_VERSION(0, 1, 0),
      apiVersion: VK_MAKE_VERSION(1, 1, 0),
    };

    uint32_t glfwExtensionCount = 0;
    const char** glfwExtensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

    VkInstanceCreateInfo instanceCreateInfo = {
      pApplicationInfo: &appInfo,
      enabledLayerCount: 0,
      enabledExtensionCount: glfwExtensionCount,
      ppEnabledExtensionNames: glfwExtensions
    };

    if (enableValidationLayers) {
      auto hasReqs = checkValidationLayerSupport();
      enforce(hasReqs, "validation layers requested, but not available!");
      instanceCreateInfo.enabledLayerCount = validationLayers.length.to!uint;
      const layers = validationLayers.map!(layer => toStringz(layer)).array;
      instanceCreateInfo.ppEnabledLayerNames = layers.ptr;
    }

    enforceVk(vkCreateInstance(&instanceCreateInfo, null, &instance_));
    loadInstanceLevelFunctions(instance_);
  }

  ~this() {
    if (device != VK_NULL_HANDLE) {
      vkDeviceWaitIdle(device);
      vkDestroyCommandPool(device, commandPool_, null);
      vkDestroyDevice(device, null);
    }
    if (instance_ != VK_NULL_HANDLE) vkDestroyInstance(instance_, null);
  }

  bool ready() @property const {
    return device != VK_NULL_HANDLE && physicalDevice_ != VK_NULL_HANDLE;
  }

  VkInstance instance() @property const {
    return cast(VkInstance) instance_;
  }

  VkDevice handle() @property const {
    return cast(VkDevice) device;
  }
  VkPhysicalDevice physicalDevice() @property const {
    return cast(VkPhysicalDevice) physicalDevice_;
  }

  VkCommandPool commandPool() @property const {
    return cast(VkCommandPool) commandPool_;
  }

  // TODO: Rename this to `graphicsQueue`?
  VkQueue presentQueue() @property const {
    return cast(VkQueue) presentQueue_;
  }

  void acquire() {
    // Acquire graphics device
    uint numPhysicalDevices;
    enforceVk(vkEnumeratePhysicalDevices(instance_, &numPhysicalDevices, null));
    assert(numPhysicalDevices > 0);
    auto physicalDevices = new VkPhysicalDevice[](numPhysicalDevices);
	  enforceVk(vkEnumeratePhysicalDevices(instance_, &numPhysicalDevices, physicalDevices.ptr));
    physicalDevice_ = physicalDevices[0];

    // Pick the queue that supports presentation over GLFW
    uint numQueues;
    vkGetPhysicalDeviceQueueFamilyProperties(physicalDevices[0], &numQueues, null);
    assert(numQueues >= 1);
    auto queueFamilyProperties = new VkQueueFamilyProperties[numQueues];
    vkGetPhysicalDeviceQueueFamilyProperties(physicalDevices[0], &numQueues, queueFamilyProperties.ptr);
    for (auto i = 0; i < numQueues; i += 1) {
      // Presumably, this checks for VK_QUEUE_GRAPHICS_BIT
      if (glfwGetPhysicalDevicePresentationSupport(instance_, physicalDevices[0], i)) {
        assert(queueFamilyProperties[i].queueCount >= 1);
        graphicsQueueFamilyIndex = i.to!uint;
      }
    }
    // Use first queue if no graphics queue was found
    // TODO: Is this correct?
    if (graphicsQueueFamilyIndex == uint.max) graphicsQueueFamilyIndex = 0;

    // Create the logical device
    const float[1] queuePriorities = [ 1.0f ];
    VkDeviceQueueCreateInfo queueCreateInfo = {
      queueFamilyIndex: graphicsQueueFamilyIndex,
      queueCount: 1,
      pQueuePriorities: queuePriorities.ptr,
    };
    VkPhysicalDeviceFeatures deviceFeatures = {
      samplerAnisotropy: VK_TRUE,
    };
    const enabledExtensions = deviceExtensions.map!(name => toStringz(name)).array;
    VkDeviceCreateInfo deviceCreateInfo = {
      queueCreateInfoCount: 1,
      pQueueCreateInfos: &queueCreateInfo,
      pEnabledFeatures: &deviceFeatures,
      enabledExtensionCount: deviceExtensions.length.to!uint,
      ppEnabledExtensionNames: enabledExtensions.ptr,
    };
    enforceVk(vkCreateDevice(physicalDevices[0], &deviceCreateInfo, null, &device));
    loadDeviceLevelFunctions(device);

    // Create the command buffer pool
    VkCommandPoolCreateInfo poolInfo = {
      queueFamilyIndex: graphicsQueueFamilyIndex,
      flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, // Graphics command buffers may be reset
      // TODO: In a separate _transient_ command pool, set the VK_COMMAND_POOL_CREATE_TRANSIENT_BIT
    };
    enforceVk(vkCreateCommandPool(device, &poolInfo, null, &commandPool_));

    // Get the command buffer queue
    vkGetDeviceQueue(device, graphicsQueueFamilyIndex, 0, &presentQueue_);
  }

  SwapChain createSwapChain(const Surface surface, const Size framebufferSize, const SwapChain oldSwapChain = null) {
    import teraflop.graphics : Color;

    VkBool32 supported = VK_FALSE;
    enforceVk(vkGetPhysicalDeviceSurfaceSupportKHR(
      physicalDevice_, graphicsQueueFamilyIndex, surface.surfaceKhr, &supported
    ));
    enforce(supported == VK_TRUE, "Surface is not supported for presentation");
    auto swapChain = new SwapChain(this, surface, framebufferSize, oldSwapChain);

    // Setup default command buffer
    auto commands = createCommandBuffer(swapChain);
    auto clearColor = Color.black.toVulkan;
    commands.beginRenderPass(&clearColor);
    commands.endRenderPass();

    return swapChain;
  }

  Buffer createBuffer(ulong size, BufferUsage usage = BufferUsage.vertexBuffer) const {
    return new Buffer(this, size, usage);
  }

  CommandBuffer createCommandBuffer(SwapChain swapChain) {
    return swapChain.presentationCommands = new CommandBuffer(
      this, swapChain.framebuffers, swapChain.extent, swapChain.presentationPass
    );
  }

  CommandBuffer createSingleTimeCommandBuffer() inout {
    return new CommandBuffer(this);
  }
}

package (teraflop) class Surface {
  private VkInstance instance;
  private VkSurfaceKHR surface_;

  this(VkInstance instance, VkSurfaceKHR surface) {
    this.instance = instance;
    this.surface_ = surface;
  }

  ~this() {
    vkDestroySurfaceKHR(instance, surface_, null);
  }

  static Surface fromGlfw(VkInstance instance, GLFWwindow* window) {
    VkSurfaceKHR surface;
    enforceVk(glfwCreateWindowSurface(instance, window, null, &surface));
    return new Surface(instance, surface);
  }

  VkSurfaceKHR surfaceKhr() @property const {
    return cast(VkSurfaceKHR) surface_;
  }
}

// https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_KHR_swapchain.html
package (teraflop) final class SwapChain {
  import std.algorithm.iteration : filter, joiner, map;
  import std.array : array;
  import teraflop.graphics : Material;

  const int MAX_FRAMES_IN_FLIGHT = 2;

  private Device device;
  private const VkSurfaceFormatKHR surfaceFormat = {
    format: VK_FORMAT_B8G8R8A8_SRGB,
    colorSpace: VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
  };
  private VkPresentModeKHR presentMode;
  package VkExtent2D extent;
  private VkSwapchainKHR handle;
  private VkImage[] swapChainImages;
  private VkImageView[] imageViews;
  package (teraflop) RenderPass presentationPass_;
  private VkFramebuffer[] framebuffers;
  package CommandBuffer presentationCommands;
  private VkDescriptorPool descriptorPool;
  private VkDescriptorSetLayout[] descriptorSetLayouts;
  private VkDescriptorSet[] descriptorSets;
  private BindingGroup[] descriptorGroups;
  private Buffer[] uniformBuffers;
  private Pipeline[const Material] pipelines;
  private VkSemaphore[MAX_FRAMES_IN_FLIGHT] imageAvailableSemaphores;
  private VkSemaphore[MAX_FRAMES_IN_FLIGHT] renderFinishedSemaphores;
  private VkFence[MAX_FRAMES_IN_FLIGHT] inFlightFences;
  private VkFence[] imagesInFlight;
  private auto dirty_ = false;
  private auto currentFrame = 0;

  this(Device device, const Surface surface, const Size framebufferSize, const SwapChain oldSwapChain = null) {
    this.device = device;

    SupportDetails details = getSupportDetails(device, surface);
    presentMode = choosePresentMode(details.presentModes);
    extent = chooseExtent(details.capabilities, framebufferSize);
    presentationPass_ = new RenderPass(device);

    uint imageCount = details.capabilities.minImageCount + 1;
    if (details.capabilities.maxImageCount > 0 && imageCount > details.capabilities.maxImageCount)
      imageCount = details.capabilities.maxImageCount;

    VkSwapchainCreateInfoKHR createInfo = {
      surface: surface.surfaceKhr,
      minImageCount: imageCount,
      imageFormat: surfaceFormat.format,
      imageColorSpace: surfaceFormat.colorSpace,
      imageExtent: extent,
      imageArrayLayers: 1,
      imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
      imageSharingMode: VK_SHARING_MODE_EXCLUSIVE,
      queueFamilyIndexCount: 0,
      pQueueFamilyIndices: null,
      preTransform: details.capabilities.currentTransform,
      compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
      presentMode: presentMode,
      clipped: VK_TRUE,
      oldSwapchain: oldSwapChain is null ? VK_NULL_HANDLE : cast(VkSwapchainKHR) oldSwapChain.handle,
    };
    enforceVk(vkCreateSwapchainKHR(device.handle, &createInfo, null, &handle));

    // Get the swap chain's images
    vkGetSwapchainImagesKHR(device.handle, handle, &imageCount, null);
    swapChainImages = new VkImage[imageCount];
    vkGetSwapchainImagesKHR(device.handle, handle, &imageCount, swapChainImages.ptr);

    // Create image views for the swap chain's images
    imageViews = new VkImageView[imageCount];
    for (auto i = 0; i < imageCount; i += 1) {
      VkImageViewCreateInfo view = {
        image: swapChainImages[i],
        viewType: VK_IMAGE_VIEW_TYPE_2D,
        format: surfaceFormat.format,
      };
      view.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
      view.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
      view.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
      view.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
      view.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
      view.subresourceRange.baseMipLevel = 0;
      view.subresourceRange.levelCount = 1;
      view.subresourceRange.baseArrayLayer = 0;
      view.subresourceRange.layerCount = 1;
      enforceVk(vkCreateImageView(device.handle, &view, null, &imageViews[i]));
    }

    // Create frame buffers for the swap chain's images
    framebuffers = new VkFramebuffer[imageViews.length];
    for (auto i = 0; i < imageViews.length; i += 1) {
      VkFramebufferCreateInfo framebufferInfo = {
        renderPass: presentationPass_.handle,
        attachmentCount: 1,
        pAttachments: &imageViews[i],
        width: extent.width,
        height: extent.height,
        layers: 1,
      };

      enforceVk(vkCreateFramebuffer(device.handle, &framebufferInfo, null, &framebuffers[i]));
    }

    // Create the swap chain's descriptor pool, for UBOs and whatnot
    VkDescriptorPoolSize poolSize = {
      descriptorCount: swapChainImages.length.to!uint,
    };
    VkDescriptorPoolCreateInfo poolInfo = {
      poolSizeCount: 1,
      pPoolSizes: &poolSize,
      maxSets: swapChainImages.length.to!uint,
      flags: VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    };
    enforceVk(vkCreateDescriptorPool(device.handle, &poolInfo, null, &descriptorPool));

    // Create the swap chain's synchronization primitives
    VkSemaphoreCreateInfo semaphoreInfo;
    VkFenceCreateInfo fenceInfo = {flags: VK_FENCE_CREATE_SIGNALED_BIT};
    imagesInFlight = new VkFence[imageCount];
    for (auto i = 0; i < imageCount; i += 1) {
      if (i < MAX_FRAMES_IN_FLIGHT) {
        enforceVk(vkCreateSemaphore(device.handle, &semaphoreInfo, null, &imageAvailableSemaphores[i]));
        enforceVk(vkCreateSemaphore(device.handle, &semaphoreInfo, null, &renderFinishedSemaphores[i]));
        enforceVk(vkCreateFence(device.handle, &fenceInfo, null, &inFlightFences[i]));
      }
      imagesInFlight[i] = VK_NULL_HANDLE;
    }

    if (oldSwapChain !is null) {
      vkDeviceWaitIdle(device.handle);
      destroy(oldSwapChain);
    }
  }

  ~this() {
    vkDeviceWaitIdle(device.handle);
    foreach (framebuffer; framebuffers)
      vkDestroyFramebuffer(device.handle, framebuffer, null);
    destroy(presentationCommands);
    foreach (pipeline; pipelines.values)
      destroy(pipeline);
    destroy(presentationPass_);
    foreach (imageView; imageViews)
      vkDestroyImageView(device.handle, imageView, null);
    vkDestroyDescriptorPool(device.handle, descriptorPool, null);
    foreach (descriptorSetLayout; descriptorSetLayouts)
      vkDestroyDescriptorSetLayout(device.handle, descriptorSetLayout, null);
    foreach (buffer; uniformBuffers)
      destroy(buffer);
    for (auto i = 0; i < MAX_FRAMES_IN_FLIGHT; i += 1) {
      vkDestroySemaphore(device.handle, renderFinishedSemaphores[i], null);
      vkDestroySemaphore(device.handle, imageAvailableSemaphores[i], null);
      vkDestroyFence(device.handle, inFlightFences[i], null);
    }
    vkDestroySwapchainKHR(device.handle, handle, null);
  }

  bool ready() @property const {
    return presentationCommands !is null;
  }

  const(RenderPass) presentationPass() @property const {
    return presentationPass_;
  }

  inout(CommandBuffer) commandBuffer() @property inout {
    return presentationCommands;
  }

  bool hasPipeline(const Material material) {
    return (material in pipelines) !is null;
  }
  const(Pipeline) pipelineOf(const Material material) {
    assert(hasPipeline(material));
    return pipelines[material];
  }
  const(Pipeline) trackPipeline(const Material material, const PipelineLayout layout) {
    descriptorGroups ~= layout.bindingGroups;

    // Recreate descriptor sets and uniform buffers to fit new pipeline's descriptor layout
    vkDeviceWaitIdle(device.handle);
    if (descriptorSets.length)
      vkFreeDescriptorSets(device.handle, descriptorPool, descriptorSets.length.to!uint, descriptorSets.ptr);
    foreach (descriptorSetLayout; descriptorSetLayouts)
      vkDestroyDescriptorSetLayout(device.handle, descriptorSetLayout, null);
    foreach (buffer; uniformBuffers)
      destroy(buffer);
    descriptorSetLayouts = new VkDescriptorSetLayout[0];
    createDescriptorSets();
    presentationCommands.descriptorSets = descriptorSets;

    return pipelines[material] = new Pipeline(
      device, extent, presentationPass_, material, layout, descriptorSetLayouts
    );
  }

  bool dirty() @property const {
    return dirty_;
  }

  private void createDescriptorSets() {
    import std.algorithm.iteration : sum;
    import std.range : enumerate, repeat;

    if (descriptorGroups.length == 0) return;

    descriptorSetLayouts = descriptorGroups.map!(group => {
      const descriptorLayoutBindings = group.bindings.map!(descriptor => {
        VkDescriptorSetLayoutBinding descriptorLayout = {
          binding: descriptor.bindingLocation,
          descriptorType: descriptor.bindingType,
          descriptorCount: 1,
          stageFlags: descriptor.shaderStage,
          pImmutableSamplers: null,
        };
        return descriptorLayout;
      }()).array;

      VkDescriptorSetLayoutCreateInfo layoutInfo = {
        bindingCount: descriptorLayoutBindings.length.to!uint,
        pBindings: descriptorLayoutBindings.ptr,
      };
      VkDescriptorSetLayout setLayout;
      enforceVk(vkCreateDescriptorSetLayout(device.handle, &layoutInfo, null, &setLayout));
      return setLayout;
    }()).array;

    // Create a uniform buffer for each swap chain image
    uniformBuffers = new Buffer[swapChainImages.length];
    const size_t size = descriptorGroups
      .map!(group => group.bindings.filter!(b => b.bindingType == BindingType.uniform).map!(u => u.size))
      .joiner.sum;
    for (size_t i = 0; i < swapChainImages.length; i += 1) {
      uniformBuffers[i] = new Buffer(device, size, BufferUsage.uniformBuffer);
    }

    const layouts = descriptorSetLayouts.repeat(swapChainImages.length).joiner.array;
    descriptorSets = new VkDescriptorSet[swapChainImages.length];
    VkDescriptorSetAllocateInfo allocInfo = {
      descriptorPool: descriptorPool,
      descriptorSetCount: layouts.length.to!uint,
      pSetLayouts: layouts.ptr,
    };
    enforceVk(vkAllocateDescriptorSets(device.handle, &allocInfo, descriptorSets.ptr));

    const(VkWriteDescriptorSet)[] descriptorWrites;
    for (size_t i = 0; i < swapChainImages.length; i += 1) {
      foreach (v, group; descriptorGroups.enumerate()) {
        descriptorWrites ~= group.bindings.map!(binding => binding.descriptorWrite(
          descriptorSets[i + v], uniformBuffers[i]
        )).array;
      }
    }
    vkUpdateDescriptorSets(device.handle, descriptorWrites.length.to!uint, descriptorWrites.ptr, 0, null);
  }

  void drawFrame() {
    import std.algorithm.mutation : copy;

    assert(ready);
    assert(presentationCommands.handles.length == swapChainImages.length);

    vkWaitForFences(device.handle, 1, &inFlightFences[currentFrame], VK_TRUE, ulong.max);

    uint imageIndex;
    VkResult result = vkAcquireNextImageKHR(
      device.handle, handle, ulong.max, imageAvailableSemaphores[currentFrame], VK_NULL_HANDLE, &imageIndex
    );

    if (result == VK_ERROR_OUT_OF_DATE_KHR) return;
    enforce(result == VK_SUCCESS || result == VK_SUBOPTIMAL_KHR, "Failed to acquire swap chain image!");

    // Check if a previous frame is using this image, i.e. it has a fence to wait on
    if (imagesInFlight[imageIndex] != VK_NULL_HANDLE) {
      vkWaitForFences(device.handle, 1, &imagesInFlight[imageIndex], VK_TRUE, ulong.max);
    }
    // Mark the image as now being in use by this frame
    imagesInFlight[imageIndex] = inFlightFences[currentFrame];

    const commandBuffer = presentationCommands.handles[imageIndex];

    if (uniformBuffers.length) {
      // TODO: Only blit dirty uniforms?
      byte[] uniformData;
      auto uniforms = descriptorGroups
        .map!(group => group.bindings.filter!(b => b.bindingType == BindingType.uniform))
        .joiner;
      foreach (uniform; uniforms)
        uniformData ~= uniform.data;
      const unfilled = uniformData.copy(uniformBuffers[imageIndex].map());
      assert(unfilled.length == 0);
      uniformBuffers[imageIndex].unmap();
    }

    VkSubmitInfo submitInfo;
    const VkSemaphore[] waitSemaphores = [imageAvailableSemaphores[currentFrame]];
    const VkPipelineStageFlags[] waitStages = [VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT];
    submitInfo.waitSemaphoreCount = 1;
    submitInfo.pWaitSemaphores = waitSemaphores.ptr;
    submitInfo.pWaitDstStageMask = waitStages.ptr;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &commandBuffer;
    const VkSemaphore[] signalSemaphores = [renderFinishedSemaphores[currentFrame]];
    submitInfo.signalSemaphoreCount = 1;
    submitInfo.pSignalSemaphores = signalSemaphores.ptr;

    vkResetFences(device.handle, 1, &inFlightFences[currentFrame]);
    enforceVk(vkQueueSubmit(device.presentQueue, 1, &submitInfo, inFlightFences[currentFrame]));

    const VkSwapchainKHR[] swapChains = [handle];
    VkPresentInfoKHR presentInfo = {
      waitSemaphoreCount: 1,
      pWaitSemaphores: signalSemaphores.ptr,
      swapchainCount: 1,
      pSwapchains: swapChains.ptr,
      pImageIndices: &imageIndex,
      pResults: null,
    };
    result = vkQueuePresentKHR(device.presentQueue, &presentInfo);

    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR) {
      dirty_ = true;
    } else enforce(result == VK_SUCCESS, "Failed to present swap chain image!");

    currentFrame = (currentFrame + 1) % MAX_FRAMES_IN_FLIGHT;
  }

  static bool supported(const Device device, const Surface surface) {
    SupportDetails details = getSupportDetails(device, surface);

    // Require VK_FORMAT_B8G8R8A8_SRGB (BGRA8 is what Ultrlight uses)
    return details.formats.any!(availableFormat =>
      availableFormat.format == VK_FORMAT_B8G8R8A8_SRGB &&
      availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR
    ) && details.presentModes.length;
  }

  private struct SupportDetails {
    VkSurfaceCapabilitiesKHR capabilities;
    VkSurfaceFormatKHR[] formats;
    VkPresentModeKHR[] presentModes;
  }

  private static SupportDetails getSupportDetails(const Device device, const Surface surface) {
    auto physicalDevice = device.physicalDevice;
    auto surfaceKhr = surface.surfaceKhr;

    SupportDetails details;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surfaceKhr, &details.capabilities);
    // Get supported texture formats
    uint formatCount;
    vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surfaceKhr, &formatCount, null);
    if (formatCount) {
      details.formats = new VkSurfaceFormatKHR[formatCount];
      vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surfaceKhr, &formatCount, details.formats.ptr);
    }
    // Get supported present modes
    uint presentModeCount;
    vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surfaceKhr, &presentModeCount, null);
    if (presentModeCount != 0) {
      details.presentModes = new VkPresentModeKHR[presentModeCount];
      vkGetPhysicalDeviceSurfacePresentModesKHR(
        physicalDevice, surfaceKhr, &presentModeCount, details.presentModes.ptr
      );
    }

    return details;
  }

  private VkPresentModeKHR choosePresentMode(VkPresentModeKHR[] availablePresentModes) {
    foreach (availablePresentMode; availablePresentModes) {
      if (availablePresentMode == VK_PRESENT_MODE_MAILBOX_KHR) return availablePresentMode;
    }

    return VK_PRESENT_MODE_FIFO_KHR;
  }

  private VkExtent2D chooseExtent(const VkSurfaceCapabilitiesKHR capabilities, Size framebufferSize) {
    import std.algorithm.comparison : max, min;

    if (capabilities.currentExtent.width != uint.max) {
      return capabilities.currentExtent;
    } else {
      auto actualExtent = VkExtent2D(framebufferSize.width, framebufferSize.height);
      actualExtent.width = max(
        capabilities.minImageExtent.width,
        min(capabilities.maxImageExtent.width, actualExtent.width)
      );
      actualExtent.height = max(
        capabilities.minImageExtent.height,
        min(capabilities.maxImageExtent.height, actualExtent.height)
      );

      return actualExtent;
    }
  }
}

/// Allowed usage of a buffer. May be used in bitwise combinations.
enum BufferUsage : VkBufferUsageFlagBits {
  /// Buffer can be used as source in a memory transfer operation.
  transferSrc = VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
  /// Buffer can be used as destination in a memory transfer operation.
  transferDst = VK_BUFFER_USAGE_TRANSFER_DST_BIT,
  uniformTexelBuffer = VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT,
  storageTexelBuffer = VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT,
  uniformBuffer = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
  storageBuffer = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
  indexBuffer = VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
  vertexBuffer = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
  indirectBuffer = VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT,
}

package (teraflop) class Buffer {
  const BufferUsage usage;
  private const Device device;
  private VkBufferCreateInfo bufferInfo;
  private VkBuffer buffer = VK_NULL_HANDLE;
  private VkDeviceMemory bufferMemory = VK_NULL_HANDLE;

  this(const Device device, ulong size, BufferUsage usage = BufferUsage.vertexBuffer, bool hostVisible = true) {
    this.device = device;
    this.usage = usage;

    bufferInfo.size = size;
    bufferInfo.usage = usage;
    bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    enforceVk(vkCreateBuffer(device.handle, &bufferInfo, null, &buffer));

    VkMemoryRequirements memRequirements;
    vkGetBufferMemoryRequirements(device.handle, buffer, &memRequirements);

    VkMemoryAllocateInfo allocInfo = {
      allocationSize: memRequirements.size,
      memoryTypeIndex: findMemoryType(
        device,
        memRequirements.memoryTypeBits,
        hostVisible
          ? VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
          : VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
      ),
    };
    enforceVk(vkAllocateMemory(device.handle, &allocInfo, null, &bufferMemory));

    vkBindBufferMemory(device.handle, buffer, bufferMemory, 0);
  }

  ~this() {
    vkDestroyBuffer(device.handle, buffer, null);
    vkFreeMemory(device.handle, bufferMemory, null);
  }

  VkBuffer handle() @property const {
    return cast(VkBuffer) buffer;
  }

  bool ready() @property const {
    return buffer != VK_NULL_HANDLE && bufferMemory != VK_NULL_HANDLE;
  }

  ulong size() @property const {
    return bufferInfo.size;
  }

  ubyte[] map(ulong offset = 0, ulong size = VK_WHOLE_SIZE) {
    ubyte* data;
    enforceVk(vkMapMemory(device.handle, bufferMemory, offset, size, 0, cast(void**) &data));
    const mappedSize = size == VK_WHOLE_SIZE ? bufferInfo.size : size;
    return data[0 .. mappedSize];
  }

  void unmap() {
    vkUnmapMemory(device.handle, bufferMemory);
  }
}

package (teraflop) enum ImageUsage : VkImageUsageFlagBits {
  transferDst = VK_IMAGE_USAGE_TRANSFER_DST_BIT,
  sampled = VK_IMAGE_USAGE_SAMPLED_BIT,
  colorAttachment = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
}

package (teraflop) enum ImageLayoutTransition {
  undefinedToTransferOptimal,
  transferOptimalToShaderReadOnlyOptimal
}

package (teraflop) class Image {
  const Size size;
  const uint mipLevels;
  const uint arrayLayers;
  const VkExtent3D extent;

  private const Device device;
  private VkImage image;
  private VkDeviceMemory imageMemory;
  private VkImageView imageView;

  static const defaultUsage = ImageUsage.transferDst | ImageUsage.sampled;

  this(const Device device, const Size size, const ImageUsage usage = defaultUsage) {
    this.size = size;
    this.device = device;

    VkImageCreateInfo imageInfo = {
      imageType: VK_IMAGE_TYPE_2D,
      format: VK_FORMAT_B8G8R8A8_SRGB,
      mipLevels: 1,
      arrayLayers: 1,
      tiling: VK_IMAGE_TILING_OPTIMAL,
      initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
      usage: usage,
      sharingMode: VK_SHARING_MODE_EXCLUSIVE,
      samples: VK_SAMPLE_COUNT_1_BIT,
    };
    imageInfo.extent.width = cast(uint) size.width;
    imageInfo.extent.height = cast(uint) size.height;
    imageInfo.extent.depth = 1;

    this.mipLevels = imageInfo.mipLevels;
    this.arrayLayers = imageInfo.arrayLayers;
    this.extent = imageInfo.extent;

    enforceVk(vkCreateImage(device.handle, &imageInfo, null, &image));

    VkMemoryRequirements memRequirements;
    vkGetImageMemoryRequirements(device.handle, image, &memRequirements);

    VkMemoryAllocateInfo allocInfo = {
      allocationSize: memRequirements.size,
      memoryTypeIndex: findMemoryType(device, memRequirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
    };
    enforceVk(vkAllocateMemory(device.handle, &allocInfo, null, &imageMemory));

    vkBindImageMemory(device.handle, image, imageMemory, 0);

    // Create default image view
    VkImageViewCreateInfo viewInfo = {
      image: image,
      viewType: VK_IMAGE_VIEW_TYPE_2D,
      format: imageInfo.format,
    };
    viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    viewInfo.subresourceRange.baseMipLevel = 0;
    viewInfo.subresourceRange.levelCount = mipLevels;
    viewInfo.subresourceRange.baseArrayLayer = 0;
    viewInfo.subresourceRange.layerCount = arrayLayers;
    enforceVk(vkCreateImageView(device.handle, &viewInfo, null, &imageView));
  }

  ~this() {
    vkDestroyImageView(device.handle, imageView, null);

    vkDestroyImage(device.handle, image, null);
    vkFreeMemory(device.handle, imageMemory, null);
  }

  VkImage handle() @property const {
    return cast(VkImage) image;
  }

  VkImageView defaultView() @property const {
    return cast(VkImageView) imageView;
  }
}

package (teraflop) class Sampler {
  private const Device device;
  private VkSampler sampler;

  this(const Device device) {
    this.device = device;

    VkSamplerCreateInfo samplerInfo = {
      magFilter: VK_FILTER_LINEAR,
      minFilter: VK_FILTER_LINEAR,
      addressModeU: VK_SAMPLER_ADDRESS_MODE_REPEAT,
      addressModeV: VK_SAMPLER_ADDRESS_MODE_REPEAT,
      addressModeW: VK_SAMPLER_ADDRESS_MODE_REPEAT,
      anisotropyEnable: VK_TRUE,
      maxAnisotropy: 16.0f,
      borderColor: VK_BORDER_COLOR_INT_OPAQUE_BLACK,
      unnormalizedCoordinates: VK_FALSE,
      compareEnable: VK_FALSE,
      compareOp: VK_COMPARE_OP_ALWAYS,
      mipmapMode: VK_SAMPLER_MIPMAP_MODE_LINEAR,
      mipLodBias: 0.0f,
      minLod: 0.0f,
      maxLod: 0.0f,
    };
    enforceVk(vkCreateSampler(device.handle, &samplerInfo, null, &sampler));
  }

  ~this() {
    vkDestroySampler(device.handle, sampler, null);
  }

  VkSampler handle() @property const {
    return cast(VkSampler) sampler;
  }
}

private uint findMemoryType(const Device device, uint typeFilter, VkMemoryPropertyFlags properties) {
  VkPhysicalDeviceMemoryProperties memProperties;
  vkGetPhysicalDeviceMemoryProperties(device.physicalDevice, &memProperties);

  for (uint i = 0; i < memProperties.memoryTypeCount; i += 1) {
    if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
      return i;
    }
  }

  enforce(false, "Failed to find suitable GPU memory type!");
  assert(0);
}

package (teraflop) class CommandBuffer {
  private const Device device;
  private const RenderPass presentationPass = null;
  private const VkFramebuffer[] framebuffers = [];
  private const VkExtent2D extent = VkExtent2D();
  private VkDescriptorSet[] descriptorSets_;
  private VkCommandBuffer[] commandBuffers;

  /// Create a one-time use command buffer
  this(const Device device) {
    this.device = device;

    commandBuffers = new VkCommandBuffer[1];
    VkCommandBufferAllocateInfo allocInfo = {
      commandPool: device.commandPool,
      level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
      commandBufferCount: commandBuffers.length.to!uint,
    };
    enforceVk(vkAllocateCommandBuffers(device.handle, &allocInfo, commandBuffers.ptr));

    VkCommandBufferBeginInfo beginInfo = {
      flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    enforceVk(vkBeginCommandBuffer(commandBuffers[0], &beginInfo));
  }

  this(
    const Device device, const VkFramebuffer[] framebuffers, const VkExtent2D extent, const RenderPass presentationPass
  ) {
    this.device = device;
    this.presentationPass = presentationPass;
    this.framebuffers = framebuffers;
    this.extent = extent;

    commandBuffers = new VkCommandBuffer[framebuffers.length];
    VkCommandBufferAllocateInfo allocInfo = {
      commandPool: device.commandPool,
      level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
      commandBufferCount: commandBuffers.length.to!uint,
    };
    enforceVk(vkAllocateCommandBuffers(device.handle, &allocInfo, commandBuffers.ptr));
  }

  ~this() {
    vkFreeCommandBuffers(device.handle, device.commandPool, commandBuffers.length.to!uint, commandBuffers.ptr);
  }

  VkCommandBuffer[] handles() @property const {
    return cast(VkCommandBuffer[]) commandBuffers;
  }

  package void descriptorSets(VkDescriptorSet[] value) @property {
    descriptorSets_ = value;
  }

  void flush() {
    for (auto i = 0; i < commandBuffers.length; i += 1)
      vkEndCommandBuffer(commandBuffers[i]);

    VkSubmitInfo submitInfo = {
      commandBufferCount: commandBuffers.length.to!uint,
      pCommandBuffers: commandBuffers.ptr,
    };

    vkQueueSubmit(device.presentQueue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(device.presentQueue);
  }

  void copyBuffer(const Buffer source, const Buffer destination, size_t size) {
    for (auto i = 0; i < commandBuffers.length; i += 1) {
      VkBufferCopy copyRegion = { size: size };
      vkCmdCopyBuffer(commandBuffers[i], source.handle, destination.handle, 1, &copyRegion);
    }
  }

  void transitionImageLayout(const Image image, ImageLayoutTransition transition) {
    VkImageLayout oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    VkImageLayout newLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    switch (transition) {
      case ImageLayoutTransition.undefinedToTransferOptimal:
        newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        break;
      case ImageLayoutTransition.transferOptimalToShaderReadOnlyOptimal:
        oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        break;
      default:
        enforce(0, "Unsupported layout transition!");
        break;
    }

    VkImageMemoryBarrier barrier = {
      oldLayout: oldLayout,
      newLayout: newLayout,
      srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
      dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
      image: image.handle,
    };
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = image.mipLevels;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = image.arrayLayers;

    VkPipelineStageFlags sourceStage;
    VkPipelineStageFlags destinationStage;

    if (transition == ImageLayoutTransition.undefinedToTransferOptimal) {
      barrier.srcAccessMask = 0;
      barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

      sourceStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
      destinationStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (transition == ImageLayoutTransition.transferOptimalToShaderReadOnlyOptimal) {
      barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
      barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

      sourceStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
      destinationStage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    }

    for (auto i = 0; i < commandBuffers.length; i += 1)
      vkCmdPipelineBarrier(
        commandBuffers[i],
        sourceStage, destinationStage,
        0,
        0, null,
        0, null,
        1, &barrier
      );
  }

  void copyBufferToImage(const Buffer buffer, const Image image) {
    VkBufferImageCopy region = {
      bufferOffset: 0,
      bufferRowLength: 0,
      bufferImageHeight: 0,
    };
    region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.mipLevel = 0;
    region.imageSubresource.baseArrayLayer = 0;
    region.imageSubresource.layerCount = image.arrayLayers;

    region.imageOffset = VkOffset3D(0, 0, 0);
    region.imageExtent = image.extent;

    for (auto i = 0; i < commandBuffers.length; i += 1)
      vkCmdCopyBufferToImage(
        commandBuffers[i], buffer.handle, image.handle, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region
      );
  }

  void beginRenderPass(VkClearValue* clearColor = null) {
    assert(presentationPass !is null);
    assert(framebuffers.length);
    assert(commandBuffers.length == framebuffers.length);

    for (auto i = 0; i < commandBuffers.length; i += 1) {
      VkCommandBufferBeginInfo beginInfo;
      enforceVk(vkBeginCommandBuffer(commandBuffers[i], &beginInfo));

      VkRenderPassBeginInfo renderPassInfo = {
        renderPass: presentationPass.handle,
        framebuffer: cast(VkFramebuffer) framebuffers[i],
      };
      renderPassInfo.renderArea.offset = VkOffset2D(0, 0);
      renderPassInfo.renderArea.extent = cast(VkExtent2D) extent;
      if (clearColor !is null) {
        renderPassInfo.clearValueCount = 1;
        renderPassInfo.pClearValues = clearColor;
      }
      vkCmdBeginRenderPass(commandBuffers[i], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
    }
  }

  void endRenderPass() {
    foreach (buffer; commandBuffers) {
      vkCmdEndRenderPass(buffer);
      enforceVk(vkEndCommandBuffer(buffer));
    }
  }

  void bindPipeline(const Pipeline pipeline) {
    foreach (buffer; commandBuffers)
      vkCmdBindPipeline(buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.handle);
    if (descriptorSets_.length)
      for (auto i = 0; i < commandBuffers.length; i += 1)
        vkCmdBindDescriptorSets(
          commandBuffers[i], VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipelineLayout,
          0, 1, &descriptorSets_[i], 0, null
        );
  }

  void bindVertexBuffers(const(Buffer[]) buffers ...) {
    import std.algorithm.iteration : map;
    import std.array : array;

    debug {
      foreach (buffer; buffers)
        assert((buffer.usage & BufferUsage.vertexBuffer) == BufferUsage.vertexBuffer);
    }

    auto bufferHandles = buffers.map!(buf => buf.handle).array;
    VkDeviceSize[1] offsets = [0];
    foreach (buffer; commandBuffers)
      vkCmdBindVertexBuffers(buffer, 0, 1, bufferHandles.ptr, offsets.ptr);
  }

  void bindIndexBuffer(const Buffer indexBuffer) {
    assert((indexBuffer.usage & BufferUsage.indexBuffer) == BufferUsage.indexBuffer);

    foreach (buffer; commandBuffers)
      vkCmdBindIndexBuffer(buffer, indexBuffer.handle, 0, VK_INDEX_TYPE_UINT32);
  }

  void draw(uint vertexCount, uint instanceCount, uint firstVertex, uint firstInstance) {
    foreach (buffer; commandBuffers)
      vkCmdDraw(buffer, vertexCount, instanceCount, firstVertex, firstInstance);
  }

  void drawIndexed(uint indexCount, uint instanceCount, uint firstIndex, uint indexOffset, uint firstInstance) {
    foreach (buffer; commandBuffers)
      vkCmdDrawIndexed(buffer, indexCount, instanceCount, firstIndex, indexOffset, firstInstance);
  }
}

package (teraflop) class RenderPass {
  private const Device device;
  private VkRenderPass renderPass = VK_NULL_HANDLE;

  this(const Device device) {
    this.device = device;

    VkAttachmentDescription colorAttachment = {
      format: VK_FORMAT_B8G8R8A8_SRGB,
      samples: VK_SAMPLE_COUNT_1_BIT,
      loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
      storeOp: VK_ATTACHMENT_STORE_OP_STORE,
      stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
      stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
      initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
      finalLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };
    VkAttachmentReference colorAttachmentRef = {
      attachment: 0,
      layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    VkSubpassDescription subpass = {
      pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
      colorAttachmentCount: 1,
      pColorAttachments: &colorAttachmentRef,
    };

    VkRenderPassCreateInfo renderPassInfo = {
      attachmentCount: 1,
      pAttachments: &colorAttachment,
      subpassCount: 1,
      pSubpasses: &subpass,
    };
    const VkSubpassDependency dependency = {
      srcSubpass: VK_SUBPASS_EXTERNAL,
      dstSubpass: 0,
      srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      srcAccessMask: 0,
      dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };
    renderPassInfo.dependencyCount = 1;
    renderPassInfo.pDependencies = &dependency;

    enforceVk(vkCreateRenderPass(device.handle, &renderPassInfo, null, &renderPass));
  }

  ~this() {
    if (renderPass != VK_NULL_HANDLE) vkDestroyRenderPass(device.handle, renderPass, null);
  }

  VkRenderPass handle() @property const {
    return cast(VkRenderPass) renderPass;
  }
}

package (teraflop) enum BindingType : VkDescriptorType {
  uniform = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
  storageBuffer = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
  sampler = VK_DESCRIPTOR_TYPE_SAMPLER,
  sampledTexture = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
  storageTexture = VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER
}

/// A GPU descriptor binding, e.g. uniform buffer or texture sampler.
/// See_Also: `teraflop.graphics.UniformBuffer`
abstract class BindingDescriptor {
  import teraflop.graphics : ShaderStage;

  protected uint bindingLocation_;
  protected ShaderStage shaderStage_;
  protected BindingType bindingType_;
  private auto dirty_ = true;

  /// Whether this uniform's data is new or changed and needs to be uploaded to the GPU.
  bool dirty() @property const {
    return dirty_;
  }
  package (teraflop) void dirty(bool value) @property {
    dirty_ = value;
  }

  /// Descriptor binding location, e.g. `layout(binding = 0)` in GLSL.
  uint bindingLocation() @property const {
    return bindingLocation_;
  }

  /// Which shader stages this descriptor is going to be referenced.
  ShaderStage shaderStage() @property const {
    return shaderStage_;
  }

  BindingType bindingType() @property const {
    return bindingType_;
  }

  package const(VkWriteDescriptorSet) descriptorWrite(VkDescriptorSet set, Buffer uniformBuffer) const {
    VkWriteDescriptorSet descriptorWrite = {
      dstSet: set,
      dstBinding: bindingLocation_,
      dstArrayElement: 0,
      descriptorType: bindingType_,
      descriptorCount: 1,
      pBufferInfo: null,
      pImageInfo: null,
      pTexelBufferView: null,
    };
    switch (bindingType_) {
      case BindingType.uniform:
        descriptorWrite.pBufferInfo = new VkDescriptorBufferInfo(uniformBuffer.handle, 0, uniformBuffer.size);
        break;
      case BindingType.sampler:
      case BindingType.sampledTexture:
        assert(sampler !is null);
        descriptorWrite.pImageInfo = new VkDescriptorImageInfo(
          sampler.handle,
          image !is null ? image.defaultView : VK_NULL_HANDLE,
          VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
        );
        break;
      default: assert(0, "Descriptor type not supported");
    }
    return descriptorWrite;
  }

  size_t size() @property const {
    return 0;
  }
  const(ubyte[]) data() @property const {
    return [];
  }
  package (teraflop) const(Sampler) sampler() @property const {
    return null;
  }
  package (teraflop) const(Image) image() @property const {
    return null;
  }
}

package (teraflop) struct BindingGroup {
  uint index;
  const BindingDescriptor[] bindings;
}

package (teraflop) struct VertexDataDescriptor {
  VkVertexInputBindingDescription bindingDescription;
  VkVertexInputAttributeDescription[] attributeDescriptions;
}

package (teraflop) struct PipelineLayout {
  BindingGroup[] bindingGroups;
  VertexDataDescriptor vertexData;
}

package (teraflop) class Pipeline {
  import teraflop.graphics : Material, Shader;

  private Device device;
  private const VkExtent2D viewport;
  private const RenderPass renderPass;
  private const Material material;
  private const PipelineLayout layout;
  private VkPipelineLayout pipelineLayout_ = VK_NULL_HANDLE;
  private VkPipeline graphicsPipeline = VK_NULL_HANDLE;

  this(Device device, const VkExtent2D viewport, const RenderPass renderPass,
    const Material material, const PipelineLayout layout,
    const VkDescriptorSetLayout[] descriptorSetLayouts
  ) {
    this.device = device;
    this.viewport = viewport;
    this.renderPass = renderPass;
    this.material = material;
    this.layout = layout;

    VkPipelineVertexInputStateCreateInfo vertexInputInfo = {
      vertexBindingDescriptionCount: 1,
      pVertexBindingDescriptions: &layout.vertexData.bindingDescription,
      vertexAttributeDescriptionCount: layout.vertexData.attributeDescriptions.length.to!uint,
      pVertexAttributeDescriptions: layout.vertexData.attributeDescriptions.ptr,
    };
    VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
      topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
      primitiveRestartEnable: VK_FALSE,
    };
    VkViewport pipelineViewport = {
      x: 0.0f,
      y: 0.0f,
      width: this.viewport.width.to!float,
      height: this.viewport.height.to!float,
      minDepth: 0.0f,
      maxDepth: 1.0f,
    };
    VkRect2D scissor = {
      offset: VkOffset2D(0, 0),
      extent: this.viewport,
    };
    VkPipelineViewportStateCreateInfo viewportState = {
      viewportCount: 1,
      pViewports: &pipelineViewport,
      scissorCount: 1,
      pScissors: &scissor,
    };
    VkPipelineRasterizationStateCreateInfo rasterizer = {
      depthClampEnable: VK_FALSE,
      rasterizerDiscardEnable: VK_FALSE,
      polygonMode: VK_POLYGON_MODE_FILL,
      lineWidth: 1.0f,
      cullMode: material.cullMode,
      frontFace: material.frontFace,
      depthBiasEnable: VK_FALSE,
      depthBiasConstantFactor: 0.0f,
      depthBiasClamp: 0.0f,
      depthBiasSlopeFactor: 0.0f,
    };
    VkPipelineMultisampleStateCreateInfo multisampling = {
      sampleShadingEnable: VK_FALSE,
      rasterizationSamples: VK_SAMPLE_COUNT_1_BIT,
      minSampleShading: 1.0f,
      pSampleMask: null,
      alphaToCoverageEnable: VK_FALSE,
      alphaToOneEnable: VK_FALSE,
    };
    VkPipelineDepthStencilStateCreateInfo depthStencil = {
      depthTestEnable: VK_TRUE,
      depthWriteEnable: VK_TRUE,
      depthCompareOp: VK_COMPARE_OP_LESS,
      depthBoundsTestEnable: VK_FALSE,
      minDepthBounds: 0.0f,
      maxDepthBounds: 1.0f,
      stencilTestEnable: VK_FALSE,
      // front: {},
      // back: {},
    };
    VkPipelineColorBlendAttachmentState colorBlendAttachment = {
      colorWriteMask: VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT |
        VK_COLOR_COMPONENT_A_BIT,
      blendEnable: VK_TRUE,
      srcColorBlendFactor: VK_BLEND_FACTOR_SRC_ALPHA,
      dstColorBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
      colorBlendOp: VK_BLEND_OP_ADD,
      srcAlphaBlendFactor: VK_BLEND_FACTOR_ONE,
      dstAlphaBlendFactor: VK_BLEND_FACTOR_ZERO,
      alphaBlendOp: VK_BLEND_OP_ADD,
    };
    VkPipelineColorBlendStateCreateInfo colorBlending = {
      logicOpEnable: VK_FALSE,
      logicOp: VK_LOGIC_OP_COPY,
      attachmentCount: 1,
      pAttachments: &colorBlendAttachment,
    };

    VkPipelineLayoutCreateInfo pipelineLayoutInfo = {
      setLayoutCount: descriptorSetLayouts.length.to!uint,
      pSetLayouts: descriptorSetLayouts.ptr,
      pushConstantRangeCount: 0,
      pPushConstantRanges: null,
    };
    enforceVk(vkCreatePipelineLayout(device.handle, &pipelineLayoutInfo, null, &pipelineLayout_));

    // Create the pipeline
    const shaderStages = material.shaders.map!(shader => shader.stageCreateInfo).array;
    VkGraphicsPipelineCreateInfo pipelineInfo = {
      stageCount: shaderStages.length.to!uint,
      pStages: shaderStages.ptr,
      pVertexInputState: &vertexInputInfo,
      pInputAssemblyState: &inputAssembly,
      pViewportState: &viewportState,
      pRasterizationState: &rasterizer,
      pMultisampleState: &multisampling,
      pDepthStencilState: &depthStencil,
      pColorBlendState: &colorBlending,
      pDynamicState: null,
      layout: pipelineLayout_,
      renderPass: renderPass.handle,
      subpass: 0,
      basePipelineHandle: VK_NULL_HANDLE,
      basePipelineIndex: -1,
    };
    enforceVk(vkCreateGraphicsPipelines(device.handle, VK_NULL_HANDLE, 1, &pipelineInfo, null, &graphicsPipeline));
  }

  ~this() {
    if (pipelineLayout_ != VK_NULL_HANDLE) vkDestroyPipelineLayout(device.handle, pipelineLayout_, null);
    if (graphicsPipeline != VK_NULL_HANDLE) vkDestroyPipeline(device.handle, graphicsPipeline, null);
  }

  VkPipeline handle() @property const {
    return cast(VkPipeline) graphicsPipeline;
  }

  VkPipelineLayout pipelineLayout() @property const {
    return cast(VkPipelineLayout) pipelineLayout_;
  }
}

unittest {
  // TODO: A headless unit test to render a triangle
}
