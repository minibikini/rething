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

describe 'RethinkDB ORM', ->
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

  after (done) ->
    app.db.close done
  #   r.dbDrop(app.config.rethinkdb.db).run app.db.getConn(), done

  describe 'Model Instanse', ->
    user = null
    post = null

    it 'should save new model to db', (done) ->
      user = new User getFakeUserData()
      user.isNewRecord.should.be.true
      user.save (err) ->
        should.not.exist err
        user.isNewRecord.should.be.false
        done()

    it 'should delete a model from db', (done) ->
      user2 = new User getFakeUserData()
      user2.save (err) ->
        should.not.exist err
        user2.remove (err) ->
          should.not.exist err
          done()

    describe 'Defaults', ->
      user = null
      before ->
        user = new User

      it 'should has defaults', ->
        user.roles.should.equal User.schema.roles.default

      it 'should has defaults generated by function', ->
        user.something.should.equal 'some string'

      it 'should has `createdAt`', (done) ->
        user.save (err) ->
          should.not.exist err
          user.should.have.property 'createdAt'
          r.db(app.config.rethinkdb.db)
            .table(User.tableName)
            .get(user.id).run app.db.getConn(), (err, data) ->
              should.not.exist err
              data.should.have.property 'createdAt'
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

  describe 'Model Class', ->
    user = null

    before (done) ->
      user = new User getFakeUserData()
      user.save done

    describe 'get()', ->
      it 'should get a record', (done) ->
        User.get user.id, (err, record) ->
          should.not.exist err
          should.exist record
          record.should.has.property 'id', user.id
          record.isNewRecord.should.be.false
          done()

    describe 'with()', ->
      before (done) ->
        user.addPost getFakePost()
        user.addPost getFakePost()
        user.save done

      it 'should get record with relations defined by string (relation name)', (done) ->
        User.get(user.id).with 'posts', (err, record) ->
          should.not.exist err
          record.posts.should.be.an('array').with.lengthOf 2
          done()

      it 'should get record with relations defined by config object', (done) ->
        rels =
          name: 'posts'
          # with: {name: 'answers', order: 'order'}

        User.get(user.id).with rels, (err, record) ->
          should.not.exist err
          record.posts.should.be.an('array').with.lengthOf 2
          done()
