/*******************************************************************************

    The Logger hierarchy implementation.

    We keep a reference to each logger in a hash-table for convenient lookup
    purposes, plus keep each logger linked to the others in an ordered group.
    Ordering places shortest names at the head and longest ones at the tail,
    making the job of identifying ancestors easier in an orderly fashion.
    For example, when propagating levels across descendants it would be
    a mistake to propagate to a child before all of its ancestors were
    taken care of.

    Copyright:
        Copyright (c) 2004 Kris Bell.
        Some parts copyright (c) 2009-2016 dunnhumby Germany GmbH.
        All rights reserved.

    License:
        Tango Dual License: 3-Clause BSD License / Academic Free License v3.0.
        See LICENSE_TANGO.txt for details.

*******************************************************************************/

module dtext.log.Hierarchy;

import std.exception: assumeUnique;
import dtext.log.Logger;


/// Ditto
package class Hierarchy : Logger.Context
{
    private Logger              root_;
    private string              label_;
    private Logger.Context      context_;
    private Logger[string]      loggers;


    /***************************************************************************

        Construct a hierarchy with the given name.

    ***************************************************************************/

    this (string hlabel)
    {
        this.label_ = hlabel;

        // insert a root node; the root has an empty name
        this.root_ = new Logger(this, "");
        this.context_ = this;
    }

    /***************************************************************************

        Returns:
            The label associated with this Hierarchy

    ***************************************************************************/

    final string label ()
    {
        return this.label_;
    }

    /***************************************************************************

        Set the name of this Hierarchy

    ***************************************************************************/

    final void label (string value)
    {
        this.label_ = value;
    }

    /***************************************************************************

        Tells whether a given `level` is higher than another `test` level

    ***************************************************************************/

    final bool enabled (Logger.Level level, Logger.Level test)
    {
        return test >= level;
    }

    /***************************************************************************

        Return the diagnostic context.
        Useful for setting an override logging level.

    ***************************************************************************/

    final Logger.Context context ()
    {
        return this.context_;
    }

    /***************************************************************************

        Set the diagnostic context.

        Not usually necessary, as a default was created.
        Useful when you need to provide a different implementation,
        such as a ThreadLocal variant.

    ***************************************************************************/

    final void context (Logger.Context context)
    {
        this.context_ = context;
    }

    /***************************************************************************

        Return the root node.

    ***************************************************************************/

    final Logger root ()
    {
        return this.root_;
    }

    /***************************************************************************

        Return the instance of a Logger with the provided label.
        If the instance does not exist, it is created at this time.

        Note that an empty label is considered illegal, and will be ignored.

    ***************************************************************************/

    final Logger lookup (in char[] label)
    {
        if (!label.length)
            return null;

        return this.inject(label);
    }

    /***************************************************************************

        Traverse the set of configured loggers

    ***************************************************************************/

    final int opApply (scope int delegate(ref Logger) dg)
    {
        int ret;

        for (auto log = this.root; log; log = log.next)
            if ((ret = dg(log)) != 0)
                break;
        return ret;
    }

    /***************************************************************************

        Returns a Logger matching the provided label, inject if necessary.

        This function will create (allocate/instantiate) the Logger
        if necessary. However if the Logger already exists, it will be returned.

        Params:
          label = The label to look up

        Returns:
          A `Logger` instance matching `label`

    ***************************************************************************/

    private Logger inject (in char[] label)
    {
        // try not to allocate unless you really need to
        char[255] stack_buffer;
        char[] buffer = stack_buffer;

        if (buffer.length < label.length + 1)
            buffer.length = label.length + 1;

        buffer[0 .. label.length] = label[];
        buffer[label.length] = '.';

        auto name_ = buffer[0 .. label.length + 1];
        if (auto pinstance = name_ in this.loggers)
            return *pinstance;

        // We need a `string` for the associative array, as well as
        // the `Logger`'s constructor, so make sure we do not use
        // the stack allocated buffer.
        string name = (name_.ptr is stack_buffer.ptr) ?
            name_.idup : assumeUnique(name_);

        // Create a new logger
        auto li = new Logger(this, name);
        // insert into linked list
        this.insert(li);
        // Look for and adjust children. Don't force
        // property inheritance on existing loggers
        this.update(li);
        // Insert into map
        this.loggers[name] = li;

        return li;
    }

    /***************************************************************************

        Loggers are maintained in a sorted linked-list. The order is maintained
        such that the shortest name is at the root, and the longest at the tail.

        This is done so that updateLoggers() will always have a known
        environment to manipulate, making it much faster.

    ***************************************************************************/

    private void insert (Logger l)
    {
        Logger prev,
               curr = this.root;

        while (curr)
        {
            // insert here if the new name is shorter
            if (l.name.length < curr.name.length)
            {
                assert(prev !is null);
                l.next = prev.next;
                prev.next = l;
                return;
            }
            else
                // find best match for parent of new entry
                // and inherit relevant properties (level, etc)
                this.propagate(l, curr, true);

            // remember where insertion point should be
            prev = curr;
            curr = curr.next;
        }

        // add to tail
        prev.next = l;
    }

    /***************************************************************************

         Propagate hierarchical changes across known loggers.
         This includes changes in the hierarchy itself, and to
         the various settings of child loggers with respect to
         their parent(s).

    ***************************************************************************/

    private void update (Logger changed, bool force = false)
    {
        foreach (logger; this)
            this.propagate(logger, changed, force);
    }

    /***************************************************************************

         Propagates the `Level` to all child loggers.

         Params:
            parent = Name of the parent logger
            value = New `Level` value to apply

    ***************************************************************************/

    package void propagateLevel (string parent, Logger.Level value)
    {
        foreach (log; this)
        {
            if (log.isChildOf(parent))
            {
                log.level_ = value;
            }
        }
    }

    /***************************************************************************

         Propagates the property to all child loggers.

         Params:
            parent = Name of the parent logger
            option = Option to set
            value = Value to set `option` to

    ***************************************************************************/

    package void propagateOption (string parent, LogOption option, bool value)
    {
        foreach (log; this)
        {
            if (log.isChildOf(parent))
            {
                if (value)
                    log.options_ |= option;
                else
                    log.options_ &= ~option;
            }
        }
    }

    /***************************************************************************

        Propagate changes in the hierarchy downward to child Loggers.
        Note that while 'parent' is always changed, the adjustment of
        'level' is selectable.

    ***************************************************************************/

    private void propagate (Logger logger, Logger changed, bool force = false)
    {
        // is the changed instance a better match for our parent?
        if (logger.isCloserAncestor(changed))
        {
            // update parent (might actually be current parent)
            logger.parent = changed;

            // if we don't have an explicit level set, inherit it
            // Be careful to avoid recursion, or other overhead
            if (force)
            {
                logger.level_ = changed.level;
                logger.options_ = changed.options_;
            }
        }
    }
}
