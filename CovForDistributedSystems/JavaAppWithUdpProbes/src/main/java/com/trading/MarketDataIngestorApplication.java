package com.trading;

import com.trading.domain.Flag;
import com.trading.domain.Quote;
import com.trading.domain.Trade;
import com.trading.messagehandler.MarketDataHandlerImpl;

public class MarketDataIngestorApplication {
    public static void main(String[] args) {
        MarketDataHandlerImpl marketDataHandlerImpl = new MarketDataHandlerImpl();
        // Do some wiring e.g. wire up the above handler with the message broker/queue etc.
    }
}
