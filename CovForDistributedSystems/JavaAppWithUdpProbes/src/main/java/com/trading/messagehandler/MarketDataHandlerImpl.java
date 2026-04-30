package com.trading.messagehandler;

import com.trading.domain.Quote;
import com.trading.domain.Trade;
import com.trading.domain.mprewriter;
import com.trading.service.MarketDataCalculator;
import com.trading.service.MarketDataCalculatorImpl;
import com.trading.tasks.MarketEventCalculationTask;
import com.trading.utils.WrappedLogger;

import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;

/**
  This is the implementation of the MarketDataHandler, and it is
  meant to be an application-level singleton (a "bean" perhaps).
  The single instance is supposed to be wired up with the market-data
  client/broker/queue to feed the events into our system. See
  the MarketDataHandler interface comments for further details.
 */
public class MarketDataHandlerImpl implements MarketDataHandler {
    private MarketDataCalculatorImpl calculator;
    WrappedLogger log = new WrappedLogger();

    BlockingQueue<Object> stagingQueue = new LinkedBlockingQueue<>();


   private void initCalculatorThread()
   {mprewriter.scope_START(10001);
       Thread marketEventCalculationThread = new Thread(new MarketEventCalculationTask(stagingQueue, calculator));
       marketEventCalculationThread.start();
   }

    public MarketDataHandlerImpl(MarketDataCalculatorImpl calculator) {mprewriter.scope_START(10002);
        this.calculator = calculator;
        initCalculatorThread();
    }

    /*
     mvn dependency:copy-dependencies
     java -cp "target/classes;target/dependency/*" clojure.main
(ns my-clojure-app.core
  (:import [com.trading.messagehandler MarketDataHandlerImpl]))
(println (MarketDataHandlerImpl/factorial 10))
     */
    public static int factorial(int n) {mprewriter.scope_START(10003);
       if (n <= 1) return 1;
       else return n * factorial(n - 1 );
    }
    public MarketDataHandlerImpl()  {
        this(new MarketDataCalculatorImpl());
    }

    @Override
    public void handleTradeEvent(Trade trade)
    {mprewriter.scope_START(10004);
        try {mprewriter.scope_START(10005);
            stagingQueue.put(trade);
        } catch(InterruptedException ex) {mprewriter.scope_START(10006);
            log.error("Staging queue addition interrupted for trade {0}", trade);
        }
    }

    @Override
    public void handleQuoteEvent(Quote quote)
    {mprewriter.scope_START(10007);
        try {mprewriter.scope_START(10008);
            stagingQueue.put(quote);
        } catch(InterruptedException ex) {mprewriter.scope_START(10009);
            log.error("Staging queue addition interrupted for quote {0}", quote);
        }
    }

    @Override
    public MarketDataCalculator getCalculator() {mprewriter.scope_START(10010);return calculator; };

}

