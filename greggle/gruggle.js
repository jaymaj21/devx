#!/usr/bin/env node
// gruggle.js - DOT loader/merger in pure Node.js (no deps)

const fs = require('fs');

function usage() {
  console.log(`Usage: node gruggle.js [-i file.dot ...] [subcommands...]
  -i file   Add a DOT file to parse and merge (repeatable)
  --ortho | --rectilinear  Use rectilinear edges (Graphviz splines=ortho)
  --curved                 Use curved spline edges (default)
  -h        Show help

If no -i is supplied, starts from an empty digraph.
Run 'node gruggle.js help' for a detailed command reference.`);
}

function detailedHelp() {
  console.log(`Gruggle command reference
============================
General:
  help                         Show this help.
  set-name <name>              Rename the graph.
  chain "cmd1 ..." ...         Run subcommands in order; inside chain, -f <file> injects
                               commands line-by-line at that point (blank/# lines ignored).
  to-svg <file.svg>            Emit SVG via dot -Tsvg -o <file.svg>.

Building graphs:
  add-nodes <id>|<prefix:start:end>    Add a node or a range (e.g., nx:1:3 -> nx1,nx2,nx3).
  add-edges <label> <fromRe> <toRe>    Add edges for all pairs matching regexes (directed if graph is digraph).
  add-edges <count> <fromRe> <toRe> [label]  Add up to <count> random distinct pairs.
  add-chain <root> <n>                 Add nodes root_1..root_n and chain edges between them.
  add-ring <root> <n> [start]          Add chain and close the ring from last to first.
  add-grid <root> <rows> <cols> [start] Add a rows x cols grid with nodes root_i_j (i,j start at start).
  add-clique <root> <n> [start]        Add complete graph on nodes root_{start..start+n-1}.
  add-nodes <count> <root> [start]     Add count isolated nodes root_start ... root_{start+count-1}.
  delete-isolated-nodes                 Drop nodes with no incident edges.
  remove-nodes <regex>                  Delete nodes matching regex (and incident edges).
  remove-edges-between-nodes <fromRe> <toRe>  Delete edges whose tail/head match regexes.

Path-based operations:
  keep-paths <fromRe> <toRe>            Mark nodes/edges on paths from sources->targets as keep.
  remove-paths <fromRe> <toRe>          Mark nodes/edges on such paths as remove.
  keep-path-edges <fromRe> <toRe>       Mark only edges on such paths as keep.
  remove-path-edges <fromRe> <toRe>     Mark only edges on such paths as remove.
  filter-to-paths <fromRe> <toRe>       Keep only nodes/edges on such paths; mark all others remove.
  select-nodes-on-paths <fromRe> <toRe> Select all nodes on such paths.
  select-edges-on-paths <fromRe> <toRe> Select all edges on such paths.
  find-path <regex> <label>             Annotate one path matching a greggle-compatible regex with label.
                                        Regexes may include node-lifted predicates:
                                        P@ tests the source node label, @P tests the sink node label.
  select-neighbours [in|out|both] <hops> Expand selection via BFS over neighbors (default both,1).
  select-nodes-degree <lt|le|eq|ge|gt> <k> Select nodes by total degree (in+out for digraphs).
  select-nodes-indegree <lt|le|eq|ge|gt> <k> Select nodes by indegree.
  select-nodes-outdegree <lt|le|eq|ge|gt> <k> Select nodes by outdegree.
  select-component-of-nodes <regex>     Select all nodes/edges in components of matching nodes.
  select-components-with-selected       Select all nodes/edges in components containing selected nodes.
  clear-selection                       Clear selection on all nodes/edges.
  invert-selection-nodes                Flip selection flag on nodes.
  invert-selection-edges                Flip selection flag on edges.
  add-labels-to-edges-on-paths <fromRe> <toRe> <label>    Append label to edges on such paths.
  remove-labels-from-edges-on-paths <fromRe> <toRe> <label> Remove label from edges on such paths.

Selection and bulk edits:
  select-nodes <regex>                  Select nodes by ID regex (for later bulk ops).
  deselect-nodes <regex>                Unselect matching nodes.
  select-edges <labelRe>                Select edges whose label contains a component matching labelRe.
  select-edges <fromRe> <toRe>          Select edges whose tail/head IDs match regexes.
  deselect-edges ...                    Unselect matching edges (same forms as select-edges).
  delete-selected                       Delete selected nodes (and incident edges) and selected edges.
  add-labels-to-selected <label>        Append label to all selected nodes/edges (comma separated).
  remove-labels-from-selected <label>   Remove label from selected nodes/edges (drops attr if empty).
  select-nodes-label <labelRe>          Select nodes whose label attribute has a matching component.
  set-node-attr-on-selected <attr> <value>   Set DOT attribute on selected nodes.
  set-edge-attr-on-selected <attr> <value>   Set DOT attribute on selected edges.
  unset-node-attr-on-selected <attr>         Remove DOT attribute from selected nodes.
  unset-edge-attr-on-selected <attr>         Remove DOT attribute from selected edges.
  clear-visual-attrs-on-selected             Remove common visual attrs (color, fillcolor, fontcolor,
                                             style, shape, penwidth, arrowsize, fontsize) on selected.

Labels:
  add-labels-to-selected / add-labels-to-edges-on-paths accept/emit comma-separated labels.

Examples:
  node gruggle.js -i g1.dot -i g2.dot chain "set-name merged" "to-svg merged.svg"
  node gruggle.js chain "add-nodes nx:1:5" "add-edges 10 nx.* nx.*"
  node gruggle.js -i g.dot chain "select-edges error" "add-labels-to-selected reviewed"
  node gruggle.js -i g.dot chain -f commands.txt "delete-selected"
`);
}

// --- Graph model helpers ----------------------------------------------------
const emptyGraph = () => ({
  type: 'digraph',
  strict: false,
  name: 'G',
  graphAttrs: {
    splines: 'spline', // curved by default
    nodesep: '0.35',
    ranksep: '0.5',
  },
  nodeDefaults: {
    shape: 'box',
    style: 'rounded,filled',
    fillcolor: '#e6f2ff',
    color: '#4a6fa5',
    fontname: 'Helvetica',
    fontsize: '10',
  },
  edgeDefaults: {
    color: '#4a6fa5',
    penwidth: '1.2',
    arrowsize: '0.8',
  },
  nodes: new Map(), // id -> {attrs, keep?, remove?, selected?}
  edges: [], // list of {tail, head, tailPort, headPort, directed, attrs, keep?, remove?, selected?}
  edgeIndex: new Map(), // key -> index in edges
});

const edgeKey = (t, h, dir, tp = '', hp = '') => `${t}:${tp}->${h}:${hp}:${dir}`;

function ensureNodeObj(graph, id) {
  if (!graph.nodes.has(id)) {
    graph.nodes.set(id, { id, attrs: Object.assign({}, graph.nodeDefaults), keep: false, remove: false, selected: false });
  } else {
    const obj = graph.nodes.get(id);
    obj.id = id;
  }
  return graph.nodes.get(id);
}

function addNode(graph, id, attrs = {}, defaults = {}) {
  const nodeObj = ensureNodeObj(graph, id);
  nodeObj.attrs = Object.assign({}, defaults, nodeObj.attrs, attrs);
}

function addEdge(graph, tail, head, directed, attrs, defaults, tailPort = '', headPort = '') {
  const merged = Object.assign({}, defaults, attrs);
  const key = edgeKey(tail, head, directed, tailPort, headPort);
  if (graph.edgeIndex.has(key)) {
    const idx = graph.edgeIndex.get(key);
    graph.edges[idx].attrs = Object.assign({}, graph.edges[idx].attrs, merged);
  } else {
    graph.edges.push({ tail, head, tailPort, headPort, directed, attrs: merged, keep: false, remove: false, selected: false });
    graph.edgeIndex.set(key, graph.edges.length - 1);
  }
}

function rebuildEdgeIndex(graph) {
  graph.edgeIndex = new Map();
  graph.edges.forEach((e, idx) => {
    const key = edgeKey(e.tail, e.head, e.directed, e.tailPort, e.headPort);
    graph.edgeIndex.set(key, idx);
  });
}

