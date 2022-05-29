/// Native window primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.platform.window;

import bindbc.glfw;
import std.conv : to;
import std.string : toStringz;
import teraflop.async : EventLoop;
import teraflop.ecs : Resource;
import teraflop.platform.wgpu;

private int lastWindowId = 0;

/// A native window.
class Window : Resource {
  import wgpu.api : Adapter, Device, Surface, SwapChain;

  /// Window identifier
  const int id;

  private GLFWwindow* window;
  private Device device_;
  private Surface surface_;
  private SwapChain swapChain_;
  private const EventLoop eventLoop_;
  private bool valid_ = false;
  private string title_;
  private WindowData data;

  /// Initialize a new Window.
  ///
  /// Params:
  /// title = Title of the Window
  /// width = Initial width of the Window
  /// height = Initial height of the Window
  /// initiallyFocused = Whether the window will be given input focus when created
  this(string title, int width = 800, int height = 600, bool initiallyFocused = true) {
    import teraflop.async : createEventLoop;

    id = lastWindowId += 1;
    title_ = title;
    eventLoop_ = createEventLoop();

    // https://www.glfw.org/docs/3.3/window_guide.html#window_hints
    glfwWindowHint(GLFW_RESIZABLE, true);
    glfwWindowHint(GLFW_FOCUSED, initiallyFocused);
    glfwWindowHint(GLFW_FOCUS_ON_SHOW, true);
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API); // Graphics are handled by wgpu

    window = glfwCreateWindow(width, height, toStringz(title), null, null);
    valid_ = window !is null;
    if (!valid_) {
      errorCallback(0, toStringz("Failed to initialize a new GLFW Window"));
      return;
    }
    glfwSetWindowUserPointer(window, &data);
    data.update(window);

    // Initialize GPU surface and swap chain descriptor
    surface_ = createPlatformSurface(window);
    valid_ = surface_.id != null;
    if (!valid) {
      glfwDestroyWindow(window);
      errorCallback(0, toStringz("Failed to initialize a new GPU surface"));
      return;
    }
  }

  ~this() {
    if (valid) glfwDestroyWindow(window);
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

  ///
  EventLoop eventLoop() @trusted @property const {
    return cast(EventLoop) this.eventLoop_;
  }

  package (teraflop) Surface surface() @trusted @property const {
    return cast(Surface) surface_;
  }
  package (teraflop) bool dirty() @property const {
    return data.dirty;
  }
  package (teraflop) SwapChain swapChain() @trusted @property const {
    return cast(SwapChain) swapChain_;
  }

  /// See_Also: `Resource`
  void initialize(Adapter adapter, Device device) {
    import wgpu.api : PresentMode, TextureUsage;

    this.device_ = device;

    auto swapChainFormat = surface.preferredFormat(adapter);
    swapChain_ = device.createSwapChain(
      surface, data.width, data.height, swapChainFormat,
      // TODO: Remove this redundant texture usage parameter
      TextureUsage.renderAttachment,
      PresentMode.fifo,
      title
    );
  }

  package (teraflop) void update() {
    if (glfwWindowShouldClose(window)) {
      glfwDestroyWindow(window);
      valid_ = false;
      return;
    }

    data.update(window);
    if (data.dirty) updateSwapChain();

    glfwSetWindowTitle(window, toStringz(title_));

    // TODO: Add input event listeners at Window construction and trigger the Game's AsyncNotifier (https://libasync.dpldocs.info/libasync.notifier.AsyncNotifier.html)
  }

  private void updateSwapChain() {
    import std.typecons : Yes;
    import wgpu.utils : resize;

    // Force wait to flush GPU queue and pump callbacks
    device_.poll(Yes.forceWait);
    swapChain_ = swapChain_.resize(device_, data.width, data.height);
    data.dirty = false;
  }

  // https://github.com/dkorpel/glfw-d/blob/master/example/app.d
  private struct WindowData {
    // TODO: When exiting fullscreen, set to the position where it was before entering fullscreen
    int xpos;
    int ypos;
    int width;
    int height;
    bool dirty = false;

    void update(GLFWwindow* window) @nogc nothrow {
      assert(window !is null);

      const size_t oldData = xpos + ypos + width + height;

      glfwPollEvents();
      glfwGetWindowPos(window, &this.xpos, &this.ypos);
      glfwGetWindowSize(window, &this.width, &this.height);

      // TODO: Mark the window dirty if the window's display's DPI changed. Use adjusted, physical size for swap chains?
      dirty = oldData != xpos + ypos + width + height;
    }
  }
}

version (OSX) {
  mixin(bindGLFW_Cocoa);
}

version (Windows) {
  // Import platform API bindings
  import core.sys.windows.windows;
  // Mixin function declarations and loader
  mixin(bindGLFW_Windows);
}

package (teraflop) bool initGlfw() @trusted {
  const GLFWSupport loadResult;

  version (Windows) {
    loadResult = loadGLFW_Windows();

    if (loadResult != glfwSupport && loadResult == GLFWSupport.noLibrary) {
        errorCallback(0, toStringz("GLFW shared library failed to load."));
    } else if (GLFWSupport.badLibrary) {
      // One or more symbols failed to load. The likely cause is that the
      // shared library is for a lower version than bindbc-glfw was configured
      // to load (via GLFW_31, GLFW_32 etc.)
      errorCallback(0, toStringz("One or more GLFW symbols failed to load. Is glfw >= 3.2 installed?"));
    }

    // TODO: Fix this for Windows? Or just use the static lib everywhere?
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
