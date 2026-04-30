package com.trading.utils;

import com.trading.domain.Flag;
import com.trading.domain.Trade;
import com.trading.utils.WrappedLogger;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
This is a lookup structure for looking up the largest trade
for a given flag, for a single symbol. This is in effect the
same as a hash map where key is the Flag and the value is
the largest trade for the given key.
Internally it maintains a fixed sized array list for which
the number of flags is the same as the possible number of
flags. This is an optimization + interface simplification
over using a hashmap, based on the knowledge that we only
have a small predetermined number of flags.
 */
public class LargestTradePerFlagForSingleSymbol {

    WrappedLogger log = new WrappedLogger();
    private List<Trade> largestTradesByFlag;

    public LargestTradePerFlagForSingleSymbol() {
        largestTradesByFlag = Collections.synchronizedList(new ArrayList<>(Collections.nCopies(Flag.values().length, null)));
    }

    public void ingestTrade(Trade trade)
    {
        String[] flags = trade.getFlags().split(",");
        for(String flag : flags) {
            Flag flagEnum = Flag.UNKNOWN;
            try {
                flagEnum = Flag.valueOf(flag);
            } catch(IllegalArgumentException ex) {}
            finally {
                if (flagEnum == Flag.UNKNOWN) {
                    log.error("Trade {0} has an unknown flag {1}", trade, flag);
                }
                int index = flagEnum.getValue();
                Trade currentTrade = largestTradesByFlag.get(index);
                if ( currentTrade == null || currentTrade.getSize() < trade.getSize() ) {
                    largestTradesByFlag.set(index, trade);
                }
            }
        }
    }

    public Trade get(Flag flag)
    {
        return largestTradesByFlag.get(flag.getValue());
    }
}
