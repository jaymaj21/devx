package com.jm.cov;

import org.objectweb.asm.*;
import org.objectweb.asm.commons.AdviceAdapter;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.jar.*;

import static org.objectweb.asm.Opcodes.*;

/**
 * Branch + handler + method-entry instrumenter.
 * Injects a call to com.trading.domain.mprewriter.scope_START(int id)
 * and embeds META-INF/branch-probes.csv with mapping:
 *   id,class,method,where,source,line
 *
 * CLI:
 *   java -jar branch-probe-instrumenter-jar-with-dependencies.jar [--startid=N] [--sidecar]
 *          input.jar output.jar
 *
 * Prints LAST_ID=<n> to stdout after finishing.
 */
public class JarInstrumenter {

    private static final AtomicInteger PROBE_COUNTER = new AtomicInteger(1);
    private static final StringBuilder PROBE_INDEX = new StringBuilder("id,class,method,where,source,line,edge,opcode,sense\n");
    private static final java.util.Set<String> ALLOWED_KINDS;
    private static final ExclusionMatcher EXCLUSIONS = ExclusionMatcher.fromFile(System.getProperty("bp.excludefile", ""));
    private static final InclusionMatcher INCLUSIONS = InclusionMatcher.fromFile(System.getProperty("bp.includefile", ""));
    static {
        String def = "METHOD_ENTRY,CATCH_ENTRY,FINALLY_ENTRY,IF_TRUE,IF_FALSE"; // include all by default
        String spec = System.getProperty("bp.inject", def);
        java.util.Set<String> s = new java.util.HashSet<>();
        for (String p : spec.split(",")) { s.add(p.trim()); }
        ALLOWED_KINDS = java.util.Collections.unmodifiableSet(s);
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Usage: java -jar branch-probe-instrumenter-jar-with-dependencies.jar [--startid=N] [--sidecar] <in.jar> <out.jar>");
            System.exit(2);
        }

        boolean sidecar = false;
        File in = null, out = null;
        for (int i = 0; i < args.length; i++) {
            String a = args[i];
            if (a.startsWith("--startid=")) {
                int s = Integer.parseInt(a.substring("--startid=".length()));
                PROBE_COUNTER.set(s);
            } else if (a.equals("--sidecar")) {
                sidecar = true;
            } else if (in == null) {
                in = new File(a);
            } else {
                out = new File(a);
            }
        }
        if (in == null || out == null) {
            System.err.println("Missing input/output jar.");
            System.exit(2);
        }

        instrumentJar(in, out);

        // Optionally write a neighbor CSV next to output
        if (sidecar) {
            File side = new File(out.getParentFile(), out.getName().replaceAll("\\.jar$", "") + "-branch-probes.csv");
            try (FileOutputStream fos = new FileOutputStream(side)) {
                fos.write(PROBE_INDEX.toString().getBytes(StandardCharsets.UTF_8));
            }
            System.out.println("Wrote sidecar: " + side.getAbsolutePath());
        }

