gulp = require 'gulp'
mocha = require 'gulp-mocha'
# gutil = require 'gulp-util'

gulp.task 'default', ['test']

gulp.task 'test', ->
  gulp.src './test/*.test.coffee'
    .pipe mocha
      reporter: 'spec'
      bail: yes
    .on 'error', -> @emit 'end'

gulp.task 'watch', ->
  gulp.watch ['./examples/**/*.coffee', './test/**/*.coffee', './lib/**/*.coffee'], ['test']
