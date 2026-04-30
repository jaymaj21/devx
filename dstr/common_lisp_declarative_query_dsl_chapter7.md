# Mastering Common Lisp Systems: Modular Build — A Declarative Query DSL

## Chapter 7 — Modular Build: A Declarative Query DSL

## Introduction

This chapter develops a concrete case study: a declarative query DSL operating over structured in-memory data.

The DSL is intended to:

- describe **what** should happen, not **how**
- enforce structural constraints
- normalize syntax into a stable intermediate representation
- execute predictably
- remain extensible
- support optimization evolution

The chapter’s architectural pipeline is:

**Surface DSL → Validation → Normalized IR → Execution Engine → Optimization Layer**

The goal is not merely to make a pleasant macro, but to build a modular, extensible, production-grade query system.

---

## 7.1 Design Expressive Query Syntax and Constraints

The query DSL supports:

- filtering
- selection
- optional aggregation as a future extension

A typical surface form looks like this:

```lisp
(query
  (filter (> age 18))
  (filter (< age 65))
  (select name email))
```

This is declarative:

- the order of filter clauses should not matter
- the order of selected fields should not change semantic meaning

### Declarative invariants

The syntax layer enforces several invariants:

- exactly one `select` clause is required
- zero or more `filter` clauses are allowed
- duplicate `select` clauses are not allowed
- unsupported clause keywords are rejected
- filter expressions must follow the shape `(operator field value)`

### Step 1 — Define legal clause vocabulary

Allowed clause heads are explicit and closed:

- `filter`
- `select`

A simple validation rule can begin with:

```lisp
(member (car clause) '(filter select))
```

If a clause head falls outside that set, the DSL should signal a syntax error during macro expansion.

### Step 2 — Structural constraints

The syntax layer should enforce:

- exactly one `select`
- at least one selected field
- each `filter` form must contain a predicate form

Examples of invalid DSL forms include:

```lisp
(query (select))                         ; empty select
(query (filter age))                     ; malformed predicate
(query (select name) (select email))     ; duplicate select
```

Surface validation must fail during macro expansion, not later.

### Step 3 — Predicate form constraints

Allowed operators initially are:

- `>`
- `<`
- `=`

Each predicate must follow:

```lisp
(operator field value)
```

Validation should ensure:

- the operator symbol is recognized
- the field is a valid identifier
- the value is an atomic or structured literal

If these rules are violated, the macro should signal a structured syntax error.

### Step 4 — Thin surface macro

The surface macro should remain thin and declarative:

```lisp
(defmacro query (&rest clauses)
  (validate-query-clauses clauses)
  `(execute-query
     ,(normalize-clauses clauses)))
```

The key architectural observations are:

- no heavy logic belongs inside the macro
- validation and normalization are delegated to ordinary functions
- layer separation remains intact

A useful conceptual flow is:

**User Query → Macro Validation → Normalization Call**

The surface macro should orchestrate, not interpret.

### Step 5 — Enforce declarative discipline

Because the DSL is declarative, clause order must not imply process semantics.

During normalization:

- gather all filter forms independently of order
- treat filters semantically as a set, not as a sequence

This prevents accidental imperative drift.

### Step 6 — Future extension awareness

Clause parsing should be designed for growth.

Possible future clauses might include:

```lisp
(order-by age)
(limit 10)
```

For that reason, clause dispatch should be pattern-based rather than sequence-based:

```lisp
(case (car clause)
  (filter ...)
  (select ...)
  (otherwise (error ...)))
```

This preserves extensibility.

### Surface design summary

At the end of syntax design, the DSL surface should provide:

- clear constraints
- declarative semantics
- a strict validation boundary
- an extensible clause structure

The surface DSL is now stable and disciplined.

---

## 7.2 Compile DSL Expressions into Normalized IR

Surface syntax is user language.  
IR is system meaning.

The purpose of IR is to:

- represent query semantics explicitly
- eliminate syntactic variability
- support optimization
- remain stable across versions

### Step 1 — Define IR structure

A minimal IR for the query DSL can be represented with a structure:

```lisp
(defstruct query-ir
  filters
  projections)
