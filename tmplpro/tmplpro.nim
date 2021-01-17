# -*- nim -*-
#
# SPDX-License-Identifier: Unlicense
#
# Blame: Jordan Hrycaj <jordan@teddy-net.com>


## =======================
## Template text processor
## =======================

## This modulel realises a template text processor by applying recursive text
## block substititon filters:
## ::
##    Parser (input, FiltersTable, Variables)
##      repeat for input
##        block    <- collect text block
##        filter() <- FiltersTable (block)
##        data     <- filter (block, FiltersTable, Variables)
##        output   <- for data substitute text fragments from Variables
##
##
## Built-in text blocks
## --------------------
##
## Single text lines, terminated with '\\n'
##
## * Lines with first character `';'` are discarded. Formally, the
##   *filter()* applied here returns empty data.
##
## * Lines not starting with a key word `:<keyName>:` are passed on
##   as-is (i.e. unfiltered). A key word can be preceeded by spaces.
##
## Multi lines text:
##
## * all text lines between `:STASH:` and `:END:`
##   ::
##     :STASH:
##     .. text block ..
##     :END:
##   are collected and shashed as variable `@STASHED@`. Formally, the
##   *filter()* applied here returns empty data.
##
##
## Other text blocks
## ------------------
##
## All other text blocks are defined by means of a lookup table which may
## differ with every *filter()* recursion. A lookup table entry looks like
## ::
##    ("<keyName>",(<ifFilter>,<elseFilter>))
##
## where the *<keyName>* is looked up and one of the filter functions
## *<ifFilter>* or *<elseFilter>* is applied to the selected text block.
##
## * If *<keyName>* matches `IF_<ifName>` for some text *<ifName>*, then the
##   following syntax is supported
##   ::
##     :IF_<ifName>:
##     .. text block ..
##     :ELSE:
##     .. alternative text block ..
##     :END:
##
##     :IF_NOT_<ifName>:
##     .. alternative text block ..
##     :ELSE:
##     .. text block ..
##     :END:
##
##   where in the first case the filters are applied as
##   ::
##     ifFilter(".. text block ..")
##     elseFilter(".. alternative text block ..")
##
##   and in the second case
##   ::
##     elseFilter(".. alternative text block ..")
##     ifFilter(".. text block ..")
##
##   If the `:ELSE:` clause is missing the corresponding filter is not applied.
##
##   A trivial example for an if/else filter table entry for a *true*
##   condition can be set up with the *toIfElse()* convenience function as
##   ::
##     ("IF_TRUE", toIfElse(true))
##
## * Any other *<keyName>* value (not matching `IF_<ifName>`) supports the
##   clause
##   ::
##     :<keyName>:
##     .. text block ..
##     :END:
##
##   in which case the *<elseFilter>* of the lookup table entry is ignored. A
##   loop filter can be contructed from an iterator example
##   ::
##     iterator exampleItems(p: TmplParser): TmplParser {.closure.} =
##       for k in .. items ..:
##         var localVars = @[("@VAR1@", val1(k)), ("@VAR2@", val2(k)), ..]
##         yield (p.filter, localVars.concat(p.vars))
##
##   using a variant of the *toIfElse()* convenience function as
##   ::
##     ("FOR_ITEMS", toIfElse(exampleItems))
##
## Other directives
## ----------------
##
## The key word `:STOP:` teminates any text bock collection other than in
## `:STASH:` scope.
##
##
## Variable substitution filter
## ----------------------------
##
## After a *filter()* is applied to a text block, the *Variables* list
## consisting of pairs
## ::
##   ("<textN>", "<substituteN>")
##
## is appied to the fitered data replacing each ocurrence of *<textN>* with
## *<substituteN>* for all *N*.
##
## Parser usage example
## --------------------
##

