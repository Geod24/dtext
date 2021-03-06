/*******************************************************************************

    Implementation of logging appender which writes to both stdout and stderr
    based on logging level.

    Copyright:
        Copyright (c) 2009-2016 dunnhumby Germany GmbH.
        All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE_BOOST.txt for details.
        Alternatively, this file may be distributed under the terms of the Tango
        3-Clause BSD License (see LICENSE_BSD.txt for details).

*******************************************************************************/

module dtext.log.AppendStderrStdout;

import dtext.log.Appender;
import dtext.log.Event;
import dtext.log.ILogger;

import std.stdio;

/*******************************************************************************

    Appender class.

    Important properties:
        - always flushes after logging
        - warnings/errors/fatals go to stderr
        - info/traces/debug goes to stdout

    Exact log level to be treated as first "stderr" level can be configured
    via constructor.

*******************************************************************************/

public class AppendStderrStdout : Appender
{
    /***********************************************************************

        Cached mask value used by logger internals

    ***********************************************************************/

    private Mask mask_;

    /***********************************************************************

        Defines which logging Level will be used as first "error" level.

    ***********************************************************************/

    private ILogger.Level first_stderr_level;

    /***********************************************************************

        Constructor

        Params:
            first_stderr_level = LogEvent with this level and higher will
                be written to stderr. Defaults to Level.Warn
            how = optional custom layout object

    ************************************************************************/

    public this (ILogger.Level first_stderr_level = ILogger.Level.Warn,
                 Appender.Layout how = null)
    {
        this.mask_ = this.register(name);
        this.first_stderr_level = first_stderr_level;
        this.layout(how);
    }

    /***********************************************************************

        Returns:
            the fingerprint for this class

    ************************************************************************/

    final override public Mask mask ()
    {
        return this.mask_;
    }

    /***********************************************************************

        Returns:
            the name of this class

    ************************************************************************/

    override public string name ()
    {
        return this.classinfo.name;
    }

    /***********************************************************************

        Writes log event to target stream

        Params:
            event = log message + metadata

    ************************************************************************/

    final override public void append (LogEvent event)
    {
        File output = (event.level >= this.first_stderr_level)
            ? stderr : stdout;

        this.layout.format(
            event,
            (in char[] content) {
                output.write(content);
            }
        );
        output.writeln();
        output.flush;
    }
}
