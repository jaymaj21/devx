package com.example.demo;

public class Service {

    public static String fizzBuzz(int n) {
        if (n % 15 == 0) return "FizzBuzz";
        if (n % 3 == 0) return "Fizz";
        if (n % 5 == 0) return "Buzz";
        return String.valueOf(n);
    }

    public static String categoryOf(int x) {
        switch (x) {
            case -1: return "minus one";
            case 0: return "zero";
            case 1: case 2: case 3: return "small";
            case 4: case 5: return "medium";
            default:
                if (x < 0) return "negative other";
                return (x % 2 == 0) ? "even large" : "odd large";
        }
    }

    public static int fib(int n) {
        if (n <= 1) return n;
        return fib(n - 1) + fib(n - 2);
    }

    public static void branchyLambda(String s) {
        if (s == null || s.isBlank()) {
            System.out.println("lambda: blank");
        } else if (s.length() < 5) {
            System.out.println("lambda: short");
        } else {
            System.out.println("lambda: ok (" + s + ")");
        }
    }
}
