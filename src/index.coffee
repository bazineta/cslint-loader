#-----------------------------------------------------------------------------#
#
#  CoffeeLint Loader for Webpack
#
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Imports
#-----------------------------------------------------------------------------#

coffeelint  = require 'coffeelint'
utils       = require 'loader-utils'
{getConfig} = require 'coffeelint/lib/configfinder'

#-----------------------------------------------------------------------------#
# Lint Error; bag the call stack, as it's just noise.
#-----------------------------------------------------------------------------#

class LintError extends Error

  constructor: (message) ->
    super message
    @name  = @constructor.name
    @stack = false

#-----------------------------------------------------------------------------#
# Lint Type, used as a type-specific accumulator for errors and warnings.
#-----------------------------------------------------------------------------#

class LintType

  constructor: ({@fail, @emit}) ->
    @lines = []

  count: -> @lines.length

  issue: (issue) ->

    line  = "\nLine #{issue.lineNumber}: #{issue.message}"
    line += ": #{issue.context}" if issue.context
    
    @lines.push line

    return

  check: ->

    # If we have no issues, our work is done here.

    return unless @count()

    # We have issues; create an error object describing them.

    error = new LintError @lines.join()

    # If we are supposed to fail the build, then do so by returning
    # the error, otherwise just emit the error.

    return error if @fail
    @emit error
    return

#-----------------------------------------------------------------------------#
# Reduce an error report to something easy to deal with.
#-----------------------------------------------------------------------------#

reduce = ({error, warn}) -> ({paths}) ->

  type =
    error: new LintType error
    warn:  new LintType warn
        
  for issues from Object.values paths
    type[issue.level].issue issue for issue from issues

  return {
    issue:    type.error.count() or type.warn.count()
    check: -> type.error.check() or type.warn.check()
  }

#-----------------------------------------------------------------------------#
# Attempt to load a reporter of the type requested, which can be either a
# function, in which case we're done, one of the default reporters that
# ship with CoffeeLint, or an external reporter. If no reporter was
# provided, use the stylish reporter. Throw if the reporter type provided
# is invalid.
#-----------------------------------------------------------------------------#

loadReporter = (type) ->

  return type if typeof type is 'function'

  type ?= 'coffeelint-stylish'

  try return require "coffeelint/lib/reporters/#{type}"
  try return require type

  return throw new Error "#{type} is not a valid reporter"

#-----------------------------------------------------------------------------#
# Attempt to load the reporter code, create a new instance of the reporter,
# and publish the results to standard output.
#-----------------------------------------------------------------------------#

report = (errorReport, options) ->

  reporter = loadReporter options.reporter
  instance = new reporter errorReport
  instance.publish()

  return

#-----------------------------------------------------------------------------#
# Normalize the resource path by removing the current working directory from
# it, to allow having relative paths in ignore specifications.
#-----------------------------------------------------------------------------#

normalize = (resourcePath) ->

  cwd = process.cwd() + '/'

  return resourcePath[cwd.length...] if resourcePath.startsWith cwd
  return resourcePath

#-----------------------------------------------------------------------------#
# Exports
#-----------------------------------------------------------------------------#

module.exports = (input, other...) ->

  resourcePath = normalize @resourcePath
  errorReport  = coffeelint.getErrorReport()
  callback     = @async()
  options      = utils.getOptions @
  config       = getConfig @context
  lint         = reduce {
    error:
      fail: options.failOnError
      emit: @emitError
    warn:
      fail: options.failOnWarning
      emit: @emitWarning
  }

  # Ideally, webpack wants us to be async, so hey, let's be async.

  setImmediate ->

    # Run the linter; results will be accumlated by CoffeeLint into the
    # errorReport object.

    errorReport.lint resourcePath, input, config

    # From which, we really just want to know if there was any kind of
    # issue, and, if there was, we need to check how to deal with them.

    {
      issue
      check
    } = lint errorReport

    # If there was some type of issue, then issue a report. If checking
    # on the issue results in an error, then the issue is a fatal one.

    if issue
      report errorReport, options
      return callback err if (err = check())

    # We either didn't encounter an issue, or the issue was non-fatal.

    return callback null, input, other...

  return

#-----------------------------------------------------------------------------#
