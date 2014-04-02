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
    it 'should save new model to db', (done) ->
      user = new User getFakeUserData()
      user.save (err) ->
        should.not.exist err
        done()

    it 'should delete a model from db', (done) ->
      user = new User getFakeUserData()
      user.save (err) ->
        should.not.exist err
        user.remove (err) ->
          should.not.exist err
          done()