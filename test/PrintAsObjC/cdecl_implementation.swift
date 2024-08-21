// Please keep this file in alphabetical order!

// REQUIRES: objc_interop

// Temporarily disable on arm64e (rdar://127675057)
// UNSUPPORTED: CPU=arm64e

// RUN: %empty-directory(%t)

// FIXME: BEGIN -enable-source-import hackaround
// RUN:  %target-swift-frontend(mock-sdk: -sdk %S/../Inputs/clang-importer-sdk -I %t) -emit-module -o %t %S/../Inputs/clang-importer-sdk/swift-modules/ObjectiveC.swift -disable-objc-attr-requires-foundation-module
// RUN:  %target-swift-frontend(mock-sdk: -sdk %S/../Inputs/clang-importer-sdk -I %t) -emit-module -o %t  %S/../Inputs/clang-importer-sdk/swift-modules/CoreGraphics.swift
// RUN:  %target-swift-frontend(mock-sdk: -sdk %S/../Inputs/clang-importer-sdk -I %t) -emit-module -o %t  %S/../Inputs/clang-importer-sdk/swift-modules/Foundation.swift
// FIXME: END -enable-source-import hackaround


// RUN: %target-swift-frontend(mock-sdk: -sdk %S/../Inputs/clang-importer-sdk -I %t) -emit-module -enable-experimental-feature CImplementation -I %S/Inputs/custom-modules -import-underlying-module -o %t %s -disable-objc-attr-requires-foundation-module -target %target-stable-abi-triple
// RUN: %target-swift-frontend(mock-sdk: -sdk %S/../Inputs/clang-importer-sdk -I %t) -parse-as-library %t/cdecl_implementation.swiftmodule -typecheck -enable-experimental-feature CImplementation -I %S/Inputs/custom-modules -emit-objc-header-path %t/cdecl_implementation-Swift.h -import-underlying-module -disable-objc-attr-requires-foundation-module -target %target-stable-abi-triple
// RUN: %FileCheck --check-prefix=NEGATIVE %s --input-file %t/cdecl_implementation-Swift.h
// RUN: %check-in-clang -I %S/Inputs/custom-modules/ %t/cdecl_implementation-Swift.h
// RUN: %check-in-clang -I %S/Inputs/custom-modules/ -fno-modules -Qunused-arguments %t/cdecl_implementation-Swift.h

import Foundation

@_cdecl("CImplFunc") @_objcImplementation func CImplFunc() {}
// NEGATIVE-NOT: CImplFunc(
