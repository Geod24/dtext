/*******************************************************************************

    Logging system for applications

    The most common pattern for using this class is to have a module-global
    object and initialize it on construction:

    ---
    module superapp.main;

    import dtext.log.Logger;

    private Logger log;
    static this ()
    {
        log = Log.lookup("superapp.main");
    }

    void main (string[] args)
    {
        log.info("App started with {} arguments: {}", args.length, args);
    }
    ---

    This usage can however be problematic in complex cases, as it introduces
    a module constructor which can lead to cycles during module construction,
    hence sometimes it might be worth moving to a narrower scope
    (e.g. nesting it inside a class / struct).

    `Logger`s can be configured to output their message using a certain `Layout`
    (see `ocean.util.log.layout` package), which will define how the message
    looks like, and they can output to one or more `Appender`, which defines
    where the message is writen. Common choices are standard outputs
    (stdout / stderr), syslog, or a file.

    In order to make `Logger` common use cases more simple, and allow flexible
    usage of logger without needing to re-compile the application, a module
    to configure a hierarchy from a configuration file is available under
    `ocean.util.log.Config`.

    Copyright:
        Copyright (c) 2009-2017 dunnhumby Germany GmbH.
        All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE_BOOST.txt for details.
        Alternatively, this file may be distributed under the terms of the Tango
        3-Clause BSD License (see LICENSE_BSD.txt for details).

*******************************************************************************/

module dtext.log.Logger;

import dtext.format.Formatter;
import dtext.log.Appender;
import dtext.log.Event;
import dtext.log.Hierarchy;
import dtext.log.ILogger;

version (unittest)
{
    import dtext.Test;
}

/// Convenience alias to available log level, see `ILogger.Level`
public alias ILogger.Level Level;

/// Convenience alias
public alias LogOption = ILogger.Option;

/*******************************************************************************

    Manager for routing Logger calls to the default hierarchy. Note
    that you may have multiple hierarchies per application, but must
    access the hierarchy directly for root() and lookup() methods within
    each additional instance.

*******************************************************************************/

public struct Log
{
    alias typeof(this) This;

    /***************************************************************************

        Structure for accumulating number of log events issued.

        Note:
            this takes the logging level in account, so calls that are not
            logged because of the minimum logging level are not counted.

    ***************************************************************************/

    public struct Stats
    {
        alias typeof(this) This;

        /// Number of debug log events issued
        public uint logged_debug;

        /// Number of trace log events issued
        public uint logged_trace;

        /// Number of verbose log events issued
        public uint logged_verbose;

        /// Number of info log events issued
        public uint logged_info;

        /// Number of warn log events issued
        public uint logged_warn;

        /// Number of error log events issued
        public uint logged_error;

        /// Number of fatal log events issue
        public uint logged_fatal;

        static assert(Level.max == This.tupleof.length,
                      "Number of members doesn't match Levels");

        /***********************************************************************

            Total count of all events emitted during this period.

            Returns:
                Total count of all events emitted during this period.

        ***********************************************************************/

        public uint total ()
        {
            uint total;

            foreach (field; this.tupleof)
            {
                total += field;
            }

            return total;
        }

        /// Resets the counters
        private void reset ()
        {
            foreach (ref field; this.tupleof)
            {
                field = field.init;
            }
        }

        /***********************************************************************

            Accumulate the LogEvent into the stats.

            Params:
                event_level = level of the event that has been logged.

        ***********************************************************************/

        private void accumulate (Level event_level)
        {
            with (Level) switch (event_level)
            {
            case Debug:
                this.logged_debug++;
                break;
            case Trace:
                this.logged_trace++;
                break;
            case Verbose:
                this.logged_verbose++;
                break;
            case Info:
                this.logged_info++;
                break;
            case Warn:
                this.logged_warn++;
                break;
            case Error:
                this.logged_error++;
                break;
            case Fatal:
                this.logged_fatal++;
                break;
            case None:
                break;
            default:
                assert(false, "Non supported log level");
            }
        }
    }

    /// Stores all the existing `Logger` in a hierarchical manner
    private static Hierarchy hierarchy_;

    /// Logger stats
    private static Stats logger_stats;