function mergeGraphs(graphs) {
  if (!graphs.length) return emptyGraph();
  const base = graphs[0];
  for (let i = 1; i < graphs.length; i++) {
    const g = graphs[i];
    if (g.type === 'digraph') base.type = 'digraph';
    if (g.strict) base.strict = true;
    if (!base.name && g.name) base.name = g.name;
    base.graphAttrs = Object.assign({}, base.graphAttrs, g.graphAttrs);
    base.nodeDefaults = Object.assign({}, base.nodeDefaults, g.nodeDefaults);
    base.edgeDefaults = Object.assign({}, base.edgeDefaults, g.edgeDefaults);
    for (const [nid, nodeObj] of g.nodes.entries()) {
      const prev = ensureNodeObj(base, nid);
      prev.attrs = Object.assign({}, prev.attrs, nodeObj.attrs);
      prev.keep = prev.keep || nodeObj.keep;
      prev.remove = prev.remove || nodeObj.remove;
      prev.selected = prev.selected || nodeObj.selected;
    }
    for (const e of g.edges) {
      addEdge(
        base,
        e.tail,
        e.head,
        e.directed,
        e.attrs,
        {},
        e.tailPort,
        e.headPort
      );
      const key = edgeKey(e.tail, e.head, e.directed, e.tailPort, e.headPort);
      const idx = base.edgeIndex.get(key);
      base.edges[idx].keep = base.edges[idx].keep || e.keep;
      base.edges[idx].remove = base.edges[idx].remove || e.remove;
      base.edges[idx].selected = base.edges[idx].selected || e.selected;
    }
  }
  return base;
}

// --- Tokenizer --------------------------------------------------------------
function tokenize(text) {
  const tokens = [];
  let i = 0, line = 1, col = 1;
  const len = text.length;
  const push = (type, val) => tokens.push({ type, val, line, col });
  const bump = (n = 1) => { i += n; col += n; };

  while (i < len) {
    const ch = text[i];
    // whitespace
    if (ch === ' ' || ch === '\t' || ch === '\r') { bump(); continue; }
    if (ch === '\n') { i++; line++; col = 1; continue; }

    // comments
    if (ch === '/' && i + 1 < len && text[i + 1] === '/') {
      i += 2; col += 2;
      while (i < len && text[i] !== '\n') { i++; col++; }
      continue;
    }
    if (ch === '/' && i + 1 < len && text[i + 1] === '*') {
      i += 2; col += 2;
      while (i < len - 1) {
        if (text[i] === '\n') { i++; line++; col = 1; continue; }
        if (text[i] === '*' && text[i + 1] === '/') { i += 2; col += 2; break; }
        i++; col++;
      }
      continue;
    }
    if (ch === '#') {
      while (i < len && text[i] !== '\n') { i++; col++; }
      continue;
    }

    // punctuation
    if ('{}[]=;,:'.includes(ch)) { push(ch, ch); bump(); continue; }
    if (ch === '-' && i + 1 < len && (text[i + 1] === '-' || text[i + 1] === '>')) {
      push('edgeop', text[i] + text[i + 1]); bump(2); continue;
    }

    // quoted string
    if (ch === '"') {
      let buf = ''; bump();
      while (i < len) {
        const c = text[i];
        if (c === '\\') {
          if (i + 1 < len) {
            const n = text[i + 1];
            const escapes = { n: '\n', r: '\r', t: '\t', '"': '"', '\\': '\\' };
            buf += (escapes[n] !== undefined ? escapes[n] : n);
            bump(2);
            continue;
          }
        } else if (c === '"') { bump(); break; }
        buf += c; bump();
      }
      push('id', buf);
      continue;
    }

    // HTML-like <...>
    if (ch === '<') {
      let depth = 1, buf = '<'; bump();
      while (i < len && depth > 0) {
        const c = text[i];
        buf += c;
        if (c === '<') depth++;
        else if (c === '>') depth--;
        if (c === '\n') { line++; col = 1; i++; continue; }
        bump();
      }
      push('id', buf);
      continue;
    }

    // identifiers / numbers
    const identStart = /[A-Za-z_\x80-\xff]/;
    const identRest = /[A-Za-z0-9_\x80-\xff\.]/;
    if (identStart.test(ch)) {
      const start = i;
      bump();
      while (i < len && identRest.test(text[i])) bump();
      push('word', text.slice(start, i));
      continue;
    }
    if (/[0-9]/.test(ch)) {
      const start = i;
      bump();
      while (i < len && /[0-9.]/.test(text[i])) bump();
      push('id', text.slice(start, i));
      continue;
    }

    throw new Error(`Unexpected character '${ch}' at ${line}:${col}`);
  }
  return tokens;
}

// --- Parser -----------------------------------------------------------------
const peek = (toks, idx) => (idx < toks.length ? toks[idx] : null);

function parseAttrList(toks, idx) {
  const attrs = {};
  while (peek(toks, idx) && peek(toks, idx).val === '[') {
    idx++; // [
    while (true) {
      const tok = peek(toks, idx);
      if (!tok) throw new Error('Unterminated attribute list');
      if (tok.val === ']') { idx++; break; }
      if (!['word', 'id'].includes(tok.type)) throw new Error(`Expected attribute name at ${tok.line}:${tok.col}`);
      const key = tok.val; idx++;
      let val = '';
      const next = peek(toks, idx);
      if (next && next.val === '=') {
        idx++;
        const vtok = peek(toks, idx);
        if (!vtok) throw new Error('Missing attribute value');
        val = vtok.val; idx++;
      }
      attrs[key] = val;
      const sep = peek(toks, idx);
      if (!sep) throw new Error('Unterminated attribute list');
      if (sep.val === ',' || sep.val === ';') { idx++; continue; }
      if (sep.val === ']') continue;
    }
  }
  return [attrs, idx];
}

function parseNodeId(toks, idx) {
  const tok = peek(toks, idx);
  if (!tok || !['word', 'id'].includes(tok.type)) throw new Error(`Expected node identifier at ${tok ? tok.line : 'EOF'}`);
  const id = tok.val; idx++;
  let port = '';
  if (peek(toks, idx) && peek(toks, idx).val === ':') {
    idx++;
    const pTok = peek(toks, idx);
    if (!pTok) throw new Error('Missing port after colon');
    port = pTok.val; idx++;
    if (peek(toks, idx) && peek(toks, idx).val === ':') {
      idx++;
      const compass = peek(toks, idx);
      if (!compass) throw new Error('Missing compass after second colon');
      port = `${port}:${compass.val}`; idx++;
    }
  }
  return [{ id, port }, idx];
}

function parseSubgraph(toks, idx, graph, state) {
  const nodes = [];
  idx++; // {
  while (true) {
    const tok = peek(toks, idx);
    if (!tok) throw new Error('Unterminated subgraph');
    if (tok.val === '}') { idx++; break; }
    let collector = nodes;
    [idx, collector] = parseStatement(toks, idx, graph, state, collector);
    const sep = peek(toks, idx);
    if (sep && (sep.val === ';' || sep.val === ',')) idx++;
  }
  return [nodes, idx];
}

function parsePrimary(toks, idx, graph, state) {
  const tok = peek(toks, idx);
  if (!tok) throw new Error('Unexpected end of input');
  if (tok.val === 'subgraph') {
    idx++;
    const maybeName = peek(toks, idx);
    if (maybeName && maybeName.val !== '{') idx++; // discard name
    const next = peek(toks, idx);
    if (!next || next.val !== '{') throw new Error(`Expected '{' after subgraph at ${tok.line}:${tok.col}`);
    return parseSubgraph(toks, idx, graph, state);
  }
  if (tok.val === '{') return parseSubgraph(toks, idx, graph, state);
  const [node, newIdx] = parseNodeId(toks, idx);
  return [[node], newIdx];
}

function parseEdgeStatement(toks, idx, firstNodes, graph, state) {
  let leftNodes = firstNodes;
  let directed = true;
  while (true) {
    const opTok = peek(toks, idx);
    if (!opTok || opTok.type !== 'edgeop') break;
    directed = opTok.val === '->';
    idx++;
    const [rightNodes, newIdx] = parsePrimary(toks, idx, graph, state);
    idx = newIdx;
    const pairs = [];
    for (const l of leftNodes) for (const r of rightNodes) pairs.push([l, r]);
    leftNodes = rightNodes;

    const [attrs, afterIdx] = parseAttrList(toks, idx);
    idx = afterIdx;
    for (const [l, r] of pairs) {
      addNode(graph, l.id, {}, state.nodeDefaults);
      addNode(graph, r.id, {}, state.nodeDefaults);
      addEdge(graph, l.id, r.id, directed, attrs, state.edgeDefaults, l.port, r.port);
    }
  }
  return idx;
}

