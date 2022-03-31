/*******************************************************************************

    Appends to an internal buffer, overwritting earlier messages when full.

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module dtext.log.appender.Circular;

import dtext.log.Appender;
import dtext.log.Event;

import std.algorithm : min;
import std.range : Cycle, cycle, isOutputRange, takeExactly, put;

/// Ditto
public class CircularAppender (size_t BufferSize = 2^^20) : Appender
{
    /// Mask
    private Mask mask_;

    /// Used length of the buffer, only grows, up to buffer.length
    private size_t used_length;

    /// Backing store for the cyclic buffer
    private char[BufferSize] buffer;

    /// Cyclic Output range over buffer
    private Cycle!(typeof(buffer)) cyclic;

    /// Ctor
    public this ()
    {
        this.mask_ = register(name);
        this.cyclic = cycle(this.buffer);
    }

    /// Print the contents of the appender to the console
    public void print (R) (R output)
        if (isOutputRange!(R, char))
    {
        // edge-case: if the buffer isn't filled yet,
        // write from buffer index 0, not the cycle's current index
        if (this.used_length < this.buffer.length)
            output.put(this.buffer[0 .. this.used_length]);
        else
            // Create a new range to work around `const` issue:
            // https://issues.dlang.org/show_bug.cgi?id=20888
            output.put(this.cyclic[0 .. $].takeExactly(this.buffer.length));
        output.put("\n");
    }

    /// Returns: the name of this class
    public override string name ()
    {
        return this.classinfo.name;
    }

    /// Return the fingerprint for this class
    public final override Mask mask ()
    {
        return this.mask_;
    }

    /// Append an event to the buffer
    public final override void append (LogEvent event)
    {
        // add a newline only before a subsequent event is logged
        // (avoids trailing empty lines with only a newline)
        if (this.used_length > 0)
        {
            this.cyclic.put("\n");
            this.used_length++;
        }

        this.layout.format(event,
            (in char[] content)
            {
                this.cyclic.put(content);
                this.used_length = min(this.buffer.length,
                    this.used_length + content.length);
            });
    }

    ///
    public void clear ()
    {
        this.used_length = 0;
        this.cyclic = cycle(this.buffer);
    }
}

///
unittest
{
    import dtext.format.Formatter;

    static class MockLayout : Appender.Layout
    {
        /// Format the message
        public override void format (LogEvent event, scope FormatterSink dg)
        {
            sformat(dg, "{}", event.msg);
        }
    }

    scope get_log_output = (string log_msg){
        import dtext.log.ILogger;

        immutable buffer_size = 7;
        char[buffer_size + 1] result_buff;
        scope appender = new CircularAppender!(buffer_size);
        LogEvent event = {
            msg: log_msg,
        };
        appender.layout(new MockLayout());
        appender.append(event);
        appender.print(result_buff[]);
        return result_buff[0 .. min(log_msg.length, buffer_size)].dup;
    };

    // case 1
    // the internal buffer size is greater than the length of the messages
    // that we are trying to log
    assert(get_log_output("01234") == "01234");

    // case 2
    // the internal buffer size is equal to the length of the messages
    // that we are trying to log(there is a terminating newline)
    assert(get_log_output("012345") == "012345");

    // case 3
    // the internal buffer size is smaller than the length of the messages
    // that we are trying to log
    assert(get_log_output("0123456789") == "3456789");

    // Make sure we don't trip on stray format specifiers
    assert(get_log_output("Thou shalt ignore random %s in the string") == " string");

    // log a map over a range
    import std.algorithm;
    import std.range;
    assert(get_log_output(format("{}", iota(2).map!(i => i + 1))) == "[1, 2]");
}
