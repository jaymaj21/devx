
import java.lang.*;
import java.math.*;

import java.util.*;

import java.text.SimpleDateFormat;
import java.io.*;

class intpair {

    public int loc;
    public int ctxt;

    public intpair(int loc, int ctxt) {
        this.loc = loc;
        this.ctxt = ctxt;
    }
}

public class mprewriter {

    static boolean silence = false;
    private static PrintWriter writer = null;
    private static mprewriter theMprewriter = null;
    private static Object theMutex = new Object();
    private static SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss:SSS");
    private int maxContextId = 0;

    private int currentContextId = 1;
    private TreeMap<intpair, Long> hits = new TreeMap<intpair, Long>(
            new Comparator<intpair>() {
        public int compare(intpair p1, intpair p2) {
            if (p1.loc != p2.loc) {
                return p1.loc - p2.loc;
            } else {
                return p1.ctxt - p2.ctxt;
            }
        }
    });
    private TreeMap<String, Integer> contexts = new TreeMap<String, Integer>(
            new Comparator<String>() {
        public int compare(String p1, String p2) {
            return p1.compareTo(p2);
        }
    }
    );

    mprewriter() {
        if (silence) {
            return;
        }
        try {

            Calendar cal = Calendar.getInstance();
            SimpleDateFormat sdf = new SimpleDateFormat("-yyyy-MM-dd-HH-mm-ss-SSS");
            writer = new PrintWriter("/tmp/mprewriter-trace" + sdf.format(cal.getTime()) + ".txt", "UTF-8");
        } catch (Exception e) {
            System.out.println("Failed to open trace file");
        }
    }

    public static void close() {
        if (silence) {
            return;
        }

        synchronized (theMutex) {
            writer.close();
            theMprewriter = null;
            writer = null;
        }
    }
    
    
    static {
        Runtime.getRuntime().addShutdownHook(new Thread() {
        public void run() {
            // perform cleanup tasks here
            save_coverage();
            close();
        }
        });
    }

    public static void stack_trace(String preamble, String message) {
        if (silence) {
            return;
        }
        if (message == null) {
            return;
        }
        synchronized (theMutex) {
            // Do the following block under a global lock
            if (theMprewriter == null) {
                theMprewriter = new mprewriter();
            }

            Calendar cal = Calendar.getInstance();
            mprewriter.writer.println("STACKTRACE" + preamble + ":" + message
                    + " from thread " + Thread.currentThread().getId() + " at "
                    + sdf.format(cal.getTime()));
            mprewriter.writer.flush();
            mprewriter.writer.println("Stack trace from thread "
                    + Thread.currentThread().getId() + " at "
                    + sdf.format(cal.getTime()));
            mprewriter.writer.flush();

            // Temporarily let us print the stack here too.
            StackTraceElement[] st = Thread.currentThread().getStackTrace();
            for (int i = 2; i < st.length; ++i) {
                mprewriter.writer.println(st[i].getFileName() + ":"
                        + st[i].getLineNumber() + ": STACKLOC "
                        + st[i].getClassName() + "::" + st[i].getMethodName());
            }

            mprewriter.writer.flush();
        }
    }

    public static void write_stack_trace(StackTraceElement[] st) {
        if (silence) {
            return;
        }
        if (st == null) {
            return;
        }
        synchronized (theMutex) {

// Do the following block under a global lock
            if (theMprewriter == null) {
                theMprewriter = new mprewriter();

                ++theMprewriter.maxContextId;

                Integer val = new Integer(theMprewriter.maxContextId);
                theMprewriter.contexts.put("default", val);
            }
            Calendar cal = Calendar.getInstance();

            for (int i = 0; i < st.length; ++i) {
                mprewriter.writer.println(st[i].getFileName()
                        + ":" + st[i].getLineNumber() + ": STACKLOC "
                        + st[i].getClassName() + "::" + st[i].getMethodName());
            }

            mprewriter.writer.println(" from thread " + Thread.currentThread().getId() + " at "
                    + sdf.format(cal.getTime()));

            mprewriter.writer.flush();
        }
    }

