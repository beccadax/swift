//===--- TypeDifference.cpp - Utility for concrete type unification -------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#include "TypeDifference.h"
#include "swift/AST/Types.h"
#include "swift/AST/TypeMatcher.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"
#include "RewriteContext.h"
#include "RewriteSystem.h"
#include "Term.h"

using namespace swift;
using namespace rewriting;

void TypeDifference::dump(llvm::raw_ostream &out) const {
  llvm::errs() << "LHS: " << LHS << "\n";
  llvm::errs() << "RHS: " << RHS << "\n";

  for (const auto &pair : SameTypes) {
    out << "- " << LHS.getSubstitutions()[pair.first] << " (#";
    out << pair.first << ") -> " << pair.second << "\n";
  }

  for (const auto &pair : ConcreteTypes) {
    out << "- " << LHS.getSubstitutions()[pair.first] << " (#";
    out << pair.first << ") -> " << pair.second << "\n";
  }
}

void TypeDifference::verify(RewriteContext &ctx) const {
#ifndef NDEBUG

#define VERIFY(expr, str) \
  if (!(expr)) { \
    llvm::errs() << "TypeDifference::verify(): " << str << "\n"; \
    dump(llvm::errs()); \
    abort(); \
  }

  VERIFY(LHS.getKind() == RHS.getKind(), "Kind mismatch");

  if (LHS == RHS) {
    VERIFY(SameTypes.empty(), "Abstract substitutions with equal symbols");
    VERIFY(ConcreteTypes.empty(), "Concrete substitutions with equal symbols");
  } else {
    VERIFY(!SameTypes.empty() || !ConcreteTypes.empty(),
           "Missing substitutions with non-equal symbols");

    llvm::DenseSet<unsigned> lhsVisited;

    for (const auto &pair : SameTypes) {
      auto first = LHS.getSubstitutions()[pair.first];
      VERIFY(*first.compare(pair.second, ctx) > 0, "Order violation");
      VERIFY(lhsVisited.insert(pair.first).second, "Duplicate substitutions");
    }

    for (const auto &pair : ConcreteTypes) {
      VERIFY(pair.first < LHS.getSubstitutions().size(),
             "Out-of-bounds substitution");
      VERIFY(lhsVisited.insert(pair.first).second, "Duplicate substitutions");
      VERIFY(pair.second.getKind() == Symbol::Kind::ConcreteType, "Bad kind");
    }
  }

#undef VERIFY
#endif
}

namespace {
  class ConcreteTypeMatcher : public TypeMatcher<ConcreteTypeMatcher> {
    ArrayRef<Term> LHSSubstitutions;
    ArrayRef<Term> RHSSubstitutions;
    RewriteContext &Context;
    
  public:
    /// Mismatches where both sides are type parameters and the left hand
    /// side orders before the right hand side. The integer is an index
    /// into the LHSSubstitutions array.
    SmallVector<std::pair<unsigned, Term>, 1> SameTypesOnLHS;

    /// Mismatches where both sides are type parameters and the left hand
    /// side orders after the right hand side. The integer is an index
    /// into the RHSSubstitutions array.
    SmallVector<std::pair<unsigned, Term>, 1> SameTypesOnRHS;

    /// Mismatches where the left hand side is concrete and the right hand
    /// side is a type parameter. The integer is an index into the
    /// RHSSubstitutions array.
    SmallVector<std::pair<unsigned, Symbol>, 1> ConcreteTypesOnLHS;

    /// Mismatches where the right hand side is concrete and the left hand
    /// side is a type parameter. The integer is an index into the
    /// LHSSubstitutions array.
    SmallVector<std::pair<unsigned, Symbol>, 1> ConcreteTypesOnRHS;

    /// Mismatches where both sides are concrete; the presence of at least
    /// one such mismatch indicates a conflict.
    SmallVector<std::pair<CanType, CanType>, 1> ConcreteConflicts;

    ConcreteTypeMatcher(ArrayRef<Term> lhsSubstitutions,
                        ArrayRef<Term> rhsSubstitutions,
                        RewriteContext &ctx)
        : LHSSubstitutions(lhsSubstitutions),
          RHSSubstitutions(rhsSubstitutions),
          Context(ctx) {}

    bool alwaysMismatchTypeParameters() const { return true; }