function parseStatement(toks, idx, graph, state, collector = null) {
  const tok = peek(toks, idx);
  if (!tok) return [idx, collector];
  if (tok.val === 'strict') { graph.strict = true; idx++; return [idx, collector]; }
  if (['graph', 'node', 'edge'].includes(tok.val)) {
    const kind = tok.val; idx++;
    const [attrs, newIdx] = parseAttrList(toks, idx);
    idx = newIdx;
    if (kind === 'graph') graph.graphAttrs = Object.assign({}, graph.graphAttrs, attrs);
    if (kind === 'node') state.nodeDefaults = Object.assign({}, state.nodeDefaults, attrs);
    if (kind === 'edge') state.edgeDefaults = Object.assign({}, state.edgeDefaults, attrs);
    return [idx, collector];
  }
  if (tok.val === 'subgraph' || tok.val === '{') {
    const [nodes, newIdx] = parsePrimary(toks, idx, graph, state);
    idx = newIdx;
    if (collector) collector.push(...nodes);
    return [idx, collector];
  }

  const [node, afterNodeIdx] = parseNodeId(toks, idx);
  idx = afterNodeIdx;
  const next = peek(toks, idx);

  if (next && next.type === 'edgeop') {
    idx = parseEdgeStatement(toks, idx, [node], graph, state);
    if (collector) collector.push(node);
    return [idx, collector];
  }
  if (next && next.val === '=') {
    idx++;
    const vtok = peek(toks, idx);
    if (!vtok) throw new Error('Missing value after =');
    idx++;
    graph.graphAttrs[node.id] = vtok.val;
    return [idx, collector];
  }

  const [attrs, newIdx] = parseAttrList(toks, idx);
  idx = newIdx;
  addNode(graph, node.id, attrs, state.nodeDefaults);
  if (collector) collector.push(node);
  return [idx, collector];
}

function parseGraph(toks) {
  let idx = 0;
  const graph = emptyGraph();
  const state = { nodeDefaults: {}, edgeDefaults: {} };

  if (peek(toks, idx) && peek(toks, idx).val === 'strict') { graph.strict = true; idx++; }
  const kindTok = peek(toks, idx);
  if (!kindTok || !['graph', 'digraph'].includes(kindTok.val)) throw new Error('Expected graph or digraph');
  graph.type = kindTok.val; idx++;

  const nameTok = peek(toks, idx);
  if (nameTok && nameTok.val !== '{') { graph.name = nameTok.val; idx++; }

  if (!peek(toks, idx) || peek(toks, idx).val !== '{') throw new Error('Expected { to start graph');
  idx++;

  while (true) {
    const tok = peek(toks, idx);
    if (!tok) throw new Error('Unterminated graph body');
    if (tok.val === '}') { idx++; break; }
    [idx] = parseStatement(toks, idx, graph, state);
    const sep = peek(toks, idx);
    if (sep && (sep.val === ';' || sep.val === ',')) idx++;
  }
  return graph;
}

function parse(text) {
  const toks = tokenize(text);
  return parseGraph(toks);
}

// --- Path marking helpers ---------------------------------------------------
function buildAdjacency(graph) {
  const adj = new Map();
  const radj = new Map();
  const add = (m, a, b) => {
    if (!m.has(a)) m.set(a, new Set());
    m.get(a).add(b);
  };
  const nodes = Array.from(graph.nodes.keys());
  for (const n of nodes) {
    if (!adj.has(n)) adj.set(n, new Set());
    if (!radj.has(n)) radj.set(n, new Set());
  }
  for (const e of graph.edges) {
    add(adj, e.tail, e.head);
    add(radj, e.head, e.tail);
    if (!e.directed) {
      add(adj, e.head, e.tail);
      add(radj, e.tail, e.head);
    }
  }
  return { adj, radj };
}

function bfs(startSet, adj) {
  const seen = new Set(startSet);
  const q = [...startSet];
  while (q.length) {
    const u = q.shift();
    const nbrs = adj.get(u);
    if (!nbrs) continue;
    for (const v of nbrs) {
      if (!seen.has(v)) {
        seen.add(v);
        q.push(v);
      }
    }
  }
  return seen;
}

function markItem(item, mode) {
  if (mode === 'keep') {
    item.keep = true;
    item.remove = false;
  } else {
    item.remove = true;
    item.keep = false;
  }
}

function markPaths(graph, fromRe, toRe, mode) {
  const nodes = Array.from(graph.nodes.keys());
  const sources = nodes.filter(n => fromRe.test(n));
  const targets = nodes.filter(n => toRe.test(n));
  if (!sources.length || !targets.length) return;
  const { adj, radj } = buildAdjacency(graph);
  const reachFromSrc = bfs(sources, adj);
  const reachToTgt = bfs(targets, radj);

  const nodeOnPath = new Set();
  for (const n of nodes) {
    if (reachFromSrc.has(n) && reachToTgt.has(n)) {
      nodeOnPath.add(n);
      markItem(graph.nodes.get(n), mode);
    }
  }
  for (const e of graph.edges) {
    if (reachFromSrc.has(e.tail) && reachToTgt.has(e.head) &&
        nodeOnPath.has(e.tail) && nodeOnPath.has(e.head)) {
      markItem(e, mode);
    }
  }
}

function edgesOnPaths(graph, fromRe, toRe) {
  const nodes = Array.from(graph.nodes.keys());
  const sources = nodes.filter(n => fromRe.test(n));
  const targets = nodes.filter(n => toRe.test(n));
  if (!sources.length || !targets.length) return [];
  const { adj, radj } = buildAdjacency(graph);
  const reachFromSrc = bfs(sources, adj);
  const reachToTgt = bfs(targets, radj);
  const out = [];
  const nodeOnPath = new Set(nodes.filter(n => reachFromSrc.has(n) && reachToTgt.has(n)));
  for (const e of graph.edges) {
    if (reachFromSrc.has(e.tail) && reachToTgt.has(e.head) &&
        nodeOnPath.has(e.tail) && nodeOnPath.has(e.head)) {
      out.push(e);
    }
  }
  return out;
}

function bfsWithHops(startSet, nextFn, maxHops) {
  const seen = new Set(startSet);
  let frontier = new Set(startSet);
  for (let hop = 0; hop < maxHops; hop++) {
    const nextFrontier = new Set();
    for (const u of frontier) {
      for (const v of nextFn(u)) {
        if (!seen.has(v)) {
          seen.add(v);
          nextFrontier.add(v);
        }
      }
    }
    if (!nextFrontier.size) break;
    frontier = nextFrontier;
  }
  return seen;
}

function computeDegrees(graph) {
  const deg = new Map();
  for (const nid of graph.nodes.keys()) deg.set(nid, 0);
  for (const e of graph.edges) {
    deg.set(e.tail, (deg.get(e.tail) ?? 0) + 1);
    deg.set(e.head, (deg.get(e.head) ?? 0) + 1);
  }
  return deg;
}

function computeDirectedDegrees(graph) {
  const deg = new Map();
  const ensure = (nid) => {
    if (!deg.has(nid)) deg.set(nid, { in: 0, out: 0 });
    return deg.get(nid);
  };
  for (const nid of graph.nodes.keys()) ensure(nid);
  for (const e of graph.edges) {
    if (e.directed) {
      ensure(e.tail).out += 1;
      ensure(e.head).in += 1;
    } else {
      // For undirected edges, count both directions on both ends.
      const tail = ensure(e.tail);
      const head = ensure(e.head);
      tail.in += 1; tail.out += 1;
      head.in += 1; head.out += 1;
    }
  }
  return deg;
}

function buildUndirectedAdj(graph) {
  const und = new Map();
  const add = (a, b) => {
    if (!und.has(a)) und.set(a, new Set());
    und.get(a).add(b);
  };
  for (const nid of graph.nodes.keys()) und.set(nid, new Set());
  for (const e of graph.edges) {
    add(e.tail, e.head);
    add(e.head, e.tail);
  }
  return und;
}

function componentFromSeed(seed, undirectedAdj) {
  const seen = new Set([seed]);
  const q = [seed];
  while (q.length) {
    const u = q.shift();
    const nbrs = undirectedAdj.get(u) || new Set();
    for (const v of nbrs) {
      if (!seen.has(v)) {
        seen.add(v);
        q.push(v);
      }
    }
  }
  return seen;
}

function edgeMatchesLabelRegex(edge, re) {
  const lbl = edge.attrs.label ?? '';
  if (lbl === '') return false;
  const parts = lbl.split(',').map(s => s.trim()).filter(Boolean);
  return parts.some(p => re.test(p)) || re.test(lbl);
}

function nodeMatchesLabelRegex(nodeObj, re, idFallback) {
  const lbl = nodeObj.attrs.label ?? '';
  if (lbl === '') return false;
  const { components } = parseNodeLabel(lbl, idFallback);
  return components.some(c => re.test(c)) || re.test(lbl);
}

function appendLabelAttr(attrs, label) {
  const cur = attrs.label ?? '';
  const parts = cur === '' ? [] : cur.split(',').map(s => s.trim()).filter(Boolean);
  if (!parts.includes(label)) parts.push(label);
  attrs.label = parts.join(',');
}

function removeLabelAttr(attrs, label) {
  const cur = attrs.label ?? '';
  if (cur === '') return;
  const parts = cur.split(',').map(s => s.trim()).filter(Boolean);
  const filtered = parts.filter(p => p !== label);
  if (filtered.length) {
    attrs.label = filtered.join(',');
  } else {
    delete attrs.label;
  }
}

function sampleRandom(list, count) {
  const arr = [...list];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr.slice(0, count);
}

