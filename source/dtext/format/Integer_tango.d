/*******************************************************************************

    A set of functions for converting between string and integer
    values.

    Applying the D "import alias" mechanism to this module is highly
    recommended, in order to limit namespace pollution:
    ---
    import Integer = ocean.text.convert.Integer_tango;

    auto i = Integer.parse ("32767");
    ---

    Copyright:
        Copyright (c) 2004 Kris Bell.
        Some parts copyright (c) 2009-2016 dunnhumby Germany GmbH.
        All rights reserved.

    License:
        Tango Dual License: 3-Clause BSD License / Academic Free License v3.0.
        See LICENSE_TANGO.txt for details.

    Version: Initial release: Nov 2005

    Authors: Kris

 *******************************************************************************/

module dtext.format.Integer_tango;

import std.traits;

/*******************************************************************************

  Supports format specifications via an array, where format follows
  the notation given below:
  ---
  type width prefix
  ---

  Type is one of [d, g, u, b, x, o] or uppercase equivalent, and
  dictates the conversion radix or other semantics.

  Width is optional and indicates a minimum width for zero-padding,
  while the optional prefix is one of ['#', ' ', '+'] and indicates
  what variety of prefix should be placed in the output. e.g.
  ---
  "d"     => integer
  "u"     => unsigned
  "o"     => octal
  "b"     => binary
  "x"     => hexadecimal
  "X"     => hexadecimal uppercase

  "d+"    => integer prefixed with "+"
  "b#"    => binary prefixed with "0b"
  "x#"    => hexadecimal prefixed with "0x"
  "X#"    => hexadecimal prefixed with "0X"

  "d8"    => decimal padded to 8 places as required
  "b8"    => binary padded to 8 places as required
  "b8#"   => binary padded to 8 places and prefixed with "0b"
  ---

  Note that the specified width is exclusive of the prefix, though
  the width padding will be shrunk as necessary in order to ensure
  a requested prefix can be inserted into the provided output.

 *******************************************************************************/

const(char)[] format(N) (char[] dst, N i_, in char[] fmt)
{
    char    pre;
    int     width;

    assert(fmt.length > 0);

    const char type = fmt[0];
    if (fmt.length > 1)
    {
        auto p = &fmt[1];
        for (int j=1; j < fmt.length; ++j, ++p)
        {
            if (*p >= '0' && *p <= '9')
                width = width * 10 + (*p - '0');
            else
                pre = *p;
        }
    }

    ulong i;
    FormatStyle index;

    if (!dst.length)
        return "{output width too small}";

    bool usePrefix = (pre is '#');
    switch (type)
    {
        case 'd':
        case 'D':
        case 'g':
        case 'G':
            if (i_ < 0)
                index = FormatStyle.NegativeB10;
            else if (pre is ' ')
                index = FormatStyle.JustifiedB10;
            else if (pre is '+')
                index = FormatStyle.PositiveB10;
            /// Otherwise, keep `FormatStyle.DefaultB10`
            i = i_ >= 0 ? i_ : -i_;
            usePrefix = true;
            break;

        case 'u':
        case 'U':
            i = reinterpretInteger!(ulong)(i_);
            usePrefix = true;
            break;

        case 'b':
        case 'B':
            index = FormatStyle.Binary;
            i = reinterpretInteger!(ulong)(i_);
            break;

        case 'o':
        case 'O':
            index = FormatStyle.Octal;
            i = reinterpretInteger!(ulong)(i_);
            break;

        case 'x':
            index = FormatStyle.LowercaseB16;
            i = reinterpretInteger!(ulong)(i_);
            break;

        case 'X':
            index = FormatStyle.UppercaseB16;
            i = reinterpretInteger!(ulong)(i_);
            break;

        default:
            immutable mlen = "{unknown format 'X'}".length;
            if (dst.length < mlen)
                return "{unknown format}";
            dst[0 .. mlen - 3] = "{unknown format '";
            dst[mlen - 3] = type;
            dst[mlen - 2 .. mlen] = "'}";
            return dst;
    }
    return formatInternal(dst, i, Styles[index].fill(usePrefix, width));
}

