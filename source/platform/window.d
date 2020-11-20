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

private uint lastWindowId = 0;

/// A native window.
class Window {
  import teraflop.graphics : Color;
  import teraflop.math : Size;
  import teraflop.vulkan : Device, Surface;

  private GLFWwindow* window;
  private Surface surface_;
  private WindowData data;
  private bool valid_ = false;
  private string title_;

  /// Window identifier.
  const int id;

  /// Color this window's framebuffer should be cleared to when rendered.
  auto clearColor = Color.black;

  /// Initialize a new Window.
  ///
  /// Params:
  /// title = Title of the Window
  /// width = Initial width of the Window
  /// height = Initial height of the Window
  /// initiallyFocused = Whether the window will be given input focus when created
  this(string title, int width = 800, int height = 600, bool initiallyFocused = true) {
    id = lastWindowId += 1;
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
    glfwSetFramebufferSizeCallback(window, &framebufferResizeCallback);
    glfwSetWindowIconifyCallback(window, &iconifyCallback);

    data.update(window);
  }

  ~this() {
    if (valid) glfwDestroyWindow(window);
    destroy(surface_);
  }

  // Swap chains are keyed on their windows
  // https://dlang.org/spec/hash-map.html#using_classes_as_key
  override size_t toHash() @safe @nogc const pure {
    return id;
  }
  override bool opEquals(Object o) @safe @nogc const pure {
    Window other = cast(Window) o;
    return other && id == other.id;
  }

  /// Whether the native window handle is valid.
  ///
  /// May be `false` if Window initialization failed .
  bool valid() @property const {
    return valid_;
  }

  /// Title of this Window.
  string title() @property const {
    return title_;
  }
  void title(string value) @property {
    title_ = value;
  }

  /// Size of this Window, in <a href="https://www.glfw.org/docs/latest/intro_guide.html#coordinate_systems">screen coordinates</a>.
  ///
  /// This value may not necessarily match `Window.framebufferSize`. For example, on mac OS machines with high-DPI Retina displays.
  /// See_Also: <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_size">Window size</a> in the GLFW documentation
  const(Size) size() @property const {
    return data.size;
  }
  /// Size of this Window, in pixels.
  ///
  /// This value may not necessarily match `Window.size`. For example, on mac OS machines with high-DPI Retina displays.
  /// See_Also: <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_fbsize">Framebuffer size</a> in the GLFW documentation
  const(Size) framebufferSize() @property const {
    return data.framebufferSize;
  }

  /// Whether this window is minimized.
  /// See_Also: <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_iconify">Window iconification</a> in the GLFW documentation
  bool minimized() @property const {
    return data.minimized;
  }

  package (teraflop) bool dirty() @property const {
    return data.dirty;
  }
  package (teraflop) const(Surface) surface() @property const {
    return surface_;
  }
  package (teraflop) void createSurface(VkInstance instance) {
    surface_ = Surface.fromGlfw(instance, window);
  }

  package (teraflop) void update() {
    if (glfwWindowShouldClose(window)) {
      glfwDestroyWindow(window);
      valid_ = false;
      return;
    }

    glfwPollEvents();
    data.update(window);

    glfwSetWindowTitle(window, toStringz(title_));

    // TODO: Add input event listeners at Window construction and trigger the Game's AsyncNotifier (https://libasync.dpldocs.info/libasync.notifier.AsyncNotifier.html)
  }

  extern(C) {
    private static void framebufferResizeCallback(GLFWwindow* window, int, int) nothrow {
      auto data = cast(WindowData*) glfwGetWindowUserPointer(window);
      assert(data !is null, "Could not retrieve GLFW window data");
      data.update(window);
    }

    private static void iconifyCallback(GLFWwindow* window, int iconified) nothrow {
      auto data = cast(WindowData*) glfwGetWindowUserPointer(window);
      assert(data !is null, "Could not retrieve GLFW window data");

      const wasMinimized = data.minimized;
      data.minimized = iconified == GLFW_TRUE;
      if (!wasMinimized && data.minimized) data.dirty = true;
    }
  }

  // https://github.com/dkorpel/glfw-d/blob/master/example/app.d
  private struct WindowData {
    // These are stored in the window's user data so that when exiting fullscreen,
    // the window can be set to the position where it was before entering fullscreen
    // instead of resetting to e.g. (0, 0)
    int xpos;
    int ypos;
    Size size;
    Size framebufferSize;
    bool minimized = false;
    bool dirty = false;

    void update(GLFWwindow* window) @nogc nothrow {
      assert(window !is null);

      const size_t oldData = framebufferSize.width + framebufferSize.height;
      glfwGetWindowPos(window, &this.xpos, &this.ypos);
      glfwGetWindowSize(window, cast(int*) &this.size.width, cast(int*) &this.size.height);
      glfwGetFramebufferSize(window, cast(int*) &this.framebufferSize.width, cast(int*) &this.framebufferSize.height);
      if (!minimized && framebufferSize.width == 0 && framebufferSize.height == 0)
        minimized = true;
      // TODO: Mark the window dirty if the window's display's DPI changed
      // https://www.glfw.org/docs/3.3/window_guide.html#window_scale
      dirty = oldData != framebufferSize.width + framebufferSize.height;
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
