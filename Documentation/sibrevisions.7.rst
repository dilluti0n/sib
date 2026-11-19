============
sibrevisions
============

-------------------------------------------
specifying chains, ranges and names for sib
-------------------------------------------

:Manual section: 7
:Manual group: Sib Manual

SYNOPSIS
========

| *<chain-ish>*
| *<chain-ish>*\ **:**\ *<key>*
| *<range>*
| *<name>*
| *<refname>*

DESCRIPTION
===========

Sib commands take one of the arguments below. Sib resolves conversation
names itself and hands git only full ref names or object ids, so git's own
name lookup (tags, branches, remotes) never applies.

Chain-ish
---------

A *<chain-ish>* names a single chain (commit). It is *<name><suffix>*,
where *<suffix>* starts at the first of **~**, **^**, **:** or **@{**. None
of these may appear in a ref name, so the split is unambiguous. *<name>* is
resolved as follows:

**HEAD**, **@**
    HEAD.

**refs/...**
    The ref as is. Use this to reach refs outside **refs/conv/**, e.g.
    **refs/tags/v1**.

*n*, **conv/**\ *n*
    **refs/conv/**\ *n*, if it exists.

*<hex>*
    The commit whose object id starts with these 4 to 40 hex digits.

A *<name>* that is both a conversation and a commit is an error; write
**conv/**\ *n* or a longer hash. Tags and branches are never found by short
name.

*<suffix>* is passed to git as is; see **gitrevisions**\ (7). The useful
ones are **~**\ *n* (*n*\ th ancestor), **^** (parent) and **@{**\ *n*\ **}**
(*n*\ th prior value of the ref, from its reflog). A bare **@{**\ *n*\ **}**
applies to the ref HEAD follows, or to HEAD when it is detached. Since sib
commits carry no message, **^{/**\ *re*\ **}** and **:/**\ *re* never match.

A *<chain-ish>* followed by **:**\ *<key>* names the value of *<key>*
on that chain, byte for byte. The split is at the first **:** outside
**@{...}**, so a key may itself contain **:**. Only **show** takes it.

Taken by **ask -p**, **switch**, **save** (target), **log**, **show**,
**edit**, **tool pending**, **ls-chain**, **chain-trace -p**,
**chain-jsonl -p** and the values of **update-ref**.

Range
-----

A *<range>* names a list of chains. It is a *<chain-ish>*,
**^**\ *<chain-ish>* (exclude it and its ancestors), *a*\ **..**\ *b*
(ancestors of *b* that are not ancestors of *a*), or *a*\ **...**\ *b*
(ancestors of either but not both). Each side is resolved as a
*<chain-ish>*; an empty side means HEAD. Arguments starting with **-** are
passed to **git-rev-list**\ (1) as options.

Taken by **rev-list** and **rev-jsonl**.

Name
----

A *<name>* is where a conversation is, or will be, stored. *n* and
**conv/**\ *n* both mean **refs/conv/**\ *n*; a full **refs/...** name is
taken as is. HEAD is not a name, and a name may not carry a *<suffix>*.
**sib rev-parse --ref** *<name>* prints the ref.

Taken by **save**, **save -d**, **ask -t** and **switch -t**/**-f**.

Refname
-------

A *<refname>* is HEAD or a full **refs/...** name, taken literally and
checked with **git-check-ref-format**\ (1). No lookup is done.

Taken by **update-ref**, **show-ref**, **symbolic-ref** and **ls-refs** (as
a prefix).

Object id
---------

**ls-trace** and the trace argument of **chain-trace** take a hex object id
only.

Examples
--------

**sib show work~1**
    The chain before the tip of **refs/conv/work**.

**sib show HEAD~2:content**
    The content of the item two before HEAD.

**sib log work@{1}**
    The conversation as it was before the last update of **work**.

**sib rev-jsonl main..work**
    The turns on **work** that are not on **main**.

**sib show conv/3f2a**
    The conversation saved by **sib save 3f2a**. A plain **3f2a** is an
    error when a commit id also starts with it.

SEE ALSO
========

**gitrevisions**\ (7)
