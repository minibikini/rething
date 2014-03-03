r = require 'rethinkdb'
glob = require("glob")
EventEmitter = require("events").EventEmitter
inflection = require "inflection"
async = require "async"
typeOf = require('typeof')

module.exports = class DbManager extends EventEmitter
  conn: null
  models: null

  constructor: (@app) ->
    @config = @app.config.rethinkdb
    @config.ensureIndexes ?= yes
    @logger = @app.logger
    @Model = require('./Model')(@)
    @models = {}
    @on "connect", =>
      @checkDb()

    @on 'db:ready',=>
      @loadModels()

    @on 'db:ensureIndexes:ready', =>
      @emit 'ready'

    @on 'modelsLoaded', =>
      process.nextTick =>
        if @config.ensureIndexes
          @ensureIndexes()
        else
          @emit 'ready'

    @r = r.db(@config.db)

  connect: (cb = ->) ->
    r.connect @config, (err, @conn) =>
      if err?
        cb err
        @emit "error", err
        @app.logger.error "connection error" , err
      else
        cb()
        @emit "connect"
    @

  getConn: -> @conn

  checkDb: ->
    r.dbList().run @getConn(), (err, databases) =>
      if @config.db in databases
        @emit "db:ready"
      else
        r.dbCreate(@config.db).run @getConn(), (err) =>
          return @app.logger.error err if err?
          @emit "db:ready"

  loadModel: (file, cb) =>
    cls = require(file)(@, @app)
    modelName = cls::constructor.name
    @models[modelName] = cls
    cls.schema ?= {}
    cls.tableName ?= inflection.underscore inflection.pluralize modelName
    cls.timestamp ?= yes

    if cls.timestamp
      cls.schema.createdAt ?=
       type: Date
       index: yes

      cls.schema.modifiedAt ?=
       type: Date
       index: yes

    cls.indexes ?= {}

    if cls.tableName not in @tableList
      r.tableCreate(cls.tableName, primaryKey: cls.primaryKey).run @getConn(), (err, results) ->
        if err
          cb err
        else
          cb()
    else
      cb()

  loadModels: ->
    r.tableList().run @getConn(), (err, @tableList) =>
      glob "#{__dirname}/../models/*.coffee", (err, files) =>
        async.each files, @loadModel, (err) =>
          @emit 'modelsLoaded'

  ensureIndexes: ->
    for modelName, model of @models
      for key, opts of model.schema when typeOf(opts) is 'object' and opts.index?
        model.indexes[key] = opts.index

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
      @app.logger.trace "db:ensureIndexes:ready"
      @emit "db:ensureIndexes:ready"

