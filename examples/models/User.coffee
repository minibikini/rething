rething = require '../../'

module.exports = class User extends rething.Model
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

    something:
      type: String
      default: -> 'some string'

  # relations
  @hasMany 'posts'
  @hasMany 'comments'

  # Instanse methods
  fullName: -> @firstName + ' ' + @lastName

  # beforeSave: (cb) ->
  #   cb null

  # @someStatic: ->