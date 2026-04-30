#include "greggle_parse.h"
#include "greggle_regex.h"

#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <queue>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

struct AutomatonState {
    bool accepting = false;
    std::vector<int> eps;
    std::vector<std::pair<std::shared_ptr<greggle::EdgePred>, int>> trans;
};

struct Automaton {
    int start = 0;
    bool isDeterministic = false;
    std::vector<AutomatonState> states;
};

struct Options {
    bool toDFA = false;
    bool negate = false;
    std::string regexText;
    std::string outputPath;
};

int newState(Automaton& automaton) {
    int id = static_cast<int>(automaton.states.size());
    automaton.states.emplace_back();
    return id;
}

std::shared_ptr<greggle::EdgePred> makeAnyPred() {
    auto p = std::make_shared<greggle::EdgePred>();
    p->kind = greggle::EdgePred::Kind::Any;
    return p;
}

std::shared_ptr<greggle::EdgePred> makeAtomPred(const std::string& lab) {
    auto p = std::make_shared<greggle::EdgePred>();
    p->kind = greggle::EdgePred::Kind::Atom;
    p->label = lab;
    return p;
}

std::shared_ptr<greggle::EdgePred> makeNegatePred(const std::shared_ptr<greggle::EdgePred>& sub) {
    auto p = std::make_shared<greggle::EdgePred>();
    p->kind = greggle::EdgePred::Kind::Not;
    p->sub = sub;
    return p;
}

std::shared_ptr<greggle::EdgePred> makeAllOfPred(
    const std::vector<std::shared_ptr<greggle::EdgePred>>& children) {
    if (children.empty()) {
        return makeAnyPred();
    }
    if (children.size() == 1) {
        return children[0];
    }
    auto p = std::make_shared<greggle::EdgePred>();
    p->kind = greggle::EdgePred::Kind::AllOf;
    p->children = children;
    return p;
}

std::shared_ptr<greggle::EdgePred> makeSomeOfPred(
    const std::vector<std::shared_ptr<greggle::EdgePred>>& children) {
    if (children.empty()) {
        return nullptr;
    }
    if (children.size() == 1) {
        return children[0];
    }
    auto p = std::make_shared<greggle::EdgePred>();
    p->kind = greggle::EdgePred::Kind::SomeOf;
    p->children = children;
    return p;
}

std::pair<int, int> buildNFA(const std::shared_ptr<greggle::Regex>& re, Automaton& automaton) {
    using Kind = greggle::Regex::Kind;
    if (!re) {
        int s = newState(automaton);
        int e = newState(automaton);
        automaton.states[s].eps.push_back(e);
        return {s, e};
    }
    switch (re->kind) {
    case Kind::Symbol: {
        int s = newState(automaton);
        int e = newState(automaton);
        std::shared_ptr<greggle::EdgePred> p = re->pred;
        if (!p) {
            p = makeAtomPred(re->symbol);
        }
        automaton.states[s].trans.emplace_back(p, e);
        return {s, e};
    }
    case Kind::Concat: {
        std::pair<int, int> acc;
        bool first = true;
        for (const auto& child : re->children) {
            auto sub = buildNFA(child, automaton);
            if (first) {
                acc = sub;
                first = false;
            } else {
                automaton.states[acc.second].eps.push_back(sub.first);
                acc.second = sub.second;
            }
        }
        if (first) {
            int s = newState(automaton);
            int e = newState(automaton);
            automaton.states[s].eps.push_back(e);
            return {s, e};
        }
        return acc;
    }
    case Kind::Alt: {
        int s = newState(automaton);
        int e = newState(automaton);
        for (const auto& child : re->children) {
            auto sub = buildNFA(child, automaton);
            automaton.states[s].eps.push_back(sub.first);
            automaton.states[sub.second].eps.push_back(e);
        }
        return {s, e};
    }
    case Kind::Star: {
        auto sub = buildNFA(re->sub, automaton);
        int s = newState(automaton);
        int e = newState(automaton);
        automaton.states[s].eps.push_back(sub.first);
        automaton.states[s].eps.push_back(e);
        automaton.states[sub.second].eps.push_back(sub.first);
        automaton.states[sub.second].eps.push_back(e);
        return {s, e};
    }
    case Kind::Plus: {
        auto sub = buildNFA(re->sub, automaton);
        int s = newState(automaton);
        int e = newState(automaton);
        automaton.states[s].eps.push_back(sub.first);
        automaton.states[sub.second].eps.push_back(sub.first);
        automaton.states[sub.second].eps.push_back(e);
        return {s, e};
    }
    }
    int s = newState(automaton);
    int e = newState(automaton);
    automaton.states[s].eps.push_back(e);
    return {s, e};
}