runnableExamples:
  import
    algorithm, os, sequtils, tmplpro

  iterator envItems(p: TmplParser): TmplParser {.closure.} =
    for k in envPairs.toSeq.mapIt(it.key.string).sorted:
      var
        # Loop-local variables
        key = ("@KEY@", k)
        value = ("@VALUE@", k.getEnv.string)
      yield (p.filter, @[key, value].concat(p.vars))

  # Template processor parser specification
  proc newSpecs(): TmplParser =
    result = (newTmplFilter(), newSeq[(string,string)]())

    # Global variable
    result.vars.add(("@TITLE@", "Hello World"))

    # Simple if/else clause
    result.filter["IF_ENABLED"] = toIfElse(true)

    # Loop clause
    result.filter["FOR_ENV"] = envItems.toIfElse(result)

  # Template text page
  var tmplPage = """
@TITLE@
;                  -- comment
:STASH:
stashed text
:END:

:IF_ENABLED:       -- outer
+++ aaa
  :IF_NOT_ENABLED: -- inner
+++ bbb
  :ELSE:           -- inner
+++ ddd @STASHED@
  :END:            -- inner
+++ eee
:ELSE:             -- outer
+++ bbb
:END:              -- outer

:STASH:
***
:END:
:FOR_ENV:
@STASHED@ @KEY@ = @VALUE@
:END:
"""

  # Apply template processor
  var expandedPage =
    tmplPage.tmplParser(newSpecs())


## then the contents of the variable `expandedPage` above contains something
## like
## ::
##   Hello World
##
##   +++ aaa
##   +++ ddd stashed text
##   +++ eee
##
##   *** COLUMNS = 79
##   *** DBUS_SESSION_BUS_ADDRESS = unix:path=/run/user/1000/bus
##   *** DESKTOP_AUTOSTART_ID = 1054b02024a...
##   *** DESKTOP_SESSION = lightdm-xsession
##   *** DESKTOP_STARTUP_ID = x-session-manager-...
##   *** DISPLAY = :0
##   *** GDMSESSION = lightdm-xsession
##   *** GPG_AGENT_INFO = /run/user/1000/...
##   *** GTK3_MODULES = gtk-vector-screenshot
##   *** GTK_MODULES = gail:atk-bridge
##   *** ...
##
## Debugging
## ---------
##
## When including the library, compile with the flag `tracer` as in
## ::
##   nim c -r -d:tracer:1 ...
##
## in order to dump the parser state to *stderr* after each action
## of the template processor.
##

import
  sequtils, strformat, strutils, tables

export
  tables

# -----------------------------------------------------------------------------
# Constants, variables, types, and settings
# -----------------------------------------------------------------------------

const
  tracer {.intdefine.}: int = 0
  isTracer = tracer > 0
when isTracer:
  discard

type
  TmplFilterFn* =
    proc(x:string):
      string {.closure.}

  TmplIfElse* =
    (TmplFilterFn,TmplFilterFn)

  TmplFilter* =
    TableRef[string,TmplIfElse]

  TmplParser* = tuple
     filter: TmplFilter
     vars: seq[(string,string)]

  TmplLoopIt* =
    iterator(parser: TmplParser):
      TmplParser {.closure.}

  TmplParserState = tuple
    stopOK: bool                  # stop parsing if *true*
    clause: tuple[
      thenFn: TmplFilterFn,       # if/loop clause filter function
      elseFn: TmplFilterFn,       # else clause filter function
      elseOk: bool,               # else clause enabled
      nesting: int]               # nesting level
    resultCache: tuple[
      data: string,               # data collection w/zero nesting level
      dataNlOK: bool]             # strip first '\n' in data variable
    nestingCache: tuple[
      data: string,               # data collection w/positive nesting level
      dataNlOK: bool]             # strip first '\n' in data variable
    stashed: tuple[
      collectOK: bool,            # collect data here rather than cache it
      enabledOK: bool,            # valid data
      data: string]               # @STASHED@ variable data
    args: TmplParser              # current parser arguments

