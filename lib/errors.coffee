
class BaseError extends Error
  constructor: (@message) ->
    @name = @constructor.name
    Error.captureStackTrace @, @constructor

class ValidationError  extends BaseError

class ModelError  extends BaseError

module.exports = {ValidationError, ModelError}