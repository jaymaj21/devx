package com.divideandconcur.core;
import com.divideandconcur.examples.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class ExampleTest {
    @Test void lostUpdateExampleFindsFailure() {
        assertTrue(LostUpdateExample.run().failedRuns()>0);
    } @Test void lazyInitExampleFindsFailure() {
        assertTrue(LazyInitBugExample.run().failedRuns()>0);
    } @Test void brokenBakeryFindsMutualExclusionFailure() {
        assertTrue(BrokenBakeryNoTieBreakExample.run().failedRuns()>0);
    } @Test void correctBakerySketchHasNoMutualExclusionFailure() {
        assertEquals(0,BakerySketchCorrectExample.run().failedRuns());
    }
}
