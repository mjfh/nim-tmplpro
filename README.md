# Text template processor

This text processor has very limited capabilities (unlike *jinja*, *go* or
*Perl templates*.) The processor can

 * selectively enable text blocks, as with *if/else*
 * filter/replace text blocks, as for a loop implied by an *iterator()*
 * text replacement, emulating variable interpolation

It is currently used to support CGI tools with text template files used to
define the *HTML* layout.

## Example

Let's look at this rather silly template example

       @TITLE@
       ;                  -- comment

       :IF_ENABLED:       -- outer
       +++ aaa
         :IF_NOT_ENABLED: -- inner
       +++ bbb
         :ELSE:           -- inner
       +++ ddd
         :END:            -- inner
       +++ eee
       :ELSE:             -- outer
       +++ bbb
       :END:              -- outer

       :FOR_ENV:
       *** @KEY@ = @VALUE@
       :END:

The directives *:ELSE:* and *:END:* are pre-defined by the template processor.
For the template example, we set

 * *@TITLE@* to be replaced by the text *"Hello World"*

 * *:IF_ENABLED:* to sort of evaluate *true*

 * *:FOR_ENV:* to iterate through the environment variables defining
   *@KEY@* and *@VALUE@* to be replaced with appropriate text for each
   *key/value* pairs of environment entries.

then this should translate to something like

       Hello World

       +++ aaa
       +++ ddd
       +++ eee

       *** COLUMNS = 79
       *** DBUS_SESSION_BUS_ADDRESS = unix:path=/run/user/1000/bus
       *** DESKTOP_AUTOSTART_ID = 1054b02024a...
       *** DESKTOP_SESSION = lightdm-xsession
       *** ...

The corresponding *NIM* source code to configure the template text processor
that produces this outcome looks like

       import
         algorithm, os, sequtils, tmplpro

       iterator envItems(p: TmplParser): TmplParser {.closure.} =
         for k in envPairs.toSeq.mapIt(it.key.string).sorted:
           var
             # Loop-local variables
             key = ("@KEY@", k)
             value = ("@VALUE@", k.getEnv.string)
           yield (p.filter, @[key, value].concat(p.vars))

       # Text template processor parser specification
       proc newSpecs(): TmplParser =
         result = (newTmplFilter(), newSeq[(string,string)]())

         # Global variable
         result.vars.add(("@TITLE@", "Hello World"))

         # Simple if/else clause
         result.filter["IF_ENABLED"] = toIfElse(true)

         # Loop clause
         result.filter["FOR_ENV"] = envItems.toIfElse(result)


Assuming that the template example text is assigned to the variable
**tmplPage**, the translated text is produced and printed out with

       # Apply template processor
       echo tmplPage.tmplParser(newSpecs())
