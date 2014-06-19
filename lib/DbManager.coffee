r = require 'rethinkdb'
glob = require("glob")
EventEmitter = require("events").EventEmitter
inflection = require "inflection"
async = require "async"
typeOf = require('typeof')
Pool = require('rethinkdb-pool')


module.exports = class DbManager extends EventEmitter
  conn: null
  models: null
  autoReconnect: on
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

    @rr = r
    @r = r.db(@config.db)

    @pool = Pool(@config, 30)

  connect: (cb = ->) ->
    @pool.acquire (error, conn) =>
      if err?
        # console.log err.message?, err.message.indexOf 'ECONNREFUSED'
        @app.logger.error "connection error" , err
        cb err
        # @reconnect() if @autoReconnect
      else
        r.dbList().run conn, (err, databases) =>
          @pool.release conn
          if databases
            @emit "connect"
            cb()
          else cb err
            # @conn.on 'close', (err) =>
            #   @reconnect() if @autoReconnect

            # @conn.on 'error', (err) ->
            #   console.log 'error', err

            # @conn.on 'timeout', (err) ->
            #   console.log 'timeout'
          # else
          #   console.log err
          #   @reconnect() if @autoReconnect

    @

  reconnect: ->
    reconnect = =>
      @app.logger.info "Reconnecting to the DB..."

      @connect (err) =>
        fail = =>
          @reconnectDelay += @reconnectDelay
          @app.logger.info "Reconnection faild. Retry in #{@reconnectDelay/1000}s."

        if err?
          fail()
        else
          @checkConn (err) =>
            if err?
              fail()
              @reconnect()
            else
              @app.logger.info "Reconnected."
              @reconnectDelay = 100

    setTimeout reconnect, @reconnectDelay


  close: (cb = ->) ->
    @autoReconnect = off
    # @conn.close cb
    cb()

  getConn: -> @conn

  checkConn: (cb) ->
    @pool.acquire (err, conn) =>
      r.db(@config.db).tableList().run conn, (err, tables) =>
        if tables.length
          r.db(@config.db).table(tables[0]).indexList().run conn, (err, existed) =>
            @pool.release conn
            cb(err)
        else
          @pool.release conn
          cb()

  checkDb: ->
    @pool.acquire (err, conn) =>
      r.dbList().run conn, (err, databases) =>
        if @config.db in databases
          @emit "db:ready"
          @pool.release conn
        else
          r.dbCreate(@config.db).run conn, (err) =>
            return @app.logger.error err if err?
            @emit "db:ready"
            @pool.release conn

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

      cls.order ?= 'createdAt'

      cls.schema.modifiedAt ?=
       type: Date
       index: yes

    cls.indexes ?= {}

    if cls.tableName not in @tableList
      @pool.acquire (err, conn) =>
        r.tableCreate(cls.tableName, primaryKey: cls.primaryKey).run conn, (err, results) =>
          @pool.release conn
          if err
            cb err
          else
            cb()
    else
      cb()

  loadModels: ->
    @pool.acquire (err, conn) =>
      r.tableList().run conn, (err, @tableList) =>
        @pool.release conn
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

