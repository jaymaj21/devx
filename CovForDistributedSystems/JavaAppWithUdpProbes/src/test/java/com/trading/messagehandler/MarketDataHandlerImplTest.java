package com.trading.messagehandler;

import com.trading.domain.Flag;
import com.trading.domain.Quote;
import com.trading.domain.Trade;
import com.trading.domain.mprewriter;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class MarketDataHandlerImplTest {

    @Test
    void handleSomeEventsAndAssertOnCalculatorResult() throws InterruptedException
    {
        mprewriter.add_context_from_callstack();
        MarketDataHandlerImpl marketDataHandlerImpl = new MarketDataHandlerImpl();

        // Send some events to the market data handler
        marketDataHandlerImpl.handleTradeEvent(new Trade(System.currentTimeMillis(), "AAPL", 150.5, 100, "X,Y,Z"));
        marketDataHandlerImpl.handleTradeEvent(new Trade(System.currentTimeMillis(), "AAPL", 151.0, 200, "X,P"));
        marketDataHandlerImpl.handleTradeEvent(new Trade(System.currentTimeMillis(), "AAPL", 152.0, 500, "Y,Q"));
        marketDataHandlerImpl.handleQuoteEvent(new Quote(System.currentTimeMillis(), "AAPL", 149.5, 300, 151.5, 300));
        marketDataHandlerImpl.handleTradeEvent(new Trade(System.currentTimeMillis(), "META", 700.0, 50, "X,Y,Z"));
        marketDataHandlerImpl.handleTradeEvent(new Trade(System.currentTimeMillis(), "META", 701.0, 100, "X,P"));
        marketDataHandlerImpl.handleTradeEvent(new Trade(System.currentTimeMillis(), "META", 702.0, 255, "Y,Q"));
        marketDataHandlerImpl.handleQuoteEvent(new Quote(System.currentTimeMillis(), "META", 702.5, 400, 705.5, 300));

        Thread.sleep(1000);

        // Assert on some largest trade values
        Trade largestTradeAAPL_X = marketDataHandlerImpl.getCalculator().getLargestTrade("AAPL", Flag.X);
        assertNotNull(largestTradeAAPL_X);
        assert(largestTradeAAPL_X.getSize() == 200);

        Trade largestTradeAAPL_Y = marketDataHandlerImpl.getCalculator().getLargestTrade("AAPL", Flag.Y);
        assertNotNull(largestTradeAAPL_Y);
        assert(largestTradeAAPL_Y.getSize() == 500);

        Trade largestTradeMETA_X = marketDataHandlerImpl.getCalculator().getLargestTrade("META", Flag.X);
        assertNotNull(largestTradeMETA_X);
        assert(largestTradeMETA_X.getSize() == 100);

        Trade largestTradeMETA_Y = marketDataHandlerImpl.getCalculator().getLargestTrade("META", Flag.Y);
        assertNotNull(largestTradeMETA_Y);
        assert(largestTradeMETA_Y.getSize() == 255);


        // Assert on some quote mids
        Double midPriceAAPL = marketDataHandlerImpl.getCalculator().getMidPrice("AAPL");
        assertNotNull(midPriceAAPL);
        assertEquals(150.5, midPriceAAPL, 0.0001);

        Double midPriceMETA = marketDataHandlerImpl.getCalculator().getMidPrice("META");
        assertNotNull(midPriceMETA);
        assertEquals(704, midPriceMETA, 0.0001);

        // Assert on absent values

        // Absent symbol
        Trade largestTradeGOOG_Y = marketDataHandlerImpl.getCalculator().getLargestTrade("GOOG", Flag.Y);
        assertNull(largestTradeGOOG_Y);

        // Symbol present but not the flag
        Trade largestTradeMETA_FLAG1 = marketDataHandlerImpl.getCalculator().getLargestTrade("META", Flag.FLAG1);
        assertNull(largestTradeMETA_FLAG1);

        // Absent symbol
        Double midPriceGOOG = marketDataHandlerImpl.getCalculator().getMidPrice("GOOG");
        assertNull(midPriceGOOG);

    }

}