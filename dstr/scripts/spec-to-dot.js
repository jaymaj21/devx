#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

function main() {
  const args = process.argv.slice(2);
  if (args.length === 0 || args.includes("--help") || args.includes("-h")) {
    printUsage();
    process.exit(args.length === 0 ? 1 : 0);
  }

  const options = {
    includeAllStates: false,
    rankdir: "TB",
    maxStates: null,
    forceCompact: false,
    noLegend: false,
  };
  const positional = [];

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === "--all-states") {
      options.includeAllStates = true;
    } else if (arg === "--compact") {
      options.forceCompact = true;
    } else if (arg === "--no-legend") {
      options.noLegend = true;
    } else if (arg === "--rankdir") {
      const value = args[i + 1];
      if (!value) {
        fail("--rankdir expects a value such as LR or TB");
      }
      options.rankdir = value;
      i += 1;
    } else if (arg === "--max-states") {
      const value = args[i + 1];
      if (!value || !/^\d+$/.test(value) || Number(value) <= 0) {
        fail("--max-states expects a positive integer");
      }
      options.maxStates = Number(value);
      i += 1;
    } else if (arg.startsWith("--")) {
      fail(`Unknown option: ${arg}`);
    } else {
      positional.push(arg);
    }
  }

  if (positional.length < 1 || positional.length > 2) {
    fail("Expected: node scripts/spec-to-dot.js <spec.json> [output.dot]");
  }

  const inputPath = path.resolve(positional[0]);
  const outputPath = positional[1] ? path.resolve(positional[1]) : null;
  const spec = JSON.parse(fs.readFileSync(inputPath, "utf8"));

  validateSpec(spec);
  const graph = buildGraph(spec, options);
  const dot = renderDot(graph, options);

  if (outputPath) {
    fs.writeFileSync(outputPath, dot, "utf8");
  } else {
    process.stdout.write(dot);
  }
}

function printUsage() {
  console.error("Usage: node scripts/spec-to-dot.js <spec.json> [output.dot] [--all-states] [--compact] [--no-legend] [--rankdir TB|LR] [--max-states N]");
}

function fail(message) {
  console.error(`Error: ${message}`);
  process.exit(1);
}

function validateSpec(spec) {
  if (!spec || typeof spec !== "object") fail("Spec must be a JSON object");
  if (!Array.isArray(spec.variables) || spec.variables.length === 0) fail("spec.variables must be a non-empty array");
  if (!Array.isArray(spec.actions)) fail("spec.actions must be an array");
  if (!spec.domains || typeof spec.domains !== "object") fail("spec.domains must be an object");
  if (!spec.init) fail("spec.init is required");
  if (!spec.next) fail("spec.next is required");
  spec.invariants = Array.isArray(spec.invariants) ? spec.invariants : [];
  spec.properties = Array.isArray(spec.properties) ? spec.properties : [];
}