    /***************************************************************************

        Return an instance of the named logger

        Names should be hierarchical in nature, using dot notation (with '.')
        to separate each name section. For example, a typical name might be
        something like "ocean.io.Stdout".

        If the logger does not currently exist, it is created and inserted into
        the hierarchy. A parent will be attached to it, which will be either
        the root logger or the closest ancestor in terms of the hierarchical
        name space.

    ***************************************************************************/

    public static Logger lookup (in char[] name)
    {
        return This.hierarchy().lookup(name);
    }

    /***************************************************************************

        Return the root Logger instance.

        This is the ancestor of all loggers and, as such, can be used to
        manipulate the entire hierarchy. For instance, setting the root 'level'
        attribute will affect all other loggers in the tree.

    ***************************************************************************/

    public static Logger root ()
    {
        return This.hierarchy().root;
    }

    /***************************************************************************

        Return (and potentially initialize) the hierarchy singleton

        Logger themselves have little knowledge about their hierarchy.
        Everything is handled by a `Hierarchy` instance, which is
        stored as a singleton in this `struct`, and for which convenient
        functions are provided.
        This function returns said singleton, and initialize it on first call.

    ***************************************************************************/

    public static Hierarchy hierarchy ()
    {
        if (This.hierarchy_ is null)
        {
            This.hierarchy_ = new Hierarchy("ocean");
        }
        return This.hierarchy_;
    }


    /***************************************************************************

        Initialize the behaviour of a basic logging hierarchy.

        Adds a StreamAppender to the root node, and sets the activity level
        to be everything enabled.

    ***************************************************************************/

    public static void defaultConfig ()
    {
        import dtext.log.AppendConsole;
        This.root.add(new AppendConsole());
    }

    /***************************************************************************

        Gets the stats of the logger system between two calls to this method.

        Returns:
            number of log events issued after last call to stats, aggregated
            per logger level

    ***************************************************************************/

    public static Stats stats ()
    {
        // Make a copy to return
        Stats s = This.logger_stats;
        This.logger_stats.reset();

        return s;
    }
}


/*******************************************************************************

    Loggers are named entities, sometimes shared, sometimes specific to
    a particular portion of code. The names are generally hierarchical in
    nature, using dot notation (with '.') to separate each named section.
    For example, a typical name might be something like "mail.send.writer"

    ---
    import dtext.log.Logger;

    auto log = Log.lookup("mail.send.writer");

    log.info("an informational message");
    log.error("an exception message: {}", exception.toString);

    // etc ...
    ---

    It is considered good form to pass a logger instance as a function or
    class-ctor argument, or to assign a new logger instance during static
    class construction. For example: if it were considered appropriate to
    have one logger instance per class, each might be constructed like so:
    ---
    module myapp.util.Transmogrifier;

    private Logger log;

    static this()
    {
        log = Log.lookup("myapp.util.Transmogrifier");
    }
    ---

    Messages passed to a Logger are assumed to be either self-contained
    or configured with "{}" notation a la `dtext.format.Formatter`:
    ---
    log.warn ("temperature is {} degrees!", 101);
    ---

    Note that an internal workspace is used to format the message, which
    is limited to 2048 bytes. Use "{.256}" truncation notation to limit
    the size of individual message components. You can also use your own
    formatting buffer:
    ---
    log.buffer(new char[](4096));

    log.warn("a very long warning: {}", someLongWarning);
    ---

    Or you can use explicit formatting:
    ---
    char[4096] buf = void;

    log.warn(log.format(buf, "a very long warning: {}", someLongWarning));
    ---

    If argument construction has some overhead which you'd like to avoid,
    you can check to see whether a logger is active or not:

    ---
    if (log.enabled(log.Warn))
        log.warn("temperature is {} degrees!", complexFunction());
    ---

    The `dtext.log` package closely follows both the API and the behaviour
    as documented at the official Log4J site, where you'll find a good tutorial.
    Those pages are hosted over:
    http://logging.apache.org/log4j/docs/documentation.html

*******************************************************************************/

public final class Logger : ILogger
{
    public alias Level.Info  Debug;     /// Shortcut to `Level` values
    public alias Level.Trace Trace;     /// Ditto
    public alias Level.Info  Verbose;   /// Ditto
    public alias Level.Info  Info;      /// Ditto
    public alias Level.Warn  Warn;      /// Ditto
    public alias Level.Error Error;     /// Ditto
    public alias Level.Fatal Fatal;     /// Ditto

