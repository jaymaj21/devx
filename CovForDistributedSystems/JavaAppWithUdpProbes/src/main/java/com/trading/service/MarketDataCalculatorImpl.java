package com.trading.service;

import com.trading.domain.Flag;
import com.trading.domain.mprewriter;
import com.trading.utils.LargestTradePerFlagForSingleSymbol;
import com.trading.domain.Quote;
import com.trading.domain.Trade;
import com.trading.utils.WrappedLogger;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 Implementation of the MarketDataCalculator interface.
 It stores :
 (A) a hashmap from symbols mapping to the latest quote for the symbol. The key is the symbol (a String) and the value is the latest Quote
 (B) a hashmap from symbols mapping to a lookup table of the largest trade grouped per flag, for that symbol. The key is the symbol (a String) and the value is the said lookup table (a LargestTradePerFlagForSingleSymbol)
 When it processes a quote or a trade, it just updates the above two hashmaps.
 */
public class MarketDataCalculatorImpl implements  MarketDataCalculator {

    static WrappedLogger log = new WrappedLogger();
    private final Map<String, LargestTradePerFlagForSingleSymbol> largestTradesByTag;

    private final Map<String, Quote> latestQuotes;

    public MarketDataCalculatorImpl() {mprewriter.scope_START(20001);
        largestTradesByTag = new ConcurrentHashMap<>();
        latestQuotes = new ConcurrentHashMap<>();
    }

    public void processTrade(Trade trade) {mprewriter.scope_START(20002);
        log.info("Processing trade {0}", trade);
        LargestTradePerFlagForSingleSymbol tradesByFlagForSymbol = largestTradesByTag.getOrDefault(trade.getSymbol(), null);
        if (tradesByFlagForSymbol ==null) {mprewriter.scope_START(20003);
            tradesByFlagForSymbol = new LargestTradePerFlagForSingleSymbol();
            largestTradesByTag.put(trade.getSymbol(), tradesByFlagForSymbol);
        }
        tradesByFlagForSymbol.ingestTrade(trade);
    }

    public void processQuote(Quote quote) {mprewriter.scope_START(20004);
        log.info("Processing quote {0}", quote);
        latestQuotes.put(quote.getSymbol(), quote);
    }

    @Override
    public Trade getLargestTrade(String symbol, Flag flag) {mprewriter.scope_START(20005);
        LargestTradePerFlagForSingleSymbol largestTradeForSingleSymbol = largestTradesByTag.getOrDefault(symbol, null);
        if (largestTradeForSingleSymbol == null) {mprewriter.scope_START(20006);
            return null;
        }
        return largestTradeForSingleSymbol.get(flag);
    }

    @Override
    public Double getMidPrice(String symbol) {mprewriter.scope_START(20007);
        Quote quote = latestQuotes.get(symbol);
        if (quote == null) return null;
        return quote.getMidPrice();
    }
}