function buildGraph(spec, options) {
  const universeInfo = enumerateStates(spec, options);
  const universe = universeInfo.states;
  const actionMap = new Map(spec.actions.map((action) => [action.name, action.body]));
  const reachable = new Set();
  const queue = [];
  const initialStates = [];

  for (const state of universe) {
    const ctx = { now: state, next: null, locals: new Map(), actionResults: new Map() };
    if (asBoolean(evalExpr(spec.init, ctx, actionMap))) {
      const key = stateKey(spec.variables, state);
      reachable.add(key);
      queue.push(state);
      initialStates.push(key);
    }
  }

  const invariantFailures = new Map();
  const deadlocks = new Set();
  const edgeMap = new Map();

  while (queue.length > 0) {
    const current = queue.shift();
    const currentKey = stateKey(spec.variables, current);
    const failedInvariants = [];

    for (const invariant of spec.invariants) {
      const ok = asBoolean(evalExpr(invariant.body, {
        now: current,
        next: null,
        locals: new Map(),
        actionResults: new Map(),
      }, actionMap));
      if (!ok) {
        failedInvariants.push(invariant.name);
      }
    }
    if (failedInvariants.length > 0) {
      invariantFailures.set(currentKey, failedInvariants);
    }

    let hasSuccessor = false;
    for (const candidate of universe) {
      const actionResults = new Map();
      const enabledActions = [];
      for (const action of spec.actions) {
        const enabled = asBoolean(evalExpr(action.body, {
          now: current,
          next: candidate,
          locals: new Map(),
          actionResults: new Map(),
        }, actionMap));
        actionResults.set(action.name, enabled);
        if (enabled) {
          enabledActions.push(action.name);
        }
      }

      const nextAllowed = asBoolean(evalExpr(spec.next, {
        now: current,
        next: candidate,
        locals: new Map(),
        actionResults,
      }, actionMap));

      if (!nextAllowed) {
        continue;
      }

      hasSuccessor = true;
      const candidateKey = stateKey(spec.variables, candidate);
      const labels = enabledActions.length > 0 ? enabledActions : ["next"];
      const edgeKey = `${currentKey}->${candidateKey}`;
      const existing = edgeMap.get(edgeKey);
      if (existing) {
        for (const label of labels) existing.labels.add(label);
      } else {
        edgeMap.set(edgeKey, {
          from: currentKey,
          to: candidateKey,
          labels: new Set(labels),
        });
      }

      if (!reachable.has(candidateKey)) {
        reachable.add(candidateKey);
        queue.push(candidate);
      }
    }

    if (!hasSuccessor) {
      deadlocks.add(currentKey);
    }
  }

  const nodes = universe
    .filter((state) => options.includeAllStates || reachable.has(stateKey(spec.variables, state)))
    .map((state) => {
      const key = stateKey(spec.variables, state);
      return {
        id: nodeId(key),
        key,
        state,
        reachable: reachable.has(key),
        initial: initialStates.includes(key),
        deadlock: deadlocks.has(key),
        invariantFailures: invariantFailures.get(key) || [],
      };
    });

  nodes.forEach((node, index) => {
    node.displayId = `s${index}`;
  });

  const edges = Array.from(edgeMap.values()).filter(
    (edge) => options.includeAllStates || (reachable.has(edge.from) && reachable.has(edge.to)),
  );

  const propertySummaries = spec.properties.map((property) => ({
    name: property.name,
    result: evaluateProperty(spec, property, universe, reachable, actionMap),
    pretty: formatExpr(property.body),
  }));

  return {
    name: spec.name || path.basename("spec"),
    variables: spec.variables,
    nodes,
    edges,
    initialStates,
    reachableCount: reachable.size,
    totalStates: universeInfo.estimatedTotal,
    enumeratedStates: universe.length,
    universeTruncated: universeInfo.truncated,
    maxStates: options.maxStates,
    projectedOutVariables: universeInfo.projectedOutVariables,
    deadlockCount: deadlocks.size,
    invariantFailureCount: invariantFailures.size,
    propertySummaries,
    actionNames: spec.actions.map((action) => action.name),
    includeAllStates: options.includeAllStates,
    compact: options.forceCompact || nodes.length > 20 || edges.length > 50,
  };
}

