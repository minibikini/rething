should = require('chai').should()
AppSpine = require 'appspine'
r = require 'rethinkdb'
Rething = require '../'
Faker = require 'Faker'
typeOf = require 'typeof'

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

    it 'should has `createdAt` by default', (done) ->
      user2 = new User getFakeUserData()
      user2.save (err) ->
        should.not.exist err
        user2.should.have.property 'createdAt'
        r.db(app.config.rethinkdb.db)
          .table(User.tableName)
          .get(user2.id).run app.db.getConn(), (err, data) ->
            should.not.exist err
            data.should.have.property 'createdAt'
            done()


    it 'should delete a model from db', (done) ->
      user2 = new User getFakeUserData()
      user2.save (err) ->
        should.not.exist err
        user2.remove (err) ->
          should.not.exist err
          done()

    describe 'hasMany', ->
      it 'should create a record for hasMany relation', (done) ->
        post = user.addPost getFakePost()
        should.not.exist post.id
        user.save (err) ->
          should.not.exist err
          should.exist post.id
          post.userId.should.equal user.id
          done()

      it 'should load hasMany relation - style #1', (done) ->
        user.addPost getFakePost()
        user.addPost getFakePost()
        user.save (err) ->
          should.not.exist err

          rels =
            name: 'posts'
            # with: {name: 'answers', order: 'order'}

          User.get(user.id).with rels, (err, u) ->
            u.posts.should.be.an('array').with.lengthOf 3
            # console.log 2, u.posts.length, typeOf u.posts
            should.not.exist err
            done()

      it 'should load hasMany relation - style #2 (the shortest)', (done) ->
        User.get(user.id).with 'posts', (err, u) ->
          u.posts.should.be.an('array').with.lengthOf 3
          should.not.exist err
          done()