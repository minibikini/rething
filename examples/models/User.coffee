module.exports = (db, app) ->
  class User extends db.Model
    @schema:
      email:
        type: String
        index: on

      firstName: String
      lastName: String
      password: String
      username: String
      roles:
        type: String
        default: ['user']

    # relations
    @hasMany 'posts'
    @hasMany 'comments'

    # Instanse methods
    fullName: -> @firstName + ' ' + @lastName

    # beforeSave: (cb) ->
    #   db.r.table('settings').get('lastPollId')
    #     .update({ value: db.rr.row('value').add(1)}, {return_vals: true})
    #     .run db.conn, (err, results) =>
    #       @id = results.new_val.value
    #       app.lastPollid = @id
    #       cb err

    # @addAnswer: (pollId, questions, cb) ->
    #   addAnswer = (q, cb) ->
    #     db.models.Question.addAnswer q, cb

    #   async.each questions, addAnswer, (err) ->
    #     return cb err if err?
    #     db.r.table('polls')
    #       .get(pollId)
    #       .update(responses: db.rr.row('responses').default(0).add(1))
    #       .run db.conn, cb

    # getStrId: -> @id.toString 36

    # getUrl: (results = no) ->
    #   if results
    #     @getUrl() + '/results'
    #   else
    #     "/p/#{@getStrId()}"

    # getFullUrl: ->
    #   "http://flisti.com/p/#{@getStrId()}"

    # getDisqusId: ->
    #   if @importId
    #     if @importId[0..2] is 'com'
    #       @importId[3..]
    #   else
    #     @getStrId()

    # addWidgetView: (cb = ->) ->
    #   @constructor.r().get(@id)
    #     .update(widgetViews: db.rr.row('widgetViews').default(0).add(1))
    #     .run db.conn, cb
