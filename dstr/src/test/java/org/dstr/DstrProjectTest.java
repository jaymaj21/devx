package org.dstr;

import static org.junit.jupiter.api.Assertions.*;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import java.util.stream.Stream;
import org.dstr.check.ExplicitStateChecker;
import org.dstr.model.CheckResult;
import org.dstr.model.Spec;
import org.dstr.parse.SpecParser;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;

public class DstrProjectTest {
    private static final Path SPECS_DIR = Path.of("test-suite/specs");
    private static final Set<String> SLOW_SPECS = Set.of("bakery-3proc.json");

    private final SpecParser parser = new SpecParser();
    private final ExplicitStateChecker checker = new ExplicitStateChecker();

    @ParameterizedTest(name = "{0}")
    @MethodSource("fastSpecFiles")
    void fastSpecsInTestSuiteParseAndCheckAsExpected(Path specFile) throws Exception {
        Spec spec = parser.parse(specFile);
        CheckResult result = checker.check(spec);
        assertSpecResult(specFile.getFileName().toString(), spec, result);
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("slowSpecFiles")
    void slowSpecsInTestSuiteParseAndCheckAsExpected(Path specFile) throws Exception {
        Assumptions.assumeTrue(includeSlowSpecs(),
                "Slow specs are skipped by default; set -Ddstr.includeSlowSpecs=true to include them");

        Spec spec = parser.parse(specFile);
        CheckResult result = checker.check(spec);
        assertSpecResult(specFile.getFileName().toString(), spec, result);
    }

    static Stream<Path> fastSpecFiles() throws Exception {
        return specFiles(false);
    }

    static Stream<Path> slowSpecFiles() throws Exception {
        return specFiles(true);
    }

    private static Stream<Path> specFiles(boolean slowOnly) throws Exception {
        List<Path> specFiles;
        try (var stream = Files.list(SPECS_DIR)) {
            specFiles = stream
                    .filter(path -> path.getFileName().toString().endsWith(".json"))
                    .filter(path -> SLOW_SPECS.contains(path.getFileName().toString()) == slowOnly)
                    .sorted()
                    .toList();
        }
        if (!slowOnly) {
            assertFalse(specFiles.isEmpty(), "No fast spec files found under " + SPECS_DIR);
        }
        return specFiles.stream();
    }

    private static boolean includeSlowSpecs() {
        return Boolean.getBoolean("dstr.includeSlowSpecs")
                || "true".equalsIgnoreCase(System.getenv("DSTR_INCLUDE_SLOW_SPECS"));
    }

    private void assertSpecResult(String fileName, Spec spec, CheckResult result) {
        switch (fileName) {
            case "light-switch.json" -> {
                assertEquals("light-switch", spec.name());
                assertEquals(1, spec.variables().size());
                assertEquals(2, spec.actions().size());
                assertEquals(2, result.reachableStates().size());
                assertTrue(result.invariantViolations().isEmpty());
                assertTrue(result.existentialProperties().get("eventually-on"));
            }
            case "mutex-2proc.json" -> {
                assertTrue(result.invariantViolations().isEmpty());
                assertTrue(result.existentialProperties().get("p1-can-reach-cs"));
                assertTrue(result.existentialProperties().get("p2-can-reach-cs"));
            }
            case "broken-mutex.json" -> {
                assertFalse(result.invariantViolations().isEmpty());
                assertEquals("mutual-exclusion", result.invariantViolations().get(0).name());
            }
            case "counter.json" -> assertTrue(result.existentialProperties().get("can-reach-three"));
            case "frame-only-variable.json" -> {
                assertEquals(2, result.reachableStates().size());
                assertTrue(result.invariantViolations().isEmpty());
                assertTrue(result.existentialProperties().get("can-reach-one"));
            }
            case "tla-hour-clock.json" -> {
                assertEquals(12, result.reachableStates().size());
                assertEquals(12, result.exploredTransitions());
                assertTrue(result.invariantViolations().isEmpty());
                assertTrue(result.deadlocks().isEmpty());
                assertTrue(result.existentialProperties().get("can-reach-twelve"));
            }
            case "tla-die-hard.json" -> {
                assertTrue(result.invariantViolations().isEmpty());
                assertTrue(result.deadlocks().isEmpty());
                assertTrue(result.existentialProperties().get("can-measure-four-gallons"));
            }
            case "tla-peterson-2proc.json" -> {
                assertTrue(result.invariantViolations().isEmpty());
                assertTrue(result.existentialProperties().get("p1-can-reach-cs"));
                assertTrue(result.existentialProperties().get("p2-can-reach-cs"));
            }
            case "instrument-lifecycle-small.json", "instrument-lifecycle.json" -> {
                assertEquals(5, result.reachableStates().size());
                assertEquals(8, result.exploredTransitions());
                assertTrue(result.invariantViolations().isEmpty());
                assertFalse(result.deadlocks().isEmpty());
            }
            case "bakery-3proc.json" -> {
                assertTrue(result.invariantViolations().isEmpty());
                assertTrue(result.existentialProperties().get("p1-can-reach-cs"));
                assertTrue(result.existentialProperties().get("p2-can-reach-cs"));
                assertTrue(result.existentialProperties().get("p3-can-reach-cs"));
                assertFalse(result.deadlocks().isEmpty());
            }
            case "cas-2proc-race.json" -> {
                assertTrue(result.invariantViolations().isEmpty());
                assertTrue(result.existentialProperties().get("p1-can-win"));
                assertTrue(result.existentialProperties().get("p2-can-win"));
                assertTrue(result.existentialProperties().get("p1-can-lose"));
                assertTrue(result.existentialProperties().get("p2-can-lose"));
                assertFalse(result.deadlocks().isEmpty());
            }
            default -> fail("Missing expectations for spec file: " + fileName);
        }
    }
}

