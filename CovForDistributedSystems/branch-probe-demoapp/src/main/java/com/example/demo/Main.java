package com.example.demo;

public class Main {
    public static void main(String[] args) {
        System.out.println("DemoApp: start");

        // FizzBuzz style branches
        for (int i = 1; i <= 20; i++) {
            System.out.println("fizzBuzz(" + i + ") = " + Service.fizzBuzz(i));
        }

        // Switch branches
        for (int x : new int[]{-1, 0, 1, 2, 3, 4, 5, 42}) {
            System.out.println("categoryOf(" + x + ") = " + Service.categoryOf(x));
        }

        // Recursion with branches
        System.out.println("fib(6) = " + Service.fib(6));

        // Try/catch/finally branches
        TryCatch.div(10, 2);
        TryCatch.div(1, 0);

        // Lambda with branch
        Thread t = new Thread(() -> Service.branchyLambda("hello"));
        t.start();
        try { t.join(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }

        System.out.println("DemoApp: end");
    }
}
