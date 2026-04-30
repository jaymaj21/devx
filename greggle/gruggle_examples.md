node gruggle.js  chain "add-node nx:1:10" "add-edge 10 nx.* nx.*" "delete-isolated-nodes" "to-svg graph1.svg"
node gruggle.js -i graph1.g chain "keep-paths nx10 nx[12]" "to-svg graph2.svg"

node gruggle.js chain "add-nodes nx:1:10" "add-nodes bx:1:1" "add-edges 10 bx.* nx.*" "to-svg star.svg"

node gruggle.js chain "add-nodes nx:1:10" "add-nodes bx:1:1" "add-nodes cx:1:20" "add-edges 10 bx.* nx.*" "add-edges 20 nx.* cx.*" "to-svg tree.svg"

node gruggle.js chain "add-nodes nx:1:10" "add-nodes bx:1:1" "add-nodes cx:1:20" "add-edges 10 bx.* nx.*" "add-edges 20 nx.* cx.*" "delete-isolated-nodes" "to-svg tree.svg"

node gruggle.js -i tree.g chain "remove-nodes nx10" "delete-isolated-nodes" "to-svg tree2.svg"
