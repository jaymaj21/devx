package com.example.demo;

public class TryCatch {
    public static int div(int a, int b) {
        try {
            int r = a / b;
            System.out.println("div: " + a + " / " + b + " = " + r);
            return r;
        } catch (ArithmeticException ex) {
            System.out.println("div: caught " + ex);
            return Integer.MIN_VALUE;
        } finally {
            System.out.println("div: finally for " + a + " / " + b);
        }
    }
}
