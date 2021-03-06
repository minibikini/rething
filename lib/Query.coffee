typeOf = require('typeof')
js_beautify = require('js-beautify').js_beautify
chalk = require 'chalk'
Promise = require 'bluebird'

beautify = (str) -> js_beautify str, indent_size: 2

wrapAsync = require './wrapAsync'

module.exports = (db) ->
  class Query
    collection: no
    ordered: no
    wrap: yes

    constructor: (@model, @query) ->

    toRQL: -> @query

    run: (cb) ->
      if @collection and @model.order and not @ordered
        @order @model.order

      opts = {}
        # connection: db.getConn()
        # profile: on
        # useOutdated: no

      if db.config.logQueries
        startTime = Date.now()
        queryStr = @query.toString()

      db.run @query, (err, data) =>
        if db.config.logQueries
          console.log chalk.gray "=========================================="
          queryStr =  beautify queryStr
          queryStr = queryStr.split('\n')[0] if db.config.logQueries is 'short'
          console.log chalk.green("Executed ReQL (#{Date.now()-startTime}ms): \n"), queryStr

        return cb err if err?

        if not @wrap
          cb err, data
        else
          wrapAsync data, @model, {isNew: no, wrapRelated: yes}, (err, data) =>
            return cb err if err?
            if not @collection and typeOf(data) is 'array'
              data = if data.length then data[0] else null
            cb err, data

    with: (rels, cb) ->
      rels = rels.trim().split(' ') if typeOf(rels) is 'string'
      rels = [rels] if typeOf(rels) is 'object'

      rels = for rel in rels
        if typeOf(rel) is 'object'
          rel
        else
          name: rel

      @order()

      @query = @model.relatedQuery(rels, @query)

      if cb? then @run cb else @

    order: (rules, cb) ->
        if rules?
          if typeOf(rules) is 'string'
            rules = rules.trim().split(' ')

          unless typeOf(rules) is 'array'
            rules = [rules]

          rules = for rule in rules
            if typeOf(rule) is 'string'
              if rule[0] is '-' then db.r.desc rule[1..] else rule
            else if typeOf(rule) is 'object'
              if rule.index[0] is '-' then index: db.r.desc rule.index[1..] else rule

          @query = @query.orderBy.apply @query, rules
          @ordered = yes

        if cb? then @run cb else @

    skip: (num, cb) ->
      @query = @query.skip num
      if cb? then @run cb else @

    limit: (num, cb) ->
      @query = @query.limit num
      if cb? then @run cb else @

    count: (cb) ->
      @query = @query.count()
      @wrap = no
      if cb? then @run cb else @

    countBy: (key, cb) ->
      @query = @query.count(key)
      @wrap = no
      if cb? then @run cb else @

    group: (key, cb) ->
      @query = @query.group(key)
      if cb? then @run cb else @

    ungroup: (cb) ->
      @query = @query.ungroup()
      if cb? then @run cb else @

    map: (fn, cb) ->
      @query = @query.map(fn)
      if cb? then @run cb else @

    concatMap: (fn, cb) ->
      @query = @query.concatMap(fn)
      if cb? then @run cb else @


    filter: (predicate, cb) ->
      @query = @query.filter(predicate)
      if cb? then @run cb else @

    increment: (field, num, cb) ->
      if arguments.length is 2
        cb = num
        num = 1

      update = {}
      update[field] = db.r.row(field).add(num)
      db.run @query.update(update, returnChanges: yes), cb

    then: (onFulfilled, onRejected) ->
      promise = new Promise (resolve, reject) =>
        @run (err, res) =>
          return reject err if err
          resolve res
      # promise.bind @
      promise.then onFulfilled, onRejected