function tokenizeRegexSExpr(text) {
  const tokens = [];
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (/\s/.test(ch)) {
      i += 1;
      continue;
    }
    if (ch === '(' || ch === ')') {
      tokens.push(ch);
      i += 1;
      continue;
    }
    if (ch === '"') {
      let j = i + 1;
      let out = '';
      while (j < text.length) {
        if (text[j] === '\\' && j + 1 < text.length) {
          out += text[j + 1];
          j += 2;
          continue;
        }
        if (text[j] === '"') break;
        out += text[j];
        j += 1;
      }
      if (j >= text.length || text[j] !== '"') throw new Error('unterminated quoted regex atom');
      tokens.push({ type: 'string', value: out });
      i = j + 1;
      continue;
    }
    let j = i;
    while (j < text.length && !/\s/.test(text[j]) && text[j] !== '(' && text[j] !== ')') j += 1;
    tokens.push({ type: 'atom', value: text.slice(i, j) });
    i = j;
  }
  return tokens;
}

function parseRegexSExpr(text) {
  const tokens = tokenizeRegexSExpr(text);
  let idx = 0;
  const parseOne = () => {
    if (idx >= tokens.length) throw new Error('unexpected end of regex');
    const tok = tokens[idx++];
    if (tok === '(') {
      const list = [];
      while (idx < tokens.length && tokens[idx] !== ')') list.push(parseOne());
      if (idx >= tokens.length || tokens[idx] !== ')') throw new Error('unbalanced regex parentheses');
      idx += 1;
      return { type: 'list', items: list };
    }
    if (tok === ')') throw new Error('unexpected )');
    return tok;
  };
  const out = parseOne();
  if (idx !== tokens.length) throw new Error('extra tokens after regex');
  return out;
}

function regexAtomValue(sexpr) {
  if (!sexpr || sexpr.type === 'list') throw new Error('expected regex atom');
  return sexpr.value;
}

function stripRegexQuotes(text) {
  return text.length >= 2 && text.startsWith('"') && text.endsWith('"')
    ? text.slice(1, -1)
    : text;
}

function buildEdgePred(sexpr) {
  if (sexpr.type !== 'list') {
    const atom = regexAtomValue(sexpr);
    if (atom === 'dot') return { kind: 'any' };
    if (atom.startsWith('@') && atom.length > 1) return { kind: 'sinkNodeMatch', pattern: stripRegexQuotes(atom.slice(1)) };
    if (atom.endsWith('@') && atom.length > 1) return { kind: 'sourceNodeMatch', pattern: stripRegexQuotes(atom.slice(0, -1)) };
    if (atom.startsWith('~') && atom.length > 1) return { kind: 'not', sub: { kind: 'atom', label: stripRegexQuotes(atom.slice(1)) } };
    return { kind: 'atom', label: atom };
  }
  if (!sexpr.items.length) throw new Error('empty edge predicate');
  const op = regexAtomValue(sexpr.items[0]);
  if (op === 'negate') {
    if (sexpr.items.length !== 2) throw new Error('negate expects one argument');
    return { kind: 'not', sub: buildEdgePred(sexpr.items[1]) };
  }
  if (op === 'all-of' || op === 'some-of') {
    if (sexpr.items.length < 2) throw new Error(`${op} expects at least one argument`);
    return { kind: op === 'all-of' ? 'allOf' : 'someOf', children: sexpr.items.slice(1).map(buildEdgePred) };
  }
  return buildEdgePred(sexpr.items[0]);
}

function buildRegexAst(sexpr) {
  if (sexpr.type !== 'list') {
    return { kind: 'symbol', pred: buildEdgePred(sexpr) };
  }
  if (!sexpr.items.length) throw new Error('empty regex list');
  const op = regexAtomValue(sexpr.items[0]);
  if (op === 'concat') return { kind: 'concat', children: sexpr.items.slice(1).map(buildRegexAst) };
  if (op === 'alt') return { kind: 'alt', children: sexpr.items.slice(1).map(buildRegexAst) };
  if (op === 'star' || op === 'plus') {
    if (sexpr.items.length !== 2) throw new Error(`${op} expects one argument`);
    return { kind: op, sub: buildRegexAst(sexpr.items[1]) };
  }
  if (op === 'negate' || op === 'all-of' || op === 'some-of') {
    return { kind: 'symbol', pred: buildEdgePred(sexpr) };
  }
  if (sexpr.items.length === 1) return { kind: 'symbol', pred: buildEdgePred(sexpr.items[0]) };
  return { kind: 'concat', children: sexpr.items.map(buildRegexAst) };
}

function evalFindPathEdgePred(pred, edge, graph) {
  switch (pred.kind) {
    case 'any':
      return true;
    case 'atom': {
      const lbl = edge.attrs.label ?? '';
      const parts = lbl === '' ? [] : lbl.split(',').map(s => s.trim()).filter(Boolean);
      return parts.includes(pred.label);
    }
    case 'sourceNodeMatch': {
      const node = graph.nodes.get(edge.tail);
      const label = node?.attrs?.label ?? edge.tail;
      try { return new RegExp(pred.pattern).test(label); } catch { return false; }
    }
    case 'sinkNodeMatch': {
      const node = graph.nodes.get(edge.head);
      const label = node?.attrs?.label ?? edge.head;
      try { return new RegExp(pred.pattern).test(label); } catch { return false; }
    }
    case 'not':
      return !evalFindPathEdgePred(pred.sub, edge, graph);
    case 'allOf':
      return pred.children.every(child => evalFindPathEdgePred(child, edge, graph));
    case 'someOf':
      return pred.children.some(child => evalFindPathEdgePred(child, edge, graph));
    default:
      return false;
  }
}

function buildRegexNfa(ast, nfa) {
  const newState = () => {
    const id = nfa.states.length;
    nfa.states.push({ accepting: false, eps: [], trans: [] });
    return id;
  };
  if (!ast) {
    const s = newState();
    const e = newState();
    nfa.states[s].eps.push(e);
    return [s, e];
  }
  switch (ast.kind) {
    case 'symbol': {
      const s = newState();
      const e = newState();
      nfa.states[s].trans.push([ast.pred, e]);
      return [s, e];
    }
    case 'concat': {
      if (!ast.children.length) {
        const s = newState();
        const e = newState();
        nfa.states[s].eps.push(e);
        return [s, e];
      }
      let [s, e] = buildRegexNfa(ast.children[0], nfa);
      for (const child of ast.children.slice(1)) {
        const [cs, ce] = buildRegexNfa(child, nfa);
        nfa.states[e].eps.push(cs);
        e = ce;
      }
      return [s, e];
    }
    case 'alt': {
      const s = newState();
      const e = newState();
      for (const child of ast.children) {
        const [cs, ce] = buildRegexNfa(child, nfa);
        nfa.states[s].eps.push(cs);
        nfa.states[ce].eps.push(e);
      }
      return [s, e];
    }
    case 'star': {
      const [cs, ce] = buildRegexNfa(ast.sub, nfa);
      const s = newState();
      const e = newState();
      nfa.states[s].eps.push(cs, e);
      nfa.states[ce].eps.push(cs, e);
      return [s, e];
    }
    case 'plus': {
      const [cs, ce] = buildRegexNfa(ast.sub, nfa);
      const s = newState();
      const e = newState();
      nfa.states[s].eps.push(cs);
      nfa.states[ce].eps.push(cs, e);
      return [s, e];
    }
    default:
      throw new Error(`unknown regex kind ${ast.kind}`);
  }
}

function epsilonClosure(nfa, states) {
  const out = new Set(states);
  const stack = [...states];
  while (stack.length) {
    const s = stack.pop();
    for (const t of nfa.states[s].eps) {
      if (!out.has(t)) {
        out.add(t);
        stack.push(t);
      }
    }
  }
  return out;
}

function findPathByRegex(graph, regexStr) {
  const ast = buildRegexAst(parseRegexSExpr(regexStr));
  const nfa = { start: 0, states: [] };
  const [start, end] = buildRegexNfa(ast, nfa);
  nfa.start = start;
  nfa.states[end].accepting = true;
  const outgoing = new Map();
  for (const e of graph.edges) {
    if (!outgoing.has(e.tail)) outgoing.set(e.tail, []);
    outgoing.get(e.tail).push(e);
  }
  for (const startNode of graph.nodes.keys()) {
    const startClosure = epsilonClosure(nfa, [nfa.start]);
    const queue = [];
    const seen = new Set();
    const pred = new Map();
    for (const state of startClosure) {
      const key = `${startNode}@@${state}`;
      queue.push({ node: startNode, state });
      seen.add(key);
    }
    while (queue.length) {
      const cur = queue.shift();
      if (nfa.states[cur.state].accepting) {
        const pathEdges = [];
        let key = `${cur.node}@@${cur.state}`;
        while (pred.has(key)) {
          const step = pred.get(key);
          pathEdges.push(step.edge);
          key = step.prev;
        }
        pathEdges.reverse();
        return pathEdges;
      }
      for (const edge of outgoing.get(cur.node) || []) {
        for (const [edgePred, nextState] of nfa.states[cur.state].trans) {
          if (!edgePred || evalFindPathEdgePred(edgePred, edge, graph)) {
            const closure = epsilonClosure(nfa, [nextState]);
            for (const state of closure) {
              const nextKey = `${edge.head}@@${state}`;
              if (seen.has(nextKey)) continue;
              seen.add(nextKey);
              pred.set(nextKey, { prev: `${cur.node}@@${cur.state}`, edge });
              queue.push({ node: edge.head, state });
            }
          }
        }
      }
    }
  }
  return [];
}