bool evalEdgePred(const greggle::EdgePred& pred, const std::set<std::string>& labels) {
    using Kind = greggle::EdgePred::Kind;
    switch (pred.kind) {
    case Kind::Any:
        return true;
    case Kind::Atom:
        return labels.count(pred.label) > 0;
    case Kind::SourceNodeMatch:
    case Kind::SinkNodeMatch:
        throw std::runtime_error(
            "Determinization/complement is not supported for node-lifted predicates");
    case Kind::Not:
        return pred.sub ? !evalEdgePred(*pred.sub, labels) : true;
    case Kind::AllOf:
        for (const auto& child : pred.children) {
            if (child && !evalEdgePred(*child, labels)) {
                return false;
            }
        }
        return true;
    case Kind::SomeOf:
        for (const auto& child : pred.children) {
            if (child && evalEdgePred(*child, labels)) {
                return true;
            }
        }
        return false;
    }
    return false;
}

void collectAtomsFromPred(const std::shared_ptr<greggle::EdgePred>& pred, std::set<std::string>& atoms) {
    using Kind = greggle::EdgePred::Kind;
    if (!pred) {
        return;
    }
    switch (pred->kind) {
    case Kind::Any:
        return;
    case Kind::Atom:
        atoms.insert(pred->label);
        return;
    case Kind::SourceNodeMatch:
    case Kind::SinkNodeMatch:
        throw std::runtime_error(
            "Determinization/complement is not supported for node-lifted predicates");
    case Kind::Not:
        collectAtomsFromPred(pred->sub, atoms);
        return;
    case Kind::AllOf:
    case Kind::SomeOf:
        for (const auto& child : pred->children) {
            collectAtomsFromPred(child, atoms);
        }
        return;
    }
}

void collectAtomsFromAutomaton(const Automaton& automaton, std::vector<std::string>& atoms) {
    std::set<std::string> atomSet;
    for (const auto& state : automaton.states) {
        for (const auto& tr : state.trans) {
            collectAtomsFromPred(tr.first, atomSet);
        }
    }
    atoms.assign(atomSet.begin(), atomSet.end());
}

std::set<std::string> labelsForMask(std::uint64_t mask, const std::vector<std::string>& atoms) {
    std::set<std::string> labels;
    for (std::size_t i = 0; i < atoms.size(); ++i) {
        if ((mask & (std::uint64_t{1} << i)) != 0) {
            labels.insert(atoms[i]);
        }
    }
    return labels;
}

void epsilonClosure(const Automaton& automaton, const std::set<int>& input, std::set<int>& out) {
    std::vector<int> stack(input.begin(), input.end());
    out = input;
    while (!stack.empty()) {
        int s = stack.back();
        stack.pop_back();
        for (int t : automaton.states[s].eps) {
            if (!out.count(t)) {
                out.insert(t);
                stack.push_back(t);
            }
        }
    }
}

std::set<int> moveOnLabels(const Automaton& automaton,
                           const std::set<int>& subset,
                           const std::set<std::string>& labels) {
    std::set<int> rawNext;
    for (int stateId : subset) {
        const auto& state = automaton.states[stateId];
        for (const auto& tr : state.trans) {
            if (!tr.first || evalEdgePred(*tr.first, labels)) {
                rawNext.insert(tr.second);
            }
        }
    }
    std::set<int> closed;
    epsilonClosure(automaton, rawNext, closed);
    return closed;
}

bool subsetAccepting(const Automaton& automaton, const std::set<int>& subset) {
    for (int stateId : subset) {
        if (automaton.states[stateId].accepting) {
            return true;
        }
    }
    return false;
}

