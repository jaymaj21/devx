package com.trading.domain;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class mprewriterTest {

    @BeforeEach
    void setUp() {
    }

    @AfterEach
    void tearDown() {
    }

    @Test
    void scope_START() {
        mprewriter.scope_START(101);
    }

    @Test
    void log() {
        String shortLogMsg = "this is a short log message.";
        mprewriter.log(shortLogMsg);
        String longLogMsg = "this is a long log message.";
        for(int i = 0 ; i < 7; ++i) {
            longLogMsg += longLogMsg;
        }
        mprewriter.log(longLogMsg);
    }


}