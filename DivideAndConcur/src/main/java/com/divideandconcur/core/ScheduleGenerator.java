package com.divideandconcur.core;
import java.util.*;
/** Lazy recursive generator of all order-preserving interleavings, with basic constraints and preemption bound. */
public final class ScheduleGenerator {
    private ScheduleGenerator() {}
    public static List<List<Turn>> all(Map<String,Integer> counts) {
        List<List<Turn>> out=new ArrayList<>();
        visitAll(counts,ScheduleOptions.exhaustive(),s-> {out.add(List.copyOf(s)); return true;});
        return out;
    }
    public static long visitAll(Map<String,Integer> segmentCountsByThread, ScheduleOptions options, ScheduleVisitor visitor) {
        Objects.requireNonNull(segmentCountsByThread);
        Objects.requireNonNull(options);
        Objects.requireNonNull(visitor);
        LinkedHashMap<String,Integer> counts=new LinkedHashMap<>(segmentCountsByThread);
        validate(counts,options);
        List<String> tids=new ArrayList<>(counts.keySet());
        Map<String,Integer> next=new LinkedHashMap<>();
        for(String tid:tids) next.put(tid,0);
        int total=counts.values().stream().mapToInt(Integer::intValue).sum();
        GenerationState st=new GenerationState();
        backtrack(counts,tids,next,new ArrayList<>(),new HashSet<>(),total,null,0,st,options,visitor);
        return st.generated;
    }

    private static boolean backtrack(Map<String,Integer> counts,List<String> tids,Map<String,Integer> next,List<Turn> prefix,Set<Turn> chosen,int total,String prev,int preemptions,GenerationState st,ScheduleOptions opt,ScheduleVisitor visitor) {
        if(st.generated>=opt.maxSchedules()) return false;
        if(prefix.size()==total) {
            st.generated++;
            return visitor.visit(List.copyOf(prefix));
        }
        for(String tid:tids) {
            int n=next.get(tid), max=counts.get(tid);
            if(n>=max) continue;
            Turn cand=Turn.of(tid,n);
            if(blocked(cand,chosen,opt)) continue;
            int newPre=preemptions;
            if(prev!=null && !prev.equals(tid)) {
                int remainingPrev=counts.get(prev)-next.get(prev);
                if(remainingPrev>0) newPre++;
            }
            if(opt.maxPreemptions()!=null && newPre>opt.maxPreemptions()) continue;
            prefix.add(cand);
            chosen.add(cand);
            next.put(tid,n+1);
            boolean keep=backtrack(counts,tids,next,prefix,chosen,total,tid,newPre,st,opt,visitor);
            next.put(tid,n);
            chosen.remove(cand);
            prefix.remove(prefix.size()-1);
            if(!keep) return false;
        }
        return true;
    }

    private static boolean blocked(Turn cand,Set<Turn> chosen,ScheduleOptions opt) {
        for(BeforeConstraint c:opt.beforeConstraints()) if(c.blocksChoice(cand,chosen)) return true;
        return false;
    }

    private static void validate(Map<String,Integer> counts,ScheduleOptions opt) {
        if(counts.isEmpty()) throw new IllegalArgumentException("At least one thread is required");
        for(var e:counts.entrySet()) {
            if(e.getKey()==null||e.getKey().isBlank()) throw new IllegalArgumentException("Thread id must not be blank");
            if(e.getValue()==null||e.getValue()<=0) throw new IllegalArgumentException("Segment count must be positive for "+e.getKey());
        }
        for(BeforeConstraint c:opt.beforeConstraints()) {
            validateTurn(c.before(),counts);
            validateTurn(c.after(),counts);
        }
    }

    private static void validateTurn(Turn t,Map<String,Integer> counts) {
        Integer max=counts.get(t.threadId());
        if(max==null) throw new IllegalArgumentException("Constraint refers to unknown thread: "+t.threadId());
        if(t.segmentIndex()>=max) throw new IllegalArgumentException("Constraint refers to non-existent segment: "+t);
    }

    private static final class GenerationState {
        long generated=0;
    }
}
