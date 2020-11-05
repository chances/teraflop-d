/// Native window primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.platform.window;

import bindbc.glfw;
import erupted : VkInstance;
import libasync.notifier : AsyncNotifier;
import std.string : toStringz;

/// A native window.
class Window {
  import teraflop.vulkan : Device, Surface;

  private GLFWwindow* window;
  private Surface surface;
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
    if (valid) glfwDestroyWindow(window);
  }

  /// Title of this Window.
  string title() @property const {
    return title_;
  }
  void title(string value) @property {
    title_ = value;
  }

  /// Whether the native window handle is valid.
  ///
  /// May be `false` if Window initialization failed .
  bool valid() @property const {
    return valid_;
  }

  package (teraflop) void createSurface(VkInstance instance) {
    surface = Surface.fromGlfw(instance, window);
  }

  package (teraflop) void update() {
    if (glfwWindowShouldClose(window)) {
      glfwDestroyWindow(window);
      valid_ = false;
      return;
    }

    data.update(window);

    glfwSetWindowTitle(window, toStringz(title_));

    // TODO: Add input event listeners at Window construction and trigger the Game's AsyncNotifier (https://libasync.dpldocs.info/libasync.notifier.AsyncNotifier.html)
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

version(linux) {
  import std.meta : Alias;
  alias Display = Alias!(void*);
  // https://github.com/BindBC/bindbc-glfw/blob/5bed82e7bdd18afb0e810aeb173e11d38e18075b/source/bindbc/glfw/bindstatic.d#L224
  extern(C) @nogc nothrow {
    private Display* glfwGetX11Display();
    private ulong glfwGetX11Window(GLFWwindow*);
  }
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

  version (Windows) {
    loadResult = loadGLFW_Windows();
  }

  version(OSX) {
    loadResult = loadGLFW_Cocoa();
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
  }

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
