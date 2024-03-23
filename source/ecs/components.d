/// Authors: Chance Snow
/// Copyright: Copyright © 2022 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.ecs.components;

///
interface Resource {
  import wgpu.api : Adapter, Device;

  /// Whether *all* of an `teraflop.ecs.Entity`'s GPU Resources have been initialized.
  /// See_Also: `teraflop.ecs.Entity.tag`
  static const Initialized = "Initialized";

  ///
  void initialize(Adapter adapter, Device device);
}

///
interface Asset : Resource {
  // TODO: Add a `teraflop.assets` module for cached asset resources?

  /// Whether *all* of an `teraflop.ecs.Entity`'s `Asset` Components have been loaded.
  /// See_Also: `teraflop.ecs.Entity.tag`
  static const Loaded = "Loaded";
}

/// A file either read from the user's disk or from an in-memory buffer.
/// See_Also: `ObservableFile`
struct File {
  static import std.file;

  package const string componentName;
  private bool _exists = false;

  /// Path to this file.
  /// Remarks: `null` if this file exists purely in-memory.
  const string filePath;
  /// Contents of this file.
  const(ubyte)[] contents;

  /// Params:
  /// filePath = Path to a file.
  this(string filePath) {
    this.filePath = componentName = filePath;
    this._exists = std.file.exists(filePath);
  }
  /// Instantiate a static file given its in-memory `contents`.
  package (teraflop) this(const(ubyte)[] contents) {
    import std.digest.sha : toHexString, sha1Of;
    import std.string : format;

    this.filePath = null;
    this._exists = true;
    this.contents = contents;
    // Use a SHA-1 hash of `contents` as this Component's name
    componentName = format!"File:memory:%s"(toHexString(sha1Of(contents)));
  }
  ~this() {
    contents = new ubyte[0];
  }

  /// Whether this file exists.
  const(bool) exists() @property const {
    return _exists;
  }
  protected void exists(bool value) @property {
    _exists = value;
  }

  /// Whether this file exists purely in-memory.
  bool inMemory() @property const {
    return filePath is null && _exists;
  }

  /// Convert this file into a `teraflop.ecs.NamedComponent`.
  auto component() @trusted @property const {
    import teraflop.ecs : named;
    return (cast(File) this).named(componentName);
  }
}

/// A file that may be watched for changes at runtime.
/// See_Also: `File`
struct ObservableFile {
  static import std.file;
  import std.typecons : Flag, No, Yes;
  import teraflop.async : Event;

  private File* _file;

  /// Whether this file is being watched for changes.
  const bool hotReload;

  /// Fired if the file is being actively watched and when the file's contents change.
  Event!(const(ubyte)[]) onChanged;
  /// Fired if the file is being actively watched and when the file was deleted.
  Event!(string) onDeleted;

  /// Params:
  /// filePath = Path to a file.
  /// hotReload = Whether to watch the given `filePath` for changes at runtime.
  this(string filePath, Flag!"hotReload" hotReload = No.hotReload) {
    _file = new File(filePath);
    this.hotReload = hotReload;
    this.readFile();
  }
  /// Instantiate a static file given its in-memory `contents`.
  package (teraflop) this(string contents) {
    import std.conv : to;
    this(contents.to!(const ubyte[]));
  }
  /// Instantiate a static file given its in-memory `contents`.
  package (teraflop) this(const(ubyte)[] contents) {
    _file = new File(contents);
    this.hotReload = false;
  }

  /// Whether this file exists. The file could not have been found initially, later moved, or deleted.
  const(bool) exists() @property const {
    return _file.exists;
  }

  /// Contents of this file.
  const(ubyte)[] contents() const @property {
    return _file.contents;
  }

  /// Convert this file into a `teraflop.ecs.NamedComponent`.
  auto component() @trusted @property const {
    import teraflop.ecs : named;
    return (cast(ObservableFile) this).named(_file.componentName);
  }

  package (teraflop) void readFile() {
    import std.stdio : File;

    _file.exists = std.file.exists(_file.filePath);
    if (!exists) return;

    auto file = File(_file.filePath, "rb");
    _file.contents = file.rawRead(new ubyte[file.size()]);
    file.close();
  }
}