function runGreggleFindPath(graph, regexStr, label) {
  const pathEdges = findPathByRegex(graph, regexStr);
  if (!pathEdges.length) throw new Error('find-path: no path annotated');
  for (const edge of pathEdges) appendLabelAttr(edge.attrs, label);
  return graph;
}

function parseNodeLabel(labelStr, idFallback) {
  if (!labelStr) return { prefix: idFallback || '', parts: [], components: idFallback ? [idFallback] : [] };
  const [head, ...rest] = labelStr.split(':');
  if (rest.length) {
    const tail = rest.join(':');
    const parts = tail ? tail.split(',').map(s => s.trim()).filter(Boolean) : [];
    const prefix = head || idFallback || '';
    const components = [prefix, ...parts].filter(Boolean);
    return { prefix, parts, components };
  }
  // no colon; treat whole string as comma list
  const parts = head ? head.split(',').map(s => s.trim()).filter(Boolean) : [];
  const prefix = idFallback || '';
  const components = prefix ? [prefix, ...parts] : parts;
  return { prefix, parts, components };
}

function buildNodeLabel(prefix, parts) {
  const pfx = prefix || '';
  if (!parts.length) return pfx || undefined;
  return `${pfx}:${parts.join(',')}`;
}

function appendNodeLabelAttr(nodeObj, id, label) {
  const parsed = parseNodeLabel(nodeObj.attrs.label, id);
  const parts = parsed.parts.slice();
  if (!parts.includes(label)) parts.push(label);
  const lbl = buildNodeLabel(parsed.prefix || id, parts);
  if (lbl) nodeObj.attrs.label = lbl;
}

function removeNodeLabelAttr(nodeObj, id, label) {
  const parsed = parseNodeLabel(nodeObj.attrs.label, id);
  const parts = parsed.parts.filter(p => p !== label);
  const lbl = buildNodeLabel(parsed.prefix || id, parts);
  if (lbl) {
    nodeObj.attrs.label = lbl;
  } else {
    delete nodeObj.attrs.label;
  }
}

