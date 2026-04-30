package com.trading.domain;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
/**
A Quote is (the domain object for) a quote event received from an exchange's
market data feed. It consists of the timestamp, bid/ask sizes, and ask/bid prices,
for a given symbol.
Quotes are issued by market makers who provide liquidity to the exchange, as the
indicative prices and sizes at which the market maker is happy to match an order.
Depending on the exchange, the quotes either execute directly against
orders, or serve as indicative information for subsequent orders.
 */
public class Quote {
    private final long timestamp;
    private final String symbol;
    private final double bidPrice;
    private final int bidSize;
    private final double askPrice;
    private final int askSize;

    public Quote(long timestamp, String symbol, double bidPrice, int bidSize, double askPrice, int askSize) {
        this.timestamp = timestamp;
        this.symbol = symbol;
        this.bidPrice = bidPrice;
        this.bidSize = bidSize;
        this.askPrice = askPrice;
        this.askSize = askSize;
    }

    public long getTimestamp() {
        return timestamp;
    }

    public String getSymbol() {
        return symbol;
    }

    public double getBidPrice() {
        return bidPrice;
    }

    public int getBidSize() {
        return bidSize;
    }

    public double getAskPrice() {
        return askPrice;
    }

    public int getAskSize() {
        return askSize;
    }

    public double getMidPrice()
    {
        return (getAskPrice() + getBidPrice())/2.0;
    }


    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        sb.append("Quote{");
        sb.append("timestamp=").append(formatTimestamp(timestamp)).append(", ");
        sb.append("symbol='").append(symbol != null ? symbol : "null").append("', ");
        sb.append("bidPrice=").append(bidPrice).append(", ");
        sb.append("bidSize=").append(bidSize).append(", ");
        sb.append("askPrice=").append(askPrice).append(", ");
        sb.append("askSize=").append(askSize).append(", ");
        sb.append("midPrice=").append(getMidPrice());
        sb.append('}');
        return sb.toString();
    }

    private String formatTimestamp(long timestamp) {
        Instant instant = Instant.ofEpochMilli(timestamp);
        LocalDateTime dateTime = LocalDateTime.ofInstant(instant, ZoneId.systemDefault());
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSSSSS");
        return dateTime.format(formatter);
    }
}
