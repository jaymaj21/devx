#include "greggle_domain.h"

#include <algorithm>
#include <cassert>

namespace greggle {

Relation::Relation() : _rel(nullptr) {}

Relation::Relation(const std::vector<const Variable*>& vars) : _vars(vars), _rel(nullptr) {
    std::vector<Variable*> nonconst;
    nonconst.reserve(vars.size());
    for (auto* v : vars) {
        nonconst.push_back(const_cast<Variable*>(v));
    }
    _rel = new ::Relation(nonconst);
}

Relation::Relation(const Relation& other) : _vars(other._vars), _rel(nullptr) {
    if (other._rel) {
        _rel = new ::Relation(*other._rel);
    }
}

Relation::Relation(Relation&& other) noexcept
    : _vars(std::move(other._vars)), _rel(other._rel) {
    other._rel = nullptr;
}

Relation& Relation::operator=(const Relation& other) {
    if (this != &other) {
        delete _rel;
        _rel = nullptr;
        _vars = other._vars;
        if (other._rel) {
            _rel = new ::Relation(*other._rel);
        }
    }
    return *this;
}

Relation& Relation::operator=(Relation&& other) noexcept {
    if (this != &other) {
        delete _rel;
        _vars = std::move(other._vars);
        _rel = other._rel;
        other._rel = nullptr;
    }
    return *this;
}

Relation::~Relation() {
    delete _rel;
}

void Relation::addTuple(const std::vector<int>& vals) {
    if (!_rel) return;
    _rel->addTuple(vals);
}

bool Relation::hasTuple(const std::vector<int>& vals) const {
    if (!_rel) return false;
    return _rel->hasTuple(vals);
}
Relation Relation::joinAnd(const Relation& other) const {
    if (!_rel || !other._rel) return Relation();
    Relation res;
    res._rel = new ::Relation(*_rel);
    res._rel->andSelf(other._rel);
    // Rebuild variable order from underlying relation.
    res._vars.clear();
    for (auto it = res._rel->varBegin(); it != res._rel->varEnd(); ++it) {
        res._vars.push_back(*it);
    }
    return res;
}

Relation Relation::unionOr(const Relation& other) const {
    if (!_rel || !other._rel) return Relation();
    Relation res;
    res._rel = new ::Relation(*_rel);
    res._rel->orSelf(other._rel);
    res._vars.clear();
    for (auto it = res._rel->varBegin(); it != res._rel->varEnd(); ++it) {
        res._vars.push_back(*it);
    }
    return res;
}

Relation Relation::difference(const Relation& other) const {
    if (!_rel || !other._rel) return Relation();
    Relation res;
    res._rel = new ::Relation(*_rel);
    ::Relation tmp(*other._rel);
    tmp.notSelf();
    res._rel->andSelf(&tmp);
    res._vars.clear();
    for (auto it = res._rel->varBegin(); it != res._rel->varEnd(); ++it) {
        res._vars.push_back(*it);
    }
    return res;
}

Relation Relation::projectOut(const std::vector<const Variable*>& toRemove) const {
    if (!_rel) return Relation();

    // Determine kept variables.
    std::vector<const Variable*> keep;
    for (auto* v : _vars) {
        bool drop = std::find(toRemove.begin(), toRemove.end(), v) != toRemove.end();
        if (!drop) keep.push_back(v);
    }

    Relation res;
    if (keep.empty()) {
        // Zero-ary relation: TRUE iff there exists at least one tuple.
        if (!_rel->isFalse()) {
            std::vector<Variable*> none;
            res._rel = new ::Relation(none);
            res._rel->setTrue();
        }
        return res;
    }

    res._vars = keep;
    std::vector<Variable*> keepNonconst;
    keepNonconst.reserve(keep.size());
    for (auto* v : keep) {
        keepNonconst.push_back(const_cast<Variable*>(v));
    }
    res._rel = new ::Relation(keepNonconst);

    // Build index map from variable to position in original tuple.
    std::map<const Variable*, int> idxOrig;
    for (size_t i = 0; i < _vars.size(); ++i) {
        idxOrig[_vars[i]] = static_cast<int>(i);
    }

    // Enumerate all tuples in the current relation via membership checks.
    std::vector<int> values(_vars.size(), 0);
    std::function<void(size_t)> enumAll = [&](size_t idx) {
        if (idx == _vars.size()) {
            if (_rel->hasTuple(values)) {
                std::vector<int> proj;
                proj.reserve(keep.size());
                for (auto* v : keep) {
                    int pos = idxOrig[v];
                    assert(pos >= 0 && pos < static_cast<int>(values.size()));
                    proj.push_back(values[pos]);
                }
                res._rel->addTuple(proj);
            }
            return;
        }
        int maxVal = _vars[idx]->getMax();
        for (int v = 0; v < maxVal; ++v) {
            values[idx] = v;
            enumAll(idx + 1);
        }
    };
    enumAll(0);

    return res;
}

Relation Relation::logicalNot() const {
    if (!_rel) return Relation();
    Relation res;
    res._vars = _vars;
    res._rel = new ::Relation(*_rel);
    res._rel->notSelf();
    return res;
}

void Relation::traverse(const std::function<void(const Tuple&)>& cb) const {
    if (!_rel) return;
    if (_vars.empty()) {
        if (!_rel->isFalse()) {
            Tuple t;
            cb(t);
        }
        return;
    }

    std::vector<int> values(_vars.size(), 0);
    std::function<void(size_t)> enumAll = [&](size_t idx) {
        if (idx == _vars.size()) {
            if (_rel->hasTuple(values)) {
                Tuple t;
                t.values = values;
                cb(t);
            }
            return;
        }
        int maxVal = _vars[idx]->getMax();
        for (int v = 0; v < maxVal; ++v) {
            values[idx] = v;
            enumAll(idx + 1);
        }
    };
    enumAll(0);
}

bool Relation::isEmpty() const {
    if (!_rel) return true;
    return _rel->isFalse();
}

} // namespace greggle
