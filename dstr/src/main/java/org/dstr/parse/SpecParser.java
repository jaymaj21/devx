package org.dstr.parse;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.File;
import java.io.IOException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.dstr.ast.*;
import org.dstr.model.NamedExpr;
import org.dstr.model.Spec;

public final class SpecParser {
    private final ObjectMapper mapper = new ObjectMapper();

    public Spec parse(Path path) throws IOException {
        return parse(path.toFile());
    }

    public Spec parse(File file) throws IOException {
        JsonNode root = mapper.readTree(file);
        return parse(root);
    }

    public Spec parse(String json) throws IOException {
        return parse(mapper.readTree(json));
    }

    public Spec parse(JsonNode root) {
        String name = requiredText(root, "name");
        List<String> variables = parseVariables(root.required("variables"));
        Map<String, Expr> domains = parseDomains(root.path("domains"), variables);
        Set<String> actionNames = new LinkedHashSet<>();

        Expr init = parseExpr(root.required("init"), variables, actionNames, false, false);

        List<NamedExpr> actions = new ArrayList<>();
        for (JsonNode actionNode : requiredArray(root, "actions")) {
            String actionName = requiredText(actionNode, "name");
            actionNames.add(actionName);
        }
        for (JsonNode actionNode : requiredArray(root, "actions")) {
            String actionName = requiredText(actionNode, "name");
            Expr body = parseExpr(actionNode.required("body"), variables, actionNames, true, false);
            actions.add(new NamedExpr(actionName, body));
        }

        Expr next = parseExpr(root.required("next"), variables, actionNames, true, true);

        List<NamedExpr> invariants = new ArrayList<>();
        for (JsonNode invNode : root.path("invariants")) {
            invariants.add(new NamedExpr(requiredText(invNode, "name"),
                    parseExpr(invNode.required("body"), variables, actionNames, false, false)));
        }

        List<NamedExpr> properties = new ArrayList<>();
        for (JsonNode propNode : root.path("properties")) {
            properties.add(new NamedExpr(requiredText(propNode, "name"),
                    parseExpr(propNode.required("body"), variables, actionNames, false, false)));
        }

        return new Spec(name, variables, domains, init, actions, next, invariants, properties);
    }

    private List<String> parseVariables(JsonNode variablesNode) {
        if (!variablesNode.isArray() || variablesNode.isEmpty()) {
            throw new IllegalArgumentException("variables must be a non-empty array");
        }
        List<String> vars = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (JsonNode node : variablesNode) {
            String v = node.asText();
            if (!seen.add(v)) {
                throw new IllegalArgumentException("Duplicate variable: " + v);
            }
            vars.add(v);
        }
        return vars;
    }

    private Map<String, Expr> parseDomains(JsonNode domainsNode, List<String> variables) {
        Map<String, Expr> domains = new LinkedHashMap<>();
        if (domainsNode.isMissingNode()) {
            return domains;
        }
        if (!domainsNode.isObject()) {
            throw new IllegalArgumentException("domains must be an object");
        }
        Iterator<String> it = domainsNode.fieldNames();
        while (it.hasNext()) {
            String var = it.next();
            if (!variables.contains(var)) {
                throw new IllegalArgumentException("Domain provided for undeclared variable: " + var);
            }
            domains.put(var, parseExpr(domainsNode.get(var), variables, Set.of(), false, false));
        }
        return domains;
    }

