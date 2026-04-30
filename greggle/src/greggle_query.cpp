#include "greggle_query.h"

#include <queue>
#include <regex>
#include <set>

namespace greggle {

std::shared_ptr<Expr> Expr::exists(const std::vector<const Variable*>& vars,
                                   const std::shared_ptr<Expr>& sub) {
    auto e = std::make_shared<Expr>();
    e->kind = Kind::Exists;
    e->quantVars = vars;
    e->subExpr = sub;
    return e;
}

std::shared_ptr<Expr> Expr::makeAnd(const std::vector<std::shared_ptr<Expr>>& kids) {
    auto e = std::make_shared<Expr>();
    e->kind = Kind::And;
    e->children = kids;
    return e;
}

std::shared_ptr<Expr> Expr::makeOr(const std::vector<std::shared_ptr<Expr>>& kids) {
    auto e = std::make_shared<Expr>();
    e->kind = Kind::Or;
    e->children = kids;
    return e;
}

std::shared_ptr<Expr> Expr::existsPath(const Variable* v1,
                                       const Variable* v2,
                                       const std::shared_ptr<Regex>& re) {
    auto e = std::make_shared<Expr>();
    e->kind = Kind::ExistsPath;
    e->v1 = v1;
    e->v2 = v2;
    e->regex = re;
    return e;
}

std::shared_ptr<Expr> Expr::noEdge(const Variable* v1,
                                   const Variable* v2) {
    auto e = std::make_shared<Expr>();
    e->kind = Kind::NoEdge;
    e->v1 = v1;
    e->v2 = v2;
    return e;
}

std::shared_ptr<Expr> Expr::noConnection(const Variable* v1,
                                         const Variable* v2) {
    auto e = std::make_shared<Expr>();
    e->kind = Kind::NoConnection;
    e->v1 = v1;
    e->v2 = v2;
    return e;
}

std::shared_ptr<Expr> Expr::same(const Variable* v1,
                                 const Variable* v2) {
    auto e = std::make_shared<Expr>();
    e->kind = Kind::Same;
    e->v1 = v1;
    e->v2 = v2;
    return e;
}

std::shared_ptr<Expr> Expr::different(const Variable* v1,
                                      const Variable* v2) {
    auto e = std::make_shared<Expr>();
    e->kind = Kind::Different;
    e->v1 = v1;
    e->v2 = v2;
    return e;
}

std::shared_ptr<Expr> Expr::match(const Variable* v,
                                  const std::string& pattern) {
    auto e = std::make_shared<Expr>();
    e->kind = Kind::Match;
    e->v1 = v;
    e->strPattern = pattern;
    return e;
}

// --- Regex → NFA and path matching ----------------------------------------

// Edge-level predicate evaluation.
static bool evalEdgePred(const EdgePred& p,
                         const std::set<std::string>& labels,
                         const std::string& srcNodeLabel,
                         const std::string& dstNodeLabel) {
    using K = EdgePred::Kind;
    switch (p.kind) {
    case K::Any:
        return true;
    case K::Atom:
        return labels.count(p.label) > 0;
    case K::SourceNodeMatch:
        try {
            return std::regex_match(srcNodeLabel, std::regex(p.nodePattern));
        } catch (const std::regex_error&) {
            return false;
        }
    case K::SinkNodeMatch:
        try {
            return std::regex_match(dstNodeLabel, std::regex(p.nodePattern));
        } catch (const std::regex_error&) {
            return false;
        }
    case K::Not:
        return p.sub ? !evalEdgePred(*p.sub, labels, srcNodeLabel, dstNodeLabel) : true;
    case K::AllOf:
        for (const auto& child : p.children) {
            if (child && !evalEdgePred(*child, labels, srcNodeLabel, dstNodeLabel)) return false;
        }
        return true;
    case K::SomeOf:
        for (const auto& child : p.children) {
            if (child && evalEdgePred(*child, labels, srcNodeLabel, dstNodeLabel)) return true;
        }
        return false;
    }
    return false;
}

struct NFAState {
    bool accepting = false;
    std::vector<int> eps;                          // epsilon edges
    std::vector<std::pair<std::shared_ptr<EdgePred>,int>> trans;
};

struct NFA {
    int start = 0;
    std::vector<NFAState> states;
};

static int newState(NFA& nfa) {
    int id = static_cast<int>(nfa.states.size());
    nfa.states.emplace_back();
    return id;
}

static std::shared_ptr<EdgePred> atomPred(const std::string& lab) {
    auto p = std::make_shared<EdgePred>();
    p->kind = EdgePred::Kind::Atom;
    p->label = lab;
    return p;
}

static std::pair<int,int> buildNFA(const std::shared_ptr<Regex>& re, NFA& nfa) {
    using Kind = Regex::Kind;
    if (!re) {
        int s = newState(nfa);
        int e = newState(nfa);
        nfa.states[s].eps.push_back(e);
        return {s,e};
    }
    switch (re->kind) {
    case Kind::Symbol: {
        int s = newState(nfa);
        int e = newState(nfa);
        std::shared_ptr<EdgePred> p = re->pred;
        if (!p) {
            p = atomPred(re->symbol);
        }
        nfa.states[s].trans.emplace_back(p, e);
        return {s,e};
    }
    case Kind::Concat: {
        std::pair<int,int> acc;
        bool first = true;
        for (const auto& child : re->children) {
            auto sub = buildNFA(child, nfa);
            if (first) {
                acc = sub;
                first = false;
            } else {
                nfa.states[acc.second].eps.push_back(sub.first);
                acc.second = sub.second;
            }
        }
        if (first) {
            int s = newState(nfa);
            int e = newState(nfa);
            nfa.states[s].eps.push_back(e);
            return {s,e};
        }
        return acc;
    }
    case Kind::Alt: {
        int s = newState(nfa);
        int e = newState(nfa);
        for (const auto& child : re->children) {
            auto sub = buildNFA(child, nfa);
            nfa.states[s].eps.push_back(sub.first);
            nfa.states[sub.second].eps.push_back(e);
        }
        return {s,e};
    }
    case Kind::Star: {
        auto sub = buildNFA(re->sub, nfa);
        int s = newState(nfa);
        int e = newState(nfa);
        nfa.states[s].eps.push_back(sub.first);
        nfa.states[s].eps.push_back(e);
        nfa.states[sub.second].eps.push_back(sub.first);
        nfa.states[sub.second].eps.push_back(e);
        return {s,e};
    }
    case Kind::Plus: {
        auto sub = buildNFA(re->sub, nfa);
        int s = newState(nfa);
        int e = newState(nfa);
        nfa.states[s].eps.push_back(sub.first);
        nfa.states[sub.second].eps.push_back(sub.first);
        nfa.states[sub.second].eps.push_back(e);
        return {s,e};
    }
    }
    int s = newState(nfa);
    int e = newState(nfa);
    nfa.states[s].eps.push_back(e);
    return {s,e};
}

static void epsilonClosure(const NFA& nfa, const std::set<int>& in, std::set<int>& out) {
    std::vector<int> stack(in.begin(), in.end());
    out = in;
    while (!stack.empty()) {
        int s = stack.back();
        stack.pop_back();
        for (int t : nfa.states[s].eps) {
            if (!out.count(t)) {
                out.insert(t);
                stack.push_back(t);
            }
        }
    }
}

// Compute all (u,v) pairs such that there is a path from u to v whose
// label sequence is accepted by 're'.
static Relation existsPathPairs(const Graph& g,
                                const Variable* v1,
                                const Variable* v2,
                                const std::shared_ptr<Regex>& re) {
    NFA nfa;
    auto sp = buildNFA(re, nfa);
    nfa.start = sp.first;
    nfa.states[sp.second].accepting = true;

    Relation rel({v1, v2});

    for (int startNode = 0; startNode < g.numNodes(); ++startNode) {
        std::queue<std::pair<int,int>> q;
        std::set<int> startSet{nfa.start};
        std::set<int> closure;
        epsilonClosure(nfa, startSet, closure);
        std::set<std::pair<int,int>> visited;
        for (int sState : closure) {
            q.emplace(startNode, sState);
            visited.emplace(startNode, sState);
        }

        while (!q.empty()) {
            auto cur = q.front();
            q.pop();
            int node = cur.first;
            int st   = cur.second;

            if (nfa.states[st].accepting) {
                rel.addTuple({startNode, node});
            }

            for (const auto& edge : g.outgoing(node)) {
                for (const auto& tr : nfa.states[st].trans) {
                    const std::shared_ptr<EdgePred>& pred = tr.first;
                    int nextState = tr.second;
                    if (!pred || evalEdgePred(*pred,
                                              edge.labels,
                                              g.nodeLabel(edge.src),
                                              g.nodeLabel(edge.dst))) {
                        std::set<int> nextSet{nextState};
                        std::set<int> nextClosure;
                        epsilonClosure(nfa, nextSet, nextClosure);
                        for (int ns : nextClosure) {
                            std::pair<int,int> key(edge.dst, ns);
                            if (!visited.count(key)) {
                                visited.insert(key);
                                q.emplace(edge.dst, ns);
                            }
                        }
                    }
                }
            }
        }
    }

    return rel;
}

// Compute all (u,v) pairs such that there is NO edge from u to v.
static Relation noEdgePairs(const Graph& g,
                            const Variable* v1,
                            const Variable* v2) {
    Relation rel({v1, v2});
    int n = g.numNodes();
    for (int src = 0; src < n; ++src) {
        std::vector<bool> hasEdge(static_cast<std::size_t>(n), false);
        for (const auto& e : g.outgoing(src)) {
            if (e.dst >= 0 && e.dst < n) {
                hasEdge[static_cast<std::size_t>(e.dst)] = true;
            }
        }
        for (int dst = 0; dst < n; ++dst) {
            if (!hasEdge[static_cast<std::size_t>(dst)]) {
                rel.addTuple({src, dst});
            }
        }
    }
    return rel;
}

// Compute all (u,v) pairs such that there is NO edge between u and v
// in either direction (no u->v and no v->u).
static bool hasEdgeBetween(const Graph& g, int a, int b) {
    if (a == b) {
        for (const auto& e : g.outgoing(a)) {
            if (e.dst == b) return true;
        }
        return false;
    }
    for (const auto& e : g.outgoing(a)) {
        if (e.dst == b) return true;
    }
    for (const auto& e : g.outgoing(b)) {
        if (e.dst == a) return true;
    }
    return false;
}

static Relation noConnectionPairs(const Graph& g,
                                  const Variable* v1,
                                  const Variable* v2) {
    Relation rel({v1, v2});
    int n = g.numNodes();
    for (int src = 0; src < n; ++src) {
        for (int dst = 0; dst < n; ++dst) {
            if (!hasEdgeBetween(g, src, dst)) {
                rel.addTuple({src, dst});
            }
        }
    }
    return rel;
}

// Compute all (u,u) pairs (equality of variables).
static Relation samePairs(const Variable* v1,
                          const Variable* v2) {
    Relation rel({v1, v2});
    int max1 = v1->getMax();
    int max2 = v2->getMax();
    int n = (max1 < max2) ? max1 : max2;
    for (int v = 0; v < n; ++v) {
        rel.addTuple({v, v});
    }
    return rel;
}

// Compute all (u,v) pairs with u != v (inequality of variables).
static Relation differentPairs(const Variable* v1,
                               const Variable* v2) {
    Relation rel({v1, v2});
    int max1 = v1->getMax();
    int max2 = v2->getMax();
    int n1 = max1;
    int n2 = max2;
    for (int a = 0; a < n1; ++a) {
        for (int b = 0; b < n2; ++b) {
            if (a != b) {
                rel.addTuple({a, b});
            }
        }
    }
    return rel;
}

// Compute all nodes whose label matches (or contains a match for) the
// given string regular expression.
static Relation regexNodeFilter(const Graph& g,
                                const Variable* v,
                                const std::string& pattern) {
    Relation rel({v});
    int maxVal = v->getMax();
    int n = g.numNodes();
    if (maxVal < n) {
        n = maxVal;
    }
    if (n <= 0) return rel;
    try {
        std::regex re(pattern);
        for (int i = 0; i < n; ++i) {
            const std::string& label = g.nodeLabel(i);
            bool ok = std::regex_match(label, re);
            if (ok) {
                rel.addTuple({i});
            }
        }
    } catch (const std::regex_error&) {
        // Invalid pattern: leave relation empty.
    }
    return rel;
}

Relation eval(const Expr& e, const Graph& g,
              const std::vector<const Variable*>& allVars) {
    using Kind = Expr::Kind;
    switch (e.kind) {
    case Kind::ExistsPath: {
        return existsPathPairs(g, e.v1, e.v2, e.regex);
    }
    case Kind::NoEdge: {
        return noEdgePairs(g, e.v1, e.v2);
    }
    case Kind::NoConnection: {
        return noConnectionPairs(g, e.v1, e.v2);
    }
    case Kind::Same: {
        return samePairs(e.v1, e.v2);
    }
    case Kind::Different: {
        return differentPairs(e.v1, e.v2);
    }
    case Kind::Match: {
        return regexNodeFilter(g, e.v1, e.strPattern);
    }
    case Kind::And: {
        if (e.children.empty()) {
            return Relation();
        }
        Relation r = eval(*e.children[0], g, allVars);
        for (size_t i = 1; i < e.children.size(); ++i) {
            Relation r2 = eval(*e.children[i], g, allVars);
            r = r.joinAnd(r2);
        }
        return r;
    }
    case Kind::Or: {
        if (e.children.empty()) {
            return Relation();
        }
        Relation r = eval(*e.children[0], g, allVars);
        for (size_t i = 1; i < e.children.size(); ++i) {
            Relation r2 = eval(*e.children[i], g, allVars);
            r = r.unionOr(r2);
        }
        return r;
    }
    case Kind::Exists: {
        Relation sub = eval(*e.subExpr, g, allVars);
        return sub.projectOut(e.quantVars);
    }
    case Kind::Not: {
        Relation sub = eval(*e.subExpr, g, allVars);
        return sub.logicalNot();
    }
    }
    return Relation();
}

} // namespace greggle
