# -*- nim -*-
#
# $Id$
#
# Jordan Hrycaj <jordan@mjh-it.com>
#

import
  algorithm, os, sequtils, strformat, strutils, tables, tmplpro/tmplpro

const
  noisy {.intdefine.}: int = 0
  isNoisy = noisy > 0
when isNoisy:
  discard

iterator envItems(p: TmplParser): TmplParser {.closure.} =
  ## Parser filter loop over environment values
  var
    # stop after more than this many entries
    maxCount = 10
    count = 0
  for k in envPairs.toSeq.mapIt(it.key.string).sorted:
    count.inc
    var
      num = ("@COUNT@", $count)
      key = ("@KEY@", "")
      value = ("@VALUE@", "")
    if count <= maxCount:
      # collect @KEY@/@VALUE@ pair
      key[1] = k
      value[1] = k.getEnv.string
      # prettify empty string
      if value[1] == "":
        value[1] =  "** n/a **"
    elif count == maxCount + 1:
      # indicate that there is more to come
      key[1] = "..."
      value[1] = "..."
    else:
      break
    yield (p.filter, @[num, key, value].concat(p.vars))


proc newSpecs(): TmplParser =
  ## Constructor for new test parser definitions
  result = (newTmplFilter(), newSeq[(string,string)]())

  # Define some global variables
  result.vars.add(("@GLOBAL@", "GLOBAL variable"))
  result.vars.add(("@OTHER@", "OTHER variable"))
  result.vars.add(("@TITLE@", "Hello World"))

  # Simple if/else clauses
  result.filter["IF_ENABLED"] = toIfElse(true)
  result.filter["IF_DISABLED"] = toIfElse(false)

  # Loop clause
  result.filter["FOR_ENV"] = envItems.toIfElse(result)


var
  inPage = """
Template parser test

Global variables:
 +++ VARIABLE-@GLOBAL@.                              -- substituted
 +++ VARIABLE-@OTHER@.                               -- substituted
 +++ VARIABLE-@UNDEFINED@.                           -- remains as-is

Simple if/else clauses:
;
; COMMENT avoid.
;
; --- :IF_ENABLED:, no nesting ---
;
:IF_ENABLED:
 +++ IF-ENABLED required.                            -- enabled
 :STOP:
 +++ IF-ENABLED-STOP avoid.
:END:
:IF_ENABLED:
 +++ IF-ELSE-ENABLED required.                       -- enabled
 :STOP:
 +++ IF-ELSE-ENABLED-STOP avoid.
:ELSE:
 +++ IF-ELSE-ENABLED avoid.
 :STOP:
 +++ IF-ELSE-ENABLED-STOP avoid.
:END:
:IF_NOT_ENABLED:
 +++ IF-NOT-ENABLED avoid.
:END:
:IF_NOT_ENABLED:
 +++ IF-NOT-ELSE-ENABLED avoid.
:ELSE:
 +++ IF-NOT-ELSE-ENABLED required.                   -- enabled
:END:
;
; --- :IF_DISABLED:, no nesting ---
;
:IF_DISABLED:
 +++ IF-DISABLED avoid.
:END:
:IF_DISABLED:
 +++ IF-ELSE-DISABLED avoid.
:ELSE:
 +++ IF-ELSE-DISABLED required.                      -- enabled
:END:

Nested if/else clauses:
;
; --- mixed :IF_ENABLED:, :IF_DISABLED: with nesting ---
;
:STASH:
IF-ENABLED-DISABLED
:END:
;
:IF_ENABLED:
:IF_DISABLED:
  +++ IF-ENABLED-DISABLED avoid.
:ELSE:
  +++ @STASHED@ required.                            -- enabled
  :STASH:
    IF-ENABLED-DISABLED2
  :END:
  :IF_NOT_ENABLED:
     +++ IF-ENABLED-DISABLED-NOT-ENABLED avoid.
  :ELSE:
     +++ IF-ENABLED-DISABLED-NOT-ENABLED required.   -- enabled
     :STOP:
     +++ IF-ENABLED-DISABLED-NOT-ENABLED-STOP avoid.
  :END:
  +++ @STASHED@ required.                            -- enabled
:END:
  +++ IF-ENABLED2 required.                          -- enabled
:END:
;
+++ bottom level cache: @STASHED@-STASH required.      -- check

Loop over environment:
:STASH:
@KEY@ = @VALUE@
:END:
:FOR_ENV:
:IF_DISABLED:
   +++ FOR-ENV-DISABLED avoid.
:ELSE:
   ENV@COUNT@: @KEY@ = @VALUE@
:END:
:STOP:
+++ FOR-ENV avoid.
:END:

Syntax errors:
:END:                                                  -- wrong, error
:ELSE:                                                 -- wrong, error

:STASH:
:ELSE:                                               -- error not shown yet
:END:
STASHED @STASHED@                                      -- check error message

Stash clause behavior:
;
; there is processing of embedded clauses, all is taken literally
;
:STASH:
:STASH:
   +++ STASH-STASH required.
:END:
:STOP:
+++ STASH-STOP required.
:END:
STASHED @STASHED@                                      -- check
;
; chained stashed text
;
:STASH:
BASE-TEXT
:END:
:STASH:
CHAINED-@STASHED@
:END:
+++ @STASHED@ required.                               -- check

Stop here
:STOP:
+++ STOP avoid.
"""
  outPage = inPage.tmplParser(newSpecs())