    public static void write_line(String message) {
        if (silence) {
            return;
        }
        if (message == null) {
            return;
        }
        synchronized (theMutex) {
// Do the following block under a global lock
            if (theMprewriter == null) {
                theMprewriter = new mprewriter();
                ++theMprewriter.maxContextId;
                Integer val = new Integer(theMprewriter.maxContextId);
                theMprewriter.contexts.put("default", val);
            }

            Calendar cal = Calendar.getInstance();
            mprewriter.writer.println(message + " from thread "
                    + Thread.currentThread().getId() + " at "
                    + sdf.format(cal.getTime()));

            mprewriter.writer.flush();

        }
    }

    public static void trace(String preamble, String message) {
        if (silence) {
            return;
        }
        if (message == null) {
            return;
        }
        synchronized (theMutex) {
// Do the following block under a global lock
            if (theMprewriter == null) {

                theMprewriter = new mprewriter();
                ++theMprewriter.maxContextId;
                Integer val = new Integer(theMprewriter.maxContextId);
                theMprewriter.contexts.put("default", val);
            }

            Calendar cal = Calendar.getInstance();
            mprewriter.writer.println(preamble + ":" + message
                    + " from thread " + Thread.currentThread().getId() + " at "
                    + sdf.format(cal.getTime()));
            mprewriter.writer.flush();
// Temporarily let us print a bit of the stack here too.
            StackTraceElement[] st = Thread.currentThread().getStackTrace();
            int count = 0;
            for (int i = 2; i < st.length; ++i) {
                mprewriter.writer.println(st[i].getFileName() + ":"
                        + st[i].getLineNumber() + ": STACKLOC " + st[i].getClassName()
                        + "r:" + st[i].getMethodName());
                mprewriter.writer.flush();
                ++count;
                if (count >= 100) {
                    break;
                }
            }

        }
    }

    public static void add_context_from_callstack() {
        if (silence) {
            return;
        }
        synchronized (theMutex) {

            StackTraceElement[] st = Thread.currentThread().getStackTrace();
            String context = st[2].getClassName() + "." + st[2].getMethodName();

            if (theMprewriter == null) {
                theMprewriter = new mprewriter();
                ++theMprewriter.maxContextId;
                Integer val = new Integer(theMprewriter.maxContextId);
                theMprewriter.contexts.put("default", val);
            }

            Integer val = theMprewriter.contexts.get(context);
            if (val == null) {
                ++theMprewriter.maxContextId;
                val = new Integer(theMprewriter.maxContextId);
                theMprewriter.contexts.put(context, val);
            }
            theMprewriter.currentContextId = val.intValue();
        }
    }

    public static void add_context(String context) {
        if (silence) {
            return;
        }
        synchronized (theMutex) {

            if (theMprewriter == null) {
                theMprewriter = new mprewriter();
                ++theMprewriter.maxContextId;
                Integer val = new Integer(theMprewriter.maxContextId);
                theMprewriter.contexts.put("default", val);
            }

            Integer val = theMprewriter.contexts.get(context);
            if (val == null) {
                ++theMprewriter.maxContextId;
                val = new Integer(theMprewriter.maxContextId);
                theMprewriter.contexts.put(context, val);
            }
            theMprewriter.currentContextId = val.intValue();
        }
    }

    public void add_hit(int loc) {
        if (silence) {
            return;
        }
        if (theMprewriter.currentContextId != 0) {
            intpair target = new intpair(loc, theMprewriter.currentContextId);
            Long val = hits.get(target);
            if (val == null) {
                hits.put(target, new Long(1));
            } else {
                hits.put(target, new Long(val.longValue() + 1));
            }
        }
    }

    public void writeContexts(PrintWriter covWriter) {
        if (silence) {
            return;
        }
        covWriter.println("CONTEXTS " + contexts.size());
        for (Map.Entry<String, Integer> entry : contexts.entrySet()) {
            String key = entry.getKey();
            Integer value = entry.getValue();
            covWriter.println(value + " " + key);
        }
    }

