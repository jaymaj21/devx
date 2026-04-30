package com.trading.messagehandler;

import com.trading.domain.Quote;
import com.trading.domain.Trade;
import com.trading.service.MarketDataCalculator;

/**
The market data handler ingests events from the data channels
using the callback methods : handleTradeEvent and handleQuoteEvent
The market data handler owns a calculator that performs calculations
on the market data, whose results can be obtained by using the calculator's
output interface. The calculator can be obtained from the MarketDataHandler
using the getCalculator() method.
 */
public interface MarketDataHandler {

    // Messaging system's callback methods for ingesting events
    void handleTradeEvent(Trade trade);
    void handleQuoteEvent(Quote quote);

    // Obtains the market data calculator owned by this market data handler
    MarketDataCalculator getCalculator();
}
