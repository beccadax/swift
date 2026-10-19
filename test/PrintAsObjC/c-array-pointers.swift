// Pointers to C arrays are printed as pointers to arrays in Objective-C and C.

// RUN: %empty-directory(%t)

// With the modern projection visible, C arrays are InlineArrays.
// RUN: %target-swift-frontend(mock-sdk: %clang-importer-sdk) -emit-module -o %t %s -disable-objc-attr-requires-foundation-module -target %target-has-inline-array-triple -enable-experimental-feature ModernImportedCArrays -DMODERN_C_ARRAYS
// RUN: %target-swift-frontend(mock-sdk: %clang-importer-sdk) -parse-as-library %t/c-array-pointers.swiftmodule -typecheck -verify -emit-objc-header-path %t/c-array-pointers.h -import-objc-header %S/../Inputs/empty.h -disable-objc-attr-requires-foundation-module -target %target-has-inline-array-triple -enable-experimental-feature ModernImportedCArrays -DMODERN_C_ARRAYS
// RUN: %FileCheck %s < %t/c-array-pointers.h
// RUN: %check-in-clang %t/c-array-pointers.h

// With the legacy projection visible, they're tuples, but they print the same.
// RUN: %empty-directory(%t)
// RUN: %target-swift-frontend(mock-sdk: %clang-importer-sdk) -emit-module -o %t %s -disable-objc-attr-requires-foundation-module -target %target-has-inline-array-triple
// RUN: %target-swift-frontend(mock-sdk: %clang-importer-sdk) -parse-as-library %t/c-array-pointers.swiftmodule -typecheck -verify -emit-objc-header-path %t/c-array-pointers.h -import-objc-header %S/../Inputs/empty.h -disable-objc-attr-requires-foundation-module -target %target-has-inline-array-triple
// RUN: %FileCheck %s < %t/c-array-pointers.h
// RUN: %check-in-clang %t/c-array-pointers.h

// REQUIRES: objc_interop
// REQUIRES: swift_feature_ModernImportedCArrays

import ObjectiveC

// Spell C arrays the way the visible projection does.
#if MODERN_C_ARRAYS
public typealias Array2<T> = InlineArray<2, T>
public typealias Array3<T> = InlineArray<3, T>
public typealias Array4<T> = InlineArray<4, T>
#else
public typealias Array2<T> = (T, T)
public typealias Array3<T> = (T, T, T)
public typealias Array4<T> = (T, T, T, T)
#endif

// CHECK-DAG: SWIFT_EXTERN void cArrays(int32_t (* _Nonnull a)[4], int32_t const (* _Nonnull b)[2][3]) SWIFT_NOEXCEPT SWIFT_AVAILABILITY(anyappleos,introduced=26);
@available(anyAppleOS 26, *)
@c public func cArrays(_ a: UnsafeMutablePointer<Array4<Int32>>,
                       _ b: UnsafePointer<Array2<Array3<Int32>>>) {}

// The declarator of a pointer to an array encloses the declared name, which
// nests with the declarators of function types and other arrays.

public typealias Row = Array4<Int32>
public typealias RowPointer = UnsafeMutablePointer<Row>

// CHECK-DAG: SWIFT_EXTERN uint8_t const (* _Nonnull const (* _Nonnull cNested(uint8_t const (* _Nonnull const (* _Nonnull a)[4])[3]))[2])[3] SWIFT_NOEXCEPT SWIFT_WARN_UNUSED_RESULT SWIFT_AVAILABILITY(anyappleos,introduced=26);
@available(anyAppleOS 26, *)
@c public func cNested(
    _ a: UnsafePointer<Array4<UnsafePointer<Array3<UInt8>>>>
) -> UnsafePointer<Array2<UnsafePointer<Array3<UInt8>>>> {
  fatalError()
}

// CHECK-DAG: SWIFT_EXTERN int32_t (* _Nonnull cCallback(int32_t (* _Nonnull (* _Nonnull f)(int32_t (* _Nonnull)[4]))[4]))[2][4] SWIFT_NOEXCEPT SWIFT_WARN_UNUSED_RESULT SWIFT_AVAILABILITY(anyappleos,introduced=26);
@available(anyAppleOS 26, *)
@c public func cCallback(
    _ f: @convention(c) (RowPointer) -> RowPointer
) -> UnsafeMutablePointer<Array2<Row>> {
  fatalError()
}

// CHECK-DAG: SWIFT_EXTERN int32_t (* _Nonnull (* _Nonnull cFunctionPointerElements(void (* _Nonnull (* _Nonnull a)[4])(void)))[2])(int32_t) SWIFT_NOEXCEPT SWIFT_WARN_UNUSED_RESULT SWIFT_AVAILABILITY(anyappleos,introduced=26);
@available(anyAppleOS 26, *)
@c public func cFunctionPointerElements(
    _ a: UnsafeMutablePointer<Array4<@convention(c) () -> Void>>
) -> UnsafeMutablePointer<Array2<@convention(c) (Int32) -> Int32>> {
  fatalError()
}

// CHECK-LABEL: @interface Arrays
@available(anyAppleOS 26, *)
@objc class Arrays {
  // CHECK-NEXT: - (void)inlineArray:(int32_t (* _Nonnull)[4])a;
  @objc func inlineArray(_ a: UnsafeMutablePointer<Array4<Int32>>) {}

  // CHECK-NEXT: - (void)constPointer:(int32_t const (* _Nullable)[4])a;
  @objc func constPointer(_ a: UnsafePointer<Array4<Int32>>?) {}

  // CHECK-NEXT: - (void)nested:(int32_t (* _Nonnull)[3][2])a;
  @objc func nested(_ a: UnsafeMutablePointer<Array3<Array2<Int32>>>) {}

