EventEmitter = require('events').EventEmitter
typeOf = require('typeof')
inflection = require "inflection"
async = require 'async'
{ValidationError, ModelError} = require './errors'
_ = require 'lodash'

isArray = (value) ->
  typeOf(value) is 'array' or (typeOf(value) is 'object' and typeOf(value.type) is 'array')

wrapModel = (data, Model, opts = {}) ->
  wrap = (item) ->
    if item not instanceof Model
      item = new Model item

    item.isNewRecord = opts.isNew if opts.isNew
    item.wrapRelated() if opts.wrapRelated
    item

  if isArray data
    wrap item for item in data
  else
    wrap data


wrapAsync = require './wrapAsync'

module.exports = (db) ->
  Query = require('./Query')(db)
  {Promise, run, r} = db

  class Model extends EventEmitter
    isNewRecord: yes
    @primaryKey: 'id'

    @hasMany: (name, opts = {}) ->
      db.initModelsTasks.push =>
        that = @
        @relations ?= {}
        @relations.hasMany ?= {}

        opts.model ?= inflection.singularize inflection.capitalize inflection.camelize name

        if opts.through?
          opts.throughModel ?= inflection.singularize inflection.capitalize inflection.camelize opts.through
          opts.throughForeignKey ?=inflection.underscore(@::constructor.name) + 'Id'
          opts.foreignKey ?= inflection.underscore(opts.model) + 'Id'
          @relations.hasMany[name] = opts
        else
          opts.foreignKey ?= inflection.underscore(@::constructor.name) + 'Id'
          opts.primaryKey ?= @primaryKey
          @relations.hasMany[name] = opts

          capName = inflection.capitalize name
          capSingName = inflection.singularize capName

          RelModel = db.models[opts.model]
          RelModel.schema[opts.foreignKey] ?= String

          # add getter
          @::["get" + capName] ?= (cb = ->) ->
            query = new Query RelModel, RelModel.r().getAll(@getId(), index: opts.foreignKey)
            query.collection = yes
            query.order opts.order if opts.order
            if cb?
              query.run cb
            else query

          @::["set" + capName] ?= (models, cb = ->) ->
            models = wrapModel models, RelModel
            @[name] = models

          @::["add" + capSingName] ?= (model,  cb = ->) ->
            model = wrapModel model, RelModel
            @[name] ?= []
            model[opts.foreignKey] = @getId() if @getId()?
            @[name].push model
            model


    @belongsTo: (name, opts = {}) ->
      db.initModelsTasks.push =>
        @relations ?= {}
        @relations.belongsTo ?= {}

        opts.model ?= inflection.capitalize inflection.camelize name
        opts.foreignKey ?= name + 'Id'
        @relations.belongsTo[name] = opts
        capName = inflection.capitalize name
        RelModel = db.models[opts.model]

        @::["get" + capName] = (cb = ->) ->
          query = new Query RelModel, RelModel.r().get(@[opts.foreignKey])
          query.collection = no
          if cb?
            query.run cb
          else query

        @["getBy" + capName] = (id, cb = ->) =>
          query = new Query @, @r().getAll(id, {index:opts.foreignKey})
          query.collection = yes
          if cb?
            query.run cb
          else query

    @db: ->
      db.r.db(db.config.db)

    @r: ->
      @db().table @tableName

    @wrap: (data, cb) -> wrapAsync data, @, {isNew: no, wrapRelated: yes}, cb

    @wrapReply: (cb) ->
      that = @
      (err, data) ->
        if data?
          that.wrap data, cb
        else
          cb err, data

    @get: (id, cb) ->
      if _.isString id
        query = new Query @, @r().getAll(id)
        query.collection = no
      else
        query = new Query @, @r().getAll.apply @r(), id
        query.collection = yes

      if cb?
        query.run cb
      else query


    @all: (cb) ->
      query = new Query @, @r()
      query.collection = yes
      if cb? then query.run cb else query


    @getAll: (id, cb) ->
      query = new Query @, @r().getAll(id)
      query.collection = yes
      if cb? then query.run cb else query

    @getBy: (idx, val, cb) ->
      query = new Query @, @r().getAll(val, {index:idx})
      query.collection = yes
      # query.order()
      if cb? then query.run cb else query

    @getOneBy: (idx, val, cb) ->
      query = new Query @, @r().getAll val, index: idx
      query.collection = no
      # query.order()
      if cb? then query.run cb else query

    # @filter: (filter, cb) ->
    #   # filter

    # @delete: (id, cb = ->) -> @remove id, cb

    # @remove: (id, cb = ->) ->
    #   @r().get(id).delete().run db.getConn(), cb

    constructor: (data = {}, @isNewRecord = yes) ->
      c = @constructor

      @[key] = value for key, value of data

      if c.timestamp and c.schema.createdAt and @isNewRecord
        @createdAt = new Date

      @setDefaults()
      @wrapRelated()

    setDefaults: ->
      for name, value of @constructor.schema when not @[name]?
        switch typeOf value
          when 'object'
            if value.default?
              @[name] = if typeOf(value.default) is 'function'
                value.default()
              else value.default
          when "array" then @[name] = []

    getId: -> @id

    validateTypes: (cb) ->
      promise = new Promise (resolve, reject) =>
        return resolve()
        # TODO
        c = @constructor
        c.schema

        for key, opts of c.schema
          type = if typeOf(opts) is 'object' and opts.type?
            opts.type
          else
            opts

          type = type() if typeOf(type) is 'function'

          if typeOf(@[key]) isnt typeOf(type)
            return reject new ValidationError "#{key} has to be type of `#{typeOf(type)}`"

      promise.nodeify cb if cb?
      promise

    beforeSave: (cb) -> cb()

    save: (saveOpts = {}, cb) ->
      beforeSave = Promise.promisify @beforeSave, @

      if _.isFunction saveOpts
        cb = saveOpts
        saveOpts = {}

      promise = beforeSave().then =>
        # TODO: defaults, required
        c = @constructor
        newObj = {}
        # newObj[key] = @[key] for key, value of @

        @validateTypes().then =>
          if c.timestamp and c.schema.modifiedAt and !@isNewRecord
            @modifiedAt = new Date

          for key, opts of c.schema
            newObj[key] = @[key] if @[key]?
            # remove empty arrays
            # delete newObj[key] if isArray(opts) and @[key].length is 0
            # c.schema[key]

            # console.log key, typeOf(newObj[key]) if newObj[key]?

            if typeOf(opts) is 'object' and Object.keys(opts).length
              return reject new ValidationError "Type not specified for `#{key}`" unless opts.type?

            # if typeOf(opts) is 'object' (typeOf(opts) is 'object' and opts.type?)

              if opts.required and not newObj[key]?
                return reject new ValidationError "#{key} field is required"

              switch opts.type
                when String
                  # return "#{key} hase to be type of String" if
                  newObj[key] = newObj[key].toLowerCase() if opts.lowercase and newObj[key]?
                  newObj[key] = newObj[key].trim() if opts.trim and newObj[key]?

          for key, val of c.indexes
            newObj[key] = @[key] if @[key]?

          if @isNewRecord
            newObj.id = @getId() if @getId()?
            db.run(c.r().insert(newObj, saveOpts)).then (reply) =>
              unless @id?
                @id = reply?.generated_keys?[0]

              @isNewRecord = no

              @saveRelated().then => @

          else
            @saveRelated().then =>
              if @getId()?
                db.run(c.r().get(@getId()).update(newObj, saveOpts)).then => @
              else
                reject new ModelError "undefined id"

      promise.nodeify cb if cb?
      promise

    saveRelated: (cb) ->
      promise = new Promise (resolve, reject) =>
        c = @constructor
        return resolve() unless c.relations?
        relations = []

        for relName, rels of c.relations
          for name, opts of rels
            opts.name = name
            opts.type = relName
            relations.push opts

        saveRel = (rel, done) =>
          switch rel.type
            when 'hasMany' then @saveHasMany rel, done
            else done()

        async.each relations, saveRel, (err) ->
          if err then reject err else resolve()

      promise.nodeify cb if cb?
      promise


    saveHasMany: (rel, cb) ->
      return cb() unless @[rel.name]?

      save = (model, cb) =>
        model = wrapModel model, db.models[rel.model]
        model[rel.foreignKey] = @getId()
        model.save cb

      async.each @[rel.name], save, cb

    @createIndexes: ->
      run(@table().indexList()).then (existed) =>
        tasks = for name, val of @indexes when name not in existed
          if _.isBoolean val
            run @table().indexCreate name
          else
            run @table().indexCreate name, val

        Promise.all(tasks).then =>
          run @table().indexWait()

    @relatedQuery: (withRels, query)->
      query = query.map (item) =>
        obj = {}
        for name, rel of @relations.hasMany
          for withRel in withRels when withRel.name is name
            if not rel.through?
              relQuery = db.models[rel.model].getBy(rel.foreignKey, item('id'))
              relQuery.order(withRel.order) if withRel.order?
              relQuery.skip(withRel.skip) if withRel.skip?
              relQuery.limit(withRel.limit) if withRel.limit?
              relQuery.with(withRel.with) if withRel.with?
            else
              relQuery = db.models[rel.throughModel].getBy(rel.throughForeignKey, item('id'))
              relQuery.group(rel.foreignKey)
              relQuery.count()
              relQuery.ungroup()
              relQuery.skip(withRel.skip) if withRel.skip?
              relQuery.limit(withRel.limit) if withRel.limit?
              relQuery.concatMap (item) =>
                relQuery2 = db.models[rel.model].getBy('id', item('group'))
                relQuery2.with(withRel.with) if withRel.with?
                relQuery2.toRQL().coerceTo('array')

              relQuery.order(withRel.order) if withRel.order?
            obj[name] = relQuery.toRQL().coerceTo('array')

        for name, rel of @relations.belongsTo
          for withRel in withRels when withRel.name is name
            tableName = db.models[rel.model].tableName
            obj[name] = db.r.db(db.config.db).table(tableName).get(item(rel.foreignKey))

        item.merge obj
      query

    wrapRelated: (cb) ->
      wrapRelations = []
      # console.log "wrapping ", @constructor.name
      wrap = (key, ModelClass, done) =>
        # console.log 'ModelClass', ModelClass::constructor.name, @[key]
        wrapAsync @[key], ModelClass, {isNew: no, wrapRelated: yes}, (err, data) =>
          @[key] = data
          done(err)

      for relname, rels of @constructor.relations
        # console.log 'relname', relname
        wrapRelations = for key, opts of rels when @[key]?
        # wrapRelations = for key, opts of rels
          # if @[key]?
          # console.log db.models[opts.model]::constructor.name, key
            async.apply wrap, key, db.models[opts.model]

      async.parallel wrapRelations, cb

    remove: (cb = ->) ->
      c = @constructor
      db.run c.r().get(@id).delete(), cb

    'delete': (cb = ->) -> @remove cb

    toObject: ->
      c = @constructor
      newObj = {}

      for key, opts of c.schema
        newObj[key] = @[key] if @[key]?

      newObj

    @index: (name, fn) ->
      @indexes ?= {}
      @indexes[name] = fn or true
