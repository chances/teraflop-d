/// Native window primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.platform.window;

import bindbc.glfw;
import std.conv : to;
import std.string : toStringz;
import teraflop.async : Event, EventLoop;
import teraflop.ecs : Resource;
import teraflop.input;
import teraflop.platform.wgpu;

private int lastWindowId = 0;

/// A native window.
class Window : InputNode, Resource {
  import teraflop.input : KeyboardKey, MouseButton;
  import teraflop.math : Size, vec2d;
  import wgpu.api : Adapter, Device, Instance, Surface, TextureFormat;

  /// Window identifier
  const int id;

  private GLFWwindow* window;
  private Device device_;
  private Surface surface_;
  private TextureFormat swapChainFormat_;
  private const EventLoop eventLoop_;
  private string title_;
  private WindowData data;

  /// Fired when this window receives an unhandled `InputEvent`.
  Event!(const InputEvent) onUnhandledInput;

  /// Initialize a new Window.
  ///
  /// Params:
  /// title = Title of the Window
  /// width = Initial width of the Window
  /// height = Initial height of the Window
  /// initiallyFocused = Whether the window will be given input focus when created
  this(Instance instance, string title, int width = 800, int height = 600, bool initiallyFocused = true) {
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
    if (!valid) {
      errorCallback(0, toStringz("Failed to initialize a new GLFW Window"));
      return;
    }

    glfwSetWindowUserPointer(window, &data);
    // TODO: glfwSetFramebufferSizeCallback(window, &framebufferResizeCallback);
    // TODO: glfwSetWindowIconifyCallback(window, &iconifyCallback);
    // https://www.glfw.org/docs/latest/input_guide.html#input_mouse_button
    glfwSetInputMode(window, GLFW_STICKY_MOUSE_BUTTONS, GLFW_TRUE);
    // https://www.glfw.org/docs/latest/input_guide.html#scrolling
    // TODO: For GUI scrolling: glfwSetScrollCallback(window, scroll_callback);
    // https://www.glfw.org/docs/latest/input_guide.html#input_key
    glfwSetInputMode(window, GLFW_STICKY_KEYS, GLFW_TRUE);
    glfwSetInputMode(window, GLFW_LOCK_KEY_MODS, GLFW_TRUE);
    // TODO: For text inputs in the GUI: glfwSetCharCallback(window, character_callback);
    // TODO: For text input in the GUI; clipboard: https://www.glfw.org/docs/latest/input_guide.html#clipboard
    // TODO: For cursor image changes in the GUI: https://www.glfw.org/docs/latest/input_guide.html#cursor_object
    // TODO: For save games? https://www.glfw.org/docs/latest/input_guide.html#path_drop
    // TODO: https://www.glfw.org/docs/latest/input_guide.html#joystick and https://www.glfw.org/docs/latest/input_guide.html#gamepad

    // Initialize GPU surface and swap chain descriptor
    surface_ = createPlatformSurface(instance, window);
    if (!valid) {
      glfwDestroyWindow(window);
      errorCallback(0, toStringz("Failed to initialize a new GPU surface"));
      return;
    }

    data.update(window);
  }

  ~this() {
    if (!valid) return;
    glfwDestroyWindow(window);
    surface_.destroy();
  }

  // User input is keyed on the target window
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

  /// Whether the native window handle and backing GPU surface is valid.
  ///
  /// May be `false` if Window initialization failed.
  bool valid() @property const {
    import wgpu.utils : valid;
    if (window is null) return false;
    if (surface is null) return false;
    return surface_.valid;
  }

  ///
  EventLoop eventLoop() @trusted @property const {
    return cast(EventLoop) this.eventLoop_;
  }