```

Its fields represent semantic meaning directly:

- `filters`: a list of predicate objects
- `projections`: a list of selected fields

Now query intent is explicit.

### Step 2 — Normalize clauses

Normalization should:

1. iterate through clauses
2. collect filter predicates
3. collect selected fields
4. enforce invariant checks
5. construct a `query-ir`

Pseudo-logic:

```lisp
(defun normalize-clauses (clauses)
  (let ((filters '())
        (select nil))
    (dolist (clause clauses)
      (case (car clause)
        (filter
          (push (normalize-filter (cdr clause)) filters))
        (select
          (setf select (normalize-select (cdr clause))))))
    (unless select
      (error "SELECT clause required"))
    (make-query-ir
      :filters (nreverse filters)
      :projections select)))
```

Normalization transforms syntax into canonical representation.

### Step 3 — Normalize predicate structure

A surface predicate like:

```lisp
(> age 18)
```

should become a semantic object.

A structured representation is preferable to raw list encoding:

```lisp
(defstruct predicate
  operator
  field
  value)
```

Normalization can then produce:

```lisp
(make-predicate
  :operator '>
  :field 'age
  :value 18)
```

This makes IR semantic rather than syntactic.

### Step 4 — Canonicalize filter ordering

Even when filter order is semantically irrelevant, normalization may preserve physical order for debugging clarity.

Later optimization phases may reorder filters for performance.

The important rule is:

- semantic order irrelevance must be encoded conceptually
- physical list order may still exist as an implementation detail

### Step 5 — Treat IR as immutable

Once created, `query-ir` should not be mutated.

Instead:

- optimization should produce a new IR or compiled plan
- execution should consume the IR
- later stages should not mutate prior-stage artifacts

IR immutability prevents cross-stage contamination.

### Step 6 — Inspect IR directly

A useful debugging approach is to inspect normalized IR directly:

```lisp
(normalize-clauses
  '((filter (> age 18))
    (select name)))
```

A successful result should resemble:

```lisp
#S(QUERY-IR
   :FILTERS (...)
   :PROJECTIONS (...))
```

This IR should remain stable regardless of input clause order.

### Why IR normalization is critical

Without IR:

- execution must interpret raw lists
- optimization becomes ad hoc list rewriting
- validation leaks into runtime

With IR:

- execution becomes straightforward
- optimization targets structured objects
- surface syntax can evolve without breaking runtime

IR is the semantic contract.

### Modular extension readiness

Suppose a future feature adds:

```lisp
(order-by age)
```

The IR can grow explicitly:

```lisp
(defstruct query-ir
  filters
  projections
  order)
```

Normalization extends. Runtime extends. The surface remains conceptually stable.

That is the benefit of layering.

---

## 7.3 Implement the Execution Engine Over Structured Data

The execution engine operates over structured in-memory records.

Assume a dataset represented as property lists:

```lisp
(defparameter *users*
  '((:name "Alice" :age 30 :email "a@x.com")
    (:name "Bob"   :age 17 :email "b@x.com")
    (:name "Carol" :age 45 :email "c@x.com")))
```

Execution consumes:

- a `query-ir`
- a dataset
- and returns filtered, projected results

### Step 1 — Predicate evaluation

Given structured predicates:

```lisp
(defstruct predicate
  operator
  field
  value)
```

an evaluator can be defined as:

```lisp
(defun evaluate-predicate (predicate record)
  (let ((op (predicate-operator predicate))
        (field (predicate-field predicate))
        (value (predicate-value predicate)))
    (let ((record-value (getf record field)))
      (ecase op
        (> (> record-value value))
        (< (< record-value value))
        (= (= record-value value))))))
```

This is runtime semantic evaluation.

Notably:

- no surface syntax appears here
- execution consumes structured IR only

### Step 2 — Apply all filters

All predicates are treated conjunctively:

```lisp
(defun record-matches-p (filters record)
  (every (lambda (pred)
           (evaluate-predicate pred record))
         filters))
```

This respects the normalization contract and preserves declarative meaning.

### Step 3 — Apply projection

Projection extracts selected fields:

```lisp
(defun project-record (fields record)
  (loop for field in fields
        append (list field (getf record field))))
