module.exports = require './DbManager'

Pool = require 'rethinkdb-pool'
Promise = require 'bluebird'
{tableize} = require 'inflecto'
_ = require 'lodash'

{all} = Promise

db =
  Pool: Pool
  Promise: Promise
  models: {}
  initModelsTasks: []

  init: (@config = {}) ->
    @config.ensureIndexes ?= yes
    @pool ?= Pool(@config)
    @r ?= @pool.r

    @checkDb() # create db if not exist
      .then @checkTables
      .then @initModels
      .then => @ensureIndexes() if @config.ensureIndexes
      .then => @

  checkTables: ->
    {run, r} = db

    run(r.tableList()).then (tableList) ->
      tasks = for modelName, model of db.models when model.tableName not in tableList
        run r.tableCreate(model.tableName, primaryKey: model.primaryKey)

      all tasks

  initModels: ->
    all (Promise.try task for task in db.initModelsTasks)

  run: (query, cb) ->
    db.pool.run query, cb

  exec: (query) ->
    new Promise (resolve, reject) ->
      query.run (err, result) ->
        if err then reject(err)
        else resolve result

  close: (cb) ->
    db.pool.drain ->
      db.pool.destroyAllNow cb

  # create db if it not exists yet
  checkDb: ->
    @run(@r.dbList()).then (databases) =>
      unless @config.db in databases
        @run @r.dbCreate(@config.db)

  addModel: (model) ->
    modelName = model::constructor.name
    @models[modelName] = model

    model.schema ?= {}
    model.tableName ?= tableize modelName
    model.timestamp ?= yes

    if model.timestamp
      model.schema.createdAt ?=
       type: Date
       index: yes

      model.order ?= 'createdAt'

      model.schema.modifiedAt ?=
       type: Date
       index: yes

    model.indexes ?= {}

    model

  addModels: (models) ->
    for model in models
      @models[model::constructor.name] = model

  afterSave: (model, changes, modelName) ->

  ensureIndexes: ->
    for modelName, model of @models
      for key, opts of model.schema when _.isObject(opts) and opts.index?
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

    tasks = for modelName, model of @models
      model.createIndexes()

    all tasks

db.Model = require('./Model')(db)

module.exports = db
