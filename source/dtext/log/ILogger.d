/*******************************************************************************

    Base interface for Loggers implementation

    Note:
        The formatting primitives (error, info, warn...) are not part of the
        interface anymore, as they can be templated functions.

    Copyright:
        Copyright (c) 2004 Kris Bell.
        Some parts copyright (c) 2009-2016 dunnhumby Germany GmbH.
        All rights reserved.

    License:
        Tango Dual License: 3-Clause BSD License / Academic Free License v3.0.
        See LICENSE_TANGO.txt for details.

    Version: Initial release: May 2004

    Authors: Kris

*******************************************************************************/

module dtext.log.ILogger;

import core.sys.posix.strings;

version (unittest)
{
    import dtext.Test;
}


/// Ditto
interface ILogger
{
    /// Defines the level at which a message can be logged
    public enum Level : ubyte
    {
        /// The lowest level: Used for programming debug statement
        Debug,
        /// Trace messages let the user "trace" the program behavior,
        /// e.g. what function calls are made (or when they exit)
        Trace,
        /// Verbose message provide extra informations about the program
        Verbose,
        /// Informative message, this is the "default" value for the user
        Info,
        /// Warnings about potential issues
        Warn,
        /// Notify the user of a hard error
        Error,
        /// A Fatal error, which could lead to the program termination
        Fatal,
        /// No message should be output
        None,
    }

    /// List of options that can be set on a `Logger`
    /// Those are used as flags (bitwise-ORed together).
    public enum Option : uint
    {
        /// Use the `Logger` ancestors' `Appender` as well as the `Logger`'s own
        Additive       = (1 << 0),
        /// Count emitted event towards the global stats
        CollectStats   = (1 << 1),
        /// Use function names instead of logger name for `Event.name`
        FunctionOrigin = (1 << 2),
    }

    /// Internal struct to associate a `Level` with its name
    private struct Pair
    {
        /// The name associated with `value`
        string name;
        /// An `ILogger.Level` value
        Level value;
    }

    /***************************************************************************

        Poor man's SmartEnum: We don't use SmartEnum directly because
        it would change the public interface, and we accept any case anyway.

        This can be fixed when we drop D1 support.

    ***************************************************************************/

    private static immutable Pair[Level.max + 1] Pairs =
    [
        { "Debug",   Level.Debug },
        { "Trace",   Level.Trace },
        { "Verbose", Level.Verbose },
        { "Info",    Level.Info },
        { "Warn",    Level.Warn },
        { "Error",   Level.Error },
        { "Fatal",   Level.Fatal },
        { "None",    Level.None },
    ];

    /***************************************************************************

        Return the enum value associated with `name`, or a default value

        Params:
            name = Case-independent string representation of an `ILogger.Level`
                   If the name is not one of the logger, `def` is returned.
            def  = Default value to return if no match is found for `name`

        Returns:
            The `Level` value for `name`, or `def`

    ***************************************************************************/

    public static Level convert (in char[] name, Level def = Level.Trace)
    {
        foreach (field; ILogger.Pairs)
        {
            if (field.name.length == name.length
                && !strncasecmp(name.ptr, field.name.ptr, name.length))
                return field.value;
        }
        return def;
    }

    /***************************************************************************

        Return the name associated with level

        Params:
            level = The `Level` to get the name for

        Returns:
            The name associated with `level`.

    ***************************************************************************/

    public static string convert (Level level)
    {
        return ILogger.Pairs[level].name;
    }


    /***************************************************************************

        Context for a hierarchy, used for customizing behaviour of log
        hierarchies. You can use this to implement dynamic log-levels,
        based upon filtering or some other mechanism

    ***************************************************************************/

    public interface Context
    {
        /// return a label for this context
        public string label ();

        /// first arg is the setting of the logger itself, and
        /// the second arg is what kind of message we're being
        /// asked to produce
        public bool enabled (Level setting, Level target);
    }


    /***************************************************************************

        Returns:
            `true` if this logger is enabed for the specified `Level`

        Params:
            level = `Level` to test for, defaults to `Level.Fatal`.

    ***************************************************************************/

    public bool enabled (Level level = Level.Fatal);

    /***************************************************************************

        Returns:
            The name of this `ILogger` (without the appended dot).

    ***************************************************************************/

    public const(char)[] name ();


    /***************************************************************************

        Returns:
            The `Level` this `ILogger` is set to

    ***************************************************************************/

    public Level level ();

    /***************************************************************************

        Set the current `Level` for this logger (and only this logger).

        Params:
            l = New `Level` value to set this logger to.

        Returns:
            `this` for easy chaining

    ***************************************************************************/

    public ILogger level (Level l);

    /***************************************************************************

        Test whether an option is enabled or not

        Loggers support different options, listed in `LogOption`.
        This function returns whether a certain option is enabled or not.

    ***************************************************************************/

    public bool getOption (Option option) const scope @safe pure nothrow @nogc;

    /***************************************************************************

        Enable or disable a certain option

        Params:
            option = The option to enable/disable
            enabled = If `true`, enable the option, otherwise disable it
            propagate = Whether the option should be propagated to child loggers

        Returns:
            `true` if the option was previously enabled, `false` otherwise.

    ***************************************************************************/

    public bool setOption (Option option, bool enabled, bool propagate = false);

    /***************************************************************************

        Send a message to this logger.

        Params:
            level = Level at which to log the message
            exp   = Lazily evaluated message string
                    If the `level` is not enabled for this logger, it won't
                    be evaluated.
            func = Function from which the call originated

        Returns:
            `this` for easy chaining

    ***************************************************************************/

    public ILogger append (Level level, lazy const(char)[] exp, string func = __FUNCTION__);
}

unittest
{
    assert(ILogger.convert(ILogger.Level.Trace) == "Trace");
    assert(ILogger.convert(ILogger.Level.Info) == "Info");
    assert(ILogger.convert(ILogger.Level.Warn) == "Warn");
    assert(ILogger.convert(ILogger.Level.Error) == "Error");
    assert(ILogger.convert(ILogger.Level.Fatal) == "Fatal");
    assert(ILogger.convert(ILogger.Level.None) == "None");
}

unittest
{
    assert(ILogger.convert("info") == ILogger.Level.Info);
    assert(ILogger.convert("Info") == ILogger.Level.Info);
    assert(ILogger.convert("INFO") == ILogger.Level.Info);
    assert(ILogger.convert("FATAL") == ILogger.Level.Fatal);
    // Use the default value
    assert(ILogger.convert("Info!") == ILogger.Level.Trace);
    assert(ILogger.convert("Baguette", ILogger.Level.Warn) == ILogger.Level.Warn);
    // The first entry in the array
    assert(ILogger.convert("trace", ILogger.Level.Error) == ILogger.Level.Trace);
}
