should = require('chai').should()
AppSpine = require 'appspine'
r = require 'rethinkdb'
Rething = require '../'
Faker = require 'Faker'

getFakeUserData = ->
  firstName: Faker.Name.firstName()
  lastName: Faker.Name.lastName()
  username: Faker.Internet.userName()
  email: Faker.Internet.email()

getFakePost = ->
  title: Faker.Lorem.sentence()
  body: Faker.Lorem.paragraphs 3

describe 'Model', ->
  app = null
  User = null

  before (done) ->
    @timeout 15000
    app = new AppSpine require './config/config'
    app.db = new Rething app
    app.db.connect()
    app.db.once 'ready', ->
      User = app.db.models.User
      done()

  # after (done) ->
  #   r.dbDrop(app.config.rethinkdb.db).run app.db.getConn(), done
  describe 'Model Instanse', ->
    user = null
    post = null

    it 'should save new model to db', (done) ->
      user = new User getFakeUserData()
      user.save (err) ->
        should.not.exist err
        done()

    it 'should delete a model from db', (done) ->
      user2 = new User getFakeUserData()
      user2.save (err) ->
        should.not.exist err
        user2.remove (err) ->
          should.not.exist err
          done()

    it 'should create a record for hasMany relation', (done) ->
      post = user.addPost getFakePost()
      should.not.exist post.id
      user.save (err) ->
        should.exist post.id
        post.userId.should.equal user.id
        done()