    /// The hierarchy that host this logger (most likely Log.hierarchy).
    private Hierarchy       host_;
    /// Next logger in the list, maintained by Hierarchy
    package Logger          next;
    /// Parent of this logger (maintained by Hierarchy)
    package Logger          parent;
    /// List of `Appender`s this Logger emits messages to
    private Appender        appender_;
    /// Name of this logger
    private string          name_;
    /// Buffer to use for formatting. Can be `null`, see `buffer` properties
    private char[ ]         buffer_;
    /// `Level` at which this `Logger` is configured
    package Level           level_;
    /// Options enabled for this `Logger`
    package uint            options_;

    /***************************************************************************

        Construct a LoggerInstance with the specified name for the given
        hierarchy. By default, logger instances are additive and are set
        to emit all events.

        Params:
            host = Hierarchy instance that is hosting this logger
            name = name of this Logger

    ***************************************************************************/

    package this (Hierarchy host, string name) @safe pure nothrow
    {
        this.host_ = host;
        this.level_ = Level.Trace;
        this.options_ = LogOption.Additive | LogOption.CollectStats;
        this.name_ = name;
        this.buffer_ = new char[](2048);
    }

    /***************************************************************************

        Is this logger enabled for the specified Level?

        Params:
            level = Level to check for.

        Returns:
            `true` if `level` is `>=` to the current level of this `Logger`.

    ***************************************************************************/

    public bool enabled (Level level = Level.Fatal)
    {
        return this.host_.context.enabled(this.level_, level);
    }

    /***************************************************************************

        Append a message with a severity of `Level.Debug`.

        Unlike other log level, this has to be abbreviated as `debug`
        is a keyword.

        Params:
            Args = Auto-deduced format string arguments
            fmt = Format string to use.
                  See `dtext.format.Formatter` documentation for
                  more informations.
            args = Arguments to format according to `fmt`.
            func = Function from which the call originated

    ***************************************************************************/

    public void dbg (Args...) (in char[] fmt, Args args, string func = __FUNCTION__)
    {
        this.format!Args(Level.Debug, fmt, args, func);
    }

    /***************************************************************************

        Append a message with a severity of `Level.Trace`.

        Params:
            Args = Auto-deduced format string arguments
            fmt = Format string to use.
                  See `ocean.text.convert.Formatter` documentation for
                  more informations.
            args = Arguments to format according to `fmt`.
            func = Function from which the call originated

    ***************************************************************************/

    public void trace (Args...) (in char[] fmt, Args args, string func = __FUNCTION__)
    {
        this.format!Args(Level.Trace, fmt, args, func);
    }

    /***************************************************************************

        Append a message with a severity of `Level.Verbose`.

        Params:
            Args = Auto-deduced format string arguments
            fmt = Format string to use.
                  See `ocean.text.convert.Formatter` documentation for
                  more informations.
            args = Arguments to format according to `fmt`.
            func = Function from which the call originated

    ***************************************************************************/

    public void verbose (Args...) (in char[] fmt, Args args, string func = __FUNCTION__)
    {
        this.format!Args(Level.Debug, fmt, args, func);
    }

    /***************************************************************************

        Append a message with a severity of `Level.Info`.

        Params:
            Args = Auto-deduced format string arguments
            fmt = Format string to use.
                  See `ocean.text.convert.Formatter` documentation for
                  more informations.
            args = Arguments to format according to `fmt`.
            func = Function from which the call originated

    ***************************************************************************/

    public void info (Args...) (in char[] fmt, Args args, string func = __FUNCTION__)
    {
        this.format!Args(Level.Info, fmt, args, func);
    }

    /***************************************************************************

        Append a message with a severity of `Level.Warn`.

        Params:
            Args = Auto-deduced format string arguments
            fmt = Format string to use.
                  See `ocean.text.convert.Formatter` documentation for
                  more informations.
            args = Arguments to format according to `fmt`.
            func = Function from which the call originated

    ***************************************************************************/

    public void warn (Args...) (in char[] fmt, Args args, string func = __FUNCTION__)
    {
        this.format!Args(Level.Warn, fmt, args, func);
    }

