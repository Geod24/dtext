/*******************************************************************************

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

module dtext.log.layout.LayoutDate;

import dtext.format.Formatter;
import dtext.log.Appender;
import dtext.log.Event;
import dtext.log.ILogger;

import std.datetime.systime;

/*******************************************************************************

    A layout with ISO-8601 date information prefixed to each message

*******************************************************************************/

public class LayoutDate : Appender.Layout
{
    private bool localTime;

    /***************************************************************************

        Ctor with indicator for local vs UTC time. Default is local time.

    ***************************************************************************/

    this (bool localTime = true)
    {
        this.localTime = localTime;
    }

    /***************************************************************************

        Subclasses should implement this method to perform the formatting
        of the actual message content.

    ***************************************************************************/

    public override void format (LogEvent event, scope FormatterSink dg)
    {
        const dt = (localTime) ? event.time : event.time.toUTC();

        // format date according to ISO-8601 (lightweight formatter)
        sformat(dg, "{u4}-{u2}-{u2} {u2}:{u2}:{u2},{u2} {} [{}] - {}",
            dt.year, cast(ubyte) dt.month, dt.day, dt.hour, dt.minute, dt.second,
            dt.fracSecs.split!("msecs").msecs,
            ILogger.convert(event.level), event.name, event.msg);
    }
}

unittest
{
    import dtext.Test;
    import core.time;

    char[] result = new char[](2048);
    result.length = 0;
    assumeSafeAppend(result);

    scope dg = (in char[] v) { result ~= v; };
    scope layout = new LayoutDate(false);
    LogEvent event = {
        msg: "Have you met Ted?",
        name: "Barney",
        time: SysTime.fromUnixTime(1525048962) + 420.msecs,
        level: ILogger.Level.Warn,
        host: null,
    };

    testNoAlloc(layout.format(event, dg));
    assert(result == "2018-04-30 00:42:42,420 Warn [Barney] - Have you met Ted?");
}
