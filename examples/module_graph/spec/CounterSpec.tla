---- MODULE CounterSpec ----

EXTENDS Naturals, CounterHelper

VARIABLE x

Init == x = 0

Next == x' = Toggle(x)

Spec == Init /\ [][Next]_x

Inv == x \in {0, 1}

====