    bool mismatch(TypeBase *lhsType, TypeBase *rhsType,
                  Type sugaredFirstType) {
      bool lhsAbstract = lhsType->isTypeParameter();
      bool rhsAbstract = rhsType->isTypeParameter();

      if (lhsAbstract && rhsAbstract) {
        unsigned lhsIndex = RewriteContext::getGenericParamIndex(lhsType);
        unsigned rhsIndex = RewriteContext::getGenericParamIndex(rhsType);

        auto lhsTerm = LHSSubstitutions[lhsIndex];
        auto rhsTerm = RHSSubstitutions[rhsIndex];

        Optional<int> compare = lhsTerm.compare(rhsTerm, Context);
        if (*compare < 0) {
          SameTypesOnLHS.emplace_back(rhsIndex, lhsTerm);
        } else if (compare > 0) {
          SameTypesOnRHS.emplace_back(lhsIndex, rhsTerm);
        } else {
          assert(lhsTerm == rhsTerm);
        }
        return true;
      }

      if (lhsAbstract) {
        assert(!rhsAbstract);
        unsigned lhsIndex = RewriteContext::getGenericParamIndex(lhsType);

        SmallVector<Term, 2> result;
        auto rhsSchema = Context.getRelativeSubstitutionSchemaFromType(
            CanType(rhsType), RHSSubstitutions, result);
        auto rhsSymbol = Symbol::forConcreteType(rhsSchema, result, Context);

        ConcreteTypesOnRHS.emplace_back(lhsIndex, rhsSymbol);
        return true;
      }

      if (rhsAbstract) {
        assert(!lhsAbstract);
        unsigned rhsIndex = RewriteContext::getGenericParamIndex(rhsType);

        SmallVector<Term, 2> result;
        auto lhsSchema = Context.getRelativeSubstitutionSchemaFromType(
            CanType(lhsType), LHSSubstitutions, result);
        auto lhsSymbol = Symbol::forConcreteType(lhsSchema, result, Context);

        ConcreteTypesOnLHS.emplace_back(rhsIndex, lhsSymbol);
        return true;
      }

      // Any other kind of type mismatch involves conflicting concrete types on
      // both sides, which can only happen on invalid input.
      assert(!lhsAbstract && !rhsAbstract);
      ConcreteConflicts.emplace_back(CanType(lhsType), CanType(rhsType));
      return true;
    }

    void verify() const {
#ifndef NDEBUG

#define VERIFY(expr, str) \
  if (!(expr)) { \
    llvm::errs() << "ConcreteTypeMatcher::verify(): " << str << "\n"; \
    dump(llvm::errs()); \
    abort(); \
  }

      llvm::DenseSet<unsigned> lhsVisited;
      llvm::DenseSet<unsigned> rhsVisited;

      for (const auto &pair : SameTypesOnLHS) {
        auto first = RHSSubstitutions[pair.first];
        VERIFY(*first.compare(pair.second, Context) > 0, "Order violation");

        VERIFY(rhsVisited.insert(pair.first).second, "Duplicate substitution");
      }

      for (const auto &pair : SameTypesOnRHS) {
        auto first = LHSSubstitutions[pair.first];
        VERIFY(*first.compare(pair.second, Context) > 0, "Order violation");

        VERIFY(lhsVisited.insert(pair.first).second, "Duplicate substitution");
      }

      for (const auto &pair : ConcreteTypesOnLHS) {
      VERIFY(pair.first < RHSSubstitutions.size(),
             "Out-of-bounds substitution");
        VERIFY(rhsVisited.insert(pair.first).second, "Duplicate substitution");
      }

      for (const auto &pair : ConcreteTypesOnRHS) {
        VERIFY(pair.first < LHSSubstitutions.size(),
               "Out-of-bounds substitution");
        VERIFY(lhsVisited.insert(pair.first).second, "Duplicate substitution");
      }

#undef VERIFY
#endif
    }

    void dump(llvm::raw_ostream &out) const {
      out << "Abstract differences with LHS < RHS:\n";
      for (const auto &pair : SameTypesOnLHS) {
        out << "- " << RHSSubstitutions[pair.first] << " (#";
        out << pair.first << ") -> " << pair.second << "\n";
      }

      out << "Abstract differences with RHS < LHS:\n";
      for (const auto &pair : SameTypesOnRHS) {
        out << "- " << LHSSubstitutions[pair.first] << " (#";
        out << pair.first << ") -> " << pair.second << "\n";
      }

      out << "Concrete differences with LHS < RHS:\n";
      for (const auto &pair : ConcreteTypesOnLHS) {
        out << "- " << RHSSubstitutions[pair.first] << " (#";
        out << pair.first << ") -> " << pair.second << "\n";
      }

      out << "Concrete differences with RHS < LHS:\n";
      for (const auto &pair : ConcreteTypesOnRHS) {
        out << "- " << LHSSubstitutions[pair.first] << " (#";
        out << pair.first << ") -> " << pair.second << "\n";
      }

      out << "Concrete conflicts:\n";
      for (const auto &pair : ConcreteConflicts) {
        out << "- " << pair.first << " vs " << pair.second << "\n";
      }
    }
  };
}

