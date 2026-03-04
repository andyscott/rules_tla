---- MODULE ApalacheCounter ----
EXTENDS Integers

VARIABLE
    \* @type: Int;
    x

Init == x = 0

Next ==
    \/ /\ x < 3
       /\ x' = x + 1
    \/ /\ x = 3
       /\ x' = x

Inv == x >= 0 /\ x <= 3

AlwaysSafe == []Inv

====