  /// Size of this Window's content area, in <a href="https://www.glfw.org/docs/latest/intro_guide.html#coordinate_systems">screen coordinates</a>.
  ///
  /// This value may not necessarily match `Window.framebufferSize`. For example, on mac OS machines with high-DPI Retina displays.
  /// See_Also: <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_size">Window size</a> in the GLFW documentation
  const(Size) size() @property const {
    return data.size;
  }
  /// Value used to disable minimum or maximum size limits of a Window.
  /// See_Also: $(UL
  ///   $(LI `Window.minimumSize`)
  ///   $(LI `Window.maximumSize`)
  /// )
  static const Size dontCare = Size(GLFW_DONT_CARE, GLFW_DONT_CARE);
  /// Minimum size of this Window's content area, in <a href="https://www.glfw.org/docs/latest/intro_guide.html#coordinate_systems">screen coordinates</a>.
  ///
  /// To disable the minimum size limit for this Window, set this property to `Window.dontCare`.
  /// See_Also: <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_sizelimits">Window size limits</a> in the GLFW documentation
  const(Size) minimumSize() @property const {
    return data.minimumSize;
  }
  /// ditto
  void minimumSize(Size value) @property {
    data.minimumSize.width = value.width;
    data.minimumSize.height = value.height;
    glfwSetWindowSizeLimits(
      // Minimum size
      window, data.minimumSize.width, data.minimumSize.height,
      // Maximum size
      data.maximumSize.width, data.maximumSize.height
    );
  }
  /// Maximum size of this Window's content area, in <a href="https://www.glfw.org/docs/latest/intro_guide.html#coordinate_systems">screen coordinates</a>.
  ///
  /// To disable the maximum size limit for this Window, set this property to `Window.dontCare`.
  /// See_Also: <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_sizelimits">Window size limits</a> in the GLFW documentation
  const(Size) maximumSize() @property const {
    return data.maximumSize;
  }
  /// ditto
  void maximumSize(Size value) @property {
    data.maximumSize.width = value.width;
    data.maximumSize.height = value.height;
    glfwSetWindowSizeLimits(
      // Minimum size
      window, data.minimumSize.width, data.minimumSize.height,
      // Maximum size
      data.maximumSize.width, data.maximumSize.height
    );
  }

  /// Size of this Window's Surface, in pixels.
  ///
  /// This value may not necessarily match `Window.size`. For example, on mac OS machines with high-DPI Retina displays.
  /// See_Also: <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_fbsize">Framebuffer size</a> in the GLFW documentation
  const(Size) surfaceSize() @property const {
    return data.framebufferSize;
  }
  /// Size of this Window, in pixels.
  ///
  /// This value may not necessarily match `Window.size`. For example, on mac OS machines with high-DPI Retina displays.
  /// See_Also: <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_fbsize">Framebuffer size</a> in the GLFW documentation
  const(Size) framebufferSize() @property const {
    return data.framebufferSize;
  }

  /// Whether this Window is currently visible.
  /// See_Also: $(UL
  ///   $(LI `Window.show`)
  ///   $(LI `Window.hide`)
  ///   $(LI <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_hide">Window visibility</a> in the GLFW documentation)
  /// )
  bool visible() const @property {
    return data.visible;
  }
  /// ditto
  void visible(bool value) @property {
    if (this.visible && !value) hide();
    else if (!this.visible && value) show();
  }

  /// Whether this window is minimized.
  /// See_Also: <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_iconify">Window iconification</a> in the GLFW documentation
  bool minimized() @property const {
    return data.minimized;
  }

  package (teraflop) bool hasMouseInputChanged() @property const {
    const mouseButtonsChanged = data.lastMouseButtons != data.mouseButtons;
    // TODO: Check mouse wheel pos for changes
    // const mouseWheelChanged = GetMouseWheelMove() != 0;
    const mousePosChanged = data.lastMousePos.x != data.mousePos.x || data.lastMousePos.y != data.mousePos.y;
    return mouseButtonsChanged || mousePosChanged;
  }

  package (teraflop) Surface surface() @trusted @property const {
    return cast(Surface) surface_;
  }
  package (teraflop) TextureFormat surfaceFormat() @trusted @property const {
    import std.conv : asOriginalType;
    // TODO: Abstract this check back into a `Surface.valid` parameter
    auto config = surface.config;
    assert(config !is null, "Cannot create texture descriptor: This surface is not configured.");
    if (config is null) throw new Exception("Cannot create texture descriptor: This surface is not configured.");

    return config.format.asOriginalType.to!TextureFormat;
  }
  package (teraflop) bool dirty() @property const {
    return data.dirty;
  }

  bool isKeyDown(KeyboardKey key) @property const {
    return (key in data.keyPressed) !is null ? data.keyPressed[key] : false;
  }
  bool wasKeyDown(KeyboardKey key) @property const {
    return (key in data.wasKeyPressed) !is null ? data.wasKeyPressed[key] : false;
  }
  bool isKeyReleased(KeyboardKey key) @property const {
    return (key in data.keyPressed) !is null ? !data.keyPressed[key] : true;
  }

  vec2d mousePosition() @property const {
    return data.mousePos;
  }
  vec2d lastMousePosition() @property const {
    return data.lastMousePos;
  }
  int mouseButtons() @property const {
    return data.mouseButtons;
  }
  int lastMouseButtons() @property const {
    return data.lastMouseButtons;
  }