TypeDifference
swift::rewriting::buildTypeDifference(
    Symbol symbol,
    const llvm::SmallVector<std::pair<unsigned, Term>, 1> &sameTypes,
    const llvm::SmallVector<std::pair<unsigned, Symbol>, 1> &concreteTypes,
    RewriteContext &ctx) {
  auto &astCtx = ctx.getASTContext();

  SmallVector<Term, 2> resultSubstitutions;

  auto nextSubstitution = [&](Term t) -> Type {
    unsigned index = resultSubstitutions.size();
    resultSubstitutions.push_back(t);
    return GenericTypeParamType::get(/*isTypeSequence=*/false,
                                     /*depth=*/0, index, astCtx);
  };

  auto type = symbol.getConcreteType();
  auto substitutions = symbol.getSubstitutions();

  Type resultType = type.transformRec([&](Type t) -> Optional<Type> {
    if (t->is<GenericTypeParamType>()) {
      unsigned index = RewriteContext::getGenericParamIndex(t);

      for (const auto &pair : sameTypes) {
        if (pair.first == index)
          return nextSubstitution(pair.second);
      }

      for (const auto &pair : concreteTypes) {
        if (pair.first == index) {
          auto concreteSymbol = pair.second;
          auto concreteType = concreteSymbol.getConcreteType();

          return concreteType.transformRec([&](Type t) -> Optional<Type> {
            if (t->is<GenericTypeParamType>()) {
              unsigned index = RewriteContext::getGenericParamIndex(t);
              Term substitution = concreteSymbol.getSubstitutions()[index];
              return nextSubstitution(substitution);
            }

            assert(!t->is<DependentMemberType>());
            return None;
          });
        }
      }

      assert(!t->is<DependentMemberType>());
      return nextSubstitution(substitutions[index]);
    }

    return None;
  });

  auto resultSymbol = [&]() {
    switch (symbol.getKind()) {
    case Symbol::Kind::Superclass:
      return Symbol::forSuperclass(CanType(resultType),
                                   resultSubstitutions, ctx);
    case Symbol::Kind::ConcreteType:
      return Symbol::forConcreteType(CanType(resultType),
                                     resultSubstitutions, ctx);
    case Symbol::Kind::ConcreteConformance:
      return Symbol::forConcreteConformance(CanType(resultType),
                                            resultSubstitutions,
                                            symbol.getProtocol(),
                                            ctx);
    default:
      break;
    }

    llvm_unreachable("Bad symbol kind");
  }();

  return {symbol, resultSymbol, sameTypes, concreteTypes};
}

unsigned
RewriteSystem::recordTypeDifference(Symbol lhs, Symbol rhs,
                                    const TypeDifference &difference) {
  assert(lhs == difference.LHS);
  assert(rhs == difference.RHS);
  assert(lhs != rhs);

  auto key = std::make_pair(lhs, rhs);
  auto found = DifferenceMap.find(key);
  if (found != DifferenceMap.end())
    return found->second;

  unsigned index = Differences.size();
  Differences.push_back(difference);

  auto inserted = DifferenceMap.insert(std::make_pair(key, index));
  assert(inserted.second);
  (void) inserted;

  return index;
}

const TypeDifference &RewriteSystem::getTypeDifference(unsigned index) const {
  return Differences[index];
}