```

This produces a reduced property list.

### Step 4 — Execute the query

The main executor can be written over IR:

```lisp
(defun execute-query-ir (query-ir dataset)
  (let ((filters (query-ir-filters query-ir))
        (projections (query-ir-projections query-ir)))
    (loop for record in dataset
          when (record-matches-p filters record)
          collect (project-record projections record))))
```

This function is deterministic and pure relative to its inputs.

No macro logic is involved.

### Step 5 — Integrate the surface macro

The macro can now compile the surface query into IR and feed it directly to the execution engine:

```lisp
(defmacro query (&rest clauses)
  (validate-query-clauses clauses)
  (let ((ir (normalize-clauses clauses)))
    `(execute-query-ir ',ir *users*)))
```

The IR is quoted so that it is constructed once at expansion time rather than rebuilt at runtime.

### Declarative guarantee

The execution engine must respect declarative semantics:

- filter order does not change results
- projection order affects output ordering only, not meaning

Execution therefore depends only on IR, not on the original surface syntax.

### Edge case handling

Runtime must still cope with real datasets and imperfect environments.

Important cases include:

- missing fields
- unknown operators
- type mismatches

Semantic correctness should be validated as early as possible, but runtime checks still protect against variability in external data.

### Execution summary

At this point, the system provides:

- IR-based evaluation
- conjunctive filtering
- deterministic projection
- stable layer separation

---

## 7.4 Optimize Evaluation Paths for Performance

The current execution path is correct, but not yet optimized.

Optimization should:

- minimize redundant work
- reduce per-record overhead
- precompute where possible
- preserve declarative clarity

Optimization must never alter DSL meaning.

### Optimization 1 — Precompile predicate functions

Instead of dispatching on the operator for every record, compile each predicate once:

```lisp
(defun compile-predicate (predicate)
  (let ((op (predicate-operator predicate))
        (field (predicate-field predicate))
        (value (predicate-value predicate)))
    (ecase op
      (> (lambda (record)
           (> (getf record field) value)))
      (< (lambda (record)
           (< (getf record field) value)))
      (= (lambda (record)
           (= (getf record field) value))))))
```

Compile all filters once:

```lisp
(defun compile-filters (filters)
  (mapcar #'compile-predicate filters))
```

Then execute with compiled predicates:

```lisp
(defun record-matches-compiled-p (compiled-filters record)
  (every (lambda (fn)
           (funcall fn record))
         compiled-filters))
```

This removes operator branching from the hot loop.

### Optimization 2 — Short-circuit ordering

If some predicates are cheaper than others, order them by evaluation cost.

Example:

```lisp
(defun optimize-filter-order (filters)
  (sort filters #'cheap-predicate-first-p))
```

This belongs between normalization and execution.

It reduces average evaluation time while preserving semantics.

### Optimization 3 — Avoid repeated `getf` traversal

Property list lookup is linear. Repeated `getf` traversal can become expensive for large datasets.

Possible strategies:

- preprocess records into hash tables
- use vector-based representations

Example:

```lisp
(defun prepare-dataset (dataset)
  (mapcar #'convert-to-hash-table dataset))
```

This trades preprocessing cost for faster query-time lookup.

### Optimization 4 — Avoid repeated projection reconstruction

Instead of rebuilding projection structures for each record, compile projection accessors once.

For example:

```lisp
(defun compile-projection (fields)
  (lambda (record)
    (loop for field in fields
          append (list field (getf record field)))))
```

Compile once, reuse per record.

### Optimization 5 — Advanced indexing strategy

For large datasets, consider indexing frequently queried fields.

Possible approach:

- build indexes on common fields
- filter using the index first

This moves the architecture toward query planning.

However, indexing adds state and complexity and should be introduced only when profiling justifies it.

### Optimized execution pipeline

A more mature execution path looks like:

**IR → Optimization Stage → Compiled Execution Plan → Evaluation**

At this point the DSL begins to resemble database engine architecture:

- parse
- normalize
- optimize
- execute

### Performance discipline principles

Optimization should:

- precompute static decisions
- remove runtime branching where possible
- reduce allocation inside loops
- profile before adding complexity
- keep declarative semantics intact

### Declarative integrity during optimization

Optimization must preserve:

- logical equivalence
- filter conjunction semantics
- projection correctness
- dataset immutability

Optimization layers should transform IR into execution plans, not mutate DSL contracts.

---

## 7.5 Extend the DSL with Custom Operators and Plugins

The initial DSL supports a fixed operator set:

- `>`
- `<`
- `=`

A realistic system needs extensibility without rewriting the engine.

### Step 1 — Abstract operator dispatch

Replace static operator dispatch with a registry.

Define the registry:

```lisp
(defparameter *operator-registry* (make-hash-table))
```

Register the core operators:

```lisp
(setf (gethash '> *operator-registry*)
      (lambda (field-value literal)
        (> field-value literal)))

(setf (gethash '< *operator-registry*)
      (lambda (field-value literal)
        (< field-value literal)))

(setf (gethash '= *operator-registry*)
      (lambda (field-value literal)
        (= field-value literal)))
```

Now predicate compilation becomes registry-driven:

```lisp
(defun compile-predicate (predicate)
  (let* ((op (predicate-operator predicate))
         (fn (gethash op *operator-registry*)))
    (unless fn
      (error "Unknown operator ~S" op))
    (let ((field (predicate-field predicate))
          (value (predicate-value predicate)))
      (lambda (record)
        (funcall fn
                 (getf record field)
                 value)))))
```

The core engine no longer hard-codes operators.

### Step 2 — Provide registration API

Expose a controlled registration interface:

```lisp
(defun register-operator (symbol fn)
  (setf (gethash symbol *operator-registry*) fn))
```

External modules can now extend operator semantics.

Example:

```lisp
(register-operator 'starts-with
  (lambda (field-value literal)
    (and (stringp field-value)
         (search literal field-value :test #'char-equal))))
```

That enables usage such as:

```lisp
(query
  (filter (starts-with name "A"))
  (select name))
```

Notice what remains unchanged:

- surface syntax
- normalization structure
- execution pipeline

Execution automatically respects the extension.

### Step 3 — Validate custom operators

Validation must adapt to the registry.

Instead of hard-coding allowed operators, surface validation should accept operators present in the registry and reject unknown ones early:

```lisp
(unless (gethash operator *operator-registry*)
  (error "Unsupported operator ~S" operator))
```

The registry therefore defines a semantic boundary.

### Step 4 — Modular plugin pattern

Operator plugins should be encapsulated in modules.

Example:

```lisp
(defun load-string-operators ()
  (register-operator 'starts-with ...)
  (register-operator 'ends-with ...))
```

A well-formed plugin module should:

- not modify the macro
- not modify IR structure
- not modify the execution loop
- only extend the operator registry

That is modular extensibility.

### Step 5 — Preserve IR stability during extension

Operator plugins do not require changing predicate structure.

The IR remains stable.

Extensions operate at the level of execution semantics only.

A good extension architecture therefore looks like:

**Operator Registry → Predicate Compiler → Execution Engine**

Stable IR prevents structural fragmentation.

### Step 6 — Advanced extension: clause plugins

Larger features such as new clause types require broader extension.

For a clause like:

```lisp
(order-by age)
```

extension should be routed through explicit boundaries:

- validation hook
- normalization extension
- IR structure update
- execution handler

A disciplined plugin architecture should define:

- a clause registration table
- a clause normalization function
- a clause execution extension

It should **not** inject raw `case` branches into the macro body.

### Extension principles

Good extension:

- modifies registries, not macro internals
- leaves IR stable or versions it explicitly
- adds execution strategy modularly
- does not increase macro complexity

Extensibility without structural discipline leads to architectural decay.

---

## 7.6 Troubleshooting: Ambiguous Queries and Execution Errors

As the DSL grows, ambiguity and runtime failures become more likely.

Understanding these failure modes prevents semantic drift.

### Ambiguous clause ordering

A declarative DSL assumes filter order irrelevance.

If reordering filters changes the result, the DSL has become impure or imperative.

This usually indicates side effects inside predicate evaluation.

Declarative rule:

- predicate evaluation must be side-effect free
- custom operators must be pure functions

### Unknown operator errors

If an operator is not registered:

- validation should catch it before normalization completes
- runtime failure should be avoided when possible

Operator registry checks should happen during normalization or validation, not inside the hot execution loop.

### Field name errors

Example:

```lisp
(query
  (filter (> salary 1000))
  (select name))
```

If `salary` is absent from the dataset, a runtime error may occur.

A better approach is an optional semantic validation stage against dataset metadata:

- validate fields against schema
- fail before execution when possible

When schema is unavailable, runtime errors should still be clear and descriptive.

### Type mismatch failures

Example:

```lisp
(filter (> name 10))
```

If `name` contains strings, the comparison is invalid.

Predicate compilation or runtime evaluation should defend against this:

```lisp
(unless (numberp field-value)
  (error "Invalid numeric comparison for field ~S" field))
```

Typed DSLs often require defensive runtime checks unless type information is enforced earlier.

### Ambiguous projection

Duplicate projection fields, such as:

```lisp
(select name name)
```

should either be canonicalized away or rejected explicitly during normalization.

IR canonicalization prevents redundant output generation.

### Performance degradation after extension

Custom operators may:

- perform expensive work
- trigger heavy string processing
- allocate per record

The DSL core cannot prevent all plugin misuse, so plugin behavior should be profiled independently and documented clearly.

### Registry mutation risks

If the operator registry is global and mutable:

- plugins may override existing operators
- unexpected behavior may emerge

Mitigations include:

- restricting overwrite unless explicitly allowed
- introducing namespace or version boundaries

Example safeguard:

```lisp
(when (gethash symbol *operator-registry*)
  (error "Operator already registered: ~S" symbol))
```

Core invariants should be protected.

### Debugging strategy

When a query produces unexpected results:

1. inspect normalized IR
2. print the compiled predicate list
3. confirm registry mappings
4. test compiled predicates independently
5. validate projection output
6. inspect dataset schema

Always debug from IR downward, not from surface syntax.

A good debug flow is:

**Surface DSL → IR Inspection → Compiled Plan → Execution → Output**

### Isolation testing approach

Test components independently:

- `normalize-clauses`
- `compile-predicate`
- `record-matches-p`
- projection logic
- full execution

Layered testing prevents cross-layer confusion.

### Scope drift check

If adding a new clause forces macro modification in multiple locations, the architecture is signaling trouble.

Extensions should modify:

- registry
- normalization handler
- execution dispatcher

Not the macro expansion skeleton.

---

## Final Synthesis

Chapter 7 turns the earlier architectural principles into a working case study.

The finished design has these layers:

1. **Surface DSL**
2. **Validation**
3. **Normalized IR**
4. **Execution Engine**
5. **Optimization Stage**
6. **Plugin and Extension Boundaries**

The chapter demonstrates several key lessons.

### 1. Declarative query syntax must stay declarative

The query language describes intent, not process.

That means:

- filter order does not change meaning
- surface syntax should stay small and explicit
- validation should fail early

### 2. IR is the semantic contract

Normalization transforms surface syntax into a structured semantic form.

That gives the system:

- stable execution
- simpler debugging
- cleaner optimization
- safer extension

### 3. Execution should consume only IR

The runtime should not interpret raw syntax.

It should evaluate structured predicates and projections directly.

### 4. Optimization belongs between normalization and execution

Compilation of predicates, projection specialization, filter ordering, and indexing all belong in an optimization stage that consumes IR and produces an execution plan.

Optimization must preserve declarative semantics.

### 5. Extension should happen at explicit boundaries

- operator plugins extend the registry
- clause plugins extend validation, normalization, IR, and execution in a disciplined way
- macro internals should remain thin

### 6. Troubleshooting starts from IR, not syntax

A modular DSL is easier to reason about because every failure can be located within a layer.

---

## Closing Principle

A production-grade query DSL is not just a pleasant macro.

It is a layered language system in which:

- syntax is disciplined
- normalization is explicit
- IR is stable
- execution is deterministic
- optimization is modular
- extension boundaries are controlled

That is what makes the DSL declarative, extensible, and maintainable over time.