private const(char)[] formatInternal (char[] dst, ulong i, in FormatterInfo info)
    @trusted pure nothrow @nogc
{
    // convert number to text
    int len = cast(int) dst.length;
    auto p = dst.ptr + len;

    do
        *--p = info.numbers[i % info.radix];
    while ((i /= info.radix) && --len);

    if (len > info.prefix.length)
    {
        len -= info.prefix.length + 1;

        // prefix number with zeros?
        if (info.width)
        {
            auto width = cast(int) (dst.length - info.width - info.prefix.length);
            while (len > width && len > 0)
            {
                *--p = '0';
                --len;
            }
        }
        // write optional prefix string ...
        dst[len .. len + info.prefix.length] = info.prefix;

        // return slice of provided output buffer
        return dst[len .. $];
    }

    return "{output width too small}";
}

/*******************************************************************************

    Truncates or zero-extend a value of type `From` to fit into `To`.

    Getting the same binary representation of a number in a larger type can be
    quite tedious, especially when it comes to negative numbers.
    For example, turning `byte(-1)` into `long` or `ulong` gives different
    result.
    This functions allows to get the same exact binary representation of an
    integral type into another. If the representation is truncating, it is
    just a cast. If it is widening, it zero extends `val`.

    Params:
        To      = Type to convert to
        From    = Type to convert from. If not specified, it is infered from
                  val, so it will be an `int` when passing a literal.
        val     = Value to reinterpret

    Returns:
        Binary representation of `val` typed as `To`

*******************************************************************************/

private To reinterpretInteger (To, From) (From val)
{
    static if (From.sizeof >= To.sizeof)
        return cast(To) val;
    else
    {
        static struct Reinterpreter
        {
            version (LittleEndian) From value;
            // 0 padding
            ubyte[To.sizeof - From.sizeof] pad;
            version (BigEndian) From value;
        }

        Reinterpreter r = { value: val };
        return *(cast(To*) &r.value);
    }
}

private struct FormatterInfo
{
    const(char)[] prefix;
    const(char)[] numbers;
    int           width;
    byte          radix;

    ///
    private FormatterInfo fill (bool usePrefix, int width)
        const scope @safe pure nothrow @nogc
    {
        return FormatterInfo(usePrefix ? this.prefix : null,
                             this.numbers, width, this.radix);
    }
}

///
public enum FormatStyle
{
    /// Positive base 10 number
    DefaultB10,
    /// Negative base 10 number
    NegativeB10,
    /// Base 10 with optionally spaces before it to match a width
    JustifiedB10,
    // Base 10 with an explicit '+' in front
    PositiveB10,
    /// Binary representation (0..1)
    Binary,
    /// Octal representation (0..7)
    Octal,
    /// Lowercase hexadecimal representation (0...f)
    LowercaseB16,
    /// Uppercase hexadecimal representation (0...F)
    UppercaseB16,
}

private immutable FormatterInfo[FormatStyle.max + 1] Styles = [
    FormatStyle.DefaultB10:   { null, Lower, 0, 10, },
    FormatStyle.NegativeB10:  { "-" , Lower, 0, 10, },
    FormatStyle.JustifiedB10: { " " , Lower, 0, 10, },
    FormatStyle.PositiveB10:  { "+" , Lower, 0, 10, },
    FormatStyle.Binary:       { "0b", Lower, 0,  2, },
    FormatStyle.Octal:        { "0o", Lower, 0,  8, },
    FormatStyle.LowercaseB16: { "0x", Lower, 0, 16, },
    FormatStyle.UppercaseB16: { "0X", Upper, 0, 16, },
];

private immutable string Lower = "0123456789abcdef";
private immutable string Upper = "0123456789ABCDEF";
