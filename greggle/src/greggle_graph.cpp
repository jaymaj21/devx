#include "greggle_graph.h"

namespace greggle {

Graph::Graph(int numNodes) : _numNodes(numNodes), _adj(numNodes), _labels(numNodes) {
    for (int i = 0; i < numNodes; ++i) {
        _labels[i] = std::to_string(i);
    }
}

void Graph::addEdge(int src, int dst, const std::set<std::string>& labels) {
    Edge e{src, dst, labels};
    _adj[src].push_back(std::move(e));
}

} // namespace greggle