// --- Serialization ----------------------------------------------------------
const bareIdRe = /^[A-Za-z_\x80-\xff][A-Za-z0-9_\x80-\xff]*$/;
function quoteId(id) {
  if (/^<.*>$/.test(id)) return id;
  if (bareIdRe.test(id) || /^-?\d+(\.\d+)?$/.test(id)) return id;
  return `"${id.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}
function quoteAttrVal(val) {
  if (val === '') return '""';
  if (/^<.*>$/.test(val)) return val;
  if (/^-?\d+(\.\d+)?$/.test(val)) return val;
  if (bareIdRe.test(val)) return val;
  return `"${val.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}
function formatAttrs(attrs) {
  const keys = Object.keys(attrs);
  if (!keys.length) return '';
  const body = keys.sort().map(k => `${quoteId(k)}=${quoteAttrVal(attrs[k])}`).join(', ');
  return ` [${body}]`;
}

function serialize(graph) {
  const lines = [];
  let header = `${graph.type} ${quoteId(graph.name || 'G')} {`;
  if (graph.strict) header = `strict ${header}`;
  lines.push(header);

  if (Object.keys(graph.graphAttrs).length) lines.push(`    graph${formatAttrs(graph.graphAttrs)};`);
  if (Object.keys(graph.nodeDefaults).length) lines.push(`    node${formatAttrs(graph.nodeDefaults)};`);
  if (Object.keys(graph.edgeDefaults).length) lines.push(`    edge${formatAttrs(graph.edgeDefaults)};`);

  // determine keep/remove logic
  const nodesArray = Array.from(graph.nodes.entries());
  const edgesArray = graph.edges;
  const anyKeep = nodesArray.some(([, n]) => n.keep) || edgesArray.some(e => e.keep);

  const nodeIncluded = (nid, nobj) => {
    if (anyKeep) return !!nobj.keep;
    if (nobj.remove) return false;
    return true;
  };
  const edgeIncluded = (e) => {
    if (anyKeep) return !!e.keep;
    if (e.remove) return false;
    return true;
  };

  for (const [nid, nobj] of nodesArray.sort(([a], [b]) => a.localeCompare(b))) {
    if (!nodeIncluded(nid, nobj)) continue;
    lines.push(`    ${quoteId(nid)}${formatAttrs(nobj.attrs)};`);
  }
  const op = graph.type === 'digraph' ? '->' : '--';
  for (const e of edgesArray) {
    if (!edgeIncluded(e)) continue;
    let tail = quoteId(e.tail);
    let head = quoteId(e.head);
    if (e.tailPort) tail += `:${e.tailPort}`;
    if (e.headPort) head += `:${e.headPort}`;
    lines.push(`    ${tail} ${op} ${head}${formatAttrs(e.attrs)};`);
  }
  lines.push('}');
  return lines.join('\n');
}

function serializePlain(graph) {
  const lines = [];
  const op = graph.type === 'digraph' ? '->' : '--';
  lines.push(`digraph ${quoteId(graph.name || 'G')} {`);
  for (const [nid, nobj] of Array.from(graph.nodes.entries()).sort(([a], [b]) => a.localeCompare(b))) {
    lines.push(`    ${quoteId(nid)}${formatAttrs(nobj.attrs)};`);
  }
  for (const e of graph.edges) {
    let tail = quoteId(e.tail);
    let head = quoteId(e.head);
    if (e.tailPort) tail += `:${e.tailPort}`;
    if (e.headPort) head += `:${e.headPort}`;
    const parts = [];
    for (const k of Object.keys(e.attrs)) {
      const v = e.attrs[k];
      if (k === 'label') {
        parts.push(`label="${v}"`);
      } else {
        parts.push(`${quoteId(k)}=${quoteAttrVal(v)}`);
      }
    }
    const attrStr = parts.length ? ` [${parts.join(', ')}]` : '';
    lines.push(`    ${tail} ${op} ${head}${attrStr};`);
  }
  lines.push('}');
  return lines.join('\n');
}

// --- Subcommands ------------------------------------------------------------
function expandRangeOrSingle(spec) {
  const m = /^([^:]+):(\d+):(\d+)$/.exec(spec);
  if (!m) return [spec];
  const [, prefix, a, b] = m;
  const start = parseInt(a, 10);
  const end = parseInt(b, 10);
  const step = start <= end ? 1 : -1;
  const out = [];
  for (let v = start; step > 0 ? v <= end : v >= end; v += step) {
    out.push(`${prefix}${v}`);
  }
  return out;
}

function parseChainString(str) {
  const parts = str.match(/"[^"]*"|\S+/g) || [];
  return parts.map(p => p.startsWith('"') && p.endsWith('"') ? p.slice(1, -1) : p);
}

function applyOne(graph, tokens) {
  if (!tokens.length) return graph;
  const [cmd, ...rest] = tokens;
  switch (cmd) {
    case 'help': {
      detailedHelp();
      process.exit(0);
    }
    case 'set-name': {
      if (rest.length < 1) throw new Error('set-name <name>');
      graph.name = rest[0];
      return graph;
    }
    case 'add-nodes':
    case 'add-node': {
      if (!rest.length) throw new Error('add-nodes arguments missing');
      if (/^\d+$/.test(rest[0]) && rest.length >= 2) {
        const count = parseInt(rest[0], 10);
        const root = rest[1];
        const start = rest.length >= 3 ? parseInt(rest[2], 10) : 1;
        for (let i = 0; i < count; i++) {
          const id = `${root}_${start + i}`;
          addNode(graph, id, {}, graph.nodeDefaults);
        }
        return graph;
      }
      const ids = expandRangeOrSingle(rest[0]);
      for (const id of ids) addNode(graph, id, {}, graph.nodeDefaults);
      return graph;
    }
    case 'add-edges':
    case 'add-edge': {
      if (rest.length < 3) throw new Error('add-edges <label> <fromRegex> <toRegex> OR add-edges <count> <fromRegex> <toRegex> [label]');
      const first = rest[0];
      const countMode = /^[0-9]+$/.test(first);
      const fromPat = rest[1];
      const toPat = rest[2];
      const label = countMode ? (rest[3] ?? '') : first;
      const fromRe = new RegExp(fromPat);
      const toRe = new RegExp(toPat);
      const ids = Array.from(graph.nodes.keys());
      const fromIds = ids.filter(id => fromRe.test(id));
      const toIds = ids.filter(id => toRe.test(id));
      if (!fromIds.length || !toIds.length) throw new Error('add-edges: no nodes match given patterns');

      if (!countMode) {
        for (const f of fromIds) for (const t of toIds) {
          const attrs = label === '' ? {} : { label };
          addEdge(graph, f, t, graph.type === 'digraph', attrs, graph.edgeDefaults);
        }
        return graph;
      }

      const count = parseInt(first, 10);
      const pairs = [];
      for (const f of fromIds) for (const t of toIds) pairs.push([f, t]);
      if (!pairs.length) throw new Error('add-edges: no candidate pairs');
      // Fisher-Yates shuffle to randomize pairs
      for (let i = pairs.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [pairs[i], pairs[j]] = [pairs[j], pairs[i]];
      }
      const take = Math.min(count, pairs.length);
      for (let i = 0; i < take; i++) {
        const [f, t] = pairs[i];
        const attrs = label === '' ? {} : { label };
        addEdge(graph, f, t, graph.type === 'digraph', attrs, graph.edgeDefaults);
      }
      return graph;
    }
    case 'add-chain': {
      if (rest.length < 2) throw new Error('add-chain <root> <n> [start]');
      const root = rest[0];
      const n = parseInt(rest[1], 10);
      const start = rest.length >= 3 ? parseInt(rest[2], 10) : 1;
      if (!Number.isInteger(n) || n < 1) throw new Error('add-chain n must be >= 1');
      const dir = graph.type === 'digraph';
      let prev = null;
      for (let i = 0; i < n; i++) {
        const id = `${root}_${start + i}`;
        addNode(graph, id, {}, graph.nodeDefaults);
        if (prev !== null) {
          addEdge(graph, prev, id, dir, {}, graph.edgeDefaults);
        }
        prev = id;
      }
      return graph;
    }
    case 'add-ring': {
      if (rest.length < 2) throw new Error('add-ring <root> <n> [start]');
      const root = rest[0];
      const n = parseInt(rest[1], 10);
      const start = rest.length >= 3 ? parseInt(rest[2], 10) : 1;
      if (!Number.isInteger(n) || n < 1) throw new Error('add-ring n must be >= 1');
      const dir = graph.type === 'digraph';
      const ids = [];
      for (let i = 0; i < n; i++) {
        const id = `${root}_${start + i}`;
        ids.push(id);
        addNode(graph, id, {}, graph.nodeDefaults);
        if (i > 0) addEdge(graph, ids[i - 1], id, dir, {}, graph.edgeDefaults);
      }
      if (n > 1) addEdge(graph, ids[n - 1], ids[0], dir, {}, graph.edgeDefaults);
      return graph;
    }
    case 'add-clique': {
      if (rest.length < 2) throw new Error('add-clique <root> <n> [start]');
      const root = rest[0];
      const n = parseInt(rest[1], 10);
      const start = rest.length >= 3 ? parseInt(rest[2], 10) : 1;
      if (!Number.isInteger(n) || n < 1) throw new Error('add-clique n must be >= 1');
      const dir = graph.type === 'digraph';
      const ids = [];
      for (let i = 0; i < n; i++) {
        const id = `${root}_${start + i}`;
        ids.push(id);
        addNode(graph, id, {}, graph.nodeDefaults);
      }
      for (let i = 0; i < n; i++) {
        for (let j = 0; j < n; j++) {
          if (i === j) continue;
          addEdge(graph, ids[i], ids[j], dir, {}, graph.edgeDefaults);
        }
      }
      return graph;
    }
    case 'find-path': {
      if (rest.length < 2) throw new Error('find-path <regex> <label>');
      const label = rest[rest.length - 1];
      const regexStr = rest.slice(0, rest.length - 1).join(' ');
      const newGraph = runGreggleFindPath(graph, regexStr, label);
      return newGraph;
    }
    case 'add-grid': {
      if (rest.length < 3) throw new Error('add-grid <root> <rows> <cols> [start]');
      const root = rest[0];
      const rows = parseInt(rest[1], 10);
      const cols = parseInt(rest[2], 10);
      const start = rest.length >= 4 ? parseInt(rest[3], 10) : 1;
      if (!Number.isInteger(rows) || rows < 1 || !Number.isInteger(cols) || cols < 1) {
        throw new Error('add-grid rows and cols must be >= 1');
      }
      const dir = graph.type === 'digraph';
      const nodes = [];
      for (let i = 0; i < rows; i++) {
        for (let j = 0; j < cols; j++) {
          const id = `${root}_${start + i}_${start + j}`;
          nodes.push(id);
          addNode(graph, id, {}, graph.nodeDefaults);
        }
      }
      const idx = (i, j) => `${root}_${start + i}_${start + j}`;
      for (let i = 0; i < rows; i++) {
        for (let j = 0; j < cols; j++) {
          if (i < rows - 1) {
            addEdge(graph, idx(i, j), idx(i + 1, j), dir, {}, graph.edgeDefaults);
          }
          if (j < cols - 1) {
            addEdge(graph, idx(i, j), idx(i, j + 1), dir, {}, graph.edgeDefaults);
          }
        }
      }
      return graph;
    }
    case 'keep-paths': {
      if (rest.length < 2) throw new Error('keep-paths <fromRegex> <toRegex>');
      const [a, b] = rest;
      markPaths(graph, new RegExp(a), new RegExp(b), 'keep');
      return graph;
    }
    case 'remove-paths': {
      if (rest.length < 2) throw new Error('remove-paths <fromRegex> <toRegex>');
      const [a, b] = rest;
      markPaths(graph, new RegExp(a), new RegExp(b), 'remove');
      return graph;
    }
    case 'keep-path-edges': {
      if (rest.length < 2) throw new Error('keep-path-edges <fromRegex> <toRegex>');
      const [a, b] = rest;
      const edges = edgesOnPaths(graph, new RegExp(a), new RegExp(b));
      for (const e of edges) markItem(e, 'keep');
      return graph;
    }
    case 'remove-path-edges': {
      if (rest.length < 2) throw new Error('remove-path-edges <fromRegex> <toRegex>');
      const [a, b] = rest;
      const edges = edgesOnPaths(graph, new RegExp(a), new RegExp(b));
      for (const e of edges) markItem(e, 'remove');
      return graph;
    }
    case 'select-nodes-on-paths': {
      if (rest.length < 2) throw new Error('select-nodes-on-paths <fromRegex> <toRegex>');
      const [a, b] = rest;
      const nodes = Array.from(graph.nodes.keys());
      const { adj, radj } = buildAdjacency(graph);
      const sources = nodes.filter(n => new RegExp(a).test(n));
      const targets = nodes.filter(n => new RegExp(b).test(n));
      if (!sources.length || !targets.length) return graph;
      const reachFromSrc = bfs(sources, adj);
      const reachToTgt = bfs(targets, radj);
      for (const n of nodes) {
        if (reachFromSrc.has(n) && reachToTgt.has(n)) {
          const obj = graph.nodes.get(n);
          if (obj) obj.selected = true;
        }
      }
      return graph;
    }
    case 'select-edges-on-paths': {
      if (rest.length < 2) throw new Error('select-edges-on-paths <fromRegex> <toRegex>');
      const [a, b] = rest;
      const edges = edgesOnPaths(graph, new RegExp(a), new RegExp(b));
      for (const e of edges) e.selected = true;
      return graph;
    }
    case 'select-random-nodes': {
      if (rest.length < 2) throw new Error('select-random-nodes <n> <regex>');
      const n = parseInt(rest[0], 10);
      const re = new RegExp(rest[1]);
      const candidates = Array.from(graph.nodes.entries()).filter(([id]) => re.test(id));
      const take = n >= candidates.length ? candidates : sampleRandom(candidates, n);
      for (const [id, obj] of take) obj.selected = true;
      return graph;
    }
    case 'select-random-edges': {
      if (rest.length < 3) throw new Error('select-random-edges <n> <fromRegex> <toRegex>');
      const n = parseInt(rest[0], 10);
      const fromRe = new RegExp(rest[1]);
      const toRe = new RegExp(rest[2]);
      const candidates = graph.edges.filter(e => fromRe.test(e.tail) && toRe.test(e.head));
      const take = n >= candidates.length ? candidates : sampleRandom(candidates, n);
      for (const e of take) e.selected = true;
      return graph;
    }
    case 'select-neighbours':
    case 'select-neighbors': { // alias
      if (!rest.length) {
        rest.push('both', '1');
      }
      let mode = 'both';
      let hops = 1;
      if (rest.length === 1) {
        if (/^\d+$/.test(rest[0])) {
          hops = parseInt(rest[0], 10);
        } else {
          mode = rest[0];
        }
      } else {
        mode = rest[0];
        hops = parseInt(rest[1], 10);
      }
      if (!['in', 'out', 'both'].includes(mode)) throw new Error('select-neighbours mode must be in|out|both');
      if (!Number.isInteger(hops) || hops < 0) throw new Error('select-neighbours hops must be non-negative integer');

      const selectedNodes = new Set(Array.from(graph.nodes.entries()).filter(([, n]) => n.selected).map(([id]) => id));
      if (!selectedNodes.size) return graph;

      const { adj, radj } = buildAdjacency(graph);
      const nextFn = (u) => {
        if (mode === 'in') return radj.get(u) || new Set();
        if (mode === 'out') return adj.get(u) || new Set();
        // both: union
        const out = adj.get(u) || new Set();
        const inn = radj.get(u) || new Set();
        return new Set([...out, ...inn]);
      };
      const reached = bfsWithHops(selectedNodes, nextFn, hops);
      for (const id of reached) {
        const obj = graph.nodes.get(id);
        if (obj) obj.selected = true;
      }
      return graph;
    }
    case 'select-nodes-degree': {
      if (rest.length < 2) throw new Error('select-nodes-degree <lt|le|eq|ge|gt> <k>');
      const cmp = rest[0];
      const k = parseInt(rest[1], 10);
      if (!['lt', 'le', 'eq', 'ge', 'gt'].includes(cmp)) throw new Error('select-nodes-degree comparator must be lt|le|eq|ge|gt');
      if (!Number.isInteger(k)) throw new Error('select-nodes-degree k must be integer');
      const deg = computeDegrees(graph);
      const check = (v) => {
        switch (cmp) {
          case 'lt': return v < k;
          case 'le': return v <= k;
          case 'eq': return v === k;
          case 'ge': return v >= k;
          case 'gt': return v > k;
        }
      };
      for (const [id, obj] of graph.nodes.entries()) {
        if (check(deg.get(id) ?? 0)) obj.selected = true;
      }
      return graph;
    }
    case 'select-nodes-indegree':
    case 'select-nodes-outdegree': {
      if (rest.length < 2) throw new Error('select-nodes-indegree|select-nodes-outdegree <lt|le|eq|ge|gt> <k>');
      const cmp = rest[0];
      const k = parseInt(rest[1], 10);
      if (!['lt', 'le', 'eq', 'ge', 'gt'].includes(cmp)) throw new Error('select-nodes-indegree|select-nodes-outdegree comparator must be lt|le|eq|ge|gt');
      if (!Number.isInteger(k)) throw new Error('select-nodes-indegree|select-nodes-outdegree k must be integer');
      const deg = computeDirectedDegrees(graph);
      const check = (v) => {
        switch (cmp) {
          case 'lt': return v < k;
          case 'le': return v <= k;
          case 'eq': return v === k;
          case 'ge': return v >= k;
          case 'gt': return v > k;
        }
      };
      const pick = cmd === 'select-nodes-indegree' ? (vals) => vals.in : (vals) => vals.out;
      for (const [id, obj] of graph.nodes.entries()) {
        const vals = deg.get(id) || { in: 0, out: 0 };
        if (check(pick(vals))) obj.selected = true;
      }
      return graph;
    }
    case 'select-component-of-nodes': {
      if (rest.length < 1) throw new Error('select-component-of-nodes <regex>');
      const re = new RegExp(rest[0]);
      const und = buildUndirectedAdj(graph);
      const seeds = Array.from(graph.nodes.keys()).filter(id => re.test(id));
      const seenComps = new Set();
      for (const seed of seeds) {
        if (seenComps.has(seed)) continue;
        const comp = componentFromSeed(seed, und);
        for (const n of comp) {
          const obj = graph.nodes.get(n);
          if (obj) obj.selected = true;
        }
        for (const e of graph.edges) {
          if (comp.has(e.tail) && comp.has(e.head)) e.selected = true;
        }
        for (const n of comp) seenComps.add(n);
      }
      return graph;
    }
    case 'select-components-with-selected': {
      const und = buildUndirectedAdj(graph);
      const seeds = Array.from(graph.nodes.entries()).filter(([, obj]) => obj.selected).map(([id]) => id);
      const seen = new Set();
      for (const seed of seeds) {
        if (seen.has(seed)) continue;
        const comp = componentFromSeed(seed, und);
        for (const n of comp) {
          const obj = graph.nodes.get(n);
          if (obj) obj.selected = true;
        }
        for (const e of graph.edges) {
          if (comp.has(e.tail) && comp.has(e.head)) e.selected = true;
        }
        for (const n of comp) seen.add(n);
      }
      return graph;
    }
    case 'clear-selection': {
      for (const [, obj] of graph.nodes) obj.selected = false;
      for (const e of graph.edges) e.selected = false;
      return graph;
    }
    case 'invert-selection-nodes': {
      for (const [, obj] of graph.nodes) obj.selected = !obj.selected;
      return graph;
    }
    case 'invert-selection-edges': {
      for (const e of graph.edges) e.selected = !e.selected;
      return graph;
    }
    case 'filter-to-paths': {
      if (rest.length < 2) throw new Error('filter-to-paths <fromRegex> <toRegex>');
      const [a, b] = rest;
      const nodes = Array.from(graph.nodes.keys());
      const { adj, radj } = buildAdjacency(graph);
      const sources = nodes.filter(n => new RegExp(a).test(n));
      const targets = nodes.filter(n => new RegExp(b).test(n));
      if (!sources.length || !targets.length) {
        // nothing matches; remove everything
        graph.nodes.forEach(n => markItem(n, 'remove'));
        graph.edges.forEach(e => markItem(e, 'remove'));
        return graph;
      }
      const reachFromSrc = bfs(sources, adj);
      const reachToTgt = bfs(targets, radj);
      const nodeOnPath = new Set(nodes.filter(n => reachFromSrc.has(n) && reachToTgt.has(n)));
      // mark all nodes/edges remove, then unmark keep on path ones
      for (const [, n] of graph.nodes) markItem(n, 'remove');
      for (const e of graph.edges) markItem(e, 'remove');
      for (const n of nodeOnPath) {
        const obj = graph.nodes.get(n);
        if (obj) markItem(obj, 'keep');
      }
      for (const e of graph.edges) {
        if (reachFromSrc.has(e.tail) && reachToTgt.has(e.head) &&
            nodeOnPath.has(e.tail) && nodeOnPath.has(e.head)) {
          markItem(e, 'keep');
        }
      }
      return graph;
    }
    case 'select-nodes': {
      if (rest.length < 1) throw new Error('select-nodes <regex>');
      const re = new RegExp(rest[0]);
      for (const [id, obj] of graph.nodes.entries()) {
        if (re.test(id)) obj.selected = true;
      }
      return graph;
    }
    case 'select-nodes-label': {
      if (rest.length < 1) throw new Error('select-nodes-label <labelRegex>');
      const re = new RegExp(rest[0]);
      for (const [id, obj] of graph.nodes.entries()) {
        if (nodeMatchesLabelRegex(obj, re, id)) obj.selected = true;
      }
      return graph;
    }
    case 'deselect-nodes': {
      if (rest.length < 1) throw new Error('deselect-nodes <regex>');
      const re = new RegExp(rest[0]);
      for (const [id, obj] of graph.nodes.entries()) {
        if (re.test(id)) obj.selected = false;
      }
      return graph;
    }
    case 'select-edges': {
      if (rest.length === 1) {
        const re = new RegExp(rest[0]);
        for (const e of graph.edges) {
          if (edgeMatchesLabelRegex(e, re)) e.selected = true;
        }
        return graph;
      } else if (rest.length >= 2) {
        const fromRe = new RegExp(rest[0]);
        const toRe = new RegExp(rest[1]);
        for (const e of graph.edges) {
          if (fromRe.test(e.tail) && toRe.test(e.head)) e.selected = true;
        }
        return graph;
      }
      throw new Error('select-edges <labelRegex> OR select-edges <fromRegex> <toRegex>');
    }
    case 'deselect-edges': {
      if (rest.length === 1) {
        const re = new RegExp(rest[0]);
        for (const e of graph.edges) {
          if (edgeMatchesLabelRegex(e, re)) e.selected = false;
        }
        return graph;
      } else if (rest.length >= 2) {
        const fromRe = new RegExp(rest[0]);
        const toRe = new RegExp(rest[1]);
        for (const e of graph.edges) {
          if (fromRe.test(e.tail) && toRe.test(e.head)) e.selected = false;
        }
        return graph;
      }
      throw new Error('deselect-edges <labelRegex> OR deselect-edges <fromRegex> <toRegex>');
    }
    case 'delete-selected': {
      // remove selected nodes and edges; also drop edges incident to deleted nodes
      const deleteNodes = new Set(Array.from(graph.nodes.entries()).filter(([, n]) => n.selected).map(([id]) => id));
      graph.nodes.forEach((obj, id) => {
        if (deleteNodes.has(id)) graph.nodes.delete(id);
      });
      graph.edges = graph.edges.filter(e => !e.selected && !deleteNodes.has(e.tail) && !deleteNodes.has(e.head));
      rebuildEdgeIndex(graph);
      return graph;
    }
    case 'add-labels-to-selected': {
      if (rest.length < 1) throw new Error('add-labels-to-selected <label>');
      const label = rest[0];
      for (const [id, n] of graph.nodes.entries()) {
        if (n.selected) appendNodeLabelAttr(n, id, label);
      }
      for (const e of graph.edges) {
        if (e.selected) appendLabelAttr(e.attrs, label);
      }
      return graph;
    }
    case 'remove-labels-from-selected': {
      if (rest.length < 1) throw new Error('remove-labels-from-selected <label>');
      const label = rest[0];
      for (const [id, n] of graph.nodes.entries()) {
        if (n.selected) removeNodeLabelAttr(n, id, label);
      }
      for (const e of graph.edges) {
        if (e.selected) removeLabelAttr(e.attrs, label);
      }
      return graph;
    }
    case 'set-node-attr-on-selected': {
      if (rest.length < 2) throw new Error('set-node-attr-on-selected <attr> <value>');
      const [attr, value] = rest;
      for (const [, n] of graph.nodes.entries()) {
        if (n.selected) n.attrs[attr] = value;
      }
      return graph;
    }
    case 'set-edge-attr-on-selected': {
      if (rest.length < 2) throw new Error('set-edge-attr-on-selected <attr> <value>');
      const [attr, value] = rest;
      for (const e of graph.edges) {
        if (e.selected) e.attrs[attr] = value;
      }
      return graph;
    }
    case 'unset-node-attr-on-selected': {
      if (rest.length < 1) throw new Error('unset-node-attr-on-selected <attr>');
      const attr = rest[0];
      for (const [, n] of graph.nodes.entries()) {
        if (n.selected) delete n.attrs[attr];
      }
      return graph;
    }
    case 'unset-edge-attr-on-selected': {
      if (rest.length < 1) throw new Error('unset-edge-attr-on-selected <attr>');
      const attr = rest[0];
      for (const e of graph.edges) {
        if (e.selected) delete e.attrs[attr];
      }
      return graph;
    }
    case 'clear-visual-attrs-on-selected': {
      const vis = ['color', 'fillcolor', 'fontcolor', 'style', 'shape', 'penwidth', 'arrowsize', 'fontsize'];
      for (const [, n] of graph.nodes.entries()) {
        if (n.selected) vis.forEach(a => delete n.attrs[a]);
      }
      for (const e of graph.edges) {
        if (e.selected) vis.forEach(a => delete e.attrs[a]);
      }
      return graph;
    }
    case 'remove-nodes':
    case 'remove-node': {
      if (rest.length < 1) throw new Error('remove-nodes <regex>');
      const re = new RegExp(rest[0]);
      const toDelete = new Set(Array.from(graph.nodes.keys()).filter(id => re.test(id)));
      for (const id of toDelete) graph.nodes.delete(id);
      graph.edges = graph.edges.filter(e => !toDelete.has(e.tail) && !toDelete.has(e.head));
      rebuildEdgeIndex(graph);
      return graph;
    }
    case 'remove-edges-between-nodes':
    case 'remove-edge-between-nodes': {
      if (rest.length < 2) throw new Error('remove-edges-between-nodes <fromRegex> <toRegex>');
      const fromRe = new RegExp(rest[0]);
      const toRe = new RegExp(rest[1]);
      graph.edges = graph.edges.filter(e => !(fromRe.test(e.tail) && toRe.test(e.head)));
      rebuildEdgeIndex(graph);
      return graph;
    }
    case 'add-labels-to-edges-on-paths': {
      if (rest.length < 3) throw new Error('add-labels-to-edges-on-paths <fromRegex> <toRegex> <label>');
      const [fromPat, toPat, label] = rest;
      const edges = edgesOnPaths(graph, new RegExp(fromPat), new RegExp(toPat));
      for (const e of edges) {
        appendLabelAttr(e.attrs, label);
      }
      return graph;
    }
    case 'remove-labels-from-edges-on-paths':
    case 'remove-labels-to-edges-on-paths': {
      if (rest.length < 3) throw new Error('remove-labels-from-edges-on-paths <fromRegex> <toRegex> <label>');
      const [fromPat, toPat, label] = rest;
      const edges = edgesOnPaths(graph, new RegExp(fromPat), new RegExp(toPat));
      for (const e of edges) {
        removeLabelAttr(e.attrs, label);
      }
      return graph;
    }
    case 'delete-isolated-nodes': {
      const connected = new Set();
      for (const e of graph.edges) {
        connected.add(e.tail);
        connected.add(e.head);
      }
      for (const nid of Array.from(graph.nodes.keys())) {
        if (!connected.has(nid)) graph.nodes.delete(nid);
      }
      return graph;
    }
    case 'to-svg': {
      if (rest.length < 1) throw new Error('to-svg <filename>');
      const outFile = rest[0];
      const res = spawnSync('dot', ['-Tsvg', '-o', outFile], {
        input: serialize(graph),
        encoding: 'utf8',
      });
      if (res.status !== 0) {
        const msg = (res.stderr || '').toString() || `dot failed with code ${res.status}`;
        throw new Error(msg.trim());
      }
      return graph;
    }
    case 'chain': {
      if (!rest.length) return graph;
      const commands = [];
      for (let i = 0; i < rest.length; i++) {
        const tok = rest[i];
        if (tok === '-f') {
          if (i + 1 >= rest.length) throw new Error('chain -f <file>');
          const fname = rest[++i];
          const lines = fs.readFileSync(fname, 'utf8').split(/\r?\n/);
          for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('#')) continue;
            commands.push(parseChainString(trimmed));
          }
        } else {
          commands.push(Array.isArray(tok) ? tok : parseChainString(tok));
        }
      }
      for (const subTokens of commands) {
        const out = applyOne(graph, subTokens);
        if (out) graph = out;
      }
      return graph;
    }
    default:
      throw new Error(`Unknown subcommand '${cmd}'`);
  }
}

