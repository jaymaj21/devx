package com.trading.domain;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
/**
A Trade is (the domain object for) a trade event received from an exchange's
market data feed. It consists of the timestamp, the traded instrument's symbol,
the size of the trade, and the price at which the trade was executed. In addition.
it also contains a set of flags that provides additional information about the trade's
classification.
The flags field is obtained as a comma separated list of individual flag labels.
 */
public class Trade {
    private final long timestamp;
    private final String symbol;
    private final double price;
    private final int size;
    private final String flags;

    public Trade(long timestamp, String symbol, double price, int size, String flags) {
        this.timestamp = timestamp;
        this.symbol = symbol;
        this.price = price;
        this.size = size;
        this.flags = flags;
    }

    public long getTimestamp() {
        return timestamp;
    }

    public String getSymbol() {
        return symbol;
    }

    public double getPrice() {
        return price;
    }

    public int getSize() {
        return size;
    }

    public String getFlags() {
        return flags;
    }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        sb.append("Trade{");
        sb.append("timestamp=").append(formatTimestamp(timestamp)).append(", ");
        sb.append("symbol='").append(symbol != null ? symbol : "null").append("', ");
        sb.append("price=").append(price).append(", ");
        sb.append("size=").append(size).append(", ");
        sb.append("flags='").append(flags != null ? flags : "null").append("'");
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
