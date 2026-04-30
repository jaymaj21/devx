package com.codeanalytics;
import java.io.*;

public class ThreadSafeAppendableObjectOutputStream implements Closeable, Flushable {

    private final AppendableObjectOutputStream aoos;
    private static final Object readLock = new Object(); // separate lock for read operations
    private final Object writeLock = new Object(); // instance lock for write operations

    public ThreadSafeAppendableObjectOutputStream(OutputStream out, boolean append) throws IOException {
        this.aoos = new AppendableObjectOutputStream(out, append);
    }

    // Thread-safe serialization
    public void writeObject(Object obj) throws IOException {
        synchronized (writeLock) {
            aoos.writeObject(obj);
        }
    }

    @Override
    public void flush() throws IOException {
        synchronized (writeLock) {
            aoos.flush();
        }
    }

    @Override
    public void close() throws IOException {
        synchronized (writeLock) {
            aoos.close();
        }
    }

    // Thread-safe deserialization: Read the nth object (zero-based)
    public static Object readNthObject(String fileName, int n) throws IOException, ClassNotFoundException {
        synchronized (readLock) {
            try (ObjectInputStream ois = new ObjectInputStream(new FileInputStream(fileName))) {
                for (int i = 0; i <= n; i++) {
                    Object obj = ois.readObject();
                    if (i == n) return obj;
                }
                throw new EOFException("Object at index " + n + " not found.");
            }
        }
    }

    // Thread-safe deserialization: Read all objects into an array
    public static Object[] readAllObjects(String fileName) throws IOException, ClassNotFoundException {
        synchronized (readLock) {
            try (ObjectInputStream ois = new ObjectInputStream(new FileInputStream(fileName))) {
                ByteArrayOutputStream bos = new ByteArrayOutputStream();
                ObjectOutputStream tempOos = new ObjectOutputStream(bos);
                int count = 0;
                try {
                    while (true) {
                        Object obj = ois.readObject();
                        tempOos.writeObject(obj);
                        count++;
                    }
                } catch (EOFException ignored) {
                }
                tempOos.flush();

                // Deserialize objects back from byte array
                Object[] allObjects = new Object[count];
                try (ObjectInputStream tempOis = new ObjectInputStream(new ByteArrayInputStream(bos.toByteArray()))) {
                    for (int i = 0; i < count; i++) {
                        allObjects[i] = tempOis.readObject();
                    }
                }
                return allObjects;
            }
        }
    }
}