function applySubcommands(graph, args) {
  if (!args.length) return graph;
  return applyOne(graph, args);
}

// --- Programmatic API -------------------------------------------------------
class Gruggle {
  constructor(graph = emptyGraph()) {
    this.graph = graph;
  }

  static fromDot(text, edgeMode = 'curved') {
    const g = parse(text);
    if (edgeMode === 'ortho' || edgeMode === 'rectilinear') {
      g.graphAttrs.splines = 'ortho';
    } else if (edgeMode === 'curved') {
      g.graphAttrs.splines = 'spline';
    }
    return new Gruggle(g);
  }

  static fromFiles(files, edgeMode = 'curved') {
    const graphs = files.map(f => parse(fs.readFileSync(f, 'utf8')));
    const merged = mergeGraphs(graphs);
    merged.graphAttrs.splines = edgeMode === 'ortho' || edgeMode === 'rectilinear' ? 'ortho' : 'spline';
    return new Gruggle(merged);
  }

  chain(commands) {
    let rest;
    if (typeof commands === 'string') {
      rest = [commands];
    } else if (Array.isArray(commands)) {
      const hasNested = commands.some(c => Array.isArray(c));
      const hasWhitespace = commands.some(c => typeof c === 'string' && /\s/.test(c));
      rest = (hasNested || hasWhitespace) ? commands : [commands];
    } else {
      rest = [commands];
    }
    this.graph = applySubcommands(this.graph, ['chain', ...rest]);
    return this;
  }