    /***************************************************************************

        Append a message with a severity of `Level.Error`.

        Params:
            Args = Auto-deduced format string arguments
            fmt = Format string to use.
                  See `ocean.text.convert.Formatter` documentation for
                  more informations.
            args = Arguments to format according to `fmt`.
            func = Function from which the call originated

    ***************************************************************************/

    public void error (Args...) (in char[] fmt, Args args, string func = __FUNCTION__)
    {
        this.format!Args(Level.Error, fmt, args, func);
    }

    /***************************************************************************

        Append a message with a severity of `Level.Fatal`.

        Params:
            Args = Auto-deduced format string arguments
            fmt = Format string to use.
                  See `ocean.text.convert.Formatter` documentation for
                  more informations.
            args = Arguments to format according to `fmt`.
            func = Function from which the call originated

    ***************************************************************************/

    public void fatal (Args...) (in char[] fmt, Args args, string func = __FUNCTION__)
    {
        this.format!Args(Level.Fatal, fmt, args, func);
    }

    /***************************************************************************

        Returns:
            The name of this Logger (sans the appended dot).

    ***************************************************************************/

    public string name ()
    {
        auto i = this.name_.length;
        if (i > 0)
            --i;
        return this.name_[0 .. i];
    }

    /***************************************************************************

        Returns:
            The Level this logger is set to

    ***************************************************************************/

    public Level level ()
    {
        return this.level_;
    }

    /***************************************************************************

        Set the current level for this logger (and only this logger).

    ***************************************************************************/

    public Logger level (Level l)
    {
        return this.level(l, false);
    }

    /***************************************************************************

        Set the current level for this logger,
        and (optionally) all of its descendants.

        Params:
            level = Level to set the Logger(s) to
            propagate = If `true`, set the `level` to all of this `Logger`'s
                        descendants as well.

        Returns:
            `this`

    ***************************************************************************/

    public Logger level (Level level, bool propagate)
    {
        this.level_ = level;

        if (propagate)
        {
            this.host_.propagateLevel(this.name_, level);
        }

        return this;
    }

    /// See `ILogger.getOption`
    public override bool getOption (LogOption option)
        const scope @safe nothrow @nogc pure
    {
        return !!(this.options_ & option);
    }

    /// See `ILogger.setOption`
    public override bool setOption (LogOption option, bool enabled, bool propagate = false)
    {
        const previous = this.getOption(option);

        if (enabled)
            this.options_ |= option;
        else
            this.options_ &= ~option;

        if (propagate)
            this.host_.propagateOption(this.name_, option, enabled);

        return previous;
    }

    /***************************************************************************

        Add (another) appender to this logger.

        Appenders are each invoked for log events as they are produced.
        At most, one instance of each appender will be invoked.

        Params:
            another = Appender to add to this logger. Mustn't be `null`.

        Returns:
            `this`

    ***************************************************************************/

    public Logger add (Appender another)
    {
        assert(another !is null);
        another.next = appender_;
        this.appender_ = another;
        return this;
    }

    /***************************************************************************

        Remove all appenders from this Logger

        Returns:
            `this`

    ***************************************************************************/

    public Logger clear ()
    {
        this.appender_ = null;
        return this;
    }

    /***************************************************************************

        Returns:
            The current formatting buffer (null if none).

    ***************************************************************************/

    public char[] buffer ()
    {
        return this.buffer_;
    }

    /***************************************************************************

        Set the current formatting buffer.

        The size of the internal buffer determines the length of the string that
        can be logged.
        To avoid GC allocations during logging, and excessive memory allocation
        when user types are logged, the buffer is never resized internally.

        Params:
            buf = Buffer to use. If `null` is used, nothing will be logged.

        Returns:
            `this`

    ***************************************************************************/

    public Logger buffer (char[] buf)
    {
        buffer_ = buf;
        return this;
    }

    /***************************************************************************

        Emit a textual log message from the given string

        Params:
            level = Message severity
            exp   = Lazily evaluated string.
                    If the provided `level` is not enabled, `exp` won't be
                    evaluated at all.
            func = Function from which the call originated

        Returns:
            `this`

    ***************************************************************************/

    public Logger append (
        Level level, lazy const(char)[] exp, string func = __FUNCTION__)
        @trusted
    {
        import std.datetime.systime;

        if (this.enabled(level))
        {
            const name = this.getOption(LogOption.FunctionOrigin) ? func :
                (this.name_.length ? this.name_[0..$-1] : "root");
            auto event = LogEvent(
                level, name, this.host_, Clock.currTime(), exp);
            this.append(event);
        }
        return this;
    }

