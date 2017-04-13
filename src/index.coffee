#-----------------------------------------------------------------------------#
#
#  CoffeeLint Loader for Webpack
#
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Imports
#-----------------------------------------------------------------------------#

_           = require 'lodash'
async       = require 'async'
coffeelint  = require 'coffeelint'
utils       = require 'loader-utils'
{getConfig} = require 'coffeelint/lib/configfinder'

#-----------------------------------------------------------------------------#
# Lint Error; don't capture the complete calling stack, as it's just noise.
#-----------------------------------------------------------------------------#

class LintError extends Error

  constructor: (@message) ->
    @name = @constructor.name

#-----------------------------------------------------------------------------#
# Lint Type, used as a type-specific (error, warning) accumulator.
#-----------------------------------------------------------------------------#

class LintType

  constructor: ->
    @lines = []

  count: -> @lines.length

  error: (error) ->

    line  = "\nLine #{error.lineNumber}: #{error.message}"
    line += ": #{error.context}" if error.context
    
    @lines.push line

    return

  check: ({fail, emit}, callback) ->

    # If we have issues, then create an error object describing them.
    # If we are supposed to fail the build, then do so, otherwise just
    # emit the error.

    if @count()
      error = new LintError @lines.join()
      return callback error if fail
      emit error

    # We either didn't have any issues, or we had some, but were not
    # instructed to fail the build due to them.

    return callback null

#-----------------------------------------------------------------------------#
# Lint; reduces an error report to summary data.
#-----------------------------------------------------------------------------#

class Lint

  constructor: (errorReport) ->

    @type =
      error: new LintType()
      warn:  new LintType()

    _.forEach errorReport.paths, (errors) =>
      @type[error.level].error error for error in errors
      return

  count: -> _.sum _.invokeMap @type,  'count'

#-----------------------------------------------------------------------------#
# Attempt to load a reporter of the type requested, which can be either a
# function, in which case we're done, one of the default reporters that
# ship with CoffeeLint, or an external reporter. If no reporter was
# provided, use the stylish reporter. Throw if the reporter type provided
# is invalid.
#-----------------------------------------------------------------------------#

loadReporter = (type) ->

  return type if _.isFunction type

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

  return resourcePath.slice cwd.length if _.startsWith resourcePath, cwd
  return resourcePath

#-----------------------------------------------------------------------------#
# Exports
#-----------------------------------------------------------------------------#

module.exports = (input) ->

  resourcePath = normalize @resourcePath
  errorReport  = coffeelint.getErrorReport()
  callback     = _.partialRight @async(), input
  options      = utils.getOptions @

  return async.setImmediate =>

    errorReport.lint resourcePath, input, getConfig @context

    return callback null unless (lint = new Lint errorReport).count()

    report errorReport, options

    return async.parallel [

      (callback) =>

        return lint.type.error.check
          fail: options.failOnError
          emit: @emitError
        , callback

      (callback) =>

        return lint.type.warn.check
          fail: options.failOnWarning
          emit: @emitWarning
        , callback

    ], callback

#-----------------------------------------------------------------------------#