  // CHECK-NEXT: - (int32_t (* _Nullable)[4])result SWIFT_WARN_UNUSED_RESULT;
  @objc func result() -> UnsafeMutablePointer<Array4<Int32>>? { nil }

  // CHECK-NEXT: @property (nonatomic) int32_t (* _Nullable property)[4];
  @objc var property: UnsafeMutablePointer<Array4<Int32>>?

}
// CHECK-NEXT: @end

// CHECK-LABEL: @interface Edges
@available(anyAppleOS 26, *)
@objc class Edges {
  // An array of pointers to arrays
  // CHECK-NEXT: - (void)nestedPointers:(uint8_t const (* _Nonnull const (* _Nonnull)[4])[3])a;
  @objc func nestedPointers(
      _ a: UnsafePointer<Array4<UnsafePointer<Array3<UInt8>>>>) {}

  // A pointer to a pointer to an array
  // CHECK-NEXT: - (void)doublePointer:(int32_t (* _Nonnull * _Nonnull)[4])a;
  @objc func doublePointer(_ a: UnsafeMutablePointer<RowPointer>) {}

  // CHECK-NEXT: - (void)doublePointerOptional:(int32_t (* _Nullable * _Nullable)[4])a;
  @objc func doublePointerOptional(_ a: UnsafeMutablePointer<RowPointer?>?) {}

  // CHECK-NEXT: - (void)deep:(int32_t (* _Nonnull (* _Nonnull (* _Nonnull * _Nonnull)[2])[3])[4])a;
  @objc func deep(
      _ a: UnsafeMutablePointer<UnsafeMutablePointer<Array2<UnsafeMutablePointer<Array3<UnsafeMutablePointer<Row>>>>>>) {}

  // Pointers to arrays in the signatures of blocks and function pointers
  // CHECK-NEXT: - (void)block:(int32_t (* _Nullable (^ _Nonnull)(int32_t (* _Nonnull)[4]))[2])f;
  @objc func block(
      _ f: @escaping (RowPointer) -> UnsafeMutablePointer<Array2<Int32>>?) {}

  // CHECK-NEXT: - (int32_t (* _Nonnull (^ _Nonnull (^ _Nonnull)(int32_t (* _Nonnull)[4]))(int32_t (* _Nonnull)[4]))[4])blockReturningBlock SWIFT_WARN_UNUSED_RESULT;
  @objc func blockReturningBlock() -> (RowPointer) -> (RowPointer) -> RowPointer {
    fatalError()
  }

  // CHECK-NEXT: @property (nonatomic, copy) int32_t (* _Nonnull (^ _Nullable blockProperty)(int32_t (* _Nonnull)[4]))[4];
  @objc var blockProperty: ((RowPointer) -> RowPointer)?

  // CHECK-NEXT: - (void)functionPointer:(int32_t (* _Nonnull (* _Nonnull)(int32_t (* _Nonnull)[4]))[4])f;
  @objc func functionPointer(_ f: @convention(c) (RowPointer) -> RowPointer) {}

  // CHECK-NEXT: - (void)blockTakingFunctionPointerArray:(void (^ _Nonnull)(void (* _Nonnull (* _Nonnull)[2])(void)))f;
  @objc func blockTakingFunctionPointerArray(
      _ f: @escaping (UnsafeMutablePointer<Array2<@convention(c) () -> Void>>) -> Void) {}

  // An array of function pointers
  // CHECK-NEXT: - (void)functionPointerElements:(void (* _Nonnull (* _Nonnull)[4])(void))a;
  @objc func functionPointerElements(
      _ a: UnsafeMutablePointer<Array4<@convention(c) () -> Void>>) {}

  // CHECK-NEXT: - (void)functionPointerElementsWithArrays:(int32_t (* _Nonnull (* _Nonnull (* _Nonnull)[2])(int32_t (* _Nonnull)[4]))[4])a;
  @objc func functionPointerElementsWithArrays(
      _ a: UnsafeMutablePointer<Array2<@convention(c) (RowPointer) -> RowPointer>>) {}

  // Aliases and sugar
  // CHECK-NEXT: - (void)alias:(int32_t (* _Nonnull)[4])a :(int32_t (* _Nonnull)[4])b :(int32_t (* _Nonnull)[4])c;
  @objc func alias(_ a: RowPointer, _ b: UnsafeMutablePointer<Row>,
                   _ c: UnsafeMutablePointer<Array4<Int32>>) {}

  // Multiple dimensions
  // CHECK-NEXT: - (void)dimensions:(int32_t (* _Nonnull)[2][2])a :(int32_t const (* _Nonnull)[3])b;
  @objc func dimensions(_ a: UnsafeMutablePointer<Array2<Array2<Int32>>>,
                        _ b: UnsafePointer<Array3<Int32>>) {}

  // Several in one signature, and a parameter whose name is a keyword
  // CHECK-NEXT: - (int32_t (* _Nonnull)[4])several:(int32_t (* _Nonnull)[4])a :(int32_t const (* _Nonnull)[4])default_ :(int32_t (* _Nullable)[4])c SWIFT_WARN_UNUSED_RESULT;
  @objc func several(_ a: RowPointer, _ default: UnsafePointer<Row>,
                     _ c: RowPointer?) -> RowPointer {
    fatalError()
  }

  // Not confused by ordinary pointers
  // CHECK-NEXT: - (void)mixed:(int32_t * _Nonnull * _Nonnull)a :(int32_t * _Nonnull (* _Nonnull)[2])b;
  @objc func mixed(_ a: UnsafeMutablePointer<UnsafeMutablePointer<Int32>>,
                   _ b: UnsafeMutablePointer<Array2<UnsafeMutablePointer<Int32>>>) {}
}
// CHECK-NEXT: @end