function enumerateStates(spec, options) {
  const relevantVariables = collectRelevantVariables(spec);
  const domains = spec.variables.map((variable) => {
    if (!(variable in spec.domains)) {
      fail(`Missing domain for variable: ${variable}`);
    }
    const value = evalExpr(spec.domains[variable], {
      now: Object.freeze({}),
      next: null,
      locals: new Map(),
      actionResults: new Map(),
    }, new Map());
    const setValues = asSet(value);
    return Array.from(setValues.values());
  });

  if (domains.some((domain) => domain.length === 0)) {
    return {
      states: [],
      estimatedTotal: 0,
      truncated: false,
      projectedOutVariables: spec.variables.filter((variable) => !relevantVariables.has(variable)),
    };
  }

  const enumeratedVariables = spec.variables.filter((variable) => relevantVariables.has(variable));
  const projectedOutVariables = spec.variables.filter((variable) => !relevantVariables.has(variable));
  const domainMap = new Map(spec.variables.map((variable, index) => [variable, domains[index]]));
  const fixedValues = new Map(projectedOutVariables.map((variable) => [variable, domainMap.get(variable)[0]]));

  const states = [];
  const enumeratedDomains = enumeratedVariables.map((variable) => domainMap.get(variable));
  const estimatedTotal = estimateUniverseSize(enumeratedDomains);
  const limit = options.maxStates;
  const completed = buildStates(spec.variables, enumeratedVariables, enumeratedDomains, 0, {}, fixedValues, states, limit);
  return {
    states,
    estimatedTotal,
    truncated: !completed,
    projectedOutVariables,
  };
}

function buildStates(allVariables, enumeratedVariables, domains, index, partial, fixedValues, out, limit) {
  if (limit !== null && out.length >= limit) {
    return false;
  }
  if (index === enumeratedVariables.length) {
    const state = {};
    for (const variable of allVariables) {
      if (Object.prototype.hasOwnProperty.call(partial, variable)) {
        state[variable] = partial[variable];
      } else {
        state[variable] = fixedValues.get(variable);
      }
    }
    out.push(state);
    return limit === null || out.length < limit;
  }

  const variable = enumeratedVariables[index];
  for (const value of domains[index]) {
    partial[variable] = value;
    if (!buildStates(allVariables, enumeratedVariables, domains, index + 1, partial, fixedValues, out, limit)) {
      return false;
    }
  }
  return true;
}

function estimateUniverseSize(domains) {
  let total = 1;
  for (const domain of domains) {
    total *= domain.length;
    if (!Number.isFinite(total) || total > Number.MAX_SAFE_INTEGER) {
      return Infinity;
    }
  }
  return total;
}

function evaluateProperty(spec, property, universe, reachable, actionMap) {
  const reachableStates = universe.filter((state) => reachable.has(stateKey(spec.variables, state)));
  if (property.body && typeof property.body === "object" && "eventually" in property.body) {
    return reachableStates.some((state) => asBoolean(evalExpr(property.body.eventually, {
      now: state,
      next: null,
      locals: new Map(),
      actionResults: new Map(),
    }, actionMap)));
  }
  return reachableStates.some((state) => asBoolean(evalExpr(property.body, {
    now: state,
    next: null,
    locals: new Map(),
    actionResults: new Map(),
  }, actionMap)));
}