std::shared_ptr<greggle::EdgePred> maskToPredicate(std::uint64_t mask,
                                                   const std::vector<std::string>& atoms) {
    if (atoms.empty()) {
        return makeAnyPred();
    }
    std::vector<std::shared_ptr<greggle::EdgePred>> clauses;
    clauses.reserve(atoms.size());
    for (std::size_t i = 0; i < atoms.size(); ++i) {
        auto atom = makeAtomPred(atoms[i]);
        if ((mask & (std::uint64_t{1} << i)) != 0) {
            clauses.push_back(atom);
        } else {
            clauses.push_back(makeNegatePred(atom));
        }
    }
    return makeAllOfPred(clauses);
}

std::shared_ptr<greggle::EdgePred> masksToPredicate(const std::vector<std::uint64_t>& masks,
                                                    const std::vector<std::string>& atoms) {
    if (masks.empty()) {
        return nullptr;
    }
    if (atoms.size() >= 63) {
        throw std::runtime_error("Too many distinct atomic labels for predicate enumeration");
    }
    const std::uint64_t total = std::uint64_t{1} << atoms.size();
    if (masks.size() == total) {
        return makeAnyPred();
    }
    std::vector<std::shared_ptr<greggle::EdgePred>> options;
    options.reserve(masks.size());
    for (std::uint64_t mask : masks) {
        options.push_back(maskToPredicate(mask, atoms));
    }
    return makeSomeOfPred(options);
}

Automaton determinizeAutomaton(const Automaton& nfa) {
    std::vector<std::string> atoms;
    collectAtomsFromAutomaton(nfa, atoms);
    if (atoms.size() >= 20) {
        throw std::runtime_error(
            "Determinization currently supports at most 19 distinct atomic labels");
    }

    Automaton dfa;
    dfa.isDeterministic = true;

    std::set<int> startSeed{nfa.start};
    std::set<int> startSubset;
    epsilonClosure(nfa, startSeed, startSubset);

    std::map<std::set<int>, int> subsetToState;
    std::queue<std::set<int>> pending;

    auto ensureState = [&](const std::set<int>& subset) -> int {
        auto it = subsetToState.find(subset);
        if (it != subsetToState.end()) {
            return it->second;
        }
        int id = newState(dfa);
        dfa.states[id].accepting = subsetAccepting(nfa, subset);
        subsetToState[subset] = id;
        pending.push(subset);
        return id;
    };

    dfa.start = ensureState(startSubset);

    const std::uint64_t totalMasks = std::uint64_t{1} << atoms.size();
    while (!pending.empty()) {
        std::set<int> subset = pending.front();
        pending.pop();
        int srcId = subsetToState[subset];

        std::map<std::set<int>, std::vector<std::uint64_t>> grouped;
        for (std::uint64_t mask = 0; mask < totalMasks; ++mask) {
            std::set<std::string> labels = labelsForMask(mask, atoms);
            std::set<int> dstSubset = moveOnLabels(nfa, subset, labels);
            grouped[dstSubset].push_back(mask);
        }

        for (const auto& entry : grouped) {
            const std::set<int>& dstSubset = entry.first;
            const std::vector<std::uint64_t>& masks = entry.second;
            int dstId = ensureState(dstSubset);
            std::shared_ptr<greggle::EdgePred> pred = masksToPredicate(masks, atoms);
            if (!pred) {
                continue;
            }
            dfa.states[srcId].trans.emplace_back(pred, dstId);
        }
    }

    return dfa;
}

Automaton complementAutomaton(Automaton automaton) {
    if (!automaton.isDeterministic) {
        automaton = determinizeAutomaton(automaton);
    }
    for (auto& state : automaton.states) {
        state.accepting = !state.accepting;
        state.eps.clear();
    }
    automaton.isDeterministic = true;
    return automaton;
}

