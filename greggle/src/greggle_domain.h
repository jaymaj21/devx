// greggle BDD-backed Domain / Variable / Relation adapter.
// Wraps the original BDD-based Domain, Variable, and Relation
// classes (under src/relations) to present the simpler API used
// by greggle's query engine.

#pragma once

#include <vector>
#include <functional>
#include <memory>

#include "relations/Domain.h"
#include "relations/Variable.h"
#include "relations/Relation.h"
#include "relations/TupleCallback.h"

namespace greggle {

// Alias original BDD-based types into the greggle namespace.
using Domain = ::Domain;
using Variable = ::Variable;

// Simple tuple type used by greggle to expose results.
struct Tuple {
    std::vector<int> values;
};

class Relation {
public:
    Relation();
    explicit Relation(const std::vector<const Variable*>& vars);
    Relation(const Relation& other);
    Relation(Relation&& other) noexcept;
    Relation& operator=(const Relation& other);
    Relation& operator=(Relation&& other) noexcept;
    ~Relation();

    const std::vector<const Variable*>& vars() const { return _vars; }

    void addTuple(const std::vector<int>& vals);
    bool hasTuple(const std::vector<int>& vals) const;

    // Natural join (logical AND) via BDD conjunction.
    Relation joinAnd(const Relation& other) const;

    // Union (logical OR) via BDD disjunction.
    Relation unionOr(const Relation& other) const;

    // Set difference: this \ other (A AND NOT B).
    Relation difference(const Relation& other) const;

    // Existential projection / quantification.
    Relation projectOut(const std::vector<const Variable*>& toRemove) const;

    // Complement (logical NOT) over current variables.
    Relation logicalNot() const;

    // Traverse satisfying tuples in the given variable order.
    void traverse(const std::function<void(const Tuple&)>& cb) const;

    bool isEmpty() const;

private:
    std::vector<const Variable*> _vars;
    ::Relation* _rel; // owned
};

} // namespace greggle
