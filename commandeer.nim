
import parseopt2
import strutils
import tables


var
  argumentList = newSeq[string]()
  shortOptions = initTable[string, string](32)
  longOptions = initTable[string, string](32)
  argumentIndex = 0
  errorMsgs : seq[string] = @[]
  customErrorMsg : string
  inSubcommand = false
  subcommandSelected = false


## String conversion
proc convert(s : string, t : char): char =
  result = s[0]
proc convert(s : string, t : int): int =
  result = parseInt(s)
proc convert(s : string, t : float): float =
  result = parseFloat(s)
proc convert(s : string, t : bool): bool =
  ## will accept "yes", "true" as true values
  if s == "":
    ## the only way we get an empty string here is because of a key
    ## with no value, in which case the presence of the key is enough
    ## to return true
    result = true
  else:
    result = parseBool(s)
proc convert(s : string, t : string): string =
    result = s.strip


template argumentIMPL(identifier : expr, t : typeDesc): stmt {.immediate.} =
  bind argumentList
  bind argumentIndex
  bind convert
  bind errorMsgs
  bind inSubcommand
  bind subcommandSelected

  var identifier : t

  if (inSubcommand and subcommandSelected) or not inSubcommand:
    if argumentList.len <= argumentIndex:
      let eMsg = "Missing command line arguments"
      if len(errorMsgs) == 0:
        errorMsgs.add(eMsg)
      else:
        if not (errorMsgs[high(errorMsgs)][0] == 'M'):
          errorMsgs.add(eMsg)
    else:
      var typeVar : t
      try:
        identifier = convert(argumentList[argumentIndex], typeVar)
      except ValueError:
        let eMsg = capitalize(getCurrentExceptionMsg()) &
                   " for argument " & $(argumentIndex+1)
        errorMsgs.add(eMsg)

    inc(argumentIndex)


template argumentsIMPL(identifier : expr, t : typeDesc,
                       atLeast1 : bool = true): stmt {.immediate.} =
  bind argumentList
  bind argumentIndex
  bind convert
  bind errorMsgs
  bind inSubcommand
  bind subcommandSelected

  var identifier = newSeq[t]()

  if (inSubcommand and subcommandSelected) or not inSubcommand:
    if atLeast1 and (argumentList.len <= argumentIndex):
      let eMsg = "Missing command line arguments"
      if len(errorMsgs) == 0:
        errorMsgs.add(eMsg)
      else:
        if not (errorMsgs[high(errorMsgs)][0] == 'M'):
          errorMsgs.add(eMsg)
    else:
      var typeVar : t
      var firstError = true
      while true:
        if argumentList.len == argumentIndex:
          break
        try:
          let a = argumentList[argumentIndex]
          inc(argumentIndex)
          identifier.add(convert(a, typeVar))
          firstError = false
        except ValueError:
          if atLeast1 and firstError:
            let eMsg = capitalize(getCurrentExceptionMsg()) &
                       " for argument " & $(argumentIndex+1)
            errorMsgs.add(eMsg)
          break


template optionIMPL(identifier : expr, t : typeDesc, longName : string,
                    shortName : string): stmt {.immediate.} =
  bind shortOptions
  bind longOptions
  bind convert
  bind errorMsgs
  bind tables
  bind inSubcommand
  bind subcommandSelected

  var identifier : t

  if (inSubcommand and subcommandSelected) or not inSubcommand:
    var typeVar : t
    if tables.hasKey(longOptions, longName):
      try:
        identifier = convert(tables.mget(longOptions, longName), typeVar)
      except ValueError:
        let eMsg = capitalize(getCurrentExceptionMsg()) &
                   " for option --" & longName
        errorMsgs.add(eMsg)
    elif tables.hasKey(shortOptions, shortName):
      try:
        identifier = convert(tables.mget(shortOptions, shortName), typeVar)
      except ValueError:
        let eMsg = capitalize(getCurrentExceptionMsg()) &
                   " for option -" & shortName
        errorMsgs.add(eMsg)


template exitoptionIMPL(longName, shortName, msg : string): stmt =
  bind shortOptions
  bind longOptions
  bind tables

  if tables.hasKey(longOptions, longName):
    quit msg, QuitSuccess
  elif tables.hasKey(shortOptions, shortName):
    quit msg, QuitSuccess


template errormsgIMPL(msg : string): stmt =
  bind customErrorMsg
  customErrorMsg = msg


template subcommandIMPL(identifier : expr, subcommandName : string,
                        statements : stmt): stmt {.immediate.} =
  bind argumentList
  bind argumentIndex
  bind errorMsgs
  bind inSubcommand
  bind subcommandSelected

  var identifier : bool = false
  inSubcommand = true

  if argumentList.len > 0 and argumentList[0] == subcommandName:
    identifier = true
    inc(argumentIndex)
    subcommandSelected = true

  statements
  subcommandSelected = false
  inSubcommand = false


template commandLine*(statements : stmt): stmt {.immediate.} =
  bind argumentList
  bind shortOptions
  bind longOptions
  bind errorMsgs
  bind parseopt2
  bind tables
  bind customErrorMsg

  template argument(identifier : expr, t : typeDesc): stmt {.immediate.} =
    argumentIMPL(identifier, t)

  template arguments(identifier : expr, t : typeDesc,
                     atLeast1 : bool = true): stmt {.immediate.} =
    argumentsIMPL(identifier, t, atLeast1)

  template option(identifier : expr, t : typeDesc, longName : string,
                  shortName : string): stmt {.immediate.} =
    optionIMPL(identifier, t, longName, shortName)

  template exitoption(longName, shortName, msg : string): stmt {.immediate.} =
    exitoptionIMPL(longName, shortName, msg)

  template errormsg(longName, shortName, msg : string): stmt {.immediate.} =
    errormsgIMPL(longName, shortName, msg)

  template subcommand(identifier : expr, subcommandName : string,
                      statements : stmt): stmt {.immediate.} =
    subcommandIMPL(identifier, subcommandName, statements)

  for kind, key, value in parseopt2.getopt():
    case kind
    of parseopt2.cmdArgument:
      argumentList.add(key)
    of parseopt2.cmdLongOption:
      tables.add(longOptions, key, value)
    of parseopt2.cmdShortOption:
      tables.add(shortOptions, key, value)
    else:
      discard

  #Call the passed statements so that the above templates are called
  statements

  if len(errorMsgs) > 0:
    if not customErrorMsg.isNil:
      errorMsgs.add(customErrorMsg)
    quit join(errorMsgs, "\n")


when isMainModule:
  var intVar : int
  var floatVar : float
  var boolVar : bool
  var stringVar : string
  var charVar : char

  doassert(convert("10", intVar) == 10)
  doassert(convert("10.0", floatVar) == 10)
  doassert(convert("10", floatVar) == 10)
  doassert(convert("yes", boolVar) == true)
  doassert(convert("false", boolVar) == false)
  doassert(convert("no ", stringVar) == "no")
  doassert(convert("*", charVar) == '*')
