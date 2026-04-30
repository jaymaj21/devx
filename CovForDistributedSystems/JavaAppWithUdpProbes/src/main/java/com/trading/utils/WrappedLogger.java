package com.trading.utils;

import java.text.MessageFormat;
/*
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.Marker;
import org.slf4j.helpers.MessageFormatter;
*/

/**
A wrapper on the logger. It is recommended that a wrapped logger
is used instead of directly calling the logger from slf4j etc.
in order to ring-fence the references to 3rd party dependencies.
 I have commented out references to slf4j in this version.
 */
public class WrappedLogger {

    public enum LogLevel {
        TRACE(0),
        DEBUG(1),
        INFO(2),
        WARN(3),
        ERROR(4);
        private final int value;

        LogLevel(int value) {
            this.value = value;
        }

        public int getValue() {
            return value;
        }
    }

    // Logger logger;
    //public WrappedLogger(Logger logger) {// this.logger = logger;}

    private LogLevel logLevel = LogLevel.INFO;

    void setLogLevel(LogLevel logLevel)
    {
        logLevel = logLevel;
    }


    public WrappedLogger() {};

    private void writeTrace(LogLevel aLogLevel, String msg) {
        if (aLogLevel.value < logLevel.value) return;
        StackTraceElement ste = Thread.currentThread().getStackTrace()[3];
        System.out.println(ste.getFileName() + ":" + ste.getLineNumber() + ": ["+ aLogLevel.name() +"]"+ msg);
    }

    public void trace(String msg) {
        writeTrace(LogLevel.TRACE, msg);
        // this.logger.trace(msg);
    }

    public void trace(String msg, Object arg) {
        writeTrace(LogLevel.TRACE, MessageFormat.format(msg, arg));
        // this.logger.trace(msg, arg);
    }

    public void trace(String msg, Object arg1, Object arg2) {
        writeTrace(LogLevel.TRACE, MessageFormat.format(msg, arg1, arg2));
        // this.logger.trace(msg, arg1, arg2);
    }

    public void trace(String msg, Object... args) {
        writeTrace(LogLevel.TRACE, MessageFormat.format(msg, args));
        // this.logger.trace(msg, args);
    }

    public void trace(String msg, Throwable t) {
        writeTrace(LogLevel.TRACE, msg);
        // this.logger.trace(msg, t);
    }

    public void debug(String msg) {
        writeTrace(LogLevel.DEBUG,  msg);
        // this.logger.debug(msg);
    }

    public void debug(String msg, Object arg) {
        writeTrace(LogLevel.DEBUG,  MessageFormat.format(msg, arg));
        // this.logger.debug(msg, arg);
    }

    public void debug(String msg, Object arg1, Object arg2) {
        writeTrace(LogLevel.DEBUG,  MessageFormat.format(msg, arg1, arg2));
        // this.logger.debug(msg, arg1, arg2);
    }

    public void debug(String msg, Object... args) {
        writeTrace(LogLevel.DEBUG,  MessageFormat.format(msg, args));
        // this.logger.debug(msg, args);
    }

    public void debug(String msg, Throwable t) {
        writeTrace(LogLevel.DEBUG,  msg);
        // this.logger.debug(msg, t);
    }


    public void info(String msg) {
        writeTrace(LogLevel.INFO,  msg);
        // this.logger.info(msg);
    }

    public void info(String msg, Object arg) {
        writeTrace(LogLevel.INFO,  MessageFormat.format(msg, arg));
        // this.logger.info(msg, arg);
    }

    public void info(String msg, Object arg1, Object arg2) {
        writeTrace(LogLevel.INFO,  MessageFormat.format(msg, arg1, arg2));
        // this.logger.info(msg, arg1, arg2);
    }

    public void info(String msg, Object... args) {
        writeTrace(LogLevel.INFO,  MessageFormat.format(msg, args));
        // this.logger.info(msg, args);
    }

    public void info(String msg, Throwable t) {
        writeTrace(LogLevel.INFO,  msg);
        // this.logger.info(msg, t);
    }

    public void warn(String msg) {
        writeTrace(LogLevel.WARN,  msg);
        // this.logger.warn(msg);
    }

    public void warn(String msg, Object arg) {
        writeTrace(LogLevel.WARN,  MessageFormat.format(msg, arg));
        // this.logger.warn(msg, arg);
    }

    public void warn(String msg, Object arg1, Object arg2) {
        writeTrace(LogLevel.WARN,  MessageFormat.format(msg, arg1, arg2));
        // this.logger.warn(msg, arg1, arg2);
    }

    public void warn(String msg, Object... args) {
        writeTrace(LogLevel.WARN,  MessageFormat.format(msg, args));
        // this.logger.warn(msg, args);
    }

    public void warn(String msg, Throwable t) {
        writeTrace(LogLevel.WARN,  msg);
        // this.logger.warn(msg, t);
    }

    public void error(String msg) {
        writeTrace(LogLevel.ERROR,  msg);
        // this.logger.error(msg);
    }

    public void error(String msg, Object arg) {
        writeTrace(LogLevel.ERROR,  MessageFormat.format(msg, arg));
        // this.logger.error(msg, arg);
    }

    public void error(String msg, Object arg1, Object arg2) {
        writeTrace(LogLevel.ERROR,  MessageFormat.format(msg, arg1, arg2));
        // this.logger.error(msg, arg1, arg2);
    }

    public void error(String msg, Object... args) {
        writeTrace(LogLevel.ERROR,  MessageFormat.format(msg, args));
        // this.logger.error(msg, args);
    }

    public static String formatStackTrace(StackTraceElement[] stackTrace) {
        StringBuilder sb = new StringBuilder();
        for (StackTraceElement element : stackTrace) {
            sb.append("at ").append(element.toString()).append("\n");
        }
        return sb.toString();
    }

    public void error(String msg, Throwable t) {
        String fullMessage =  msg + "\n " + formatStackTrace(t.getStackTrace());
        if (t.getCause() != null) fullMessage = "\ncaused by " +
                formatStackTrace(t.getCause().getStackTrace());
        writeTrace(LogLevel.ERROR, fullMessage);
        // this.logger.error(msg, t);
    }

}

