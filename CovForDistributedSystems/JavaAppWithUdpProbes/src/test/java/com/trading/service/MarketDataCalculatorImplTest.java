package com.trading.service;

import com.trading.domain.Flag;
import com.trading.domain.Quote;
import com.trading.domain.Trade;
import com.trading.domain.mprewriter;
import com.trading.service.MarketDataCalculatorImpl;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class MarketDataCalculatorImplTest {
    @AfterAll
    public static void afterAll()
    {

    }
    @Test
    public void testLargestTrade() {
        mprewriter.add_context_from_callstack();
        MarketDataCalculatorImpl calculator = new MarketDataCalculatorImpl();
        calculator.processTrade(new Trade(System.currentTimeMillis(), "AAPL", 150.5, 100, "X,Y"));
        calculator.processTrade(new Trade(System.currentTimeMillis(), "AAPL", 151.0, 200, "X,Y"));
        calculator.processTrade(new Trade(System.currentTimeMillis(), "AAPL", 152.0, 500, "Y"));

        Trade largestTradeX = calculator.getLargestTrade("AAPL", Flag.X);
        assertNotNull(largestTradeX);
        assertEquals(200, largestTradeX.getSize());

        Trade largestTradeY = calculator.getLargestTrade("AAPL", Flag.Y);
        assertNotNull(largestTradeY);
        assertEquals(500, largestTradeY.getSize());

        Trade largestTradeFLAG1 = calculator.getLargestTrade("AAPL", Flag.FLAG1);
        assertNull(largestTradeFLAG1);

        Trade largestTradeUNKNOWN = calculator.getLargestTrade("AAPL", Flag.UNKNOWN);
        assertNull(largestTradeUNKNOWN);
    }

    @Test
    public void testLargestTradeWhileIngestingInvalidFlag() {
        mprewriter.add_context_from_callstack();
        MarketDataCalculatorImpl calculator = new MarketDataCalculatorImpl();
        calculator.processTrade(new Trade(System.currentTimeMillis(), "AAPL", 150.5, 100, "X,Y,W"));
        calculator.processTrade(new Trade(System.currentTimeMillis(), "AAPL", 151.0, 200, "X,Y"));
        calculator.processTrade(new Trade(System.currentTimeMillis(), "AAPL", 152.0, 500, "Y"));


        Trade largestTradeUNKNOWN = calculator.getLargestTrade("AAPL", Flag.UNKNOWN);
        assertNotNull(largestTradeUNKNOWN);
        assertEquals(100, largestTradeUNKNOWN.getSize());
    }

    @Test
    public void testLargestTradeWhileIngestingTwoInvalidFlags() {
        mprewriter.add_context_from_callstack();
        MarketDataCalculatorImpl calculator = new MarketDataCalculatorImpl();
        calculator.processTrade(new Trade(System.currentTimeMillis(), "AAPL", 150.5, 100, "X,Y,W"));
        calculator.processTrade(new Trade(System.currentTimeMillis(), "AAPL", 151.0, 200, "X,Y,Q"));
        calculator.processTrade(new Trade(System.currentTimeMillis(), "AAPL", 152.0, 500, "Y"));


        Trade largestTradeUNKNOWN = calculator.getLargestTrade("AAPL", Flag.UNKNOWN);
        assertNotNull(largestTradeUNKNOWN);
        assertEquals(200, largestTradeUNKNOWN.getSize());
    }

    @Test
    public void testLargestTradeForAbsentSymbol() {
        mprewriter.add_context_from_callstack();
        MarketDataCalculatorImpl calculator = new MarketDataCalculatorImpl();
        calculator.processTrade(new Trade(System.currentTimeMillis(), "AAPL", 150.5, 100, "X,Y,W"));
        calculator.processTrade(new Trade(System.currentTimeMillis(), "AAPL", 151.0, 200, "X,Y,Q"));
        calculator.processTrade(new Trade(System.currentTimeMillis(), "AAPL", 152.0, 500, "Y"));


        Trade largestTradeAbsentSymbol = calculator.getLargestTrade("GOOG", Flag.X);
        assertNull(largestTradeAbsentSymbol);
    }

    @Test
    public void testMidPrice() {
        mprewriter.add_context_from_callstack();
        MarketDataCalculatorImpl calculator = new MarketDataCalculatorImpl();
        calculator.processQuote(new Quote(System.currentTimeMillis(), "AAPL", 149.5, 500, 151.5, 300));

        Double midPrice = calculator.getMidPrice("AAPL");
        assertNotNull(midPrice);
        assertEquals(150.5, midPrice, 0.001);
    }

    @Test
    public void testMidPriceOnAbsentSymbol() {
        mprewriter.add_context_from_callstack();
        MarketDataCalculatorImpl calculator = new MarketDataCalculatorImpl();
        calculator.processQuote(new Quote(System.currentTimeMillis(), "AAPL", 149.5, 500, 151.5, 300));

        Double midPrice = calculator.getMidPrice("GOOG");
        assertNull(midPrice);
    }
}
