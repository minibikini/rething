glob = require "glob"
EventEmitter = require("events").EventEmitter
inflection = require "inflection"
async = require "async"
typeOf = require 'typeof'
Pool = require 'rethinkdb-pool'

module.exports = class DbManager extends EventEmitter
  @Pool: Pool
  Pool: Pool
  conn: null
  models: null
  reconnectDelay: 100

  constructor: (@app) ->
    @config = @app.config.rethinkdb
    @config.ensureIndexes ?= yes
    @logger = @app.logger
    @Model = require('./Model')(@)
    @models = {}

    @once "connect", =>
      @checkDb()

    @on 'db:ready',=>
      @loadModels()

    @once 'db:ensureIndexes:ready', =>
      @emit 'ready'

    @on 'modelsLoaded', =>
      if @config.ensureIndexes
        @ensureIndexes()
      else
        @emit 'ready'

    @pool = Pool(@config)
    @r = @pool.r

  run: (query, cb = ->) ->
    @pool.run query, cb

  connect: (cb = ->) ->
    @run @r.dbList(), (err, databases) =>
      if databases
        @emit "connect"
        cb()
      else cb err
    @

  close: (cb = ->) ->
    @pool.drain =>
      @pool.destroyAllNow cb

  checkDb: ->
    @run @r.dbList(), (err, databases) =>
      if @config.db in databases
        @emit "db:ready"
      else
        @run @r.dbCreate(@config.db), (err) =>
          return @app.logger.error err if err?
          @emit "db:ready"


  loadModel: (file, cb) =>
    cls = require(file)(@, @app)
    modelName = cls::constructor.name
    @models[modelName] = cls
    cls.schema ?= {}
    cls.tableName ?= inflection.tableize modelName
    cls.timestamp ?= yes

    if cls.timestamp
      cls.schema.createdAt ?=
       type: Date
       index: yes

      cls.order ?= 'createdAt'

      cls.schema.modifiedAt ?=
       type: Date
       index: yes

    cls.indexes ?= {}

    if cls.tableName not in @tableList
      query = @r.tableCreate(cls.tableName, primaryKey: cls.primaryKey)
      @run query, cb
    else
      cb()

  loadModels: ->
    @run @r.tableList(), (err, @tableList) =>
      glob "#{@config.modelsFolder}/*.coffee", (err, files) =>
        async.each files, @loadModel, (err) =>
          process.nextTick => @emit 'modelsLoaded'

  ensureIndexes: (cb = ->) ->
    process.nextTick =>
      for modelName, model of @models
        for key, opts of model.schema when typeOf(opts) is 'object' and opts.index?
          model.indexes[key] = opts.index

        model.relations ?= {}

        if model.relations.hasMany?
          for name, opts of model.relations.hasMany
            unless @models[opts.model]?
              return @app.logger.error "Unknown model:", opts.model
            @models[opts.model].indexes[opts.foreignKey] = yes

        if model.relations.belongsTo?
          for name, opts of model.relations.belongsTo
            model.indexes[opts.foreignKey] = yes

      models = (model for modelName, model of @models)

      @app.logger.trace "waiting for indexes"
      async.each models, ((model, cb) -> model.createIndexes(cb)), (err) =>
        process.nextTick =>
          @app.logger.trace "db:ensureIndexes:ready"
          @emit "db:ensureIndexes:ready"
          cb()