        System.out.println("Instrumented: " + in + " -> " + out);
        System.out.println("LAST_ID=" + (PROBE_COUNTER.get() - 1));
    }

    private static synchronized void addIndex(int id, String cls, String method, String where, String source, int line,
                                              String edge, String opcode, String sense) {
        PROBE_INDEX.append(id).append(',')
                .append(cls).append(',')
                .append(method).append(',')
                .append(where).append(',')
                .append(source == null ? "" : source).append(',')
                .append(line >= 0 ? line : "").append(',')
                .append(edge == null ? "" : edge).append(',')
                .append(opcode == null ? "" : opcode).append(',')
                .append(sense == null ? "" : sense).append('\n');
    }

    private static void instrumentJar(File inJar, File outJar) throws IOException {
        try (JarInputStream jis = new JarInputStream(new FileInputStream(inJar));
             FileOutputStream fos = new FileOutputStream(outJar)) {

            Manifest manifest = jis.getManifest();
            if (manifest == null) {
                manifest = new Manifest();
                manifest.getMainAttributes().putValue("Manifest-Version", "1.0");
            }
            try (JarOutputStream jos = new JarOutputStream(fos, manifest)) {
                JarEntry entry;
                while ((entry = jis.getNextJarEntry()) != null) {
                    String name = entry.getName();
                    byte[] bytes = jis.readAllBytes();

                    boolean copyRaw = !name.endsWith(".class")
                            || name.equals("module-info.class")
                            || (name.startsWith("META-INF/") && (name.endsWith(".SF") || name.endsWith(".RSA") || name.endsWith(".DSA") || name.endsWith("MANIFEST.MF")))
                            // Don't instrument our runtime
                            || name.replace('\\','/').endsWith("/mprewriter.class");

                    JarEntry newEntry = new JarEntry(name);
                    jos.putNextEntry(newEntry);

                    if (copyRaw) {
                        jos.write(bytes);
                    } else {
                        byte[] transformed = instrumentClass(bytes);
                        jos.write(transformed);
                    }
                    jos.closeEntry();
                }

                // Append the probe index CSV as a new entry
                JarEntry indexEntry = new JarEntry("META-INF/branch-probes.csv");
                jos.putNextEntry(indexEntry);
                byte[] csv = PROBE_INDEX.toString().getBytes(StandardCharsets.UTF_8);
                jos.write(csv);
                jos.closeEntry();
            }
        }
    }

    /** Rewrites a single class to add entry + branch + handler probes with source mapping. */
    public static byte[] instrumentClass(byte[] classBytes) {
        try {
            ClassReader cr = new ClassReader(classBytes);
            ClassWriter cw = new ClassWriter(cr, ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
            ClassVisitor cv = new ClassVisitor(ASM9, cw) {
                String internalClass;
                String superInternal;
                String sourceFile;

                @Override
                public void visit(int version, int access, String name, String signature, String superName, String[] interfaces) {
                    this.internalClass = name;
                    this.superInternal = superName;
                    super.visit(version, access, name, signature, superName, interfaces);
                }

                @Override
                public void visitSource(String source, String debug) {
                    this.sourceFile = source;
                    super.visitSource(source, debug);
                }

                @Override
                public MethodVisitor visitMethod(int access, String name, String desc, String signature, String[] exceptions) {
                    MethodVisitor mv = super.visitMethod(access, name, desc, signature, exceptions);
                    if ((access & (ACC_ABSTRACT | ACC_NATIVE)) != 0) return mv;
                    return new DenseVisitor(api, mv, access, name, desc, internalClass, superInternal, sourceFile);
                }
            };
            cr.accept(cv, ClassReader.SKIP_FRAMES);
            return cw.toByteArray();
        } catch (Throwable t) {
            // On any ASM failure, return original bytes
            return classBytes;
        }
    }

    private static class DenseVisitor extends AdviceAdapter {
        private final String methodName;
        private final String internalClass;
        private final String superInternal;
        private final String prettyClass;
        private final String sourceFile;

        private final boolean isCtor;
        private boolean superDone = false;
        private boolean pendingEntry = true;

        private final Set<Label> branchTargets = Collections.newSetFromMap(new IdentityHashMap<>());
        private final Map<Label, BranchProbeInfo> conditionalTargets = new IdentityHashMap<>();
        private final Map<Label, Integer> lineAtLabel = new IdentityHashMap<>();

        // Handler label -> set of types (null means FINALLY)
        private final Map<Label, LinkedHashSet<String>> handlerTypes = new IdentityHashMap<>();
        private final Set<Label> handlerProbed = Collections.newSetFromMap(new IdentityHashMap<Label, Boolean>());

        private int currentLine = -1;
        private boolean enterEmitted = false;
        private final Label methodStart = new Label();
        private final Label methodEnd = new Label();
        private final Label handlerLabel = new Label();
        private Label tryStart = null; // start of try region (after super() for ctors)

        protected DenseVisitor(int api, MethodVisitor mv, int access, String name, String desc,
                               String internalClass, String superInternal, String sourceFile) {
            super(api, mv, access, name, desc);
            this.methodName = name;
            this.internalClass = internalClass;
            this.superInternal = superInternal;
            this.prettyClass = internalClass.replace('/', '.');
            this.sourceFile = sourceFile;
            this.isCtor = "<init>".equals(name);
        }

        @Override public void visitCode() {
            super.visitCode();
            mv.visitLabel(methodStart);
            if (!isCtor) {
                // For normal methods, begin try region at method start
                tryStart = methodStart;
            }
        }

        @Override protected void onMethodEnter() { /* delayed via visitLineNumber for ctors */ }

        @Override
        public void visitMethodInsn(int opcode, String owner, String name, String descriptor, boolean isInterface) {
            super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
            if (isCtor && opcode == INVOKESPECIAL && "<init>".equals(name)) {
                if (!superDone && superInternal != null && superInternal.equals(owner)) {
                    superDone = true;
                }
            }
        }

        @Override
        public void visitLineNumber(int line, Label start) {
            currentLine = line;
            lineAtLabel.put(start, line);
            if (pendingEntry && (!isCtor || superDone)) {
                emitEnter();
                emitProbe("METHOD_ENTRY", line);
                pendingEntry = false;
            }
            super.visitLineNumber(line, start);
        }

        @Override
        protected void onMethodExit(int opcode) {
            if (pendingEntry) { // entry not yet emitted (e.g., no line numbers); do it now
                emitEnter();
                emitProbe("METHOD_ENTRY", -1);
                pendingEntry = false;
            }
            if (enterEmitted) emitExit();
        }

        @Override
        public void visitTryCatchBlock(Label start, Label end, Label handler, String type) {
            LinkedHashSet<String> set = handlerTypes.computeIfAbsent(handler, k -> new LinkedHashSet<>());
            set.add(type); // may be null for finally
            super.visitTryCatchBlock(start, end, handler, type);
        }

        private int resolveLine(Label label) {
            Integer ln = lineAtLabel.get(label);
            return ln != null ? ln : currentLine;
        }

        private static String joinTypes(Set<String> types) {
            List<String> out = new ArrayList<>();
            for (String t : types) {
                if (t == null) continue;
                out.add(t.replace('/', '.'));
            }
            return String.join("|", out);
        }

        @Override
        public void visitLabel(Label label) {
            super.visitLabel(label);

            LinkedHashSet<String> types = handlerTypes.get(label);
            if (types != null && !handlerProbed.contains(label)) {
                int ln = resolveLine(label);
                if (types.contains(null)) {
                    emitProbe("FINALLY_ENTRY", ln);
                } else {
                    emitProbe("CATCH_ENTRY(" + joinTypes(types) + ")", ln);
                }
                handlerProbed.add(label);
            }

            BranchProbeInfo branchInfo = conditionalTargets.remove(label);
            if (branchInfo != null) {
                branchTargets.remove(label);
                int ln = resolveLine(label);
                emitProbe("IF_FALSE", ln, "E", branchInfo.opcodeName, oppositeSense(branchInfo.jumpSense));
            } else if (branchTargets.remove(label)) {
                int ln = resolveLine(label);
                emitProbe("IF_FALSE", ln);
            }
        }

        @Override
        public void visitJumpInsn(int opcode, Label label) {
            boolean isConditional =
                    (opcode >= IFEQ && opcode <= IF_ACMPNE) || opcode == IFNULL || opcode == IFNONNULL;
            super.visitJumpInsn(opcode, label);
            if (isConditional) {
                String opcodeName = opcodeName(opcode);
                String jumpSense = jumpSense(opcode);
                emitProbe("IF_TRUE", currentLine, "T", opcodeName, jumpSense);
                conditionalTargets.put(label, new BranchProbeInfo(opcodeName, jumpSense));
                branchTargets.add(label);
            } else if (opcode == GOTO) {
                branchTargets.add(label);
            }
        }

        @Override
        public void visitTableSwitchInsn(int min, int max, Label dflt, Label... labels) {
            super.visitTableSwitchInsn(min, max, dflt, labels);
            branchTargets.add(dflt);
            for (Label l : labels) branchTargets.add(l);
        }

        @Override
        public void visitLookupSwitchInsn(Label dflt, int[] keys, Label[] labels) {
            super.visitLookupSwitchInsn(dflt, keys, labels);
            branchTargets.add(dflt);
            for (Label l : labels) branchTargets.add(l);
        }

        private void emitProbe(String where, int line) {
            emitProbe(where, line, "", "", "");
        }

        private void emitProbe(String where, int line, String edge, String opcode, String sense) {
            String kind = where;
            if (where.startsWith("CATCH_ENTRY")) kind = "CATCH_ENTRY";
            if (where.startsWith("FINALLY_ENTRY")) kind = "FINALLY_ENTRY";
            if (!ALLOWED_KINDS.contains(kind)) return;
            if (line >= 0 && EXCLUSIONS.isExcluded(prettyClass, line)) return;
            if (line >= 0 && INCLUSIONS.isActive() && !INCLUSIONS.isIncluded(prettyClass, line)) return;
            int id = PROBE_COUNTER.getAndIncrement();
            // Inject call to UDP probe: hit(id) uses current depth
            mv.visitLdcInsn(id);
            mv.visitMethodInsn(INVOKESTATIC,
                    "com/trading/domain/mprewriter",
                    "hit",
                    "(I)V",
                    false);
            addIndex(id, prettyClass, methodName, where, sourceFile, line, edge, opcode, sense);
        }

        private static String jumpSense(int opcode) {
            switch (opcode) {
                case IFEQ:
                    return "-";
                case IFNE:
                case IFLT:
                case IFGE:
                case IFGT:
                case IFLE:
                case IF_ICMPEQ:
                case IF_ICMPNE:
                case IF_ICMPLT:
                case IF_ICMPGE:
                case IF_ICMPGT:
                case IF_ICMPLE:
                case IF_ACMPEQ:
                case IF_ACMPNE:
                case IFNULL:
                case IFNONNULL:
                    return "+";
                default:
                    return "";
            }
        }

        private static String oppositeSense(String sense) {
            if ("+".equals(sense)) return "-";
            if ("-".equals(sense)) return "+";
            return "";
        }

        private static String opcodeName(int opcode) {
            switch (opcode) {
                case IFEQ: return "IFEQ";
                case IFNE: return "IFNE";
                case IFLT: return "IFLT";
                case IFGE: return "IFGE";
                case IFGT: return "IFGT";
                case IFLE: return "IFLE";
                case IF_ICMPEQ: return "IF_ICMPEQ";
                case IF_ICMPNE: return "IF_ICMPNE";
                case IF_ICMPLT: return "IF_ICMPLT";
                case IF_ICMPGE: return "IF_ICMPGE";
                case IF_ICMPGT: return "IF_ICMPGT";
                case IF_ICMPLE: return "IF_ICMPLE";
                case IF_ACMPEQ: return "IF_ACMPEQ";
                case IF_ACMPNE: return "IF_ACMPNE";
                case IFNULL: return "IFNULL";
                case IFNONNULL: return "IFNONNULL";
                default: return Integer.toString(opcode);
            }
        }

        private static final class BranchProbeInfo {
            final String opcodeName;
            final String jumpSense;

            BranchProbeInfo(String opcodeName, String jumpSense) {
                this.opcodeName = opcodeName;
                this.jumpSense = jumpSense;
            }
        }

        private void emitEnter() {
            if (enterEmitted) return;
            mv.visitMethodInsn(INVOKESTATIC, "com/trading/domain/mprewriter", "scope_ENTER", "()V", false);
            enterEmitted = true;
            if (tryStart == null) {
                tryStart = new Label();
                mv.visitLabel(tryStart);
            }
        }

        private void emitExit() {
            mv.visitMethodInsn(INVOKESTATIC, "com/trading/domain/mprewriter", "scope_EXIT", "()V", false);
        }

        @Override public void visitMaxs(int maxStack, int maxLocals) {
            // Close the try region and add a catch-all to ensure EXIT on exceptions
            mv.visitLabel(methodEnd);
            if (enterEmitted && tryStart != null) {
                mv.visitTryCatchBlock(tryStart, methodEnd, handlerLabel, "java/lang/Throwable");
                mv.visitLabel(handlerLabel);
                emitExit();
                mv.visitInsn(ATHROW);
            }
            super.visitMaxs(maxStack, maxLocals);
        }
    }
    static final class ExclusionMatcher {
        private final java.util.Map<String, java.util.List<int[]>> map = new java.util.HashMap<>();
        static ExclusionMatcher fromFile(String path) {
            ExclusionMatcher m = new ExclusionMatcher();
            if (path == null || path.isEmpty()) return m;
            try {
                java.nio.file.Path p = java.nio.file.Paths.get(path);
                if (!java.nio.file.Files.exists(p)) return m;
                for (String raw : java.nio.file.Files.readAllLines(p)) {
                    String line = raw.trim();
                    if (line.isEmpty() || line.startsWith("#")) continue;
                    int idx = line.lastIndexOf(':');
                    if (idx <= 0) continue;
                    String cls = line.substring(0, idx).trim();
                    String spec = line.substring(idx+1).trim();
                    int[] range;
                    if (spec.equals("*")) {
                        range = new int[]{Integer.MIN_VALUE, Integer.MAX_VALUE};
                    } else if (spec.contains("-")) {
                        String[] parts = spec.split("-");
                        int a = Integer.parseInt(parts[0].trim());
                        int b = Integer.parseInt(parts[1].trim());
                        range = new int[]{Math.min(a,b), Math.max(a,b)};
                    } else {
                        int v = Integer.parseInt(spec);
                        range = new int[]{v, v};
                    }
                    m.map.computeIfAbsent(cls, k -> new java.util.ArrayList<>()).add(range);
                }
            } catch (Exception ignored) {}
            return m;
        }
        boolean isExcluded(String prettyClass, int line) {
            java.util.List<int[]> ranges = map.get(prettyClass);
            if (ranges == null) return false;
            for (int[] r : ranges) {
                if (line >= r[0] && line <= r[1]) return true;
            }
            return false;
        }
    }

    static final class InclusionMatcher {
        private final java.util.Map<String, java.util.List<int[]>> map = new java.util.HashMap<>();
        static InclusionMatcher fromFile(String path) {
            InclusionMatcher m = new InclusionMatcher();
            if (path == null || path.isEmpty()) return m;
            try {
                java.nio.file.Path p = java.nio.file.Paths.get(path);
                if (!java.nio.file.Files.exists(p)) return m;
                for (String raw : java.nio.file.Files.readAllLines(p)) {
                    String line = raw.trim();
                    if (line.isEmpty() || line.startsWith("#")) continue;
                    int idx = line.lastIndexOf(':');
                    if (idx <= 0) continue;
                    String cls = line.substring(0, idx).trim();
                    String spec = line.substring(idx+1).trim();
                    int[] range;
                    if (spec.equals("*")) {
                        range = new int[]{Integer.MIN_VALUE, Integer.MAX_VALUE};
                    } else if (spec.contains("-")) {
                        String[] parts = spec.split("-");
                        int a = Integer.parseInt(parts[0].trim());
                        int b = Integer.parseInt(parts[1].trim());
                        range = new int[]{Math.min(a,b), Math.max(a,b)};
                    } else {
                        int v = Integer.parseInt(spec);
                        range = new int[]{v, v};
                    }
                    m.map.computeIfAbsent(cls, k -> new java.util.ArrayList<>()).add(range);
                }
            } catch (Exception ignored) {}
            return m;
        }
        boolean isActive() { return !map.isEmpty(); }
        boolean isIncluded(String prettyClass, int line) {
            if (map.isEmpty()) return true;
            java.util.List<int[]> ranges = map.get(prettyClass);
            if (ranges == null) return false;
            for (int[] r : ranges) {
                if (line >= r[0] && line <= r[1]) return true;
            }
            return false;
        }
    }
}