const
  nilFilter =
    proc(x: string): string {.closure.} =
      ## Simple discarding *<sectionFilter>* for *tmplTextFilter()*
      ""
  passFilter =
    proc(x: string): string {.closure.} =
      ## Simple pass-through *<sectionFilter>* for *tmplTextFilter()*
      x

var
  nilSectTab = newTable[string,TmplIfElse]()

# -----------------------------------------------------------------------------
# Private template parser helpers
# -----------------------------------------------------------------------------

# Extract section key word ":<section>:" from argument string
proc keyWord(name: string): string {.inline.} =
  if name != "":
    if name[0] == ';':
      result = ";"
    else:
      var w = name.strip
      if 2 < w.len and w[0] == ':':
        var pos = w.find(':', start = 1)
        if 0 < pos:
          result = w[1 ..< pos]

# Check for bottom nesting level
proc collectionLevel(t: var TmplParserState): bool {.inline.} =
  t.clause.nesting == 0

# Check whether section cannot be finalised yet
proc lockedLevel(t: var TmplParserState): bool {.inline.} =
  t.clause.nesting != 1

# Append to data cache (suppress inital '\n')
proc appendCache(t: var TmplParserState; data: string) {.inline.} =
  if t.nestingCache.dataNlOK:
    t.nestingCache.data &= "\n"
  else:
    t.nestingCache.dataNlOK = true
  t.nestingCache.data &= data

# Append to data collector (suppress inital '\n')
proc appendResult(t: var TmplParserState;
                  data: string; skipEmptyOK = false) {.inline.} =
  # Expand variables for appending to result cache
  var
    argVars = if t.stashed.enabledOK:
                @[("@STASHED@",t.stashed.data)].concat(t.args.vars)
              else:
                t.args.vars
    expanded = data.multiReplace(argVars)

  if expanded != "" or not skipEmptyOK:
    if t.resultCache.dataNlOK:
      t.resultCache.data &= "\n"
    else:
      t.resultCache.dataNlOK = true
  t.resultCache.data &= expanded

#           ------------------------
#           COLLECTION clause method
#           ------------------------

proc collectData(t: var TmplParserState; data: string) {.inline.} =
  if t.collectionLevel:
    t.appendResult(data)
  else:
    t.appendCache(data)

proc finalise(t: var TmplParserState): string {.inline.} =
  if not t.collectionLevel:
    t.appendResult("=== error END-OF-TEXT\n")
  result = t.resultCache.data

#           --------------------
#           BEGIN clause methods
#           --------------------

# BEGIN if/loop section
proc filterDirective(t: var TmplParserState; k: string): bool {.inline.} =
  if t.args.filter.hasKey(k):
    if t.collectionLevel:
      (t.clause.thenFn, t.clause.elseFn) = t.args.filter[k]
      t.clause.elseOk = 2 < k.len and k[0..2] == "IF_"
    else:
      t.appendCache(&":{k}:")
    t.clause.nesting.inc
    result = true

# STASH section
proc stashDirective(t: var TmplParserState; k: string) {.inline.} =
  if t.collectionLevel:
    (t.clause.thenFn, t.clause.elseFn) = (nilFilter,nilFilter)
    t.clause.elseOk = false
    t.stashed.collectOK = true
  else:
    t.appendCache(&":{k}:")
  t.clause.nesting.inc

# BEGIN if-not section
proc filterIfNotDirective(t: var TmplParserState; k: string): bool {.inline.} =
  if 7 < k.len and k[0..6] == "IF_NOT_":
    var w = "IF_" & k[7 ..< k.len]
    if t.args.filter.hasKey(w):
      if t.collectionLevel:
        var (a,b) = t.args.filter[w]
        (t.clause.thenFn, t.clause.elseFn) = (b,a)
        t.clause.elseOk = true
      else:
        t.appendCache(&":{k}:")
      t.clause.nesting.inc
      result = true