  apply(tokens) {
    this.graph = applySubcommands(this.graph, tokens);
    return this;
  }

  toDot() {
    return serialize(this.graph);
  }

  toSvg(outFile) {
    applyOne(this.graph, ['to-svg', outFile]);
    return this;
  }

  value() {
    return this.graph;
  }
}

module.exports = {
  Gruggle,
  parse,
  serialize,
  applySubcommands,
  applyOne,
  parseChainString,
  emptyGraph,
  mergeGraphs,
};

// --- CLI --------------------------------------------------------------------
function main(argv) {
  const inputs = [];
  let subargs = [];
  let edgeMode = 'curved';
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '-i') {
      if (i + 1 >= argv.length) throw new Error('-i requires a filename');
      inputs.push(argv[++i]);
    } else if (arg === '--ortho' || arg === '--rectilinear') {
      edgeMode = 'ortho';
    } else if (arg === '--curved') {
      edgeMode = 'curved';
    } else if (arg === '-h' || arg === '--help') {
      usage(); return;
    } else {
      subargs = argv.slice(i);
      break;
    }
  }

  const graphs = inputs.map(f => parse(fs.readFileSync(f, 'utf8')));
  const merged = mergeGraphs(graphs);
  merged.graphAttrs.splines = edgeMode === 'ortho' ? 'ortho' : 'spline';
  const result = applySubcommands(merged, subargs);
  console.log(serialize(result));
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (err) {
    console.error(err.message || err);
    process.exit(1);
  }
}
