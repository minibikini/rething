r = require 'rethinkdb'
EventEmitter = require('events').EventEmitter
typeOf = require('typeof')
async = require 'async'

isArray = (value) ->
  typeOf(value) is 'array' or (typeOf(value) is 'object' and typeOf(value.type) is 'array')

module.exports = (app) ->
# relations
# timestamps
#

  class ModelTable #extends EventEmitter

    isNewRecord: yes

    @r: ->
      r.db(app.config.db).table @tableName

    @wrap: (data) ->
      w = (doc) =>
        d = new @ doc
        d.isNewRecord = no
        d

      if isArray data
        (w doc for doc in data)
      else w data

    @wrapReply: (cb) ->
      that = @
      (err, data) ->
        data = that.wrap data if data?
        cb err, data

    @wrapCursor: (cb) ->
      that = @
      (err, cur) ->
        return cb err if err?
        cur.toArray that.wrapReply cb

    @all: (cb) ->
      that = @
      db.pool.acquire (error, conn) =>
        @r().run conn, @wrapCursor (err, reply) =>
          db.pool.release conn
          cb err, reply


    @get: (id, cb) -> @findById id, cb

    @findById: (id, cb) ->
      db.pool.acquire (error, conn) =>
        @r().get(id).run conn, @wrapReply (err, reply) =>
          db.pool.release conn
          cb err, reply

    @getByIndex: (query, index, cb) ->
      db.pool.acquire (error, conn) =>
        @r().getAll(query, {index: index}).run conn, (err, reply) =>
          db.pool.release conn
          cb err, reply
    @getOneByIndex: (query, index, cb) ->
      db.pool.acquire (error, conn) =>
        @r().getAll(query, {index: index}).run conn, @wrapCursor (err, docs) ->
          db.pool.release conn
          return cb err if err?
          cb err, docs[0] or null

    @findOne: (query, cb) ->
      that = @
      db.pool.acquire (error, conn) =>
        @r().filter(query).run conn, (err, cur) ->
          if err?
            db.pool.release conn
            return cb err

          if cur.hasNext()
            cur.next that.wrapReply (err, reply) ->
              db.pool.release conn
              cb err, reply
          else
            db.pool.release conn
            cb 'not found'

    @filter: (filter, cb) ->
      filter

    @delete: (id, cb = ->) -> @remove id, cb

    @remove: (id, cb = ->) ->
      db.pool.acquire (error, conn) =>
        @r().get(id).delete().run conn, (err, reply) ->
          db.pool.release conn
          cb err, reply

    @ensureIndex: (cb = ->) ->
      db.pool.acquire (error, conn) =>
        @r().indexList().run conn, (err, @indexList) =>
          needIndex = (key, opts) =>
            typeOf(opts) is 'object' and opts.index and key not in @indexList

          newIndexes = (key for key, opts of @schema when needIndex key, opts)

          createIndex = (key, cb) => @r().indexCreate(key).run conn, cb

          async.each newIndexes, createIndex, (err, data) ->
            db.pool.release conn
            cb err, data


    constructor: (data = {}) ->
      @[key] = value for key, value of data
      c = @constructor

      for key, value of c.schema when not @[key]?
        @[key] = [] if isArray(value)

    getId: -> @id

    save: (cb = ->) ->
      # TODO: defaults, required
      c = @constructor
      newObj = {}
      # newObj[key] = @[key] for key, value of @

      for key, opts of c.schema
        newObj[key] = @[key] if @[key]?
        # remove empty arrays
        # delete newObj[key] if isArray(opts) and @[key].length is 0

        if typeOf(opts) is 'object' and opts.type?
          switch opts.type
            when String
              newObj[key] = newObj[key].toLowerCase() if opts.lowercase and newObj[key]?
              newObj[key] = newObj[key].trim() if opts.trim and newObj[key]?

      if @isNewRecord
        newObj.id = @getId() if @getId()?
        db.pool.acquire (error, conn) =>
          c.r().insert(newObj).run conn, (err, reply) =>
            db.pool.release conn
            return cb err if err?
            unless @id?
              @id = reply?.generated_keys?[0]
            cb err, reply
      else
        db.pool.acquire (error, conn) =>
          c.r().get(@getId()).update(newObj).run conn, (err, reply) ->
            db.pool.release conn
            cb err, reply


    populate: (relName, cb) ->
      c = @constructor
      rel = c.schema[relName]
      unless rel?
        return cb "#{c.name}: rel is not found"

      isMany = no

      if typeOf(rel) is 'array'
        rel = rel[0]
        isMany = yes

      unless rel.field?
        rel.field = c.name.toLowerCase()


      app[rel.model].getByIndex @getId(), rel.field, (err, docs) =>
        return cb err if err?
        @[relName] = if isMany then docs else docs[0]
        cb null, @