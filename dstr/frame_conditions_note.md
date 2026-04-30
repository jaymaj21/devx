# On Omitted Next-State Constraints in `dstr`

This note records a design discussion about the meaning of omitted next-state
constraints in `dstr` actions.

## The Question

Suppose an action mentions no constraint involving `x+` for some variable `x`.
Should the system automatically behave as though the action implicitly contains:

```lisp
(= x+ x)
```

In other words, should omission mean "unchanged"?

## Current Meaning

Under the current relational reading of `dstr`, omission has a precise meaning:

- if an action says nothing about `x+`, then the action does not constrain the
  successor value of `x`
- therefore any `x+` value from the declared domain is permitted, provided the
  rest of the action predicate is satisfied

So omission is not a missing detail. It is itself a semantic choice.

Another useful way to view the current semantics is this:

- the system first determines the full state universe from the Cartesian product
  of the declared variable domains
- the `init` predicate selects the initial vertices
- the action predicates together with `next` define a binary relation over pairs
  of states
- the actual transition graph is the reachable subgraph induced by that binary
  relation

Conceptually, this is closer to pruning a complete candidate state-pair
relation than to incrementally weaving isolated vertices into a graph. One can
mentally imagine starting with every possible source-state/successor-state pair
and then discarding those pairs that fail the action and `next` predicates.

This perspective also clarifies the meaning of omission:

- if `x+` is omitted, then the transition relation is not pruned along that
  coordinate
- the action continues to admit all successor values of `x` that remain
  compatible with the rest of the predicate

That is why omission is an expressive semantic choice rather than merely absent
syntax.

## Why Implicit Frame Conditions Are Attractive

There is a good reason people often want omission to mean non-change:

- it reduces boilerplate
- it matches the way update-style actions are often written mentally
- it makes local actions shorter and easier to read
- it reduces accidental under-specification when the author simply forgot to
  write unchanged-variable clauses

This makes implicit frame conditions a strong candidate for a surface-language
feature.

## Why Omission = Unconstrained Is Valuable

Even so, the current semantics are genuinely expressive. They allow actions to
be partial transition predicates rather than only update scripts.

This matters because some actions are intended to leave parts of the successor
state open on purpose.

### Environment-Step Example

Suppose a model has:

- `pc`: control location of a process
- `msg`: message status, either `none` or `pending`

Now suppose we want to model a network environment step with this meaning:

"While the process remains in `waiting`, the message status may evolve
arbitrarily."

Under the current semantics, this can be written compactly as:

```lisp
(action network-step
  (= pc waiting)
  (= pc+ waiting))
```

Because `msg+` is omitted, the action allows both:

- `msg+ = none`
- `msg+ = pending`

That is exactly the intended nondeterministic environment behavior.

If omission instead meant non-change, the same action would silently become:

```lisp
(action network-step
  (= pc waiting)
  (= pc+ waiting)
  (= msg+ msg))
```

Now the environment is no longer allowed to affect `msg` at all. The intended
meaning is lost.

### Disturbance/Fault Example

Another compact and useful pattern under the current semantics is:

```lisp
(action disturb
  (= x+ x))
```

This means:

- `x` remains unchanged
- all other variables may change arbitrarily

That can model:

- environment interference
- disturbance
- fault steps
- abstraction over details that are intentionally left open

Under omission = unchanged semantics, the same action would instead mean that
every unmentioned variable must also remain unchanged, which destroys the point
of the action.

## Design Conclusion

The current core semantics are worth preserving:

- omission of `x+` should continue to mean "unconstrained successor value"
- this preserves relational expressiveness
- it supports nondeterminism, abstraction, environment actions, and fault models

At the same time, there is a separate ergonomic concern: authors often omit a
next-state clause when they mean "unchanged", not "arbitrary".

## Recommended Direction

A good architectural compromise is:

- keep the core JSON and checker semantics relational and explicit
- optionally make the surface DSL more convenient by inserting frame conditions
  automatically
- if such a DSL feature is added, also provide a way to explicitly mark a
  variable as unconstrained in the successor state

That approach preserves the expressive core while supporting a friendlier
authoring style.

## Summary

The key tradeoff is:

- omission = unconstrained preserves expressive relational semantics
- omission = unchanged supports a terser update-oriented notation

The current semantics are not merely permissive; they capture a meaningful and
useful class of transition specifications. For that reason, if automatic frame
conditions are ever introduced, they are best treated as a surface-language
convenience rather than a change to the underlying core semantics.
