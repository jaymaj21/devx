package com.divideandconcur.core;
import java.util.Objects;
/** A scheduled atomic segment. Turn("t1", 0) means: allow logical thread t1 to execute segment 0. */
public record Turn(String threadId, int segmentIndex) {
    public Turn {
        Objects.requireNonNull(threadId,"threadId");
        if(threadId.isBlank()) throw new IllegalArgumentException("threadId must not be blank");
        if(segmentIndex<0) throw new IllegalArgumentException("segmentIndex must be non-negative");
    }

    public static Turn of(String threadId,int segmentIndex) {
            return new Turn(threadId,segmentIndex);
        }
    public static Turn parse(String text) {
        String[] p=text.trim().split(":");
        if(p.length!=2) throw new IllegalArgumentException("Expected threadId:segmentIndex: "+text);
        return of(p[0],Integer.parseInt(p[1]));
    }
    public String toString() {
        return threadId+":"+segmentIndex;
    }
}
