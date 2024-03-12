function bar(x: Document | string): void { }
bar(0);

class C { }
class D { }
function CD(b: boolean) {
  var E = b? C: D;
  var c:C = new E(); // error, since E could be D, and D is not a subtype of C
  function qux(e: E) { } // error: value-as-type
  function qux2(e: C | D) { } // OK
  qux2(new C);
}

declare class F {
    foo(x: number):void;
    foo(x: string):void;
}
function corge(b: boolean) {
    var x = b ? "" : 0;
    new F().foo(x);
}
