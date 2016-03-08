module.exports = require './DbManager'

Promise = require 'bluebird'
{tableize} = require 'inflecto'
_ = require 'lodash'

rethinkdbdash = require('rethinkdbdash')

{all} = Promise

db =
  Promise: Promise
  models: {}
  initModelsTasks: []

  init: (@config = {}) ->
    @config.ensureIndexes ?= yes
    @r ?= rethinkdbdash @config

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
    query.run().nodeify(cb)

  exec: (query) ->
    query.run()

  close: (cb) ->
    @r.getPoolMaster().drain(cb);

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