  /// Hides this Window if it was previously visible.
  ///
  /// If the window is already hidden or is in full screen mode, this function does nothing.
  /// Returns: Whether this Window is now visible.
  /// See_Also: $(UL
  ///   $(LI `Window.visible`)
  ///   $(LI `Window.hide`)
  ///   $(LI <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_hide">Window visibility</a> in the GLFW documentation)
  /// )
  bool show() {
    glfwShowWindow(window);
    data.visible = glfwGetWindowAttrib(window, GLFW_VISIBLE) == GLFW_TRUE;
    return this.visible;
  }
  /// Makes this Window visible if it was previously hidden.
  ///
  /// If the window is already visible or is in full screen mode, this function does nothing.
  /// Returns: Whether this Window is now hidden.
  /// See_Also: $(UL
  ///   $(LI `Window.visible`)
  ///   $(LI `Window.show`)
  ///   $(LI <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_hide">Window visibility</a> in the GLFW documentation)
  /// )
  bool hide() {
    glfwHideWindow(window);
    data.visible = glfwGetWindowAttrib(window, GLFW_VISIBLE) == GLFW_TRUE;
    return !this.visible;
  }

  /// See_Also: `Resource`
  void initialize(Adapter adapter, Device device) {
    import wgpu.api : CompositeAlphaMode, PresentMode, TextureUsage;

    this.device_ = device;

    this.swapChainFormat_ = surface.preferredFormat(adapter);
    surface.configure(
      device, surfaceSize.width, surfaceSize.height, surfaceFormat,
      TextureUsage.renderAttachment,
      PresentMode.fifo, CompositeAlphaMode.auto_
    );
  }

  override void actionInput(const InputEventAction event) {
    assert(event.action.length);
    onUnhandledInput(event);
  }

  override bool unhandledInput(const InputEvent event) {
    onUnhandledInput(event);
    return true; // Mark handled
  }

  package (teraflop) void update() {
    if (glfwWindowShouldClose(window)) {
      glfwDestroyWindow(window);
      window = null;
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
    surface.resize(surfaceSize.width, surfaceSize.height);
    data.dirty = false;
  }

  // https://github.com/dkorpel/glfw-d/blob/master/example/app.d
  private struct WindowData {
    // TODO: When exiting fullscreen, set to the position where it was before entering fullscreen
    int xpos;
    int ypos;
    Size size;
    Size minimumSize = Window.dontCare;
    Size maximumSize = Window.dontCare;
    Size framebufferSize;
    bool visible = false;
    bool minimized = false;
    bool dirty = false;
    vec2d mousePos = vec2d(0, 0);
    vec2d lastMousePos = vec2d(0, 0);
    bool hovered = false;
    int mouseButtons = 0;
    int lastMouseButtons = 0;
    bool[KeyboardKey] keyPressed;
    bool[KeyboardKey] wasKeyPressed;

    void update(GLFWwindow* window) nothrow {
      assert(window !is null);

      const size_t oldData = xpos + ypos + framebufferSize.width + framebufferSize.height;

      glfwPollEvents();
      glfwGetWindowPos(window, &this.xpos, &this.ypos);
      glfwGetWindowSize(window, cast(int*) &this.size.width, cast(int*) &this.size.height);
      glfwGetFramebufferSize(window, cast(int*) &this.framebufferSize.width, cast(int*) &this.framebufferSize.height);
      if (!minimized && framebufferSize.width == 0 && framebufferSize.height == 0)
        minimized = true;

      // Mouse input
      lastMousePos.x = mousePos.x;
      lastMousePos.y = mousePos.y;
      glfwGetCursorPos(window, &this.mousePos.x, &this.mousePos.y);
      this.hovered = glfwGetWindowAttrib(window, GLFW_HOVERED) == GLFW_TRUE;
      this.lastMouseButtons = this.mouseButtons;
      this.mouseButtons = 0;
      if (glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_LEFT) == GLFW_PRESS) this.mouseButtons |= MouseButton.left;
      if (glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_RIGHT) == GLFW_PRESS) this.mouseButtons |= MouseButton.right;
      if (glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_MIDDLE) == GLFW_PRESS) this.mouseButtons |= MouseButton.middle;
      // Keyboard input
      foreach (key; keyPressed.keys)
        wasKeyPressed[key] = (key in keyPressed) !is null ? keyPressed[key] : false;
      foreach (key; KeyboardKey.min..KeyboardKey.max) {
        if (key == KeyboardKey.unknown) continue;
        if (key.to!int < KeyboardKey.space.to!int) continue;
        keyPressed[key] = glfwGetKey(window, key) == GLFW_PRESS;
      }

      // TODO: Mark the window dirty if the window's display's DPI changed
      // https://www.glfw.org/docs/3.3/window_guide.html#window_scale
      dirty = oldData != framebufferSize.width + framebufferSize.height;
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

// FIXME: Remove this
package extern (C) void glfwSetWindowSizeLimits(
  GLFWwindow* window, int minwidth, int minheight, int maxwidth, int maxheight
);

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
