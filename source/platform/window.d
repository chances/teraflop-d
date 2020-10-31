/// Native window primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.platform.window;

import bindbc.glfw;
import std.string : toStringz;

/// A native window.
class Window {
  private GLFWwindow* window;
  private WindowData data;
  private bool valid_ = false;
  private string title_;

  /// Initialize a new Window.
  ///
  /// Params:
  /// title = Title of the Window
  /// width = Initial width of the Window
  /// height = Initial height of the Window
  /// initiallyFocused = Whether the window will be given input focus when created
  this(string title, int width = 800, int height = 600, bool initiallyFocused = true) {
    title_ = title;

    // https://www.glfw.org/docs/3.3/window_guide.html#window_hints
    glfwWindowHint(GLFW_RESIZABLE, true);
    glfwWindowHint(GLFW_FOCUSED, initiallyFocused);
    glfwWindowHint(GLFW_FOCUS_ON_SHOW, true);
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API); // Graphics are handled by wgpu

    window = glfwCreateWindow(width, height, toStringz(title), null, null);
    valid_ = window !is null;
    if (!valid_) {
      errorCallback(0, toStringz("Failed to initialize a new GLFW Window."));
      return;
    }
    glfwSetWindowUserPointer(window, &data);

    data.update(window);
  }

  ~this() {
    if (isValid) glfwDestroyWindow(window);
  }

  /// Title of this Window.
  string title() const @property {
    return title_;
  }
  void title(string value) @property {
    title_ = value;
  }

  /// Whether the native window handle is valid.
  ///
  /// May be `false` if Window initialization failed .
  bool isValid() {
    if (glfwWindowShouldClose(window)) {
      glfwDestroyWindow(window);
      valid_ = false;
    }

    return valid_;
  }

  // https://github.com/dkorpel/glfw-d/blob/master/example/app.d
  private struct WindowData {
    // These are stored in the window's user data so that when exiting fullscreen,
    // the window can be set to the position where it was before entering fullscreen
    // instead of resetting to e.g. (0, 0)
    int xpos;
    int ypos;
    int width;
    int height;

    void update(GLFWwindow* window) @nogc nothrow {
      assert(window !is null);

      glfwPollEvents();
      glfwGetWindowPos(window, &this.xpos, &this.ypos);
      glfwGetWindowSize(window, &this.width, &this.height);
    }
  }
}

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

package (teraflop) bool initGlfw() {
  const GLFWSupport loadResult;

  version (Linux) {
    loadResult = loadGLFW_X11();
  }
  version(OSX) {
    loadResult = loadGLFW_Cocoa();
  }
  version (Windows) {
    loadResult = loadGLFW_Windows();
  }

  if (loadResult != glfwSupport && loadResult == GLFWSupport.noLibrary) {
      errorCallback(0, toStringz("GLFW shared library failed to load."));
  } else if (GLFWSupport.badLibrary) {
    // One or more symbols failed to load. The likely cause is that the
    // shared library is for a lower version than bindbc-glfw was configured
    // to load (via GLFW_31, GLFW_32 etc.)
    errorCallback(0, toStringz("One or more GLFW symbols failed to load. Is glfw >= 3.2 installed?"));
  }

  // TODO: Fix this for Windows and OSX? Or just use the static lib everywhere?
  // if (loadResult != GLFWSupport.glfw32 && loadResult != GLFWSupport.glfw33) {
  //   errorCallback(0, toStringz("GLFW version >= 3.2 failed to load. Is GLFW installed?"));
  //   return false;
  // }

  if (!glfwInit()) {
		return false;
	}

  glfwSetErrorCallback(&errorCallback);

  return true;
}

package (teraflop) void terminateGlfw() {
  glfwTerminate();
}

extern(C) private void errorCallback(int error, const(char)* description) @nogc nothrow {
  import core.stdc.stdio : fprintf, stderr;
	fprintf(stderr, "Error %d: %s\n", error, description);
}
