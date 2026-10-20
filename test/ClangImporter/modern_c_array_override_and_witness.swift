// A Swift @objc protocol or class can use pointers to C arrays in its API.
// A client built with the other C array projection visible must still be able
// to implement and override that API, even though a new declaration would have
// to use its own projection.

// REQUIRES: objc_interop
// REQUIRES: swift_feature_ModernImportedCArrays

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// Library with the modern projection visible, client with the legacy projection
// RUN: %target-swift-frontend -emit-module -parse-as-library %t/lib.swift -module-name Lib -o %t/Lib.swiftmodule -enable-experimental-feature ModernImportedCArrays -target %target-has-inline-array-triple -DMODERN_C_ARRAYS
// RUN: %target-swift-frontend -typecheck -verify %t/client.swift -I %t -target %target-has-inline-array-triple -DLIB_MODERN_C_ARRAYS
// RUN: %target-swift-frontend -emit-ir %t/lowering.swift -I %t -target %target-has-inline-array-triple -DLIB_MODERN_C_ARRAYS -o /dev/null

// Library with the legacy projection visible, client with the modern projection
// RUN: %target-swift-frontend -emit-module -parse-as-library %t/lib.swift -module-name Lib -o %t/Lib.swiftmodule -target %target-has-inline-array-triple
// RUN: %target-swift-frontend -typecheck -verify %t/client.swift -I %t -enable-experimental-feature ModernImportedCArrays -target %target-has-inline-array-triple
// RUN: %target-swift-frontend -emit-ir %t/lowering.swift -I %t -enable-experimental-feature ModernImportedCArrays -target %target-has-inline-array-triple -o /dev/null

//--- lib.swift
import Foundation

#if MODERN_C_ARRAYS
public typealias LibArray = InlineArray<4, Int32>
#else
public typealias LibArray = (Int32, Int32, Int32, Int32)
#endif

@objc public protocol Q {
  func take(_ a: UnsafeMutablePointer<LibArray>)
  var property: UnsafeMutablePointer<LibArray>? { get set }
  subscript(_ a: UnsafeMutablePointer<LibArray>) -> Int { get }
  func give() -> UnsafeMutablePointer<LibArray>
}

@objc open class Base: NSObject {
  @objc open func take(_ a: UnsafeMutablePointer<LibArray>) {}
  @objc open var property: UnsafeMutablePointer<LibArray>?
  @objc open subscript(_ a: UnsafeMutablePointer<LibArray>) -> Int { 0 }
  @objc open func give() -> UnsafeMutablePointer<LibArray> { fatalError() }
}

//--- client.swift
import Foundation
import Lib

// The types of the library's declarations, whichever projection that is.
#if LIB_MODERN_C_ARRAYS
typealias ClientArray = InlineArray<4, Int32>
#else
typealias ClientArray = (Int32, Int32, Int32, Int32)
#endif

class Conformer: NSObject, Q {
  func take(_ a: UnsafeMutablePointer<ClientArray>) {}
  var property: UnsafeMutablePointer<ClientArray>?
  subscript(_ a: UnsafeMutablePointer<ClientArray>) -> Int { 1 }
  func give() -> UnsafeMutablePointer<ClientArray> { fatalError() }
}

class Subclass: Base {
  override func take(_ a: UnsafeMutablePointer<ClientArray>) {}
  override var property: UnsafeMutablePointer<ClientArray>? {
    get { nil }
    set {}
  }
  override subscript(_ a: UnsafeMutablePointer<ClientArray>) -> Int { 2 }
  override func give() -> UnsafeMutablePointer<ClientArray> { fatalError() }

  // A new declaration has to use the visible projection.
  @objc func new(_ a: UnsafeMutablePointer<ClientArray>) {}
  // expected-error@-1 {{instance method cannot be marked '@objc' because the type of the parameter cannot be represented in Objective-C}}
  // expected-note@-2 {{Swift structs cannot be represented in Objective-C}}
}

// An explicit @objc doesn't make an override or witness a new declaration.

class ExplicitConformer: NSObject, Q {
  @objc func take(_ a: UnsafeMutablePointer<ClientArray>) {}
  @objc var property: UnsafeMutablePointer<ClientArray>?
  @objc subscript(_ a: UnsafeMutablePointer<ClientArray>) -> Int { 1 }
  @objc func give() -> UnsafeMutablePointer<ClientArray> { fatalError() }
}

class ExplicitSubclass: Base {
  @objc override func take(_ a: UnsafeMutablePointer<ClientArray>) {}
  @objc override var property: UnsafeMutablePointer<ClientArray>? {
    get { nil }
    set {}
  }
  @objc override subscript(_ a: UnsafeMutablePointer<ClientArray>) -> Int { 2 }
  @objc override func give() -> UnsafeMutablePointer<ClientArray> { fatalError() }
}

// A member that doesn't implement anything is still a new declaration, even in
// a class that conforms to an @objc protocol.
class Unrelated: NSObject, Q {
  func take(_ a: UnsafeMutablePointer<ClientArray>) {}
  var property: UnsafeMutablePointer<ClientArray>?
  subscript(_ a: UnsafeMutablePointer<ClientArray>) -> Int { 1 }
  func give() -> UnsafeMutablePointer<ClientArray> { fatalError() }

  @objc func other(_ a: UnsafeMutablePointer<ClientArray>) {}
  // expected-error@-1 {{instance method cannot be marked '@objc' because the type of the parameter cannot be represented in Objective-C}}
  // expected-note@-2 {{Swift structs cannot be represented in Objective-C}}
}

//--- lowering.swift
import Foundation
import Lib

#if LIB_MODERN_C_ARRAYS
typealias ClientArray = InlineArray<4, Int32>
#else
typealias ClientArray = (Int32, Int32, Int32, Int32)
#endif

class Conformer: NSObject, Q {
  func take(_ a: UnsafeMutablePointer<ClientArray>) {}
  var property: UnsafeMutablePointer<ClientArray>?
  subscript(_ a: UnsafeMutablePointer<ClientArray>) -> Int { 1 }
  func give() -> UnsafeMutablePointer<ClientArray> { fatalError() }
}

class Subclass: Base {
  override func take(_ a: UnsafeMutablePointer<ClientArray>) {}
  override var property: UnsafeMutablePointer<ClientArray>? {
    get { nil }
    set {}
  }
  override subscript(_ a: UnsafeMutablePointer<ClientArray>) -> Int { 2 }
  override func give() -> UnsafeMutablePointer<ClientArray> { fatalError() }
}

func use(_ q: Q, _ base: Base, _ pointer: UnsafeMutablePointer<ClientArray>) {
  q.take(pointer)
  base.take(pointer)
  _ = q[pointer] + base[pointer]
}

// An explicit @objc doesn't make an override or witness a new declaration.

class ExplicitConformer: NSObject, Q {
  @objc func take(_ a: UnsafeMutablePointer<ClientArray>) {}
  @objc var property: UnsafeMutablePointer<ClientArray>?
  @objc subscript(_ a: UnsafeMutablePointer<ClientArray>) -> Int { 1 }
  @objc func give() -> UnsafeMutablePointer<ClientArray> { fatalError() }
}

class ExplicitSubclass: Base {
  @objc override func take(_ a: UnsafeMutablePointer<ClientArray>) {}
  @objc override var property: UnsafeMutablePointer<ClientArray>? {
    get { nil }
    set {}
  }
  @objc override subscript(_ a: UnsafeMutablePointer<ClientArray>) -> Int { 2 }
  @objc override func give() -> UnsafeMutablePointer<ClientArray> { fatalError() }
}
