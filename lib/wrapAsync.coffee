typeOf = require 'typeof'
async = require 'async'
inspect = require('util').inspect

module.exports = (data, ModelClass, opts, cb) ->
  # if ModelClass::constructor.name is 'User'
    # console.log 'User'
  if arguments.length is 3
    cb = opts
    opts = {}

  return cb() unless data

  wrapper = (item, done) ->
    if item not instanceof ModelClass
      item = new ModelClass item

    item.isNewRecord = no unless opts.isNew

    if opts.wrapRelated
      item.wrapRelated (err) ->
        done err, item
    else
      done err, item

  # console.log data.toArray?, data
  # console.log data, typeOf(data)
  if data.toArray?
    data.toArray (err, data) =>
      # console.log 'data.toArray', data
      return cb err if err?
      async.map data, wrapper, cb
  else
    if typeOf(data) is 'array'
      async.map data, wrapper, cb
    else
      wrapper data, cb
