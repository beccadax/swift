//===--- CalleeAnalysis.swift - the callee analysis -----------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import OptimizerBridging
import SIL

public struct CalleeAnalysis {
  let bridged: BridgedCalleeAnalysis

  static func register() {
    CalleeAnalysis_register(
      // isDeinitBarrierFn:
      { (inst : BridgedInstruction, bca: BridgedCalleeAnalysis) -> Bool in
        return inst.instruction.isDeinitBarrier(bca.analysis)
      }
    )
  }

  public func getCallees(callee: Value) -> FunctionArray? {
    let bridgedFuncs = CalleeAnalysis_getCallees(bridged, callee.bridged)
    if bridgedFuncs.incomplete != 0 {
      return nil
    }
    return FunctionArray(bridged: bridgedFuncs)
  }

  public func getIncompleteCallees(callee: Value) -> FunctionArray {
    return FunctionArray(bridged: CalleeAnalysis_getCallees(bridged, callee.bridged))
  }

  public func getDestructor(ofExactType type: Type) -> Function? {
    let destructors = FunctionArray(bridged: CalleeAnalysis_getDestructors(bridged, type.bridged, /*isExactType*/ 1))
    if destructors.count == 1 {
      return destructors[0]
    }
    return nil
  }

  public func getDestructors(of type: Type) -> FunctionArray? {
    let bridgedDtors = CalleeAnalysis_getDestructors(bridged, type.bridged, /*isExactType*/ 0)
    if bridgedDtors.incomplete != 0 {
      return nil
    }
    return FunctionArray(bridged: bridgedDtors)
  }
}

extension FullApplySite {
  fileprivate func isBarrier(_ analysis: CalleeAnalysis) -> Bool {
    guard let callees = analysis.getCallees(callee: callee) else {
      return true
    }
    return callees.contains { $0.isDeinitBarrier }
  }
}

extension Instruction {
  public final func maySynchronize(_ analysis: CalleeAnalysis) -> Bool {
    if let site = self as? FullApplySite {
      return site.isBarrier(analysis)
    }
    return maySynchronizeNotConsideringSideEffects
  }

  /// Whether lifetime ends of lexical values may safely be hoisted over this
  /// instruction.
  ///
  /// Deinitialization barriers constrain variable lifetimes. Lexical
  /// end_borrow, destroy_value, and destroy_addr cannot be hoisted above them.
  public final func isDeinitBarrier(_ analysis: CalleeAnalysis) -> Bool {
    return mayAccessPointer || mayLoadWeakOrUnowned || maySynchronize(analysis)
  }
}

public struct FunctionArray : RandomAccessCollection, FormattedLikeArray {
  fileprivate let bridged: BridgedCalleeList

  public var startIndex: Int { 0 }
  public var endIndex: Int { BridgedFunctionArray_size(bridged) }

  public subscript(_ index: Int) -> Function {
    return BridgedFunctionArray_get(bridged, index).function
  }
}
// Bridging utilities

extension BridgedCalleeAnalysis {
  public var analysis: CalleeAnalysis { .init(bridged: self) }
}