    /// Ditto
    public alias append opCall;

    /***************************************************************************

        Emit a log message

        Implementation part of the public-ly available `append` function.
        This walks through appenders and emit the message for each `Appender`
        it can be emitted for.

        Params:
            event = a `LogEvent` containing informations about the message
                    to emit.

    ***************************************************************************/

    private void append (LogEvent event)
    {
        // indicator if the event was at least once emitted to the
        // appender (to use for global stats)
        bool event_emitted;

        // combine appenders from all ancestors
        auto links = this;
        Appender.Mask masks = 0;
        do {
            auto appender = links.appender_;

            // this level have an appender?
            while (appender)
            {
                auto mask = appender.mask;

                // have we visited this appender already?
                if ((masks & mask) is 0)
                    // is appender enabled for this level?
                    if (appender.level <= event.level)
                    {
                        // append message and update mask
                        appender.append(event);
                        masks |= mask;
                        event_emitted = true;
                    }
                // process all appenders for this node
                appender = appender.next;
            }
            // process all ancestors
        } while (links.getOption(LogOption.Additive) && ((links = links.parent) !is null));

        // If the event was emitted to at least one appender, and the
        // collecting stats for this log is enabled, increment the
        // stats counters
        if (this.getOption(LogOption.CollectStats) && event_emitted)
        {
            Log.logger_stats.accumulate(event.level);
        }
    }

    /***************************************************************************

        Format and emit a textual log message from the given arguments

        The formatted string emitted will have a length up to `buffer.length`,
        which is 2048 by default.
        If no formatting argument is provided (the call has only 2 parameters,
        e.g. `format(Level.Trace, "Baguette");`), then the string will be just
        emitted to the appender(s) verbatim and won't be limited in length.

        Params:
            Args  = Auto-deduced argument list
            level = Message severity
            fmt   = Format string to use, see `ocean.text.convert.Formatter`
            args  = Arguments to format according to `fmt`.
            func  = The name of the function from which the event originated

    ***************************************************************************/

    public void format (Args...) (
        Level level, in char[] fmt, Args args, string func = __FUNCTION__) @safe
    {
        static if (Args.length == 0)
            this.append(level, fmt, func);
        else
        {
            // If the buffer has length 0 / is null, we just don't log anything
            if (this.buffer_.length)
                this.append(level, snformat(this.buffer_, fmt, args), func);
        }
    }

    /***************************************************************************

        See if the provided Logger name is a parent of this one.

        Note that each Logger name has a '.' appended to the end, such that
        name segments will not partially match.

    ***************************************************************************/

    package bool isChildOf (in char[] candidate)
        const scope @safe pure nothrow @nogc
    {
        auto len = candidate.length;

        // possible parent if length is shorter
        if (len < this.name_.length)
            // does the prefix match? Note we append a "." to each
            // (the root is a parent of everything)
            return (len == 0 || candidate == this.name_[0 .. len]);
        return false;
    }

    /***************************************************************************

        See if the provided `Logger` is a better match as a parent of this one.

        This is used to restructure the hierarchy when a new logger instance
        is introduced

    ***************************************************************************/

    package bool isCloserAncestor (in Logger other)
        const scope @safe pure nothrow @nogc
    {
        auto name = other.name_;
        if (this.isChildOf(name))
            // is this a better (longer) match than prior parent?
            if ((this.parent is null)
                || (name.length >= this.parent.name_.length))
                return true;
        return false;
    }
}


// Instantiation test for templated functions
unittest
{
    static void test ()
    {
        Logger log = Log.lookup("ocean.util.log.Logger");
        log.dbg("Souvent, pour s'amuser, les hommes d'équipage");
        log.trace("Prennent des albatros, vastes oiseaux des mers,");
        log.verbose("Qui suivent, indolents compagnons de voyage,");
        log.info("Le navire glissant sur les gouffres amers.");

        log.warn("Le Poète est semblable au prince des nuées");
        log.error("Qui hante la tempête et se rit de l'archer");
        log.fatal("Exilé sur le sol au milieu des huées,");
        log.format(Level.Fatal, "Ses ailes de géant l'empêchent de marcher.");
    }
}

