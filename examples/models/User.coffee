module.exports = (db, app) ->
  class User extends db.Model
    #### Some defaults:
    # @tableName: 'users'
    # @timestamp: on
    # @order: 'createdAt'
    # @primaryKey: 'id'

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
    #   cb null

    # @someStatic: ->