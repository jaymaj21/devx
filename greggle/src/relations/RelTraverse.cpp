/*
 * rel_traverse:
 * Enumerate satisfying assignments of a BDD over all FDD variables
 * that appear in it, and call TupleCallback for each tuple.
 */

#include "Relation.h"
#include "Variable.h"
#include "Domain.h"
#include "TupleCallback.h"
#include <bdd.h>

#include <map>
#include <vector>
#include <functional>

void rel_traverse(const bdd &root, TupleCallback &cb)
{
    // Discover which FDD variables appear in this BDD.
    int *vars = nullptr;
    int numVars = 0;
    fdd_scanset(root, vars, numVars);

    std::vector<Variable*> varList;
    varList.reserve(numVars);
    for (int i = 0; i < numVars; ++i) {
        auto it = Variable::varTable.find(vars[i]);
        if (it != Variable::varTable.end()) {
            varList.push_back(it->second);
        }
    }
    if (vars) {
        free(vars);
    }

    if (varList.empty()) {
        cb.executeTrue();
        return;
    }

    std::map<Variable*, std::vector<int>*> tuple;
    std::vector<int> values(varList.size(), 0);

    std::function<void(size_t, bdd)> dfs = [&](size_t idx, const bdd &cur) {
        if (cur == bddfalse) {
            return;
        }
        if (idx == varList.size()) {
            // Found a satisfying assignment; build tuple map.
            for (size_t i = 0; i < varList.size(); ++i) {
                auto *vec = new std::vector<int>();
                vec->push_back(values[i]);
                tuple[varList[i]] = vec;
            }
            cb.execute(tuple);
            tuple.clear();
            return;
        }
        Variable *var = varList[idx];
        int maxVal = var->getMax();
        int numBits = var->numBits();
        for (int v = 0; v < maxVal; ++v) {
            values[idx] = v;
            bvec c  = bvec_con(numBits, v);
            bvec bv = bvec_varfdd(var->getVarNum());
            bdd constr = (c == bv);
            dfs(idx + 1, cur & constr);
        }
    };

    dfs(0, root);
}