function evalExpr(expr, ctx, actionMap) {
  if (expr === null || typeof expr !== "object" || Array.isArray(expr)) {
    fail(`Cannot evaluate malformed expression: ${JSON.stringify(expr)}`);
  }

  if ("lit" in expr) {
    return expr.lit;
  }
  if ("var" in expr) {
    const name = expr.var;
    if (ctx.locals.has(name)) return ctx.locals.get(name);
    return ctx.now[name];
  }
  if ("next" in expr) {
    if (!ctx.next) {
      fail(`next-variable ${expr.next} evaluated without a next-state context`);
    }
    return ctx.next[expr.next];
  }
  if ("actionRef" in expr) {
    return ctx.actionResults.get(expr.actionRef) || false;
  }
  if ("set" in expr) {
    return new Set(expr.set.map((element) => evalExpr(element, ctx, actionMap)));
  }
  if ("forall" in expr || "exists" in expr) {
    const quantifier = "forall" in expr ? "forall" : "exists";
    const payload = expr[quantifier];
    const domain = asSet(evalExpr(payload.in, ctx, actionMap));
    if (quantifier === "forall") {
      for (const value of domain.values()) {
        const nextCtx = withLocal(ctx, payload.var, value);
        if (!asBoolean(evalExpr(payload.body, nextCtx, actionMap))) {
          return false;
        }
      }
      return true;
    }
    for (const value of domain.values()) {
      const nextCtx = withLocal(ctx, payload.var, value);
      if (asBoolean(evalExpr(payload.body, nextCtx, actionMap))) {
        return true;
      }
    }
    return false;
  }
  if ("not" in expr) {
    return !asBoolean(evalExpr(expr.not, ctx, actionMap));
  }
  if ("eventually" in expr) {
    return asBoolean(evalExpr(expr.eventually, ctx, actionMap));
  }

  for (const op of ["and", "or", "+", "-", "*", "/"]) {
    if (op in expr) {
      const values = expr[op].map((arg) => evalExpr(arg, ctx, actionMap));
      switch (op) {
        case "and":
          return values.every(asBoolean);
        case "or":
          return values.some(asBoolean);
        case "+":
          return values.reduce((acc, value) => acc + asLong(value), 0);
        case "*":
          return values.reduce((acc, value) => acc * asLong(value), 1);
        case "-":
          if (values.length === 0) fail("- needs at least one argument");
          return values.slice(1).reduce((acc, value) => acc - asLong(value), asLong(values[0]));
        case "/":
          if (values.length !== 2) fail("/ expects exactly two arguments");
          return Math.trunc(asLong(values[0]) / asLong(values[1]));
      }
    }
  }

  for (const op of ["=", "!=", "<", "<=", ">", ">=", "in", "implies"]) {
    if (op in expr) {
      const [leftExpr, rightExpr] = expr[op];
      const left = evalExpr(leftExpr, ctx, actionMap);
      const right = evalExpr(rightExpr, ctx, actionMap);
      switch (op) {
        case "=":
          return deepEqual(left, right);
        case "!=":
          return !deepEqual(left, right);
        case "<":
          return compare(left, right) < 0;
        case "<=":
          return compare(left, right) <= 0;
        case ">":
          return compare(left, right) > 0;
        case ">=":
          return compare(left, right) >= 0;
        case "in":
          return setHas(asSet(right), left);
        case "implies":
          return !asBoolean(left) || asBoolean(right);
      }
    }
  }

  fail(`Unsupported expression: ${JSON.stringify(expr)}`);
}

function withLocal(ctx, name, value) {
  const locals = new Map(ctx.locals);
  locals.set(name, value);
  return { ...ctx, locals };
}

function asBoolean(value) {
  if (typeof value !== "boolean") {
    fail(`Expected boolean but got ${JSON.stringify(value)}`);
  }
  return value;
}

function asLong(value) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    fail(`Expected number but got ${JSON.stringify(value)}`);
  }
  return value;
}

function asSet(value) {
  if (!(value instanceof Set)) {
    fail(`Expected set but got ${JSON.stringify(value)}`);
  }
  return value;
}

function compare(left, right) {
  if (typeof left === "number" && typeof right === "number") return left - right;
  if (typeof left === "string" && typeof right === "string") return left.localeCompare(right);
  if (typeof left === "boolean" && typeof right === "boolean") return Number(left) - Number(right);
  fail(`Values are not comparable: ${JSON.stringify(left)} and ${JSON.stringify(right)}`);
}

function deepEqual(left, right) {
  if (left instanceof Set && right instanceof Set) {
    if (left.size !== right.size) return false;
    for (const value of left.values()) {
      if (!setHas(right, value)) return false;
    }
    return true;
  }
  return JSON.stringify(left) === JSON.stringify(right);
}

function setHas(set, target) {
  for (const value of set.values()) {
    if (deepEqual(value, target)) {
      return true;
    }
  }
  return false;
}

function stateKey(variables, state) {
  return JSON.stringify(variables.map((variable) => [variable, state[variable]]));
}

function nodeId(key) {
  return `n_${Buffer.from(key).toString("hex")}`;
}

