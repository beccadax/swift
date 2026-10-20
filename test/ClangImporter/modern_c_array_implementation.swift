// An @objc @implementation extension and an @c @implementation function can
// implement declarations from a header that have C arrays in their signatures,
// using the visible C array projection. The other projection is diagnosed.

// REQUIRES: objc_interop
// REQUIRES: executable_test
// REQUIRES: swift_feature_ModernImportedCArrays

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// Modern projection visible
// RUN: %target-swift-frontend -typecheck -verify -verify-ignore-unrelated %t/wrong.swift -I %t/include -enable-experimental-feature ModernImportedCArrays -target %target-has-inline-array-triple -DMODERN_C_ARRAYS -verify-additional-prefix modern-c-array-
// RUN: %target-build-swift -emit-executable %t/impl.swift %t/main.swift -o %t/modern -I %t/include -module-cache-path %t/module-cache -enable-experimental-feature ModernImportedCArrays -target %target-has-inline-array-triple -DMODERN_C_ARRAYS
// RUN: %target-codesign %t/modern
// RUN: %target-run %t/modern | %FileCheck %s

// Legacy projection visible
// RUN: %target-swift-frontend -typecheck -verify -verify-ignore-unrelated %t/wrong.swift -I %t/include -target %target-has-inline-array-triple -verify-additional-prefix legacy-c-array-
// RUN: %target-build-swift -emit-executable %t/impl.swift %t/main.swift -o %t/legacy -I %t/include -module-cache-path %t/module-cache -target %target-has-inline-array-triple
// RUN: %target-codesign %t/legacy
// RUN: %target-run %t/legacy | %FileCheck %s

// CHECK: method 2 2 3 4
// CHECK-NEXT: property 7 2 3 4
// CHECK-NEXT: function 3 2 3 4

//--- include/module.modulemap
module CLib {
  header "CLib.h"
  export *
}

//--- include/CLib.h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Impl : NSObject
- (void)bump:(int (*)[4])buf;
@property (nonatomic, nullable) int (*prop)[4];
@end

void cBump(int (*buf)[4]);

NS_ASSUME_NONNULL_END

//--- impl.swift
import CLib

#if MODERN_C_ARRAYS
typealias ImplArray = InlineArray<4, Int32>
#else
typealias ImplArray = (Int32, Int32, Int32, Int32)
#endif

@objc @implementation extension Impl {
  func bump(_ buf: UnsafeMutablePointer<ImplArray>) {
    UnsafeMutableRawPointer(buf).assumingMemoryBound(to: Int32.self).pointee += 1
  }

  var prop: UnsafeMutablePointer<ImplArray>?
}

@c @implementation func cBump(_ buf: UnsafeMutablePointer<ImplArray>) {
  UnsafeMutableRawPointer(buf).assumingMemoryBound(to: Int32.self).pointee += 1
}

//--- main.swift
import CLib

#if MODERN_C_ARRAYS
typealias CArray = InlineArray<4, Int32>
var array: CArray = [1, 2, 3, 4]
func show(_ label: String, _ a: CArray) { print(label, a[0], a[1], a[2], a[3]) }
#else
typealias CArray = (Int32, Int32, Int32, Int32)
var array: CArray = (1, 2, 3, 4)
func show(_ label: String, _ a: CArray) { print(label, a.0, a.1, a.2, a.3) }
#endif

let impl = Impl()
withUnsafeMutablePointer(to: &array) { pointer in
  impl.bump(pointer)
  show("method", pointer.pointee)

  impl.prop = pointer
  UnsafeMutableRawPointer(impl.prop!).assumingMemoryBound(to: Int32.self).pointee = 7
  show("property", impl.prop!.pointee)

  cBump(pointer)
  UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: Int32.self).pointee = 3
  show("function", pointer.pointee)
}

//--- wrong.swift
import CLib

#if MODERN_C_ARRAYS
typealias Wrong = (Int32, Int32, Int32, Int32)
#else
typealias Wrong = InlineArray<4, Int32>
#endif

@objc @implementation extension Impl {
  func bump(_ buf: UnsafeMutablePointer<Wrong>) {}
  // expected-error@-1 {{instance method cannot be in an '@objc @implementation' extension of a class (without final or '@nonobjc') because the type of the parameter cannot be represented in Objective-C}}
  // expected-note@-2 {{Swift structs cannot be represented in Objective-C}}

  var prop: UnsafeMutablePointer<Wrong>?
  // expected-error@-1 {{property cannot be in an '@objc @implementation' extension of a class (without final or '@nonobjc') because its type cannot be represented in Objective-C}}
}

@c @implementation func cBump(_ buf: UnsafeMutablePointer<Wrong>) {}
// expected-error@-1 {{global function cannot be marked '@c' because the type of the parameter cannot be represented in C}}
// expected-note@-2 {{Swift structs cannot be represented in C}}
// expected-error@-3 {{selector 'cBump:' for global function 'cBump' not found in header; did you mean 'cBump'?}}
