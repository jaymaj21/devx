package com.divideandconcur.examples;
import com.divideandconcur.core.*;
public final class ExampleSuite {
    private ExampleSuite() {} public static void main(String[] args) {
        run("Lost update",LostUpdateExample.run());
        run("Lazy init bug",LazyInitBugExample.run());
        run("Constrained schedule",ConstrainedScheduleExample.run());
        run("Bakery sketch, correct tie-breaker",BakerySketchCorrectExample.run());
        run("Broken bakery, no tie-breaker",BrokenBakeryNoTieBreakExample.run());
    }
    private static void run(String name,ExplorationResult result) {
        System.out.println();
        System.out.println("=== "+name+" ===");
        System.out.println(result.summary());
        result.firstFailure().ifPresent(f-> {
            System.out.println();
            System.out.println("First failing schedule:");
            System.out.println(f.pretty());
        });
    }
}
