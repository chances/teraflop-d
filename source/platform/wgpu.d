module teraflop.platform.wgpu;

import bindbc.glfw;
import wgpu.api : Device, Surface, SwapChain, SwapChainDescriptor;

///
Surface createPlatformSurface(GLFWwindow* window) {
  version (linux) {
    auto display = glfwGetX11Display();
    auto x11Window = glfwGetX11Window(window);
    if (display != null && x11Window > 0)
      return Surface.fromXlib(cast(const(void)**) display, x11Window);
  }
  version (OSX) {
    auto cocoaWindow = cast(NSWindow) glfwGetCocoaWindow(window);
    cocoaWindow.contentView.wantsLayer = true;
    assert(cocoaWindow.contentView.wantsLayer);
    cocoaWindow.contentView.layer = CAMetalLayer.layer;
    return Surface.fromMetalLayer(cast(void*) cocoaWindow.contentView.layer);
  }
}

version (OSX) {
  import core.attribute : selector;
  import std.meta : Alias;

  alias id = Alias!(void*);

  extern (C) {
    ///
    id glfwGetCocoaWindow(GLFWwindow* window);
  }

  extern (Objective-C) {
    /// An object that manages image-based content and allows you to perform animations on that content.
    /// See_Also: https://developer.apple.com/documentation/quartzcore/calayer?language=objc
    extern class CALayer {
      /// Creates and returns an instance of the layer object.
      /// See_Also: https://developer.apple.com/documentation/quartzcore/calayer/1410793-layer?language=objc
      static CALayer layer() @selector("layer");
    }
    /// A Core Animation layer that Metal can render into, typically to be displayed onscreen.
    /// See_Also: https://developer.apple.com/documentation/quartzcore/cametallayer?language=objc
    extern class CAMetalLayer : CALayer {}
    /// A window that an app displays on the screen.
    /// See_Also: https://developer.apple.com/documentation/appkit/nswindow?language=objc
    extern interface NSWindow {
      /// The window’s content view, the highest accessible view object in the window’s view hierarchy.
      /// See_Also: https://developer.apple.com/documentation/appkit/nswindow/1419160-contentview?language=objc
      NSView contentView() @selector("contentView");
    }
    /// See_Also:
    extern interface NSView {
      /// A Boolean value indicating whether the view uses a layer as its backing store.
      /// See_Also: https://developer.apple.com/documentation/appkit/nsview/1483695-wantslayer?language=objc
      @property bool wantsLayer() @selector("wantsLayer");
      /// A Boolean value indicating whether the view uses a layer as its backing store.
      /// See_Also: https://developer.apple.com/documentation/appkit/nsview/1483695-wantslayer?language=objc
      @property void wantsLayer(bool value) @selector("setWantsLayer:");
      /// The Core Animation layer that the view uses as its backing store.
      /// See_Also: https://developer.apple.com/documentation/appkit/nsview/1483298-layer?language=objc
      @property CALayer layer() @selector("layer");
      /// The Core Animation layer that the view uses as its backing store.
      /// See_Also: https://developer.apple.com/documentation/appkit/nsview/1483298-layer?language=objc
      @property CALayer layer(CALayer value) @selector("setLayer:");
    }
  }
}
