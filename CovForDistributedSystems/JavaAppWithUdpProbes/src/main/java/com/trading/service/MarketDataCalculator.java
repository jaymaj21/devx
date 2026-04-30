package com.trading.service;

import com.trading.domain.Flag;
import com.trading.domain.Quote;
import com.trading.domain.Trade;

/**
 Interface to the calculator used by the market data handler.
 The calculator has input methods to feed the events to the calculator
 and output methods to obtain the results of the calculations so far.
 There is a bit of dilemma on whether to make the input methods a part
 of the calculator's public interface (because the calculator after
 all is owned by the market data handler, and feeds its data internally,
 so the outer layer only ever should call the output methods.
 On the other hand there may be some value in terms of encouraging reuse
 outside the use-case of the event handler.
 */
public interface MarketDataCalculator {

    // Input methods : i.e. methods to feed events into the calculator
    void processTrade(Trade trade);
    void processQuote(Quote quote);

    // Output methods : i.e. methods to obtain results of calculation
    Trade getLargestTrade(String symbol, Flag flag);
    Double getMidPrice(String symbol);
}
