package com.trading.domain;
/**
Trades are labelled by certain flags. The flags consist of
a pre-determined small set of labels that are applicable on trades.
The flags are statically defined in this enum. In particular
when a received trade message has a flag symbol that does not belong
to the predetermined set defined here, it's assigned the
UNKNOWN flag defined here.
 */
public enum Flag {
    UNKNOWN(0),
    FLAG1(1),
    FLAG2(2),
    FLAG3(3),
    FLAG4(4),
    X(5),
    Y(6),
    Z(7);

    private final int value;

    Flag(int value) {
        this.value = value;
    }

    public int getValue() {
        return value;
    }
}


