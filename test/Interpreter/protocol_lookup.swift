// Check both AOT and JIT modes
// RUN: %target-run-simple-swift | FileCheck %s
// RUN: %swift -interpret %s | FileCheck %s

protocol Fooable {
  func foo()
}

struct S: Fooable {
  func foo() { println("S") }
}

class C: Fooable {
  func foo() { println("C") }
}

class D: C {
  override func foo() { println("D") }
}

class E: D {
  override func foo() { println("E") }
}

struct X {}

extension Int: Fooable {
  func foo() { println("Int") }
}

func fooify<T>(x: T) {
  if let foo = x as? Fooable {
    foo.foo()
  } else {
    println("not fooable")
  }
}

struct G<T>: Fooable {
  func foo() { println("G") }
}

struct H<T> {}

fooify(1)   // CHECK:      Int
fooify(2)   // CHECK-NEXT: Int
fooify(S()) // CHECK-NEXT: S
fooify(S()) // CHECK-NEXT: S
fooify(C()) // CHECK-NEXT: C
fooify(C()) // CHECK-NEXT: C
fooify(D()) // CHECK-NEXT: D
fooify(D()) // CHECK-NEXT: D
fooify(E()) // CHECK-NEXT: E
fooify(E()) // CHECK-NEXT: E
fooify(X()) // CHECK-NEXT: not fooable
fooify(X()) // CHECK-NEXT: not fooable
fooify(G<Int>()) // CHECK-NEXT: G
fooify(G<Float>()) // CHECK-NEXT: G
fooify(G<Int>()) // CHECK-NEXT: G
fooify(H<Int>()) // CHECK-NEXT: not fooable
fooify(H<Float>()) // CHECK-NEXT: not fooable
fooify(H<Int>()) // CHECK-NEXT: not fooable

// TODO: generics w/ dependent witness tables

// Check casts from existentials.

fooify(1 as Any)   // CHECK:      Int
fooify(2 as Any)   // CHECK-NEXT: Int
fooify(S() as Any) // CHECK-NEXT: S
fooify(S() as Any) // CHECK-NEXT: S
fooify(C() as Any) // CHECK-NEXT: C
fooify(C() as Any) // CHECK-NEXT: C
fooify(D() as Any) // CHECK-NEXT: D
fooify(D() as Any) // CHECK-NEXT: D
fooify(E() as Any) // CHECK-NEXT: E
fooify(E() as Any) // CHECK-NEXT: E
fooify(X() as Any) // CHECK-NEXT: not fooable
fooify(X() as Any) // CHECK-NEXT: not fooable
fooify(G<Int>() as Any) // CHECK-NEXT: G
fooify(G<Float>() as Any) // CHECK-NEXT: G
fooify(G<Int>() as Any) // CHECK-NEXT: G
fooify(H<Int>() as Any) // CHECK-NEXT: not fooable
fooify(H<Float>() as Any) // CHECK-NEXT: not fooable
fooify(H<Int>() as Any) // CHECK-NEXT: not fooable

protocol Barrable {
  func bar()
}
extension Int: Barrable {
  func bar() { println("Int.bar") }
}

let foo: Fooable = 2
if let bar = foo as? Barrable {
  bar.bar() // CHECK-NEXT: Int.bar
} else {
  println("not barrable")
}

let foo2: Fooable = S()
if let bar2 = foo2 as? Barrable {
  bar2.bar()
} else {
  println("not barrable") // CHECK-NEXT: not barrable
}
