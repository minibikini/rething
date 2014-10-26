rething = require '../../'

module.exports = class Post extends rething.Model
  @schema:
    title:
      type: String
      index: on

    body: String
    keywords: [String]

  # relations
  @belongsTo 'author', model: 'User'
  @hasMany 'comments'