function renderDot(graph, options) {
  const lines = [];
  lines.push(`digraph ${quoteId(graph.name || "spec")} {`);
  lines.push(`  graph [rankdir=${escapeAttr(options.rankdir)}, labelloc="t", label=${escapeAttr(buildGraphLabel(graph))}, fontname="Helvetica", overlap="false", splines="true", nodesep="${graph.compact ? "0.2" : "0.3"}", ranksep="${graph.compact ? "0.75" : "0.6"}"];`);
  lines.push(`  node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=${graph.compact ? 10 : 11}, margin="${graph.compact ? "0.12,0.08" : "0.18,0.12"}", color="#355070", fillcolor="#f8f9fb"];`);
  lines.push(`  edge [fontname="Helvetica", fontsize=${graph.compact ? 9 : 10}, color="#6d597a"];`);
  lines.push('  "__start__" [shape=point, width=0.2, color="#2a9d8f", fillcolor="#2a9d8f", label=""];');

  if (graph.compact && !options.noLegend) {
    lines.push(`  "__legend__" [shape=note, fontname="Helvetica", fontsize=10, color="#6c757d", fillcolor="#f8f9fa", label=${escapeAttr(buildLegendLabel(graph))}];`);
  }

  for (const node of graph.nodes) {
    const attrs = [];
    attrs.push(`label=${escapeAttr(buildNodeLabel(graph.variables, node.state, node, graph.compact))}`);
    attrs.push(`tooltip=${escapeAttr(node.key)}`);

    if (!node.reachable) {
      attrs.push('style="rounded,filled,dashed"');
      attrs.push('fillcolor="#f1f3f5"');
      attrs.push('color="#adb5bd"');
    } else if (node.invariantFailures.length > 0) {
      attrs.push('fillcolor="#ffe3e3"');
      attrs.push('color="#c92a2a"');
      attrs.push('penwidth=2');
    } else if (node.deadlock) {
      attrs.push('fillcolor="#fff3bf"');
      attrs.push('color="#e67700"');
      attrs.push('penwidth=2');
    } else if (node.initial) {
      attrs.push('fillcolor="#d8f3dc"');
      attrs.push('color="#2d6a4f"');
      attrs.push('penwidth=2');
    }

    lines.push(`  ${quoteId(node.id)} [${attrs.join(", ")}];`);
  }

  for (const key of graph.initialStates) {
    lines.push(`  "__start__" -> ${quoteId(nodeId(key))} [color="#2a9d8f", penwidth=2];`);
  }

  if (graph.compact && !options.noLegend && graph.nodes.length > 0) {
    lines.push(`  "__legend__" -> ${quoteId(graph.nodes[0].id)} [style="invis"];`);
  }

  for (const edge of graph.edges) {
    const labels = Array.from(edge.labels).sort();
    const renderedLabels = graph.compact
      ? labels.map(abbreviateActionLabel)
      : labels;
    lines.push(`  ${quoteId(nodeId(edge.from))} -> ${quoteId(nodeId(edge.to))} [label=${escapeAttr(renderedLabels.join(" | "))}];`);
  }

  lines.push("}");
  return `${lines.join("\n")}\n`;
}

function buildNodeLabel(variables, state, node, compact = false) {
  const lines = [node.displayId];

  if (compact) {
    lines.push(...buildCompactStateLines(variables, state));
  } else {
    lines.push(...variables.map((variable) => `${variable} = ${valueText(state[variable])}`));
  }

  if (node.initial) lines.push("init");
  if (node.deadlock) lines.push("deadlock");
  if (node.invariantFailures.length > 0) {
    lines.push(`violates: ${node.invariantFailures.join(", ")}`);
  }
  if (!node.reachable) lines.push("unreachable");
  return lines.join("\n");
}

