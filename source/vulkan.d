module teraflop.vulkan;

import bindbc.glfw : GLFWwindow;
import erupted;
import erupted.vulkan_lib_loader;
import std.conv : to;
import teraflop.platform.window : Window;

alias GLFWvkproc = void function();
extern(C) @nogc nothrow {
  private const(char)** glfwGetRequiredInstanceExtensions(uint*);
  private GLFWvkproc glfwGetInstanceProcAddress(VkInstance,const(char)*);
  private int glfwGetPhysicalDevicePresentationSupport(VkInstance,VkPhysicalDevice,uint);
  package (teraflop) VkResult glfwCreateWindowSurface(
    VkInstance,GLFWwindow*,const(VkAllocationCallbacks)*,VkSurfaceKHR*
  );
}

package (teraflop) void enforceVk(VkResult res) {
  import std.exception : enforce;
  enforce(res == VkResult.VK_SUCCESS, res.to!string);
}

package (teraflop) bool initVulkan() {
  return loadGlobalLevelFunctions();
}

package (teraflop) class Device {
  private VkInstance instance_;
  private VkDevice device;
  private VkQueue queue_;

  this(string appName) {
    import std.string : toStringz;

    // Create instance
    VkApplicationInfo appInfo = {
      pApplicationName: toStringz(appName),
      pEngineName: "Teraflop",
      engineVersion: VK_MAKE_VERSION(0, 1, 0),
      apiVersion: VK_MAKE_VERSION(1, 0, 2),
    };

    uint32_t glfwExtensionCount = 0;
    const char** glfwExtensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

    VkInstanceCreateInfo instInfo = {
      pApplicationInfo: &appInfo,
      enabledExtensionCount: glfwExtensionCount,
      ppEnabledExtensionNames: glfwExtensions
    };

    enforceVk(vkCreateInstance(&instInfo, null, &instance_));
    loadInstanceLevelFunctions(instance_);

    // Acquire graphics device
    uint numPhysicalDevices;
    enforceVk(vkEnumeratePhysicalDevices(instance_, &numPhysicalDevices, null));
    assert(numPhysicalDevices > 0);
    auto physicalDevices = new VkPhysicalDevice[](numPhysicalDevices);
	  enforceVk(vkEnumeratePhysicalDevices(instance_, &numPhysicalDevices, physicalDevices.ptr));
    // Pick the queue with VK_QUEUE_GRAPHICS_BIT set
    uint numQueues;
    vkGetPhysicalDeviceQueueFamilyProperties(physicalDevices[0], &numQueues, null);
    assert(numQueues >= 1);
    auto queueFamilyProperties = new VkQueueFamilyProperties[](numQueues);
    vkGetPhysicalDeviceQueueFamilyProperties(physicalDevices[0], &numQueues, queueFamilyProperties.ptr);
    assert(numQueues >= 1);
    uint graphicsQueueFamilyIndex = uint.max;
    foreach(i, const ref properties; queueFamilyProperties) {
      if ((properties.queueFlags & VK_QUEUE_GRAPHICS_BIT) && graphicsQueueFamilyIndex == uint.max) {
        graphicsQueueFamilyIndex = cast(uint)i;
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
    VkDeviceCreateInfo deviceCreateInfo = {
      queueCreateInfoCount: 1,
      pQueueCreateInfos: &queueCreateInfo,
      pEnabledFeatures: &deviceFeatures
    };
    enforceVk(vkCreateDevice(physicalDevices[0], &deviceCreateInfo, null, &device));
    loadDeviceLevelFunctions(device);

    // Get the command buffer queue
    vkGetDeviceQueue(device, graphicsQueueFamilyIndex, 0, &queue_);
  }

  ~this() {
    if (device != VK_NULL_HANDLE) {
      vkDeviceWaitIdle(device);
      vkDestroyDevice(device, null);
    }
    if (instance_ != VK_NULL_HANDLE) vkDestroyInstance(instance_, null);
  }

  VkInstance instance() @property const {
    return cast(VkInstance) instance_;
  }

  VkQueue queue() @property const {
    return cast(VkQueue) queue_;
  }
}
