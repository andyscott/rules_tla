---- MODULE CounterModel ----
EXTENDS Integers

VARIABLES
    \* @type: Int;
    counter,
    \* @type: Str;
    action_taken

Init ==
    /\ counter = 0
    /\ action_taken = "init"

Increment ==
    /\ counter < 3
    /\ counter' = counter + 1
    /\ action_taken' = "increment"

Decrement ==
    /\ counter > 0
    /\ counter' = counter - 1
    /\ action_taken' = "decrement"

Next == Increment \/ Decrement

CounterInBounds == counter >= 0 /\ counter <= 3

\* `rules_tla` uses this as the explicit "find me a replayable trace" goal.
TraceComplete == counter /= 2

====
