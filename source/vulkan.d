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
private string[] validationLayers =  [
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

  return validationLayers.all!(layer => availableLayerNames.any!(availableLayer => icmp(availableLayer, layer) == 0));
}

private string[] deviceExtensions = [VK_KHR_SWAPCHAIN_EXTENSION_NAME];

package (teraflop) final class Device {
  private VkInstance instance_;
  private VkDevice device = VK_NULL_HANDLE;
  private VkPhysicalDevice physicalDevice_ = VK_NULL_HANDLE;
  private uint graphicsQueueFamilyIndex = uint.max;
  private VkQueue queue_;

  this(string appName) {
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

  VkQueue queue() @property const {
    return cast(VkQueue) queue_;
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
        graphicsQueueFamilyIndex = cast(uint) i;
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
    VkPhysicalDeviceFeatures deviceFeatures = {};
    const extensions = deviceExtensions.map!(name => toStringz(name)).array;
    VkDeviceCreateInfo deviceCreateInfo = {
      queueCreateInfoCount: 1,
      pQueueCreateInfos: &queueCreateInfo,
      pEnabledFeatures: &deviceFeatures,
      enabledExtensionCount: deviceExtensions.length.to!uint,
      ppEnabledExtensionNames: extensions.ptr,
    };
    enforceVk(vkCreateDevice(physicalDevices[0], &deviceCreateInfo, null, &device));
    loadDeviceLevelFunctions(device);

    // Get the command buffer queue
    vkGetDeviceQueue(device, graphicsQueueFamilyIndex, 0, &queue_);
  }

  SwapChain createSwapChain(const Surface surface, const Size framebufferSize, const SwapChain oldSwapChain = null) {
    VkBool32 supported = VK_FALSE;
    enforceVk(vkGetPhysicalDeviceSurfaceSupportKHR(
      physicalDevice_, graphicsQueueFamilyIndex, surface.surfaceKhr, &supported
    ));
    enforce(supported == VK_TRUE, "Surface is not supported for presentation");
    return new SwapChain(this, surface, framebufferSize, oldSwapChain);
  }
}

package (teraflop) class Surface {
  private VkSurfaceKHR surface_;

  this(VkSurfaceKHR surface) {
    this.surface_ = surface;
  }

  static Surface fromGlfw(VkInstance instance, GLFWwindow* window) {
    VkSurfaceKHR surface;
    enforceVk(glfwCreateWindowSurface(instance, window, null, &surface));
    return new Surface(surface);
  }

  VkSurfaceKHR surfaceKhr() @property const {
    return cast(VkSurfaceKHR) surface_;
  }
}

// https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_KHR_swapchain.html
package (teraflop) class SwapChain {
  const Device device;
  const VkSurfaceFormatKHR surfaceFormat = {
    format: VK_FORMAT_B8G8R8A8_SRGB,
    colorSpace: VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
  };
  private VkPresentModeKHR presentMode;
  private VkExtent2D extent;
  private VkSwapchainKHR handle;
  VkImage[] swapChainImages;

  this(const Device device, const Surface surface, const Size framebufferSize, const SwapChain oldSwapChain = null) {
    this.device = device;
    SupportDetails details = getSupportDetails(device, surface);
    presentMode = choosePresentMode(details.presentModes);
    extent = chooseExtent(details.capabilities, framebufferSize);
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
      queueFamilyIndexCount: 0, // Optional
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
  }

  ~this() {
    vkDestroySwapchainKHR(device.handle, handle, null);
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