// Test that argumentless format call does not shrink the output
unittest
{
    static class Buffer : Appender
    {
        public struct Event { Logger.Level level; const(char)[] message; }
        public Event[] result;

        public override Mask mask () { Mask m = 42; return m; }
        public override string name () { return "BufferAppender"; }
        public override void append (LogEvent e)
        {
            this.result ~= Event(e.level, e.msg);
        }
    }

    // Test string of 87 chars
    static immutable TestStr = "Ce qui se conçoit bien s'énonce clairement - Et les mots pour le dire arrivent aisément";
    scope appender = new Buffer();
    char[32] log_buffer;
    Logger log = new Logger(Log.hierarchy(), "dummy.");
    log.setOption(LogOption.Additive, false);
    log.add(appender).buffer(log_buffer);
    log.info("{}", TestStr);
    log.error(TestStr);
    assert(appender.result.length == 2);
    // Trimmed string
    assert(appender.result[0].level == Logger.Level.Info);
    assert(appender.result[0].message == TestStr[0 .. 32]);
    // Full string
    assert(appender.result[1].level == Logger.Level.Error);
    assert(appender.result[1].message == TestStr);
}

// Test that the logger does not allocate if the Appender does not
unittest
{
    static class StaticBuffer : Appender
    {
        public struct Event
        {
            Logger.Level level;
            string name;
            const(char)[] message;
            char[128] buffer;
        }

        private Event[7] buffers;
        private size_t index;

        public override Mask mask () { Mask m = 42; return m; }
        public override string name () { return "StaticBufferAppender"; }
        public override void append (LogEvent e)
        {
            assert(this.index < this.buffers.length);
            auto str = snformat(this.buffers[this.index].buffer, "{}", e.msg);
            this.buffers[this.index].message = str;
            this.buffers[this.index].name = e.name;
            this.buffers[this.index++].level = e.level;
        }
    }

    scope appender = new StaticBuffer;
    Logger log = new Logger(Log.hierarchy(), "dummy.");
    log.setOption(LogOption.Additive, false);
    log.add(appender);
    log.level = Level.Debug;

    testNoAlloc({
            scope obj = new Object;
            log.trace("If you can keep your head when all about you, {}",
                      "Are losing theirs and blaming it on you;");
            log.info("If you can trust yourself when all men doubt you,");
            log.warn("But make {} for their {} too;", "allowance", "doubting");
            log.error("You'll have to google for the rest I'm afraid");
            log.fatal("{} - {} - {} - {}",
                      "This is some arg fmt", 42, obj, 1337.0f);
            log.format(Logger.Level.Info, "Just some {}", "more allocation tests");
            assert(log.setOption(LogOption.FunctionOrigin, true) == false);
            log.dbg("Make sure that func forwarding works properly");
    }());

    assert(appender.buffers[0].level == Logger.Level.Trace);
    assert(appender.buffers[1].level == Logger.Level.Info);
    assert(appender.buffers[2].level == Logger.Level.Warn);
    assert(appender.buffers[3].level == Logger.Level.Error);
    assert(appender.buffers[4].level == Logger.Level.Fatal);
    assert(appender.buffers[5].level == Logger.Level.Info);
    assert(appender.buffers[6].level == Logger.Level.Debug);

    assert(appender.buffers[0].message ==
           "If you can keep your head when all about you, " ~
           "Are losing theirs and blaming it on you;");
    assert(appender.buffers[1].message ==
           "If you can trust yourself when all men doubt you,");
    assert(appender.buffers[2].message ==
           "But make allowance for their doubting too;");
    assert(appender.buffers[3].message ==
           "You'll have to google for the rest I'm afraid");
    assert(appender.buffers[4].message ==
           "This is some arg fmt - 42 - object.Object - 1337.00");
    assert(appender.buffers[5].message == "Just some more allocation tests");
    assert(appender.buffers[6].message == "Make sure that func forwarding works properly");

    // Test logger names
    foreach (idx; 0 .. 6)
        assert(appender.buffers[idx].name == "dummy");
    // Note: This test will break if the line number change, so might need to be frequently updated
    // (as the function name depends on the line of the unittest).
    assert(appender.buffers[6].name == "dtext.log.Logger.__unittest_L948_C1.__lambda_L981_C17");
}