function buildCompactStateLines(variables, state) {
  const grouped = new Map();

  for (const variable of variables) {
    const parts = variable.split("_");
    if (parts.length >= 2) {
      const objectName = parts[0];
      const fieldName = parts.slice(1).join("_");
      if (!grouped.has(objectName)) {
        grouped.set(objectName, []);
      }
      grouped.get(objectName).push(`${abbreviateFieldName(fieldName)}=${valueText(state[variable])}`);
    } else {
      grouped.set(variable, [`=${valueText(state[variable])}`]);
    }
  }

  return Array.from(grouped.entries()).map(([objectName, entries]) => `${objectName}: ${entries.join(", ")}`);
}

function abbreviateFieldName(fieldName) {
  return fieldName
    .split("_")
    .map((part) => part.length <= 4 ? part : part.slice(0, 4))
    .join(".");
}

function abbreviateActionLabel(label) {
  const known = new Map([
    ["enrichment-complete", "enrich"],
    ["start-trading", "start"],
    ["pause-trading", "pause"],
    ["resume-trading", "resume"],
    ["disable-instrument", "disable"],
  ]);

  if (known.has(label)) {
    return known.get(label);
  }

  return label
    .split(/[-_]/)
    .map((part) => part.length <= 6 ? part : part.slice(0, 6))
    .join("-");
}

function buildGraphLabel(graph) {
  const summary = [
    `${graph.name}`,
    graph.universeTruncated
      ? `reachable ${graph.reachableCount}/${graph.enumeratedStates} enumerated states`
      : `reachable ${graph.reachableCount}/${graph.totalStates} states`,
    `${graph.edges.length} visible transitions`,
    `${graph.deadlockCount} deadlocks`,
    `${graph.invariantFailureCount} invariant-bad states`,
  ];

  if (graph.universeTruncated) {
    summary.push(`truncated to first ${graph.enumeratedStates} of ${formatCount(graph.totalStates)} states`);
  }
  if (graph.projectedOutVariables.length > 0) {
    summary.push(`projected out ${graph.projectedOutVariables.length} frame-only vars`);
  }

  if (graph.compact) {
    summary.push("see legend for actions and properties");
    summary.push("node labels begin with a short state id");
    return summary.join("\n");
  }

  const properties = graph.propertySummaries.length === 0
    ? "properties: none"
    : `properties: ${graph.propertySummaries.map((property) => `${property.name}=${property.result}`).join(", ")}`;

  const actions = graph.actionNames.length === 0
    ? "actions: none"
    : `actions: ${graph.actionNames.join(", ")}`;

  return [...summary, actions, properties].join("\n");
}

function buildLegendLabel(graph) {
  const lines = ["Legend"];
  lines.push("green = initial, amber = deadlock, red = invariant violation");
  lines.push("each node label starts with a short state id");
  if (graph.universeTruncated) {
    lines.push(`truncated: first ${graph.enumeratedStates} of ${formatCount(graph.totalStates)} states`);
  }
  if (graph.projectedOutVariables.length > 0) {
    lines.push(`projected out: ${graph.projectedOutVariables.join(", ")}`);
  }

  if (graph.actionNames.length === 0) {
    lines.push("actions: none");
  } else {
    lines.push(`actions: ${graph.actionNames.join(", ")}`);
  }

  if (graph.propertySummaries.length === 0) {
    lines.push("properties: none");
  } else {
    for (const property of graph.propertySummaries) {
      lines.push(`${property.name} = ${property.result}`);
    }
  }

  return lines.join("\n");
}

function formatCount(value) {
  return value === Infinity ? "Infinity" : String(value);
}

function collectRelevantVariables(spec) {
  const declared = new Set(spec.variables);
  const relevant = new Set();

  collectRelevantVariablesFromExpr(spec.init, declared, relevant);
  collectRelevantVariablesFromExpr(spec.next, declared, relevant);
  for (const action of spec.actions) {
    collectRelevantVariablesFromExpr(action.body, declared, relevant);
  }
  for (const invariant of spec.invariants) {
    collectRelevantVariablesFromExpr(invariant.body, declared, relevant);
  }
  for (const property of spec.properties) {
    collectRelevantVariablesFromExpr(property.body, declared, relevant);
  }

  return relevant;
}