when isNoisy:
  echo "*** outPage=", outPage, ".\n"

when true:
  # Global must-have variables
  for s in ["GLOBAL variable", "OTHER variable", "@UNDEFINED@"]:
    var
      mustHave = &"VARIABLE-{s}."
      check = outPage.find(mustHave)
    when isNoisy:
      echo &"*** try \"{mustHave}\" => {check}"
    doAssert 0 < check

  # Mandatory if/else enabled clauses
  for s in ["ENABLED", "ELSE-ENABLED", "NOT-ELSE-ENABLED", "ELSE-DISABLED",
            "ENABLED-DISABLED", "ENABLED-DISABLED-NOT-ENABLED",
            "ENABLED-DISABLED2", "ENABLED2", "ENABLED-DISABLED-STASH"]:
    var
      mustHave = &"IF-{s} required."
      check = outPage.find(mustHave)
    when isNoisy:
      echo &"*** try \"{mustHave}\" => {check}"
    doAssert 0 < check

  # Some texts must not appear
  for s in ["avoid"]:
    var
      mustAvoid = &" {s}."
      check = outPage.find(mustAvoid)
    when isNoisy:
      echo &"*** try \"{mustAvoid}\" => {check}"
    doAssert check < 0

  # Env loop
  for n in 1 .. 11:
    var
      mustHave = &"ENV{n}: "
      check = outPage.find(mustHave)
    when isNoisy:
      echo &"*** try \"{mustHave}\" => {check}"
    doAssert 0 < check

  # Error handling
  for s in ["=== error :END:", "=== error :ELSE:",
            "STASHED === error :ELSE:"]:
    var
      mustHave = &"\n{s}\n"
      check = outPage.find(mustHave)
    when isNoisy:
      echo &"*** try \"\\n{s}\\n\" => {check}"
    doAssert 0 < check

  # Stash behaviour
  for s in ["STASH-STASH", "STASH-STOP", "CHAINED-BASE-TEXT"]:
    var
      mustHave = &" {s} required."
      check = outPage.find(mustHave)
    when isNoisy:
      echo &"*** try \"{mustHave}\" => {check}"
    doAssert 0 < check
  # Ditto
  for s in ["STASHED :STASH:"]:
    var
      mustHave = &"\n{s}\n"
      check = outPage.find(mustHave)
    when isNoisy:
      echo &"*** try \"\\n{s}\\n\" => {check}"
    doAssert 0 < check

# docu example
when false:
  echo ">>>", """
=======================
@TITLE@
;                 -- comment
:STASH:
stashed text
:END:

:IF_ENABLED:      -- outer
+++ aaa
:IF_NOT_ENABLED: -- inner
+++ bbb
:ELSE:           -- inner
+++ ddd @STASHED@
:END:            -- inner
+++ eee
:ELSE:            -- outer
+++ bbb
:END:             -- outer

:STASH:
***
:END:
:FOR_ENV:
@STASHED@ @KEY@ = @VALUE@
:END:
=======================
""".tmplParser(newSpecs())

echo "*** test OK"

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------
