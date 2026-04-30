package org.dstr.model;

import java.util.List;

public record Counterexample(String kind, String name, List<State> path) {
}

