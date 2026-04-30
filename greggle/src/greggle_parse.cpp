#include "greggle_parse.h"

#include <cctype>
#include <regex>
#include <sstream>
#include <stdexcept>

namespace greggle {

static bool nextToken(std::istream& in, std::string& tok) {
    tok.clear();
    char c;
    // Skip whitespace
    while (in.get(c)) {
        if (!std::isspace(static_cast<unsigned char>(c))) {
            break;
        }
    }
    if (!in) return false;
    if (c == '(' || c == ')') {
        tok.push_back(c);
        return true;
    }
    // Atom
    tok.push_back(c);
    while (in.get(c)) {
        if (std::isspace(static_cast<unsigned char>(c)) || c == '(' || c == ')') {
            in.unget();
            break;
        }
        tok.push_back(c);
    }
    return true;
}

static SExpr parseRec(std::istream& in, std::string& tok, bool& ok) {
    SExpr e;
    if (tok == "(") {
        e.isAtom = false;
        std::string t;
        while (nextToken(in, t)) {
            if (t == ")") {
                ok = true;
                return e;
            }
            e.list.push_back(parseRec(in, t, ok));
            if (!ok) return e;
        }
        ok = false;
        return e;
    } else if (tok == ")") {
        ok = false;
        return e;
    } else {
        e.isAtom = true;
        e.atom = tok;
        ok = true;
        return e;
    }
}

bool parseSExpr(std::istream& in, SExpr& out) {
    std::string tok;
    if (!nextToken(in, tok)) return false;
    bool ok = false;
    out = parseRec(in, tok, ok);
    return ok;
}

// --- Regex builder ---------------------------------------------------------

static std::string stripQuotes(const std::string& s) {
    if (s.size() >= 2 && s.front() == '"' && s.back() == '"') {
        return s.substr(1, s.size() - 2);
    }
    return s;
}

static bool parseLiftedNodePredAtom(const std::string& atom,
                                    EdgePred::Kind& kind,
                                    std::string& pattern) {
    if (atom.size() >= 2 && atom.front() == '@') {
        kind = EdgePred::Kind::SinkNodeMatch;
        pattern = stripQuotes(atom.substr(1));
        return !pattern.empty();
    }
    if (atom.size() >= 2 && atom.back() == '@') {
        kind = EdgePred::Kind::SourceNodeMatch;
        pattern = stripQuotes(atom.substr(0, atom.size() - 1));
        return !pattern.empty();
    }
    return false;
}

// Build an edge-level boolean predicate from an S-expression.
// Atoms are label tests; leading '~' is shorthand for (negate ...).
static std::shared_ptr<EdgePred> buildEdgePredAtom(const std::string& atom) {
    EdgePred::Kind liftedKind = EdgePred::Kind::Atom;
    std::string liftedPattern;
    if (parseLiftedNodePredAtom(atom, liftedKind, liftedPattern)) {
        auto nodePred = std::make_shared<EdgePred>();
        nodePred->kind = liftedKind;
        nodePred->nodePattern = liftedPattern;
        return nodePred;
    }
    if (atom == "dot") {
        auto any = std::make_shared<EdgePred>();
        any->kind = EdgePred::Kind::Any;
        return any;
    }
    auto base = std::make_shared<EdgePred>();
    base->kind = EdgePred::Kind::Atom;
    base->label = atom;
    if (!atom.empty() && atom[0] == '~') {
        base->label = atom.substr(1);
        auto neg = std::make_shared<EdgePred>();
        neg->kind = EdgePred::Kind::Not;
        neg->sub = base;
        return neg;
    }
    return base;
}

static std::shared_ptr<EdgePred> buildEdgePred(const SExpr& sexpr) {
    if (sexpr.isAtom) {
        return buildEdgePredAtom(sexpr.atom);
    }
    if (sexpr.list.empty()) {
        throw std::runtime_error("Empty edge predicate");
    }
    const SExpr& head = sexpr.list[0];
    if (!head.isAtom) {
        throw std::runtime_error("Edge predicate head must be atom");
    }
    const std::string& op = head.atom;
    if (op == "negate") {
        if (sexpr.list.size() != 2) {
            throw std::runtime_error("negate expects one argument");
        }
        auto child = buildEdgePred(sexpr.list[1]);
        auto p = std::make_shared<EdgePred>();
        p->kind = EdgePred::Kind::Not;
        p->sub = child;
        return p;
    }
    if (op == "all-of" || op == "some-of") {
        if (sexpr.list.size() < 2) {
            throw std::runtime_error("all-of/some-of expects at least one argument");
        }
        auto p = std::make_shared<EdgePred>();
        p->kind = (op == "all-of") ? EdgePred::Kind::AllOf : EdgePred::Kind::SomeOf;
        for (size_t i = 1; i < sexpr.list.size(); ++i) {
            p->children.push_back(buildEdgePred(sexpr.list[i]));
        }
        return p;
    }
    // Fallback: treat as atomic label test.
    return buildEdgePredAtom(op);
}

std::shared_ptr<Regex> buildRegex(const SExpr& sexpr) {
    if (sexpr.isAtom) {
        auto r = std::make_shared<Regex>(sexpr.atom);
        r->pred = buildEdgePredAtom(sexpr.atom);
        return r;
    }
    if (sexpr.list.empty()) {
        throw std::runtime_error("Empty regex list");
    }
    const SExpr& head = sexpr.list[0];
    if (!head.isAtom) {
        throw std::runtime_error("Regex head must be atom");
    }
    const std::string& op = head.atom;
    if (op == "concat") {
        std::vector<std::shared_ptr<Regex>> kids;
        for (size_t i = 1; i < sexpr.list.size(); ++i) {
            kids.push_back(buildRegex(sexpr.list[i]));
        }
        return concat(kids);
    } else if (op == "alt") {
        std::vector<std::shared_ptr<Regex>> kids;
        for (size_t i = 1; i < sexpr.list.size(); ++i) {
            kids.push_back(buildRegex(sexpr.list[i]));
        }
        return alt(kids);
    } else if (op == "star" || op == "plus") {
        if (sexpr.list.size() != 2) {
            throw std::runtime_error("star/plus expects one argument");
        }
        auto sub = buildRegex(sexpr.list[1]);
        return (op == "star") ? star(sub) : plus(sub);
    } else if (op == "negate" || op == "all-of" || op == "some-of") {
        // Treat as a single edge-level predicate.
        auto r = std::make_shared<Regex>(std::string{});
        r->kind = Regex::Kind::Symbol;
        r->pred = buildEdgePred(sexpr);
        return r;
    } else {
        // Treat as symbol with implicit concatenation of remaining atoms.
        if (sexpr.list.size() == 1) {
            auto r = std::make_shared<Regex>(op);
            r->pred = buildEdgePredAtom(op);
            return r;
        }
        std::vector<std::shared_ptr<Regex>> kids;
        for (const auto& e : sexpr.list) {
            kids.push_back(buildRegex(e));
        }
        return concat(kids);
    }
}

// --- Expr builder ----------------------------------------------------------

static const Variable* getOrCreateVar(const std::string& name,
                                      Domain& dom,
                                      std::map<std::string, std::unique_ptr<Variable>>& vars) {
    auto it = vars.find(name);
    if (it != vars.end()) return it->second.get();
    auto v = std::make_unique<Variable>(name, &dom);
    const Variable* ptr = v.get();
    vars[name] = std::move(v);
    return ptr;
}

std::shared_ptr<Expr> buildExpr(const SExpr& sexpr,
                                Domain& dom,
                                std::map<std::string, std::unique_ptr<Variable>>& vars) {
    if (sexpr.isAtom) {
        throw std::runtime_error("Unexpected atom where expression was expected: " + sexpr.atom);
    }
    if (sexpr.list.empty()) {
        throw std::runtime_error("Empty expression list");
    }
    const SExpr& head = sexpr.list[0];
    if (!head.isAtom) {
        throw std::runtime_error("Expression head must be atom");
    }
    const std::string& op = head.atom;
    if (op == "exists") {
        if (sexpr.list.size() != 3) {
            throw std::runtime_error("exists expects (exists (v1 v2 ...) subexpr)");
        }
        const SExpr& varList = sexpr.list[1];
        if (varList.isAtom) {
            throw std::runtime_error("exists: second argument must be var list");
        }
        std::vector<const Variable*> qvars;
        for (const auto& vsexpr : varList.list) {
            if (!vsexpr.isAtom) {
                throw std::runtime_error("exists: variable name must be atom");
            }
            qvars.push_back(getOrCreateVar(vsexpr.atom, dom, vars));
        }
        auto sub = buildExpr(sexpr.list[2], dom, vars);
        return Expr::exists(qvars, sub);
    } else if (op == "and" || op == "or") {
        std::vector<std::shared_ptr<Expr>> kids;
        for (size_t i = 1; i < sexpr.list.size(); ++i) {
            kids.push_back(buildExpr(sexpr.list[i], dom, vars));
        }
        return (op == "and") ? Expr::makeAnd(kids) : Expr::makeOr(kids);
    } else if (op == "not") {
        if (sexpr.list.size() != 2) {
            throw std::runtime_error("not expects one subexpression");
        }
        auto sub = buildExpr(sexpr.list[1], dom, vars);
        auto e = std::make_shared<Expr>();
        e->kind = Expr::Kind::Not;
        e->subExpr = sub;
        return e;
    } else if (op == "exists-path") {
        if (sexpr.list.size() != 4) {
            throw std::runtime_error("exists-path expects 3 arguments");
        }
        const SExpr& v1s = sexpr.list[1];
        const SExpr& v2s = sexpr.list[2];
        if (!v1s.isAtom || !v2s.isAtom) {
            throw std::runtime_error("exists-path: v1 and v2 must be atoms");
        }
        const Variable* v1 = getOrCreateVar(v1s.atom, dom, vars);
        const Variable* v2 = getOrCreateVar(v2s.atom, dom, vars);
        auto re = buildRegex(sexpr.list[3]);
        return Expr::existsPath(v1, v2, re);
    } else if (op == "no-edge") {
        if (sexpr.list.size() != 3) {
            throw std::runtime_error("no-edge expects 2 arguments");
        }
        const SExpr& v1s = sexpr.list[1];
        const SExpr& v2s = sexpr.list[2];
        if (!v1s.isAtom || !v2s.isAtom) {
            throw std::runtime_error("no-edge: v1 and v2 must be atoms");
        }
        const Variable* v1 = getOrCreateVar(v1s.atom, dom, vars);
        const Variable* v2 = getOrCreateVar(v2s.atom, dom, vars);
        return Expr::noEdge(v1, v2);
    } else if (op == "no-connection") {
        if (sexpr.list.size() != 3) {
            throw std::runtime_error("no-connection expects 2 arguments");
        }
        const SExpr& v1s = sexpr.list[1];
        const SExpr& v2s = sexpr.list[2];
        if (!v1s.isAtom || !v2s.isAtom) {
            throw std::runtime_error("no-connection: v1 and v2 must be atoms");
        }
        const Variable* v1 = getOrCreateVar(v1s.atom, dom, vars);
        const Variable* v2 = getOrCreateVar(v2s.atom, dom, vars);
        return Expr::noConnection(v1, v2);
    } else if (op == "same") {
        if (sexpr.list.size() != 3) {
            throw std::runtime_error("same expects 2 arguments");
        }
        const SExpr& v1s = sexpr.list[1];
        const SExpr& v2s = sexpr.list[2];
        if (!v1s.isAtom || !v2s.isAtom) {
            throw std::runtime_error("same: v1 and v2 must be atoms");
        }
        const Variable* v1 = getOrCreateVar(v1s.atom, dom, vars);
        const Variable* v2 = getOrCreateVar(v2s.atom, dom, vars);
        return Expr::same(v1, v2);
    } else if (op == "different") {
        if (sexpr.list.size() != 3) {
            throw std::runtime_error("different expects 2 arguments");
        }
        const SExpr& v1s = sexpr.list[1];
        const SExpr& v2s = sexpr.list[2];
        if (!v1s.isAtom || !v2s.isAtom) {
            throw std::runtime_error("different: v1 and v2 must be atoms");
        }
        const Variable* v1 = getOrCreateVar(v1s.atom, dom, vars);
        const Variable* v2 = getOrCreateVar(v2s.atom, dom, vars);
        return Expr::different(v1, v2);
    } else if (op == "match") {
        if (sexpr.list.size() != 3) {
            throw std::runtime_error("match expects 2 arguments");
        }
        const SExpr& v1s = sexpr.list[1];
        const SExpr& pats = sexpr.list[2];
        if (!v1s.isAtom || !pats.isAtom) {
            throw std::runtime_error("match: arguments must be atoms");
        }
        const Variable* v1 = getOrCreateVar(v1s.atom, dom, vars);
        std::string pat = pats.atom;
        if (pat.size() >= 2 && pat.front() == '"' && pat.back() == '"') {
            pat = pat.substr(1, pat.size() - 2);
        }
        return Expr::match(v1, pat);
    }
    throw std::runtime_error("Unknown operator in expression: " + op);
}

} // namespace greggle