function collectRelevantVariablesFromExpr(expr, declared, relevant) {
  if (expr === null || typeof expr !== "object" || Array.isArray(expr)) {
    return;
  }
  if ("lit" in expr) {
    return;
  }
  if ("var" in expr) {
    if (declared.has(expr.var)) {
      relevant.add(expr.var);
    }
    return;
  }
  if ("next" in expr) {
    if (declared.has(expr.next)) {
      relevant.add(expr.next);
    }
    return;
  }
  if ("actionRef" in expr) {
    return;
  }
  if ("set" in expr) {
    for (const element of expr.set) {
      collectRelevantVariablesFromExpr(element, declared, relevant);
    }
    return;
  }
  if ("forall" in expr || "exists" in expr) {
    const quantifier = "forall" in expr ? "forall" : "exists";
    const payload = expr[quantifier];
    collectRelevantVariablesFromExpr(payload.in, declared, relevant);
    collectRelevantVariablesFromExpr(payload.body, declared, relevant);
    return;
  }
  if ("not" in expr) {
    collectRelevantVariablesFromExpr(expr.not, declared, relevant);
    return;
  }
  if ("eventually" in expr) {
    collectRelevantVariablesFromExpr(expr.eventually, declared, relevant);
    return;
  }
  for (const op of ["and", "or", "+", "-", "*", "/"]) {
    if (op in expr) {
      for (const arg of expr[op]) {
        collectRelevantVariablesFromExpr(arg, declared, relevant);
      }
      return;
    }
  }
  for (const op of ["=", "!=", "<", "<=", ">", ">=", "in", "implies"]) {
    if (op in expr) {
      if (op === "=" && isUnchangedEquality(expr[op])) {
        return;
      }
      collectRelevantVariablesFromExpr(expr[op][0], declared, relevant);
      collectRelevantVariablesFromExpr(expr[op][1], declared, relevant);
      return;
    }
  }
}

function isUnchangedEquality(args) {
  if (!Array.isArray(args) || args.length !== 2) {
    return false;
  }
  return isMatchingNowNextPair(args[0], args[1]) || isMatchingNowNextPair(args[1], args[0]);
}

function isMatchingNowNextPair(left, right) {
  return left && right
    && typeof left === "object"
    && typeof right === "object"
    && "next" in left
    && "var" in right
    && left.next === right.var;
}

function formatExpr(expr) {
  if ("lit" in expr) return valueText(expr.lit);
  if ("var" in expr) return expr.var;
  if ("next" in expr) return `${expr.next}'`;
  if ("actionRef" in expr) return `@${expr.actionRef}`;
  if ("set" in expr) return `{${expr.set.map(formatExpr).join(", ")}}`;
  if ("not" in expr) return `not (${formatExpr(expr.not)})`;
  if ("eventually" in expr) return `eventually (${formatExpr(expr.eventually)})`;
  if ("forall" in expr || "exists" in expr) {
    const q = "forall" in expr ? "forall" : "exists";
    const payload = expr[q];
    return `${q} ${payload.var} in ${formatExpr(payload.in)}: ${formatExpr(payload.body)}`;
  }
  for (const op of ["and", "or", "+", "-", "*", "/"]) {
    if (op in expr) {
      return `(${expr[op].map(formatExpr).join(` ${op} `)})`;
    }
  }
  for (const op of ["=", "!=", "<", "<=", ">", ">=", "in", "implies"]) {
    if (op in expr) {
      return `(${formatExpr(expr[op][0])} ${op} ${formatExpr(expr[op][1])})`;
    }
  }
  return JSON.stringify(expr);
}

function valueText(value) {
  if (value instanceof Set) {
    return `{${Array.from(value.values()).map(valueText).join(", ")}}`;
  }
  return typeof value === "string" ? JSON.stringify(value) : String(value);
}

function escapeAttr(text) {
  return `"${String(text).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;
}

function quoteId(text) {
  return `"${String(text).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

main();
