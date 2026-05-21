package org.dstr.cli;

import java.nio.file.Path;
import com.trading.domain.mprewriter;
import org.dstr.check.ExplicitStateChecker;
import org.dstr.model.CheckResult;
import org.dstr.model.Counterexample;
import org.dstr.model.Spec;
import org.dstr.parse.SpecParser;

public final class DstrCli {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            System.err.println("Usage: dstr <spec.json>");
            System.exit(2);
        }

        Path specPath = Path.of(args[0]);
        String specFileName = specPath.getFileName().toString();
        mprewriter.reset_context_to(specFileName);

        Spec spec = new SpecParser().parse(specPath);
        CheckResult result = new ExplicitStateChecker().check(spec);

        System.out.println("Spec: " + spec.name());
        System.out.println("Reachable states: " + result.reachableStates().size());
        System.out.println("Transitions explored: " + result.exploredTransitions());
        System.out.println("Properties: " + result.existentialProperties());

        if (!result.invariantViolations().isEmpty()) {
            System.out.println("Invariant violations:");
            for (Counterexample ce : result.invariantViolations()) {
                System.out.println("  - " + ce.name() + " path=" + ce.path());
            }
        }
        if (!result.deadlocks().isEmpty()) {
            System.out.println("Deadlocks:");
            for (Counterexample ce : result.deadlocks()) {
                System.out.println("  - path=" + ce.path());
            }
        }
    }
}