# BEGIN other/unknown section
proc cacheOtherDirective(t: var TmplParserState; k: string) {.inline.} =
  if t.collectionLevel:
    t.appendCache(&"=== error :{k}:\n")
    (t.clause.thenFn, t.clause.elseFn) = (passFilter,nilFilter)
    t.clause.elseOk = true
  else:
    t.appendCache(&":{k}:")
  t.clause.nesting.inc

#           -----------------------
#           END/ELSE clause methods
#           -----------------------

# Forward declaration => recursion in flushCache()
proc tmplParser*(tmplText: string; parser: TmplParser): string

# Helper for END/ELSE sections
proc processNestingCache(t: var TmplParserState) =
  if t.stashed.collectOK:
    var data = t.nestingCache.data.replace("@STASHED@", t.stashed.data)
    t.stashed.data = data
    t.stashed.enabledOK = true
    t.stashed.collectOK = false
  else:
    var data = t
      .clause.thenFn(t.nestingCache.data)
      .tmplParser(t.args)
      .multiReplace(t.args.vars)
      .strip(leading = false, trailing = true, chars = {'\n'})
    t.appendResult(data, skipEmptyOK = true)
  t.nestingCache.data = ""
  t.nestingCache.dataNlOK = false

# END section
proc endDirective(t: var TmplParserState; k: string) {.inline.} =
  if t.collectionLevel:
    t.appendResult(&"=== error :{k}:\n")
  elif t.lockedLevel:
    t.appendCache(&":{k}:")
  else:
    t.processNestingCache
  if 0 < t.clause.nesting:
    t.clause.nesting.dec

# STOP section
proc stopDirective(t: var TmplParserState; k: string) {.inline.} =
  if t.collectionLevel:
    t.stopOK = true
  else:
    t.appendCache(&":{k}:")

# ELSE section
proc elseDirective(t: var TmplParserState; k: string) {.inline.} =
  if t.collectionLevel:
    # stray :ELSE:
    t.appendResult(&"=== error :{k}:\n")
  elif t.lockedLevel:
    t.appendCache(&":{k}:")
  elif t.clause.elseOk:
    # botton level else => close previous :IF: data collection
    t.processNestingCache
    t.clause.elseOk = false
    t.clause.thenFn = t.clause.elseFn
  else:
    # there is no else section: ignore the :ELSE: and print the rest
    t.appendCache(&"=== error :{k}:\n")
    if not t.stashed.collectOK:
      t.processNestingCache
      t.clause.thenFn = passFilter

#           ------------------------
#               debugging
#           ------------------------

when isTracer:
  var recur = 0

  proc debugStatus(t: var TmplParserState; info = "") =
    var blurb = if info != "": &" -- {info}" else: ""
    stderr.write &"<<< (recur {recur}) (nesting {t.clause.nesting}) " &
       &"(stash {t.stashed.collectOK} {t.stashed.enabledOK}) " &
       &"(else {t.clause.elseOK}) (stop {t.stopOK}){blurb} >>>\n" &
       &"    stashed => {t.stashed.data}.\n" &
       &"    cached  => {t.nestingCache.data}.\n" &
       &"    result  => {t.resultCache.data}.\n"

  proc debugBegin(t: var TmplParserState) =
    discard t
    if recur == 0:
      stderr.write "\n\n============== debugBegin() ===========\n"
    recur.inc

  proc debugEnd(t: var TmplParserState; info = "") =
    recur.dec
    t.debugStatus(info)
    if recur == 0:
      stderr.write "============== debugEnd() ===========\n\n"

else:
  proc debugBegin(t: var TmplParserState) {.inline.} = discard
  proc debugEnd(t: var TmplParserState; info = "") {.inline.} = discard
  proc debugStatus(t: var TmplParserState; info = "") {.inline.} = discard

# -----------------------------------------------------------------------------
# Public
# -----------------------------------------------------------------------------

proc tmplUncomment*(tmplText: string): string =
  ## Filter out all lines starting with ';'.
  tmplText
    .split('\n')
    .filter(proc(x: string): bool = x == "" or x[0] != ';')
    .join("\n")