/// Computes the "meet" (LHS ∧ RHS) of two concrete type symbols (LHS and RHS
/// respectively), together with a set of transformations that turn LHS into
/// (LHS ∧ RHS) and RHS into (LHS ∧ RHS), respectively.
///
/// Returns 0, 1 or 2 transformations via the two Optional<unsigned>
/// out parameters. The integer is an index that can be passed to
/// RewriteSystem::getTypeDifference() to return a TypeDifference.
///
/// - If LHS == RHS, both lhsDifference and rhsDifference will be None.
///
/// - If LHS == (LHS ∧ RHS), then lhsTransform will be None. Otherwise,
///   lhsTransform describes the transform from LHS to (LHS ∧ RHS).
///
/// - If RHS == (LHS ∧ RHS), then rhsTransform will be None. Otherwise,
///   rhsTransform describes the transform from LHS to (LHS ∧ RHS).
///
/// - If (LHS ∧ RHS) is distinct from both LHS and RHS, then both
///   lhsTransform and rhsTransform will be populated with a value.
///
/// Also returns a boolean indicating if there was a concrete type conflict,
/// meaning that LHS and RHS had distinct concrete types at the same
/// position (eg, if LHS == Array<Int> and RHS == Array<String>).
///
/// See the comment at the top of TypeDifference in TypeDifference.h for a
/// description of the actual transformations.
bool
RewriteSystem::computeTypeDifference(Symbol lhs, Symbol rhs,
                                     Optional<unsigned> &lhsDifferenceID,
                                     Optional<unsigned> &rhsDifferenceID) {
  assert(lhs.getKind() == rhs.getKind());

  lhsDifferenceID = None;
  rhsDifferenceID = None;

  // Fast path if there's nothing to do.
  if (lhs == rhs)
    return false;

  // Match the types to find differences.
  ConcreteTypeMatcher matcher(lhs.getSubstitutions(),
                              rhs.getSubstitutions(),
                              Context);

  bool success = matcher.match(lhs.getConcreteType(),
                               rhs.getConcreteType());
  assert(success);
  (void) success;

  matcher.verify();

  auto lhsMeetRhs = buildTypeDifference(lhs,
                                        matcher.SameTypesOnRHS,
                                        matcher.ConcreteTypesOnRHS,
                                        Context);
  lhsMeetRhs.verify(Context);

  auto rhsMeetLhs = buildTypeDifference(rhs,
                                        matcher.SameTypesOnLHS,
                                        matcher.ConcreteTypesOnLHS,
                                        Context);
  rhsMeetLhs.verify(Context);

  bool isConflict = (matcher.ConcreteConflicts.size() > 0);

#ifndef NDEBUG
  if (!isConflict) {
    // The meet operation should be commutative.
    if (lhsMeetRhs.RHS != rhsMeetLhs.RHS) {
      llvm::errs() << "Meet operation was not commutative:\n\n";

      llvm::errs() << "LHS: " << lhs << "\n";
      llvm::errs() << "RHS: " << rhs << "\n";
      matcher.dump(llvm::errs());

      llvm::errs() << "\n";
      llvm::errs() << "LHS ∧ RHS: " << lhsMeetRhs.RHS << "\n";
      llvm::errs() << "RHS ∧ LHS: " << rhsMeetLhs.RHS << "\n";
      abort();
    }

    // The meet operation should be idempotent.
    {
      // (LHS ∧ (LHS ∧ RHS)) == (LHS ∧ RHS)
      auto lhsMeetLhsMeetRhs = buildTypeDifference(lhs,
                                                   lhsMeetRhs.SameTypes,
                                                   lhsMeetRhs.ConcreteTypes,
                                                   Context);

      lhsMeetLhsMeetRhs.verify(Context);

      if (lhsMeetRhs.RHS != lhsMeetLhsMeetRhs.RHS) {
        llvm::errs() << "Meet operation was not idempotent:\n\n";

        llvm::errs() << "LHS: " << lhs << "\n";
        llvm::errs() << "RHS: " << rhs << "\n";
        matcher.dump(llvm::errs());

        llvm::errs() << "\n";
        llvm::errs() << "LHS ∧ RHS: " << lhsMeetRhs.RHS << "\n";
        llvm::errs() << "LHS ∧ (LHS ∧ RHS): " << lhsMeetLhsMeetRhs.RHS << "\n";
        abort();
      }
    }

    {
      // (RHS ∧ (RHS ∧ LHS)) == (RHS ∧ LHS)
      auto rhsMeetRhsMeetRhs = buildTypeDifference(rhs,
                                                   rhsMeetLhs.SameTypes,
                                                   rhsMeetLhs.ConcreteTypes,
                                                   Context);

      rhsMeetRhsMeetRhs.verify(Context);

      if (lhsMeetRhs.RHS != rhsMeetRhsMeetRhs.RHS) {
        llvm::errs() << "Meet operation was not idempotent:\n\n";

        llvm::errs() << "LHS: " << lhs << "\n";
        llvm::errs() << "RHS: " << rhs << "\n";
        matcher.dump(llvm::errs());

        llvm::errs() << "\n";
        llvm::errs() << "RHS ∧ LHS: " << rhsMeetLhs.RHS << "\n";
        llvm::errs() << "RHS ∧ (RHS ∧ LHS): " << rhsMeetRhsMeetRhs.RHS << "\n";
        abort();
      }
    }
  }
#endif

  if (lhs != lhsMeetRhs.RHS)
    lhsDifferenceID = recordTypeDifference(lhs, lhsMeetRhs.RHS, lhsMeetRhs);

  if (rhs != rhsMeetLhs.RHS)
    rhsDifferenceID = recordTypeDifference(rhs, rhsMeetLhs.RHS, rhsMeetLhs);

  return isConflict;
}