    public void writeHits(PrintWriter covWriter) {
        if (silence) {
            return;
        }

        covWriter.println("HITS " + hits.size());

        for (Map.Entry<intpair, Long> entry : hits.entrySet()) {
            intpair key = entry.getKey();
            Long value = entry.getValue();
            covWriter.println(key.ctxt + " " + key.loc + " " + value);
        }
    }

    public void finalize() {
        if (silence) {
            return;
        }

        mprewriter.save_coverage();
    }

    public static void save_coverage() {
        if (silence) {
            return;
        }

        synchronized (theMutex) {
            try {
                Calendar cal = Calendar.getInstance();
                SimpleDateFormat sdf = new SimpleDateFormat("-yyyy-MM-dd-HH-mm-ss-SSS");
                PrintWriter covWriter = new PrintWriter("/tmp/coverage-" + sdf.format(cal.getTime()) + ".txt", "UTF-8");
                theMprewriter.writeContexts(covWriter);
                theMprewriter.writeHits(covWriter);
                covWriter.close();
            } catch (Exception e) {
                System.err.println("Failed to write coverage data");
            }
        }
    }

    public static void trace_with_stack(String preamble, String message) {
        if (silence) {
            return;
        }
        if (message == null) {
            return;
        }
        synchronized (theMutex) {
// Do the following block under a global lock
            if (theMprewriter == null) {
                theMprewriter = new mprewriter();
            }

            Calendar cal = Calendar.getInstance();
            mprewriter.writer.println(preamble + ":" + message
                    + " from thread " + Thread.currentThread().getId() + " at"
                    + sdf.format(cal.getTime()));

            mprewriter.writer.flush();
            StackTraceElement[] st = Thread.currentThread().getStackTrace();
            for (int i = 2; i < st.length; ++i) {
                mprewriter.writer.println(st[i].getFileName() + ":"
                        + st[i].getLineNumber() + ": STACKLOC "
                        + st[i].getClassName() + "::" + st[i].getMethodName());
                mprewriter.writer.flush();
            }
        }
    }

    public static void scope_START(int loc) {
        if (silence) {
            return;
        }
        synchronized (theMutex) {
// Do the following block under a global lock
            if (theMprewriter == null) {
                theMprewriter = new mprewriter();
            }
            theMprewriter.add_hit(loc);
            StackTraceElement[] trace = Thread.currentThread().getStackTrace();
            String depthstring = "";

            int framecount = trace.length - 1;

            for (int i = 0; i < framecount; ++i) {
                depthstring += (i % 10);
            }

            Calendar cal = Calendar.getInstance();
            mprewriter.writer.println(":" + depthstring + "<T"
                    + loc + "> from thread " + Thread.currentThread().getId()
                    + " at" + sdf.format(cal.getTime()));
            mprewriter.writer.flush();
        }
    }

    public static void scope_END(int loc) {
        if (silence) {
            return;
        }

        synchronized (theMutex) {

// Do the following block under a global lock
            if (theMprewriter == null) {
                theMprewriter = new mprewriter();
            }
            StackTraceElement[] trace = Thread.currentThread().getStackTrace();
            String depthstring = "";

            int framecount = trace.length - 1;

            for (int i = 0; i < framecount; ++i) {
                depthstring += (i % 10);
            }
            Calendar cal = Calendar.getInstance();
            mprewriter.writer.println(":" + depthstring
                    + "</T" + loc + "> from thread "
                    + Thread.currentThread().getId() + " at " + sdf.format(cal.getTime()));
            mprewriter.writer.flush();
        }
    }

    private static void test() {
    }

    public static void main(String[] argv) {
        test();
        mprewriter.trace("main", "before sleep");
        try {
            Thread.sleep(4000);
        } catch (Exception e) {
            System.out.println("Sleep interrupted");
        }

        mprewriter.trace("main", "after sleep");
    }
}