std::string edgePredToString(const std::shared_ptr<greggle::EdgePred>& pred) {
    using Kind = greggle::EdgePred::Kind;
    if (!pred) {
        return "<null>";
    }
    switch (pred->kind) {
    case Kind::Any:
        return "dot";
    case Kind::Atom:
        return pred->label;
    case Kind::SourceNodeMatch:
        return pred->nodePattern + "@";
    case Kind::SinkNodeMatch:
        return "@" + pred->nodePattern;
    case Kind::Not:
        return pred->sub ? "(negate " + edgePredToString(pred->sub) + ")" : "(negate)";
    case Kind::AllOf: {
        std::ostringstream oss;
        oss << "(all-of";
        for (const auto& child : pred->children) {
            oss << " " << edgePredToString(child);
        }
        oss << ")";
        return oss.str();
    }
    case Kind::SomeOf: {
        std::ostringstream oss;
        oss << "(some-of";
        for (const auto& child : pred->children) {
            oss << " " << edgePredToString(child);
        }
        oss << ")";
        return oss.str();
    }
    }
    return "<?>";
}

std::string escapeDotLabel(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    for (char ch : s) {
        if (ch == '\\' || ch == '"') {
            out.push_back('\\');
        }
        out.push_back(ch);
    }
    return out;
}

void writeDot(const Automaton& automaton, std::ostream& out) {
    out << "digraph greggle_regex_nfa {\n";
    out << "  rankdir=LR;\n";
    out << "  node [shape=circle, fontname=\"Helvetica\"];\n";
    out << "  edge [fontname=\"Helvetica\"];\n";
    out << "  start [shape=diamond, label=\"start\"];\n";
    out << "\n";

    for (std::size_t i = 0; i < automaton.states.size(); ++i) {
        out << "  q" << i << " [shape="
            << (automaton.states[i].accepting ? "doublecircle" : "circle")
            << ", label=\"q" << i << "\"];\n";
    }
    out << "\n";
    out << "  start -> q" << automaton.start << ";\n";
    out << "\n";

    for (std::size_t i = 0; i < automaton.states.size(); ++i) {
        for (int dst : automaton.states[i].eps) {
            out << "  q" << i << " -> q" << dst << " [label=\"eps\"];\n";
        }
        for (const auto& tr : automaton.states[i].trans) {
            out << "  q" << i << " -> q" << tr.second
                << " [label=\"" << escapeDotLabel(edgePredToString(tr.first)) << "\"];\n";
        }
    }

    out << "}\n";
}

void usage(const char* argv0) {
    std::cerr << "Usage: " << argv0
              << " [toDFA] [negate] \"<regex in lisp syntax>\" [output.dot]\n";
}

bool parseArgs(int argc, char** argv, Options& options) {
    std::vector<std::string> positional;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "toDFA") {
            options.toDFA = true;
            continue;
        }
        if (arg == "negate") {
            options.negate = true;
            continue;
        }
        positional.push_back(arg);
    }
    if (positional.size() != 1 && positional.size() != 2) {
        return false;
    }
    options.regexText = positional[0];
    if (positional.size() == 2) {
        options.outputPath = positional[1];
    }
    return true;
}

} // namespace

int main(int argc, char** argv) {
    Options options;
    if (!parseArgs(argc, argv, options)) {
        usage(argv[0]);
        return 1;
    }

    std::istringstream iss(options.regexText);
    greggle::SExpr sexpr;
    if (!greggle::parseSExpr(iss, sexpr)) {
        std::cerr << "Error: failed to parse regex.\n";
        return 1;
    }

    std::shared_ptr<greggle::Regex> re;
    try {
        re = greggle::buildRegex(sexpr);
    } catch (const std::exception& ex) {
        std::cerr << "Error while building regex: " << ex.what() << "\n";
        return 1;
    }

    Automaton automaton;
    auto se = buildNFA(re, automaton);
    automaton.start = se.first;
    automaton.states[se.second].accepting = true;

    try {
        if (options.toDFA || options.negate) {
            automaton = determinizeAutomaton(automaton);
        }
        if (options.negate) {
            automaton = complementAutomaton(std::move(automaton));
        }
    } catch (const std::exception& ex) {
        std::cerr << "Error while transforming automaton: " << ex.what() << "\n";
        return 1;
    }

    if (!options.outputPath.empty()) {
        std::ofstream out(options.outputPath);
        if (!out) {
            std::cerr << "Error: cannot open output file '" << options.outputPath << "'.\n";
            return 1;
        }
        writeDot(automaton, out);
        return 0;
    }

    writeDot(automaton, std::cout);
    return 0;
}
