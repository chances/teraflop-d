/// Native window primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.platform.window;

import bindbc.glfw;
import std.exception : enforce;
import std.string : toStringz;
import teraflop.input;

private uint lastWindowId = 0;

/// A native window.
class Window : InputNode {
  import teraflop.async : Event;
  import teraflop.graphics : Color;
  import teraflop.math : Size, vec2d;
  import gfx.core.rc : atomicRcCode;
  import gfx.graal : Device, Instance, Surface;
  import gfx.vulkan : VkSurfaceKHR;

  private GLFWwindow* window;
  private Surface _surface;
  private WindowData data;
  private bool _valid = false;
  private string _title;

  /// Window identifier.
  const int id;

  /// Color this window's framebuffer should be cleared to when rendered.
  auto clearColor = Color.black;
  ///
  static Color defaultClearColor = Color.black;

  /// Fired when this window receives an unhandled `InputEvent`.
  Event!(const InputEvent) onUnhandledInput;

  /// Initialize a new Window.
  ///
  /// Params:
  /// title = Title of the Window
  /// width = Initial width of the Window
  /// height = Initial height of the Window
  /// initiallyFocused = Whether the window will be given input focus when created
  this(
    string title, int width = 960, int height = 720, bool initiallyFocused = true
  ) {
    this(title, defaultClearColor, width, height, initiallyFocused);
  }
  /// Initialize a new Window.
  ///
  /// Params:
  /// title = Title of the Window
  /// clearColor = Color the window's framebuffer should be cleared to when rendered.
  /// width = Initial width of the Window
  /// height = Initial height of the Window
  /// initiallyFocused = Whether the window will be given input focus when created
  this(
    string title, Color clearColor, int width = 960, int height = 720, bool initiallyFocused = true
  ) {
    import gfx.vulkan.wsi : createVulkanGlfwSurface;
    import teraflop.platform.vulkan : instance;

    id = lastWindowId += 1;
    _title = title;
    this.clearColor = clearColor;

    // https://www.glfw.org/docs/3.3/window_guide.html#window_hints
    glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
    glfwWindowHint(GLFW_RESIZABLE, true);
    glfwWindowHint(GLFW_FOCUSED, initiallyFocused);
    glfwWindowHint(GLFW_FOCUS_ON_SHOW, true);
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API); // Graphics are handled by Vulkan

    window = glfwCreateWindow(width, height, toStringz(title), null, null);
    _valid = window !is null;
    if (!_valid) {
      errorCallback(0, toStringz("Failed to initialize a new GLFW Window."));
      return;
    }
    _surface = createVulkanGlfwSurface(instance, window);

    glfwSetWindowUserPointer(window, &data);
    glfwSetFramebufferSizeCallback(window, &framebufferResizeCallback);
    glfwSetWindowIconifyCallback(window, &iconifyCallback);
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

    data.update(window);
  }

  ///
  void dispose() {
    if (valid) glfwDestroyWindow(window);
    _surface.dispose();
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
    return _valid;
  }

  /// Title of this Window.
  string title() @property const {
    return _title;
  }
  void title(const string value) @property {
    _title = value;
    if (valid) glfwSetWindowTitle(window, value.toStringz);
  }

  /// Whether this Window is currently visible.
  /// See_Also: $(UL
  ///   $(LI `Window.show`)
  ///   $(LI `Window.hide`)
  ///   $(LI <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_hide">Window visibility</a> in the GLFW documentation)
  /// )
  bool visible() @property const {
    return data.visible;
  }
  void visible(bool value) @property {
    if (this.visible && !value) hide();
    else if (!this.visible && value) show();
  }

  /// Size of this Window, in <a href="https://www.glfw.org/docs/latest/intro_guide.html#coordinate_systems">screen coordinates</a>.
  ///
  /// This value may not necessarily match `Window.framebufferSize`. For example, on mac OS machines with high-DPI Retina displays.
  /// See_Also: <a href="https://www.glfw.org/docs/3.3/window_guide.html#window_size">Window size</a> in the GLFW documentation
  const(Size) size() @property const {
    return data.size;
  }
  /// Value used to disable minimum or maximum size limits of a Window.
  static const Size dontCare = Size(GLFW_DONT_CARE, GLFW_DONT_CARE);
  /// Minimum size of this Window's content area, in <a href="https://www.glfw.org/docs/latest/intro_guide.html#coordinate_systems">screen coordinates</a>.
  ///
  /// To disable the minimum size limit for this Window, set this property to `dontCare`.
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
  /// To disable the maximum size limit for this Window, set this property to `dontCare`.
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

  package (teraflop) bool hasMouseInputChanged() @property const {
    const mouseButtonsChanged = data.lastMouseButtons != data.mouseButtons;
    // TODO: Check mouse wheel pos for changes
    // const mouseWheelChanged = GetMouseWheelMove() != 0;
    const mousePosChanged = data.lastMousePos.x != data.mousePos.x || data.lastMousePos.y != data.mousePos.y;
    return mouseButtonsChanged || mousePosChanged;
  }

  package (teraflop) bool dirty() @property const {
    return data.dirty;
  }
  package (teraflop) Surface surface() @property const {
    return cast(Surface) _surface;
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

  package (teraflop) void update() {
    if (glfwWindowShouldClose(window)) {
      glfwDestroyWindow(window);
      _valid = false;
      return;
    }

    glfwPollEvents();
    data.update(window);
  }

  override void actionInput(const InputEventAction event) {
    assert(event.action.length);
    onUnhandledInput(event);
  }

  override bool unhandledInput(const InputEvent event) {
    onUnhandledInput(event);
    return true; // Mark handled
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
      import bindbc.glfw: GLFW_MOUSE_BUTTON_LEFT, GLFW_MOUSE_BUTTON_RIGHT, GLFW_MOUSE_BUTTON_MIDDLE;
      import std.conv : to;

      assert(window !is null);

      const size_t oldData = framebufferSize.width + framebufferSize.height;
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