    private Expr parseExpr(JsonNode node, List<String> variables, Set<String> actionNames,
                           boolean allowNextVariables, boolean allowActionRefs) {
        if (node.isObject()) {
            if (node.has("lit")) {
                JsonNode lit = node.get("lit");
                if (lit.isTextual()) return new LiteralExpr(lit.asText());
                if (lit.isBoolean()) return new LiteralExpr(lit.asBoolean());
                if (lit.isInt() || lit.isLong()) return new LiteralExpr(lit.asLong());
                if (lit.isDouble() || lit.isFloat() || lit.isBigDecimal()) return new LiteralExpr(lit.asDouble());
                if (lit.isNull()) return new LiteralExpr(null);
                throw new IllegalArgumentException("Unsupported literal node: " + lit);
            }
            if (node.has("var")) {
                String name = node.get("var").asText();
                if (!variables.contains(name)) {
                    throw new IllegalArgumentException("Unknown variable: " + name);
                }
                return new VarExpr(name, VarExpr.Phase.NOW);
            }
            if (node.has("next")) {
                String name = node.get("next").asText();
                if (!allowNextVariables) {
                    throw new IllegalArgumentException("next-variable not allowed in this context: " + name);
                }
                if (!variables.contains(name)) {
                    throw new IllegalArgumentException("Unknown variable: " + name);
                }
                return new VarExpr(name, VarExpr.Phase.NEXT);
            }
            if (node.has("actionRef")) {
                if (!allowActionRefs) {
                    throw new IllegalArgumentException("actionRef not allowed in this context");
                }
                String name = node.get("actionRef").asText();
                if (!actionNames.contains(name)) {
                    throw new IllegalArgumentException("Unknown action reference: " + name);
                }
                return new VarExpr("@action:" + name, VarExpr.Phase.NOW);
            }
            if (node.has("set")) {
                List<Expr> elems = new ArrayList<>();
                for (JsonNode elem : node.get("set")) {
                    elems.add(parseExpr(elem, variables, actionNames, allowNextVariables, allowActionRefs));
                }
                return new SetExpr(elems);
            }
            if (node.has("forall") || node.has("exists")) {
                String q = node.has("forall") ? "forall" : "exists";
                JsonNode qNode = node.get(q);
                String var = requiredText(qNode, "var");
                Expr domain = parseExpr(qNode.required("in"), variables, actionNames, allowNextVariables, allowActionRefs);
                Expr body = parseExpr(qNode.required("body"), variables, actionNames, allowNextVariables, allowActionRefs);
                return new QuantifiedExpr(q, var, domain, body);
            }
            if (node.has("not")) {
                return new UnaryExpr("not", parseExpr(node.get("not"), variables, actionNames, allowNextVariables, allowActionRefs));
            }
            for (String op : List.of("and", "or", "=", "!=", "<", "<=", ">", ">=", "+", "-", "*", "/", "in", "implies", "eventually")) {
                if (node.has(op)) {
                    JsonNode opNode = node.get(op);
                    if (op.equals("eventually")) {
                        return new UnaryExpr("eventually", parseExpr(opNode, variables, actionNames, allowNextVariables, allowActionRefs));
                    }
                    if (!opNode.isArray()) {
                        throw new IllegalArgumentException(op + " expects an array");
                    }
                    List<Expr> args = new ArrayList<>();
                    for (JsonNode child : opNode) {
                        args.add(parseExpr(child, variables, actionNames, allowNextVariables, allowActionRefs));
                    }
                    if (List.of("=", "!=", "<", "<=", ">", ">=", "in", "implies").contains(op)) {
                        if (args.size() != 2) {
                            throw new IllegalArgumentException(op + " expects exactly 2 arguments");
                        }
                        return new BinaryExpr(op, args.get(0), args.get(1));
                    }
                    return new NAryExpr(op, args);
                }
            }
        }
        throw new IllegalArgumentException("Cannot parse expression node: " + node);
    }

    private List<JsonNode> requiredArray(JsonNode node, String field) {
        JsonNode arr = node.required(field);
        if (!arr.isArray()) {
            throw new IllegalArgumentException(field + " must be an array");
        }
        List<JsonNode> result = new ArrayList<>();
        arr.forEach(result::add);
        return result;
    }

    private String requiredText(JsonNode node, String field) {
        JsonNode child = node.required(field);
        if (!child.isTextual()) {
            throw new IllegalArgumentException(field + " must be text");
        }
        return child.asText();
    }
}