proc newTmplFilter*(): TmplFilter =
  ## Create empty table to be eventually used in as *filters* argument
  ## in *tmplParser()*.
  newTable[string,TmplIfElse]()


proc tmplParser*(tmplText: string; parser: TmplParser): string =
  ## This function realises the template text processor as described above
  ## in the module documentation.
  var parserState: TmplParserState
  parserState.args = parser

  parserState.debugBegin()

  for line in tmplText.split('\n'):
    var token = line.keyWord

    parserState.debugStatus(&"processing '{line}'")

    # Process if/else/loop directive
    case token:
    of "":
      # Collect section data
      parserState.collectData(line)
      parserState.debugStatus(&"collected")

    of ";":
      # Discard comments
      discard

    of "STOP":
      # End of section data
      parserState.stopDirective(token)
      parserState.debugStatus(&"stop {token}")

    of "END":
      # Finalise and append section data
      parserState.endDirective(token)
      parserState.debugStatus(&"end {token}")

    of "ELSE":
      # Finalise, append section data and re-open section
      parserState.elseDirective(token)
      parserState.debugStatus(&"else {token}")

    of "STASH":
      parserState.stashDirective(token)
      parserState.debugStatus(&"stash {token}")

    elif parserState.filterDirective(token):
      parserState.debugStatus(&"filter {token}")

    elif parserState.filterIfNotDirective(token):
      parserState.debugStatus(&"if-not {token}")

    else:
      parserState.cacheOtherDirective(token)
      parserState.debugStatus(&"other {token}")

    if parserState.stopOK:
      break

  result = parserState.finalise
  parserState.debugEnd()


proc tmplParser*(tmplText: string;
                 filters: TmplFilter; vars: varargs[(string,string)]): string =
  ## Variant of *tmplParser()*.
  tmplText.tmplParser((filters, toSeq(vars)))


proc tmplParser*(tmplText: string; vars: varargs[(string,string)]): string =
  ## Simplified template parser without block section clauses. As a
  ## consequence, only variable/text substitution is performed.
  tmplText.tmplParser(nilSectTab,vars)


proc toIfElse*(isIfClauseOk = true): TmplIfElse =
  ## Returns the
  ## ::
  ##   (<pass-through-filter>,<discard-filter>)
  ##
  ## filter pair if argument *isIfClauseOk* is *true*, otherwise the tuple
  ## entries are swapped. The tuple returned is supposed to be used with some
  ## lookup entry for the *filters* argument table for the *tmplParser()*
  ## function.
  if isIfClauseOk:
    (passFilter, nilFilter)
  else:
    (nilFilter, passFilter)


proc toIfElse*(tmplIt: TmplLoopIt; parser: TmplParser): TmplIfElse =
  ## Returns a *TmplIfElse* filter derived from the iterator argument
  ## *tmplIt()*. The return value is supposed to be used with some lookup
  ## entry for the *filters* argument table for the *tmplParser()* function.
  var loopFilter = proc(x: string): string =
                     toSeq(tmplIt(parser))
                       .mapIt(x.tmplParser(it[0],it[1]))
                       .join("\n")
  result = (loopFilter, nilFilter)


proc toIfElse*(tmplIt: TmplLoopIt; filters: TmplFilter;
               vars: varargs[(string,string)]): TmplIfElse =
  ## Variant of *toIfElse()*.
  tmplIt.toIfElse((filters, toSeq(vars)))


proc toIfElseNil*(): TmplIfElse {.inline.} =
  ## Simple text discarding *<sectionFilter>* pair for *tmplTextFilter()*
  (nilFilter,nilFilter)

proc toIfElseNil*(ignIt: TmplLoopIt; ignFilters: TmplFilter;
                  ignVars: varargs[(string,string)]): TmplIfElse {.inline.} =
  ## Variant of *toIfElseNil()*.
  toIfElseNil()

# -----------------------------------------------------------------------------
# End
# -----------------------------------------------------------------------------
