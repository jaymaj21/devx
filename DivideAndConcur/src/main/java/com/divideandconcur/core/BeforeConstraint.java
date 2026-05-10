package com.divideandconcur.core;
import java.util.*;
public record BeforeConstraint(Turn before, Turn after) {
    public BeforeConstraint {
        Objects.requireNonNull(before);
        Objects.requireNonNull(after);
    }
    public static BeforeConstraint of(Turn b,Turn a) {
        return new BeforeConstraint(b,a);
    }
    public boolean blocksChoice(Turn candidate, Set<Turn> chosen) {
        return candidate.equals(after)&&!chosen.contains(before);
    }
    public String toString() {
        return before+" < "+after;
    }
}
