/// Built-in Components and Component primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.components;

import gfx.graal : Device;
import teraflop.ecs : NamedComponent;

public import teraflop.components.transform;

/// A Component that holds one or more handles to GPU resources.
///
/// See_Also:
/// <h3>Implementations</h3>
/// $(UL
///   $(LI `teraflop.graphics.Material`)
///   $(LI `teraflop.graphics.Mesh`)
///   $(LI `teraflop.graphics.Shader`)
///   $(LI `teraflop.graphics.Texture`)
/// )
interface IResource {
  /// Whether this Resource has been successfully initialized.
  bool initialized() @property const;
  /// Initialize this Resource. `intiialized` should be `true` if successful.
  void initialize(scope Device device);
}

/// A file either read from the user's disk or from an in-memory buffer.
/// See_Also: `ObservableFile`
abstract class File : NamedComponent {
  static import std.file;

  private bool _exists = false;

  /// Path to this file.
  const string filePath;
  /// Contents of this file.
  const(ubyte)[] contents;

  /// Params:
  /// filePath = Path to a file.
  this(string filePath) {
    this.filePath = filePath;
    this._exists = std.file.exists(filePath);
    super(filePath);
  }
  /// Instantiate a static file given its in-memory `contents`.
  private this(const(ubyte)[] contents) {
    import std.digest.sha : toHexString, sha1Of;
    import std.string : format;

    this.filePath = null;
    this._exists = true;
    this.contents = contents;
    // Use a SHA-1 hash of this file's contents as this Component's name
    super(format!"%s:memory:%s"(this.classinfo.name, toHexString(sha1Of(contents))));
  }

  /// Whether this file exists.
  const(bool) exists() @property const {
    return _exists;
  }
  protected void exists(bool value) @property {
    _exists = value;
  }

  bool inMemory() @property const {
    return filePath is null && _exists;
  }
}

/// A collection of `ObservableFile`s.
/// See_Also: `ObservableFile`
abstract class ObservableFileCollection : NamedComponent {
  /// The collection of `ObservableFile`s.
  package (teraflop) ObservableFile[] observableFiles;

  /// Initialize a new named ObservableFileCollection.
  this(string name, ObservableFile[] observableFiles = []) {
    this.observableFiles = observableFiles;
    super(name);
  }
}

/// A file readable from the user's disk that may be watched for changes at runtime.
/// See_Also: `File`
abstract class ObservableFile : File {
  static import std.file;
  import std.typecons : Flag, No, Yes;
  import teraflop.async : Event;

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
    super(filePath);
    this.hotReload = hotReload;
    this.readFile();
  }
  /// Instantiate a static file given its in-memory `contents`.
  private this(const(ubyte)[] contents) {
    super(contents);
    this.hotReload = false;
  }
  ~this() {
    contents = new ubyte[0];
  }

  /// Whether this file exists. The file could not have been found initially, later moved, or deleted.
  override const(bool) exists() @property const {
    return super.exists;
  }
  private void exists(bool value) @property {
    super.exists = value;
  }

  package (teraflop) void readFile() {
    import std.stdio : File;

    this.exists = std.file.exists(filePath);
    if (!exists) return;

    auto file = File(filePath, "rb");
    contents = file.rawRead(new ubyte[file.size()]);
    file.close();
  }
}
