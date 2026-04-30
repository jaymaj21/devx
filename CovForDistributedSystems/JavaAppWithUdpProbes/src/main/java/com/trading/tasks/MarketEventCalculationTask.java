package com.trading.tasks;

import com.trading.domain.Quote;
import com.trading.domain.Trade;
import com.trading.service.MarketDataCalculatorImpl;
import com.trading.utils.WrappedLogger;

import java.util.concurrent.BlockingQueue;

/**
 A separate task that runs on its own thread
that consumes events queued by the market data handler.
In order to be a fast consumer, the main thread of the
message handler just enqueues the event into a queue.
This task keeps polling that queue to perform the
calculations. This mechanism serves to de-couple
the message handling from the calculation.
 */
public class MarketEventCalculationTask implements Runnable {
    WrappedLogger log = new WrappedLogger();
    private final MarketDataCalculatorImpl calculator;
    private final BlockingQueue<Object> eventQueue;

    public MarketEventCalculationTask(BlockingQueue<Object> queue, MarketDataCalculatorImpl calculator) {
        this.eventQueue = queue;
        this.calculator = calculator;
    }

    @Override
    public void run() {
        while (true) {
            try {
                Object event = eventQueue.take();
                if (event instanceof Trade) {
                    calculator.processTrade((Trade)event);
                } else if (event instanceof Quote){
                    calculator.processQuote((Quote)event);
                }
            } catch (InterruptedException e) {
                log.error("Calculator thread interrupted");
                Thread.currentThread().interrupt();
            }
        }
    }
}